"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";

type Account = { id: number; name: string; allocationBps: number; balance: number; color: string };
type Transaction = {
  id: number; type: string; amount: number; fromAccountId: number | null; fromAccountName: string | null;
  toAccountId: number | null; toAccountName: string | null; note: string;
  details: { allocations?: Array<{ name: string; amount: number; allocationBps: number }> }; createdAt: string;
};
type BudgetData = { accounts: Account[]; transactions: Transaction[] };
type Modal = "deposit" | "spend" | "transfer" | "accounts" | null;

const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const parseMoney = (value: string) => Number(value.replace(/[$,\s]/g, ""));

function formatDate(value: string) {
  const normalized = value.includes("T") ? value : `${value.replace(" ", "T")}Z`;
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(normalized));
}

function transactionLabel(item: Transaction) {
  if (item.type === "deposit") return "Proceeds distributed";
  if (item.type === "spend") return `Spent from ${item.fromAccountName}`;
  if (item.type === "transfer") return `${item.fromAccountName} → ${item.toAccountName}`;
  if (item.type === "allocation_update") return "Allocation plan updated";
  if (item.type === "account_created") return "Account created";
  if (item.type === "account_deleted") return "Account deleted";
  return "Budget updated";
}

export default function BudgetTracker() {
  const [data, setData] = useState<BudgetData>({ accounts: [], transactions: [] });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [modal, setModal] = useState<Modal>(null);
  const [selectedAccountId, setSelectedAccountId] = useState<number | null>(null);
  const [activityFilter, setActivityFilter] = useState("all");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [fromAccountId, setFromAccountId] = useState<number | null>(null);
  const [toAccountId, setToAccountId] = useState<number | null>(null);
  const [draftAccounts, setDraftAccounts] = useState<Account[]>([]);
  const [newAccountName, setNewAccountName] = useState("");

  async function load() {
    try {
      setError("");
      const response = await fetch("/api/budget", { cache: "no-store" });
      const result = (await response.json()) as BudgetData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to load the budget.");
      setData(result);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Unable to load the budget.");
    } finally { setLoading(false); }
  }

  useEffect(() => { void load(); }, []);

  const totalBalance = useMemo(() => data.accounts.reduce((sum, account) => sum + account.balance, 0), [data.accounts]);
  const totalAllocatedBps = useMemo(() => data.accounts.reduce((sum, account) => sum + account.allocationBps, 0), [data.accounts]);
  const filteredTransactions = useMemo(() => {
    if (activityFilter === "all") return data.transactions;
    if (activityFilter === "income") return data.transactions.filter((item) => item.type === "deposit");
    if (activityFilter === "spend") return data.transactions.filter((item) => item.type === "spend");
    return data.transactions.filter((item) => item.type === "transfer");
  }, [activityFilter, data.transactions]);
  const latestDeposit = data.transactions.find((item) => item.type === "deposit");
  const selectedAccount = data.accounts.find((account) => account.id === selectedAccountId);

  function openModal(next: Modal, accountId?: number) {
    setError(""); setAmount(""); setNote("");
    if (accountId) setSelectedAccountId(accountId);
    if (next === "transfer") {
      const source = accountId ?? data.accounts[0]?.id ?? null;
      setFromAccountId(source);
      setToAccountId(data.accounts.find((account) => account.id !== source)?.id ?? null);
    }
    if (next === "accounts") setDraftAccounts(data.accounts.map((account) => ({ ...account })));
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
    event.preventDefault(); const numericAmount = parseMoney(amount);
    if (modal === "deposit") await act({ action: "deposit", amount: numericAmount, note }, "Proceeds distributed across your accounts.");
    else if (modal === "spend") await act({ action: "spend", accountId: selectedAccountId, amount: numericAmount, note }, "Expense recorded in the ledger.");
    else if (modal === "transfer") await act({ action: "transfer", fromAccountId, toAccountId, amount: numericAmount, note }, "Funds transferred between accounts.");
  }

  async function saveAllocations(event: FormEvent) {
    event.preventDefault();
    await act({ action: "setAllocations", accounts: draftAccounts.map(({ id, name, allocationBps }) => ({ id, name, allocationBps })) }, "Allocation plan saved.");
  }

  async function addAccount() {
    const result = await act({ action: "addAccount", name: newAccountName }, "Account added. Set its allocation before the next deposit.", true);
    if (result) { setNewAccountName(""); setDraftAccounts(result.accounts.map((account) => ({ ...account }))); }
  }

  async function deleteAccount(account: Account) {
    const result = await act({ action: "deleteAccount", accountId: account.id }, `${account.name} deleted.`, true);
    if (result) setDraftAccounts(result.accounts.map((item) => ({ ...item })));
  }

  const draftTotalBps = draftAccounts.reduce((sum, account) => sum + account.allocationBps, 0);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand-lockup"><span className="brand-mark" aria-hidden="true">FL</span><div><span className="eyebrow">Torn City finance</span><strong>Faction Ledger</strong></div></div>
        <div className="topbar-actions"><button className="button button-secondary" onClick={() => openModal("accounts")}>Manage accounts</button><button className="button button-primary" onClick={() => openModal("deposit")} disabled={loading}>+ Add proceeds</button></div>
      </header>

      <section className="hero-panel">
        <div className="hero-copy"><span className="eyebrow light">Faction treasury</span><h1>Put every dollar<br />to work.</h1><p>Record one deposit. Your allocation plan handles the rest.</p></div>
        <div className="hero-balance"><span>Total faction funds</span><strong>{loading ? "—" : money.format(totalBalance)}</strong><div className="hero-meta"><span><i className={totalAllocatedBps === 10000 ? "status-dot ready" : "status-dot"} /> {totalAllocatedBps / 100}% allocated</span><span>{data.accounts.length} active accounts</span></div></div>
        <div className="hero-grid" aria-hidden="true" />
      </section>

      {notice && <div className="notice" role="status"><span>✓</span>{notice}</div>}
      {error && !modal && <div className="page-error" role="alert">{error}<button onClick={() => void load()}>Try again</button></div>}

      <section className="summary-strip" aria-label="Budget summary">
        <div><span>Last proceeds</span><strong>{latestDeposit ? money.format(latestDeposit.amount) : "No deposits yet"}</strong><small>{latestDeposit ? formatDate(latestDeposit.createdAt) : "Add your first war income"}</small></div>
        <div><span>Allocation status</span><strong>{totalAllocatedBps === 10000 ? "Ready to distribute" : `${(10000 - totalAllocatedBps) / 100}% unassigned`}</strong><small>{data.accounts.length} earmarks configured</small></div>
        <div><span>Ledger entries</span><strong>{data.transactions.length}</strong><small>Every movement recorded</small></div>
      </section>

      <div className="content-grid">
        <section className="accounts-section">
          <div className="section-heading"><div><span className="eyebrow">Earmarked funds</span><h2>Your accounts</h2></div><button className="text-button" onClick={() => openModal("transfer")}>Transfer funds <span>→</span></button></div>
          {loading ? <div className="loading-card"><span className="spinner" /> Loading your treasury…</div> : (
            <div className="account-list">{data.accounts.map((account) => {
              const share = totalBalance > 0 ? (account.balance / totalBalance) * 100 : account.allocationBps / 100;
              return <article className="account-card" key={account.id}><div className={`account-accent ${account.color}`} /><div className="account-main">
                <div className="account-title"><div><span className={`account-icon ${account.color}`}>{account.name.slice(0, 1).toUpperCase()}</span><h3>{account.name}</h3></div><span className="allocation-pill">{account.allocationBps / 100}%</span></div>
                <strong className="account-balance">{money.format(account.balance)}</strong><div className="balance-track" aria-label={`${account.name} has ${share.toFixed(0)} percent of current funds`}><span className={account.color} style={{ width: `${Math.max(account.balance > 0 ? 2 : 0, share)}%` }} /></div>
                <div className="account-footer"><span>{share.toFixed(1)}% of treasury</span><div><button onClick={() => openModal("transfer", account.id)}>Transfer</button><button className="spend-link" onClick={() => openModal("spend", account.id)}>Record spend</button></div></div>
              </div></article>;
            })}</div>
          )}
        </section>

        <aside className="activity-section">
          <div className="section-heading compact"><div><span className="eyebrow">Audit trail</span><h2>Activity</h2></div></div>
          <div className="activity-filters" role="group" aria-label="Filter ledger">{["all", "income", "spend", "transfer"].map((filter) => <button key={filter} className={activityFilter === filter ? "active" : ""} onClick={() => setActivityFilter(filter)}>{filter === "transfer" ? "Transfers" : filter.charAt(0).toUpperCase() + filter.slice(1)}</button>)}</div>
          <div className="activity-list">{filteredTransactions.length === 0 ? <div className="empty-state"><span>◎</span><strong>No activity yet</strong><p>Your deposits, spending, and transfers will appear here.</p></div> : filteredTransactions.slice(0, 12).map((item) => <article className="activity-item" key={item.id}>
            <span className={`activity-icon ${item.type}`}>{item.type === "deposit" ? "↓" : item.type === "spend" ? "↑" : item.type === "transfer" ? "↔" : "•"}</span><div><strong>{transactionLabel(item)}</strong><p>{item.note}</p><time>{formatDate(item.createdAt)}</time>{item.type === "deposit" && item.details.allocations && <details><summary>View split</summary>{item.details.allocations.map((split) => <span key={split.name}>{split.name}<b>{money.format(split.amount)}</b></span>)}</details>}</div>
            {item.amount > 0 && <b className={`activity-amount ${item.type}`}>{item.type === "deposit" ? "+" : item.type === "spend" ? "−" : ""}{money.format(item.amount)}</b>}
          </article>)}</div>
        </aside>
      </div>

      <footer><span>Faction Ledger</span><p>Independent fan tool for Torn City faction finances.</p></footer>

      {modal && <div className="modal-backdrop" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && closeModal()}><section className={`modal ${modal === "accounts" ? "modal-wide" : ""}`} role="dialog" aria-modal="true" aria-labelledby="modal-title"><button className="modal-close" onClick={closeModal} aria-label="Close">×</button>
        {modal === "accounts" ? <form onSubmit={saveAllocations}><span className="eyebrow">Distribution rules</span><h2 id="modal-title">Manage accounts</h2><p className="modal-intro">Set the percentage each account receives whenever you add faction proceeds.</p>
          <div className={`allocation-total ${draftTotalBps === 10000 ? "valid" : ""}`}><div><span>Allocated</span><strong>{draftTotalBps / 100}%</strong></div><div className="allocation-track"><span style={{ width: `${Math.min(100, draftTotalBps / 100)}%` }} /></div><small>{draftTotalBps === 10000 ? "Ready to save" : `${Math.abs(10000 - draftTotalBps) / 100}% ${draftTotalBps < 10000 ? "left to assign" : "over the limit"}`}</small></div>
          <div className="allocation-editor">{draftAccounts.map((account) => <div className="allocation-row" key={account.id}><span className={`account-icon ${account.color}`}>{account.name.slice(0, 1).toUpperCase()}</span><label><span>Account name</span><input value={account.name} maxLength={50} onChange={(event) => setDraftAccounts((current) => current.map((item) => item.id === account.id ? { ...item, name: event.target.value } : item))} /></label><label className="percent-field"><span>Allocation</span><div><input type="number" min="0" max="100" step="0.01" value={account.allocationBps / 100} onChange={(event) => setDraftAccounts((current) => current.map((item) => item.id === account.id ? { ...item, allocationBps: Math.round(Number(event.target.value) * 100) } : item))} /><b>%</b></div></label><button type="button" className="delete-button" onClick={() => void deleteAccount(account)} disabled={account.balance !== 0 || saving} title={account.balance !== 0 ? "Empty this account before deleting" : "Delete account"}>×</button></div>)}</div>
          <div className="add-account-row"><input value={newAccountName} onChange={(event) => setNewAccountName(event.target.value)} placeholder="New account name" maxLength={50} /><button type="button" onClick={() => void addAccount()} disabled={!newAccountName.trim() || saving}>+ Add account</button></div>
          {error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button type="button" className="button button-secondary" onClick={closeModal}>Cancel</button><button className="button button-primary" disabled={saving || draftTotalBps !== 10000}>{saving ? "Saving…" : "Save allocation plan"}</button></div>
        </form> : <form onSubmit={submitFinancial}><span className="eyebrow">{modal === "deposit" ? "New income" : modal === "spend" ? "Account expense" : "Move funds"}</span><h2 id="modal-title">{modal === "deposit" ? "Add faction proceeds" : modal === "spend" ? `Spend from ${selectedAccount?.name ?? "account"}` : "Transfer funds"}</h2><p className="modal-intro">{modal === "deposit" ? "The full amount will be split using your current allocation plan." : modal === "spend" ? `Available: ${money.format(selectedAccount?.balance ?? 0)}` : "Move money without changing your distribution percentages."}</p>
          {modal === "transfer" && <div className="transfer-grid"><label><span>From</span><select value={fromAccountId ?? ""} onChange={(event) => setFromAccountId(Number(event.target.value))}>{data.accounts.map((account) => <option key={account.id} value={account.id}>{account.name} — {money.format(account.balance)}</option>)}</select></label><span className="transfer-arrow">→</span><label><span>To</span><select value={toAccountId ?? ""} onChange={(event) => setToAccountId(Number(event.target.value))}>{data.accounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label></div>}
          <label className="field"><span>Amount</span><div className="money-input"><b>$</b><input autoFocus inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0" required /></div></label><label className="field"><span>{modal === "deposit" ? "Source or note" : "Description"}</span><input value={note} onChange={(event) => setNote(event.target.value)} maxLength={160} placeholder={modal === "deposit" ? "e.g. Ranked war — August 2" : modal === "spend" ? "e.g. Xanax restock" : "Optional transfer note"} required={modal === "spend"} /></label>
          {modal === "deposit" && <div className="split-preview"><span>Estimated split</span>{data.accounts.map((account) => <div key={account.id}><span><i className={account.color} />{account.name} <small>{account.allocationBps / 100}%</small></span><b>{money.format(Math.floor((parseMoney(amount) || 0) * account.allocationBps / 10000))}</b></div>)}</div>}
          {error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button type="button" className="button button-secondary" onClick={closeModal}>Cancel</button><button className="button button-primary" disabled={saving || !amount}>{saving ? "Saving…" : modal === "deposit" ? "Distribute proceeds" : modal === "spend" ? "Record expense" : "Transfer funds"}</button></div>
        </form>}
      </section></div>}
    </main>
  );
}
