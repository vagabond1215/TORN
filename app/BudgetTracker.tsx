"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";

type Account = { id: number; name: string; allocationBps: number; balance: number; color: string };
type Policy = { sourceKey: string; label: string; taxBps: number };
type Actor = { userId: string; email: string; name: string };
type Transaction = {
  id: number; type: string; amount: number; fromAccountId: number | null; fromAccountName: string | null;
  toAccountId: number | null; toAccountName: string | null; note: string;
  details: {
    source?: string; grossAmount?: number; taxBps?: number; playerPayout?: number; factionShare?: number;
    allocations?: Array<{ name: string; amount: number; allocationBps: number }>;
  };
  actorName: string | null; actorEmail: string | null; createdAt: string;
};
type BudgetData = { currentUser: Actor | null; accounts: Account[]; policies: Policy[]; transactions: Transaction[] };
type Modal = "deposit" | "spend" | "transfer" | "settings" | null;
type SettingsSection = "accounts" | "policies" | "access" | "appearance";
type Theme = "light" | "dark" | "system";

const emptyData: BudgetData = { currentUser: null, accounts: [], policies: [], transactions: [] };
const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const parseMoney = (value: string) => Number(value.replace(/[$,\s]/g, ""));

function formatDate(value: string) {
  const normalized = value.includes("T") ? value : `${value.replace(" ", "T")}Z`;
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(normalized));
}

function transactionLabel(item: Transaction) {
  if (item.type === "deposit") return `${item.details.source ?? "Faction income"} settled`;
  if (item.type === "spend") return `Spent from ${item.fromAccountName}`;
  if (item.type === "transfer") return `${item.fromAccountName} → ${item.toAccountName}`;
  if (item.type === "allocation_update") return "Account allocations updated";
  if (item.type === "policy_update") return "Tax policies updated";
  if (item.type === "account_created") return "Account created";
  if (item.type === "account_deleted") return "Account deleted";
  if (item.type === "policy_bootstrap") return "Blood Coven defaults applied";
  return "Treasury updated";
}

export default function BudgetTracker() {
  const [data, setData] = useState<BudgetData>(emptyData);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [modal, setModal] = useState<Modal>(null);
  const [settingsSection, setSettingsSection] = useState<SettingsSection>("accounts");
  const [theme, setTheme] = useState<Theme>("system");
  const [selectedAccountId, setSelectedAccountId] = useState<number | null>(null);
  const [activityFilter, setActivityFilter] = useState("all");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [sourceKey, setSourceKey] = useState("war");
  const [fromAccountId, setFromAccountId] = useState<number | null>(null);
  const [toAccountId, setToAccountId] = useState<number | null>(null);
  const [draftAccounts, setDraftAccounts] = useState<Account[]>([]);
  const [draftPolicies, setDraftPolicies] = useState<Policy[]>([]);
  const [newAccountName, setNewAccountName] = useState("");

  async function load() {
    try {
      setError("");
      const response = await fetch("/api/budget", { cache: "no-store" });
      const result = (await response.json()) as BudgetData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to load the treasury.");
      setData(result);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Unable to load the treasury.");
    } finally { setLoading(false); }
  }

  useEffect(() => {
    const task = window.setTimeout(() => {
      void load();
      const saved = window.localStorage.getItem("blood-coven-theme");
      if (saved === "light" || saved === "dark" || saved === "system") setTheme(saved);
    }, 0);
    return () => window.clearTimeout(task);
  }, []);

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => { document.documentElement.dataset.theme = theme === "system" ? (media.matches ? "dark" : "light") : theme; };
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme]);

  const totalBalance = useMemo(() => data.accounts.reduce((sum, account) => sum + account.balance, 0), [data.accounts]);
  const filteredTransactions = useMemo(() => {
    if (activityFilter === "all") return data.transactions;
    if (activityFilter === "income") return data.transactions.filter((item) => item.type === "deposit");
    if (activityFilter === "spend") return data.transactions.filter((item) => item.type === "spend");
    if (activityFilter === "transfer") return data.transactions.filter((item) => item.type === "transfer");
    return data.transactions.filter((item) => !["deposit", "spend", "transfer"].includes(item.type));
  }, [activityFilter, data.transactions]);
  const selectedAccount = data.accounts.find((account) => account.id === selectedAccountId);
  const selectedPolicy = data.policies.find((policy) => policy.sourceKey === sourceKey) ?? data.policies[0];
  const grossPreview = parseMoney(amount) || 0;
  const factionPreview = Math.floor(grossPreview * (selectedPolicy?.taxBps ?? 0) / 10000);
  const playerPreview = grossPreview - factionPreview;

  function openModal(next: Modal, accountId?: number, section?: SettingsSection) {
    setError(""); setAmount(""); setNote("");
    if (accountId) setSelectedAccountId(accountId);
    if (next === "transfer") {
      const source = accountId ?? data.accounts[0]?.id ?? null;
      setFromAccountId(source);
      setToAccountId(data.accounts.find((account) => account.id !== source)?.id ?? null);
    }
    if (next === "settings") {
      setSettingsSection(section ?? "accounts");
      setDraftAccounts(data.accounts.map((account) => ({ ...account })));
      setDraftPolicies(data.policies.map((policy) => ({ ...policy })));
    }
    setModal(next);
  }

  const closeModal = () => { if (!saving) setModal(null); };

  async function act(payload: Record<string, unknown>, success: string, keepOpen = false) {
    setSaving(true); setError("");
    try {
      const response = await fetch("/api/budget", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
      const result = (await response.json()) as BudgetData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to save your change.");
      setData(result); setNotice(success); window.setTimeout(() => setNotice(""), 3200);
      if (!keepOpen) setModal(null);
      return result;
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : "Unable to save your change.");
      return null;
    } finally { setSaving(false); }
  }

  async function submitFinancial(event: FormEvent) {
    event.preventDefault();
    const numericAmount = parseMoney(amount);
    if (modal === "deposit") await act({ action: "deposit", amount: numericAmount, sourceKey, note }, "Proceeds settled and the faction share distributed.");
    else if (modal === "spend") await act({ action: "spend", accountId: selectedAccountId, amount: numericAmount, note }, "Expense recorded.");
    else if (modal === "transfer") await act({ action: "transfer", fromAccountId, toAccountId, amount: numericAmount, note }, "Funds transferred.");
  }

  async function saveAllocations(event: FormEvent) {
    event.preventDefault();
    const result = await act({ action: "setAllocations", accounts: draftAccounts.map(({ id, name, allocationBps }) => ({ id, name, allocationBps })) }, "Account allocations saved.", true);
    if (result) setDraftAccounts(result.accounts.map((account) => ({ ...account })));
  }

  async function savePolicies(event: FormEvent) {
    event.preventDefault();
    const result = await act({ action: "setPolicies", policies: draftPolicies.map(({ sourceKey: key, taxBps }) => ({ sourceKey: key, taxBps })) }, "Tax policies saved.", true);
    if (result) setDraftPolicies(result.policies.map((policy) => ({ ...policy })));
  }

  async function addAccount() {
    const result = await act({ action: "addAccount", name: newAccountName }, "Account added. Set its allocation before saving.", true);
    if (result) { setNewAccountName(""); setDraftAccounts(result.accounts.map((account) => ({ ...account }))); }
  }

  async function deleteAccount(account: Account) {
    const result = await act({ action: "deleteAccount", accountId: account.id }, `${account.name} deleted.`, true);
    if (result) setDraftAccounts(result.accounts.map((item) => ({ ...item })));
  }

  function chooseTheme(next: Theme) {
    setTheme(next);
    window.localStorage.setItem("blood-coven-theme", next);
  }

  function copySiteLink() {
    void navigator.clipboard.writeText(window.location.href);
    setNotice("Site link copied.");
    window.setTimeout(() => setNotice(""), 2200);
  }

  const draftTotalBps = draftAccounts.reduce((sum, account) => sum + account.allocationBps, 0);

  return (
    <main className="app-shell">
      <header className="topbar">
        <h1>Blood Coven Treasury</h1>
        <div className="topbar-actions"><button className="button button-secondary" onClick={() => openModal("settings")}>Settings</button><button className="button button-primary" onClick={() => openModal("deposit")} disabled={loading}>+ Add proceeds</button></div>
      </header>

      <section className="balance-panel" aria-label="Treasury balance"><span>Total faction funds</span><strong>{loading ? "—" : money.format(totalBalance)}</strong></section>

      {notice && <div className="notice" role="status">{notice}</div>}
      {error && !modal && <div className="page-error" role="alert">{error}<button onClick={() => void load()}>Try again</button></div>}

      <div className="content-grid">
        <section className="accounts-section">
          <div className="section-heading"><h2>Accounts</h2><button className="text-button" onClick={() => openModal("transfer")}>Transfer funds</button></div>
          {loading ? <div className="loading-card">Loading…</div> : <div className="account-list">{data.accounts.map((account) => <article className="account-card" key={account.id}>
            <div className="account-title"><h3>{account.name}</h3><span>{account.allocationBps / 100}%</span></div>
            <strong className="account-balance">{money.format(account.balance)}</strong>
            <div className="account-actions"><button onClick={() => openModal("transfer", account.id)}>Transfer</button><button onClick={() => openModal("spend", account.id)}>Spend</button></div>
          </article>)}</div>}
        </section>

        <aside className="activity-section">
          <div className="section-heading"><h2>History</h2></div>
          <div className="activity-filters" role="group" aria-label="Filter ledger">{["all", "income", "spend", "transfer", "changes"].map((filter) => <button key={filter} className={activityFilter === filter ? "active" : ""} onClick={() => setActivityFilter(filter)}>{filter === "transfer" ? "Moves" : filter.charAt(0).toUpperCase() + filter.slice(1)}</button>)}</div>
          <div className="activity-list">{filteredTransactions.length === 0 ? <div className="empty-state">No matching history.</div> : filteredTransactions.slice(0, 24).map((item) => <article className="activity-item" key={item.id}>
            <div><strong>{transactionLabel(item)}</strong><p>{item.note}</p><time>{formatDate(item.createdAt)} · {item.actorName ?? "Legacy entry"}</time>
              {item.type === "deposit" && item.details.allocations && <details><summary>View settlement</summary>
                <span>Gross proceeds<b>{money.format(item.details.grossAmount ?? item.amount)}</b></span>
                <span>Player payout<b>{money.format(item.details.playerPayout ?? 0)}</b></span>
                <span>Faction share ({(item.details.taxBps ?? 10000) / 100}%)<b>{money.format(item.details.factionShare ?? item.amount)}</b></span>
                {item.details.allocations.map((split) => <span className="account-split" key={split.name}>{split.name}<b>{money.format(split.amount)}</b></span>)}
              </details>}
            </div>
            {item.amount > 0 && <b className={`activity-amount ${item.type}`}>{item.type === "deposit" ? "+" : item.type === "spend" ? "−" : ""}{money.format(item.amount)}</b>}
          </article>)}</div>
        </aside>
      </div>

      {modal && <div className="modal-backdrop" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && closeModal()}><section className={`modal ${modal === "settings" ? "modal-settings" : ""}`} role="dialog" aria-modal="true" aria-labelledby="modal-title"><button className="modal-close" onClick={closeModal} aria-label="Close">×</button>
        {modal === "settings" ? <div className="settings-layout">
          <nav className="settings-nav" aria-label="Settings sections">{(["accounts", "policies", "access", "appearance"] as SettingsSection[]).map((section) => <button key={section} className={settingsSection === section ? "active" : ""} onClick={() => setSettingsSection(section)}>{section.charAt(0).toUpperCase() + section.slice(1)}</button>)}</nav>
          <div className="settings-content">
            {settingsSection === "accounts" && <form onSubmit={saveAllocations}><h2 id="modal-title">Accounts</h2><p className="modal-intro">Divide the faction share between treasury accounts.</p>
              {draftTotalBps !== 10000 && <p className="allocation-warning">Allocations must total 100%. Currently {draftTotalBps / 100}%.</p>}
              <div className="allocation-editor">{draftAccounts.map((account) => <div className="allocation-row" key={account.id}><label><span>Account</span><input value={account.name} maxLength={50} onChange={(event) => setDraftAccounts((current) => current.map((item) => item.id === account.id ? { ...item, name: event.target.value } : item))} /></label><label className="percent-field"><span>Share</span><div><input type="number" min="0" max="100" step="0.01" value={account.allocationBps / 100} onChange={(event) => setDraftAccounts((current) => current.map((item) => item.id === account.id ? { ...item, allocationBps: Math.round(Number(event.target.value) * 100) } : item))} /><b>%</b></div></label><button type="button" className="delete-button" onClick={() => void deleteAccount(account)} disabled={account.balance !== 0 || saving} title={account.balance !== 0 ? "Empty this account before deleting" : "Delete account"}>×</button></div>)}</div>
              <div className="add-account-row"><input value={newAccountName} onChange={(event) => setNewAccountName(event.target.value)} placeholder="New account name" maxLength={50} /><button type="button" onClick={() => void addAccount()} disabled={!newAccountName.trim() || saving}>Add</button></div>
              {error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button className="button button-primary" disabled={saving || draftTotalBps !== 10000}>{saving ? "Saving…" : "Save accounts"}</button></div>
            </form>}
            {settingsSection === "policies" && <form onSubmit={savePolicies}><h2 id="modal-title">Tax policies</h2><p className="modal-intro">These percentages determine the faction share before account allocation.</p>
              <div className="policy-editor">{draftPolicies.map((policy) => <label key={policy.sourceKey}><span>{policy.label}</span><div><input type="number" min="0" max="100" step="0.01" value={policy.taxBps / 100} onChange={(event) => setDraftPolicies((current) => current.map((item) => item.sourceKey === policy.sourceKey ? { ...item, taxBps: Math.round(Number(event.target.value) * 100) } : item))} /><b>%</b></div></label>)}</div>
              {error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button className="button button-primary" disabled={saving}>{saving ? "Saving…" : "Save policies"}</button></div>
            </form>}
            {settingsSection === "access" && <section><h2 id="modal-title">Access</h2><p className="modal-intro">The treasury uses a private email allowlist. Visitors must sign in with the ChatGPT account matching an approved email.</p><div className="access-card"><span>Signed in as</span><strong>{data.currentUser?.name ?? "Authorized member"}</strong><small>{data.currentUser?.email}</small></div><p className="settings-note">The site owner controls the leadership allowlist. Add or remove members through the site’s sharing controls.</p><button className="button button-secondary" onClick={copySiteLink}>Copy site link</button></section>}
            {settingsSection === "appearance" && <section><h2 id="modal-title">Appearance</h2><p className="modal-intro">Theme preference is saved on this device.</p><div className="theme-options">{(["light", "dark", "system"] as Theme[]).map((option) => <button key={option} className={theme === option ? "active" : ""} onClick={() => chooseTheme(option)}><strong>{option.charAt(0).toUpperCase() + option.slice(1)}</strong><small>{option === "system" ? "Match this device" : `Always use ${option} mode`}</small></button>)}</div></section>}
          </div>
        </div> : <form onSubmit={submitFinancial}><h2 id="modal-title">{modal === "deposit" ? "Record proceeds" : modal === "spend" ? `Spend from ${selectedAccount?.name ?? "account"}` : "Transfer funds"}</h2><p className="modal-intro">{modal === "deposit" ? "Enter the full gross value. The policy calculates the player payout and deposits only the faction share." : modal === "spend" ? `Available: ${money.format(selectedAccount?.balance ?? 0)}` : "Move money between treasury accounts."}</p>
          {modal === "deposit" && <label className="field"><span>Proceeds type</span><select value={sourceKey} onChange={(event) => setSourceKey(event.target.value)}>{data.policies.map((policy) => <option key={policy.sourceKey} value={policy.sourceKey}>{policy.label} — {policy.taxBps / 100}% faction</option>)}</select></label>}
          {modal === "transfer" && <div className="transfer-grid"><label><span>From</span><select value={fromAccountId ?? ""} onChange={(event) => setFromAccountId(Number(event.target.value))}>{data.accounts.map((account) => <option key={account.id} value={account.id}>{account.name} — {money.format(account.balance)}</option>)}</select></label><span>→</span><label><span>To</span><select value={toAccountId ?? ""} onChange={(event) => setToAccountId(Number(event.target.value))}>{data.accounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label></div>}
          <label className="field"><span>{modal === "deposit" ? "Gross amount" : "Amount"}</span><div className="money-input"><b>$</b><input autoFocus inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0" required /></div></label>
          <label className="field"><span>{modal === "deposit" ? "Description" : "Note"}</span><input value={note} onChange={(event) => setNote(event.target.value)} maxLength={160} placeholder={modal === "deposit" ? "e.g. Silver ranked war" : modal === "spend" ? "e.g. Xanax restock" : "Optional transfer note"} required={modal === "spend"} /></label>
          {modal === "deposit" && <div className="settlement-preview"><div><span>Gross</span><b>{money.format(grossPreview)}</b></div><div><span>Player payout</span><b>{money.format(playerPreview)}</b></div><div className="faction-row"><span>Faction share ({(selectedPolicy?.taxBps ?? 0) / 100}%)</span><b>{money.format(factionPreview)}</b></div><hr />{data.accounts.map((account) => <div className="account-split" key={account.id}><span>{account.name} <small>{account.allocationBps / 100}%</small></span><b>{money.format(Math.floor(factionPreview * account.allocationBps / 10000))}</b></div>)}</div>}
          {error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button type="button" className="button button-secondary" onClick={closeModal}>Cancel</button><button className="button button-primary" disabled={saving || !amount}>{saving ? "Saving…" : modal === "deposit" ? "Record and distribute" : modal === "spend" ? "Record expense" : "Transfer"}</button></div>
        </form>}
      </section></div>}
    </main>
  );
}
