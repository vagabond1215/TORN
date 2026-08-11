"use client";

import { FormEvent, useEffect, useMemo, useRef, useState } from "react";

type Account = { id: number; name: string; allocationBps: number; balance: number; color: string };
type Policy = { sourceKey: string; label: string; taxBps: number };
type Actor = { userId: string; email: string; name: string };
type Transaction = {
  id: number; type: string; amount: number; fromAccountId: number | null; fromAccountName: string | null;
  toAccountId: number | null; toAccountName: string | null; note: string;
  details: {
    source?: string; grossAmount?: number; taxBps?: number; playerPayout?: number; factionShare?: number; pendingWarId?: number;
    allocations?: Array<{ name: string; amount: number; allocationBps: number }>;
  };
  actorName: string | null; actorEmail: string | null; createdAt: string;
};
type BudgetData = { currentUser: Actor | null; accounts: Account[]; policies: Policy[]; transactions: Transaction[] };
type WarReward = { id: number; name: string; quantity: number; marketPrice: number; value: number };
type PendingWar = {
  warId: number; factionId: number; opponentName: string; startedAt: number; endedAt: number; won: boolean;
  grossEstimate: number; reviewedValue: number | null; reviewedTaxBps: number; status: string; rewards: WarReward[];
  members: Array<{ id: number; name: string; attacks: number; score: number }>;
};
type ActiveWar = {
  warId: number; factionId: number; opponentName: string; startedAt: number; target: number; ourScore: number;
  theirScore: number; ourChain: number; theirChain: number; updatedAt: string;
  members: Array<{ id: number; name: string; hits: number; xanax: number; refills: number; energyEstimate: number }>;
};
type WarStatus = { pendingWars: PendingWar[]; activeWar: ActiveWar | null };
type TornSyncResult = WarStatus & {
  error?: string; syncedAt?: string; warnings?: string[];
  history?: {
    warBackfill?: { imported: number; offset: number; complete: boolean };
    ocRecent?: { imported: number; count: number };
    ocBackfill?: { imported: number; offset: number; complete: boolean };
  };
};
type Modal = "deposit" | "directDeposit" | "spend" | "transfer" | "settings" | null;
type MainTab = "accounts" | "balances" | "armory" | "wars" | "ocs" | "history";
type SettingsSection = "accounts" | "policies" | "torn" | "script" | "access" | "appearance";
type Theme = "light" | "dark" | "system";
type BridgeStatus = "checking" | "connected" | "missing";
type ArmoryCategory = "all" | "primary" | "secondary" | "melee" | "temporary" | "armor" | "clothing" | "medical" | "drugs" | "boosters" | "consumables" | "utility" | "special" | "other";
type BrowserEvent = {
  eventKey: string; eventType: string; category: string; occurredAt: string | null; summary: string;
  sourceUrl: string; payload: Record<string, unknown>; createdAt: string;
};
type OcHolding = { eventKey: string; crimeName: string; status: string; cashAmount: number; items: Array<{ name: string; quantity: number }>; summary: string; occurredAt: string | null; createdAt: string };
type ArmoryItem = { itemName: string; category: string; quantity: number; source: string; updatedAt: string };
type BrowserBridgeInfo = { totalEvents: number; lastImportedAt: string | null; recentEvents: BrowserEvent[]; ocHoldings: OcHolding[]; armoryItems: ArmoryItem[] };
type AccessData = { leaders: Array<{ email: string; name: string; addedBy: string; createdAt: string }> };
type MemberAdminData = {
  balances: Array<{ memberId: number | null; memberName: string; balance: number; earnedTotal: number; paidTotal: number; updatedAt: string }>;
  requests: Array<{ id: number; memberId: number; memberName: string; amount: number; status: string; note: string; deliveryPreference: string; createdAt: string; updatedAt: string }>;
};

const emptyData: BudgetData = { currentUser: null, accounts: [], policies: [], transactions: [] };
const emptyWars: WarStatus = { pendingWars: [], activeWar: null };
const emptyBridge: BrowserBridgeInfo = { totalEvents: 0, lastImportedAt: null, recentEvents: [], ocHoldings: [], armoryItems: [] };
const BRIDGE_CHANNEL = "blood-coven-treasury-bridge-v1";
const TORN_KEY_STORAGE = "torn-treasury-api-key-v2:52984";
const ARMORY_TABS: Array<{ key: ArmoryCategory; label: string }> = [
  { key: "all", label: "All" },
  { key: "primary", label: "Primary" },
  { key: "secondary", label: "Secondary" },
  { key: "melee", label: "Melee" },
  { key: "temporary", label: "Temporary" },
  { key: "armor", label: "Armor" },
  { key: "clothing", label: "Clothing" },
  { key: "medical", label: "Medical" },
  { key: "drugs", label: "Drugs" },
  { key: "boosters", label: "Boosters" },
  { key: "consumables", label: "Consumables" },
  { key: "utility", label: "Utility" },
  { key: "special", label: "Special" },
  { key: "other", label: "Other" },
];
const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const integer = new Intl.NumberFormat("en-US");
const parseMoney = (value: string) => Number(value.replace(/[$,\s]/g, ""));

function formatDate(value: string) {
  const normalized = value.includes("T") ? value : `${value.replace(" ", "T")}Z`;
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(normalized));
}
function formatUnix(value: number) {
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric" }).format(new Date(value * 1000));
}
function tornTimestampFromText(value: string) {
  const matches = Array.from(value.matchAll(/(\d{2}):(\d{2}):(\d{2})\s*(\d{2})\/(\d{2})\/(\d{2})/g));
  const match = matches.at(-1);
  if (!match) return 0;
  return Date.UTC(2000 + Number(match[6]), Number(match[5]) - 1, Number(match[4]), Number(match[1]), Number(match[2]), Number(match[3]));
}
function browserEventTime(event: BrowserEvent) {
  const endedAt = Number(event.payload.endedAt);
  if (Number.isFinite(endedAt) && endedAt > 0) return endedAt * 1000;
  return tornTimestampFromText(event.summary) || tornTimestampFromText(event.occurredAt ?? "") || Date.parse(event.occurredAt ?? event.createdAt) || Date.parse(event.createdAt);
}
function formatTornEventDate(event: BrowserEvent) {
  return `${new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", second: "2-digit", timeZone: "UTC" }).format(new Date(browserEventTime(event)))} TC`;
}
function cleanTornActivitySummary(value: string) {
  return value
    .replace(/\s*(?:Copy\s*)?(?:Save\s*)+$/i, "")
    .replace(/\s*Copy\s*$/i, "")
    .replace(/\s*\d{2}:\d{2}:\d{2}\s*\d{2}\/\d{2}\/\d{2}\s*$/i, "")
    .replace(/\s*\[view\]\s*$/i, "")
    .trim();
}
function transactionLabel(item: Transaction) {
  if (item.type === "deposit") return `${item.details.source ?? "Faction income"} settled`;
  if (item.type === "direct_deposit") return `Deposited to ${item.toAccountName}`;
  if (item.type === "spend") return `Spent from ${item.fromAccountName}`;
  if (item.type === "transfer") return `${item.fromAccountName} to ${item.toAccountName}`;
  if (item.type === "allocation_update") return "Account allocations updated";
  if (item.type === "policy_update") return "Tax policies updated";
  if (item.type === "account_created") return "Account created";
  if (item.type === "account_deleted") return "Account deleted";
  if (item.type === "policy_bootstrap") return "Blood Coven defaults applied";
  return "Treasury updated";
}

function warPayoutEstimates(war: PendingWar, grossAmount: number, taxBps: number) {
  const payouts = new Map<number, number>();
  const eligible = war.members.filter((member) => member.id > 0 && member.attacks > 0);
  const totalAttacks = eligible.reduce((sum, member) => sum + member.attacks, 0);
  if (!totalAttacks) return payouts;
  const playerPool = grossAmount - Math.floor(grossAmount * taxBps / 10000);
  const portions = eligible.map((member) => {
    const exact = playerPool * member.attacks;
    return { member, amount: Math.floor(exact / totalAttacks), remainder: exact % totalAttacks };
  });
  let remainder = playerPool - portions.reduce((sum, item) => sum + item.amount, 0);
  for (const item of [...portions].sort((a, b) => b.remainder - a.remainder || a.member.id - b.member.id)) {
    if (remainder-- <= 0) break;
    item.amount += 1;
  }
  for (const item of portions) payouts.set(item.member.id, item.amount);
  return payouts;
}

export default function BudgetTracker() {
  const [data, setData] = useState<BudgetData>(emptyData);
  const [wars, setWars] = useState<WarStatus>(emptyWars);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const syncingRef = useRef(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [modal, setModal] = useState<Modal>(null);
  const [mainTab, setMainTab] = useState<MainTab>("accounts");
  const [settingsSection, setSettingsSection] = useState<SettingsSection>("accounts");
  const [theme, setTheme] = useState<Theme>("system");
  const [selectedAccountId, setSelectedAccountId] = useState<number | null>(null);
  const [activityFilter, setActivityFilter] = useState("all");
  const [armoryCategory, setArmoryCategory] = useState<ArmoryCategory>("all");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [sourceKey, setSourceKey] = useState("war");
  const [pendingWarId, setPendingWarId] = useState<number | null>(null);
  const [fromAccountId, setFromAccountId] = useState<number | null>(null);
  const [toAccountId, setToAccountId] = useState<number | null>(null);
  const [draftAccounts, setDraftAccounts] = useState<Account[]>([]);
  const [draftPolicies, setDraftPolicies] = useState<Policy[]>([]);
  const [newAccountName, setNewAccountName] = useState("");
  const [tornKey, setTornKey] = useState("");
  const [tornKeyDraft, setTornKeyDraft] = useState("");
  const [reviewValues, setReviewValues] = useState<Record<number, string>>({});
  const [reviewTaxBps, setReviewTaxBps] = useState<Record<number, number>>({});
  const [warTaxMode, setWarTaxMode] = useState<"standard" | "custom">("standard");
  const [customWarTax, setCustomWarTax] = useState("20");
  const [lastSyncAt, setLastSyncAt] = useState("");
  const [bridgeStatus, setBridgeStatus] = useState<BridgeStatus>("checking");
  const [bridgePendingCount, setBridgePendingCount] = useState(0);
  const [bridgeInfo, setBridgeInfo] = useState<BrowserBridgeInfo>(emptyBridge);
  const [accessData, setAccessData] = useState<AccessData>({ leaders: [] });
  const [memberAdmin, setMemberAdmin] = useState<MemberAdminData>({ balances: [], requests: [] });
  const [leaderEmail, setLeaderEmail] = useState("");
  const bridgeImportingRef = useRef(false);

  function flash(message: string) {
    setNotice(message);
    window.setTimeout(() => setNotice(""), 3200);
  }

  async function loadBudget() {
    const response = await fetch("/api/budget", { cache: "no-store" });
    const result = (await response.json()) as BudgetData & { error?: string };
    if (response.status === 403) { window.location.replace("/balance"); return; }
    if (!response.ok) throw new Error(result.error || "Unable to load the treasury.");
    setData(result);
  }

  function applyWarStatus(result: WarStatus) {
    setWars(result);
    setReviewValues((current) => {
      const next = { ...current };
      for (const war of result.pendingWars) if (!next[war.warId]) next[war.warId] = String(war.reviewedValue ?? war.grossEstimate);
      return next;
    });
    setReviewTaxBps((current) => {
      const next = { ...current };
      for (const war of result.pendingWars) if (next[war.warId] === undefined) next[war.warId] = war.reviewedTaxBps ?? 2000;
      return next;
    });
  }

  async function loadWars() {
    const response = await fetch("/api/torn", { cache: "no-store" });
    const result = (await response.json()) as WarStatus & { error?: string };
    if (!response.ok) throw new Error(result.error || "Unable to load war tracking.");
    applyWarStatus(result);
  }

  async function loadBridgeInfo() {
    const response = await fetch("/api/torn-browser", { cache: "no-store" });
    const result = (await response.json()) as BrowserBridgeInfo & { error?: string };
    if (!response.ok) throw new Error(result.error || "Unable to load browser imports.");
    setBridgeInfo(result);
  }

  async function loadAccess() {
    const response = await fetch("/api/access", { cache: "no-store" });
    const result = await response.json() as AccessData & { error?: string };
    if (!response.ok) throw new Error(result.error || "Unable to load leadership access.");
    setAccessData(result);
  }

  async function loadMemberAdmin() {
    const response = await fetch("/api/member-balance", { cache: "no-store" });
    const result = await response.json() as MemberAdminData & { error?: string };
    if (!response.ok) throw new Error(result.error || "Unable to load member balances.");
    setMemberAdmin(result);
  }

  async function importBridgeEvents(events: unknown[]) {
    if (bridgeImportingRef.current || events.length === 0) return;
    bridgeImportingRef.current = true;
    try {
      const response = await fetch("/api/torn-browser", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ events }),
      });
      const result = (await response.json()) as BrowserBridgeInfo & { acceptedKeys?: string[]; error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to import Torn browser activity.");
      setBridgeInfo(result);
      window.postMessage({ channel: BRIDGE_CHANNEL, kind: "ack", eventKeys: result.acceptedKeys ?? [] }, window.location.origin);
      await loadWars();
      await loadMemberAdmin();
    } catch (importError) {
      setError(importError instanceof Error ? importError.message : "Unable to import Torn browser activity.");
    } finally {
      bridgeImportingRef.current = false;
    }
  }

  function checkBridge() {
    setBridgeStatus("checking");
    window.postMessage({ channel: BRIDGE_CHANNEL, kind: "ping" }, window.location.origin);
    window.setTimeout(() => setBridgeStatus((current) => current === "checking" ? "missing" : current), 1800);
  }

  useEffect(() => {
    const task = window.setTimeout(() => {
      const savedTheme = window.localStorage.getItem("blood-coven-theme");
      if (savedTheme === "light" || savedTheme === "dark" || savedTheme === "system") setTheme(savedTheme);
      const savedKey = window.localStorage.getItem(TORN_KEY_STORAGE) ?? window.localStorage.getItem("blood-coven-torn-key") ?? "";
      if (savedKey) window.localStorage.setItem(TORN_KEY_STORAGE, savedKey);
      window.localStorage.removeItem("blood-coven-torn-key");
      setTornKey(savedKey);
      setTornKeyDraft(savedKey);
      Promise.all([loadBudget(), loadWars(), loadMemberAdmin()]).catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Unable to load the treasury."))
        .finally(() => setLoading(false));
    }, 0);
    return () => window.clearTimeout(task);
  // Initial device settings and first data load should run once per page load.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const onBridgeMessage = (event: MessageEvent) => {
      if (event.source !== window || event.origin !== window.location.origin || event.data?.channel !== BRIDGE_CHANNEL) return;
      if (event.data.kind === "ready") {
        setBridgeStatus("connected");
        setBridgePendingCount(Number(event.data.pendingCount) || 0);
      } else if (event.data.kind === "events" && Array.isArray(event.data.events)) {
        setBridgeStatus("connected");
        void importBridgeEvents(event.data.events);
      }
    };
    window.addEventListener("message", onBridgeMessage);
    const initialCheck = window.setTimeout(checkBridge, 0);
    const initialLoad = window.setTimeout(() => void loadBridgeInfo().catch(() => undefined), 0);
    return () => { window.removeEventListener("message", onBridgeMessage); window.clearTimeout(initialCheck); window.clearTimeout(initialLoad); };
  // The userscript handshake is device-local and begins once per page load.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => { document.documentElement.dataset.theme = theme === "system" ? (media.matches ? "dark" : "light") : theme; };
    apply(); media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme]);

  async function syncTorn(apiKey = tornKey, announce = true) {
    if (!apiKey || syncingRef.current) return;
    syncingRef.current = true; setSyncing(true); setError("");
    try {
      const response = await fetch("/api/torn", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "sync", apiKey }) });
      const result = (await response.json()) as TornSyncResult;
      if (!response.ok) throw new Error(result.error || "Unable to sync Torn.");
      applyWarStatus(result);
      await loadBridgeInfo();
      setLastSyncAt(result.syncedAt ?? new Date().toISOString());
      if (announce) {
        const warHistory = result.history?.warBackfill;
        const ocHistory = result.history?.ocBackfill;
        const progress = [
          warHistory && !warHistory.complete ? `war history offset ${warHistory.offset}` : null,
          ocHistory && !ocHistory.complete ? `OC history offset ${ocHistory.offset}` : null,
        ].filter(Boolean).join(" · ");
        if (result.warnings?.length) flash(`Torn data updated. ${result.warnings[0]}`);
        else flash(progress ? `Torn data updated · ${progress}` : "Torn data and history updated.");
      }
    } catch (syncError) {
      setError(syncError instanceof Error ? syncError.message : "Unable to sync Torn.");
    } finally { syncingRef.current = false; setSyncing(false); }
  }

  useEffect(() => {
    if (!tornKey) return;
    const initial = window.setTimeout(() => void syncTorn(tornKey, false), 0);
    const timer = window.setInterval(() => void syncTorn(tornKey, false), 120_000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  // The stored key is the subscription boundary; syncTorn reads current UI state.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tornKey]);

  const totalBalance = useMemo(() => data.accounts.reduce((sum, account) => sum + account.balance, 0), [data.accounts]);
  const filteredTransactions = useMemo(() => {
    if (activityFilter === "all") return data.transactions;
    if (activityFilter === "income") return data.transactions.filter((item) => ["deposit", "direct_deposit"].includes(item.type));
    if (activityFilter === "spend") return data.transactions.filter((item) => item.type === "spend");
    if (activityFilter === "transfer") return data.transactions.filter((item) => item.type === "transfer");
    return data.transactions.filter((item) => !["deposit", "direct_deposit", "spend", "transfer"].includes(item.type));
  }, [activityFilter, data.transactions]);
  const activeTotals = useMemo(() => (wars.activeWar?.members ?? []).reduce((totals, member) => ({
    hits: totals.hits + member.hits, xanax: totals.xanax + member.xanax, refills: totals.refills + member.refills,
    energy: totals.energy + member.energyEstimate,
  }), { hits: 0, xanax: 0, refills: 0, energy: 0 }), [wars.activeWar]);
  const selectedAccount = data.accounts.find((account) => account.id === selectedAccountId);
  const selectedPolicy = data.policies.find((policy) => policy.sourceKey === sourceKey) ?? data.policies[0];
  const grossPreview = parseMoney(amount) || 0;
  const customWarTaxBps = customWarTax.trim() ? Math.round(Number(customWarTax) * 100) : Number.NaN;
  const modalTaxBps = pendingWarId ? (warTaxMode === "standard" ? 2000 : customWarTaxBps) : (selectedPolicy?.taxBps ?? 0);
  const validModalTaxBps = Number.isInteger(modalTaxBps) && modalTaxBps >= 0 && modalTaxBps <= 10000 ? modalTaxBps : 0;
  const factionPreview = Math.floor(grossPreview * validModalTaxBps / 10000);
  const playerPreview = grossPreview - factionPreview;
  const pendingWarPayouts = useMemo(() => new Map(wars.pendingWars.map((war) => {
    const gross = Math.max(0, parseMoney(reviewValues[war.warId] ?? "") || war.reviewedValue || war.grossEstimate);
    const taxBps = reviewTaxBps[war.warId] ?? war.reviewedTaxBps ?? 2000;
    return [war.warId, warPayoutEstimates(war, gross, taxBps)] as const;
  })), [reviewTaxBps, reviewValues, wars.pendingWars]);

  function openModal(next: Modal, accountId?: number, section?: SettingsSection) {
    setError(""); setAmount(""); setNote(""); setPendingWarId(null);
    if (accountId) setSelectedAccountId(accountId);
    if (next === "transfer") {
      const source = accountId ?? data.accounts[0]?.id ?? null;
      setFromAccountId(source); setToAccountId(data.accounts.find((account) => account.id !== source)?.id ?? null);
    }
    if (next === "settings") {
      setSettingsSection(section ?? "accounts");
      setDraftAccounts(data.accounts.map((account) => ({ ...account })));
      setDraftPolicies(data.policies.map((policy) => ({ ...policy })));
      setTornKeyDraft(tornKey);
      void loadAccess().catch(() => undefined);
    }
    setModal(next);
  }

  function openWarReview(war: PendingWar) {
    const taxBps = reviewTaxBps[war.warId] ?? war.reviewedTaxBps ?? 2000;
    setPendingWarId(war.warId); setSourceKey("war"); setAmount(reviewValues[war.warId] ?? String(war.reviewedValue ?? war.grossEstimate));
    setWarTaxMode(taxBps === 2000 ? "standard" : "custom"); setCustomWarTax(String(taxBps / 100));
    setNote(`Ranked war vs ${war.opponentName}`); setError(""); setModal("deposit");
  }
  const closeModal = () => { if (!saving) setModal(null); };

  async function act(payload: Record<string, unknown>, success: string, keepOpen = false) {
    setSaving(true); setError("");
    try {
      const response = await fetch("/api/budget", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
      const result = (await response.json()) as BudgetData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to save your change.");
      setData(result); flash(success); if (!keepOpen) setModal(null); return result;
    } catch (actionError) { setError(actionError instanceof Error ? actionError.message : "Unable to save your change."); return null; }
    finally { setSaving(false); }
  }

  async function submitFinancial(event: FormEvent) {
    event.preventDefault();
    const numericAmount = parseMoney(amount);
    if (modal === "deposit") {
      if (pendingWarId && (!Number.isInteger(modalTaxBps) || modalTaxBps < 0 || modalTaxBps > 10000)) { setError("Enter a tax rate between 0% and 100%."); return; }
      const result = await act({ action: "deposit", amount: numericAmount, sourceKey, note, pendingWarId, taxBpsOverride: pendingWarId ? modalTaxBps : undefined }, pendingWarId ? "War proceeds reviewed and distributed." : "Proceeds settled and distributed.");
      if (result && pendingWarId) { setPendingWarId(null); await loadWars(); }
    } else if (modal === "directDeposit") await act({ action: "directDeposit", accountId: selectedAccountId, amount: numericAmount, note }, "Direct deposit recorded.");
    else if (modal === "spend") await act({ action: "spend", accountId: selectedAccountId, amount: numericAmount, note }, "Expense recorded.");
    else if (modal === "transfer") await act({ action: "transfer", fromAccountId, toAccountId, amount: numericAmount, note }, "Funds transferred.");
  }

  async function warAction(payload: Record<string, unknown>, success?: string) {
    setSaving(true); setError("");
    try {
      const response = await fetch("/api/torn", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
      const result = (await response.json()) as WarStatus & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to update war review.");
      applyWarStatus(result); if (success) flash(success);
    } catch (actionError) { setError(actionError instanceof Error ? actionError.message : "Unable to update war review."); }
    finally { setSaving(false); }
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
  function chooseTheme(next: Theme) { setTheme(next); window.localStorage.setItem("blood-coven-theme", next); }
  function saveTornKey(event: FormEvent) {
    event.preventDefault();
    const next = tornKeyDraft.trim();
    if (!next) { setError("Enter a Torn API key."); return; }
    window.localStorage.setItem(TORN_KEY_STORAGE, next); setTornKey(next); setError(""); flash("Torn key saved on this device. Syncing now.");
  }
  function removeTornKey() {
    window.localStorage.removeItem(TORN_KEY_STORAGE); window.localStorage.removeItem("blood-coven-torn-key"); setTornKey(""); setTornKeyDraft(""); setLastSyncAt(""); flash("Torn key removed from this device.");
  }
  function copySiteLink() { void navigator.clipboard.writeText(window.location.href); flash("Site link copied."); }
  function copyBalanceLink() { void navigator.clipboard.writeText(`${window.location.origin}/balance`); flash("Member balance link copied."); }
  async function updateLeader(action: "add" | "remove", email: string) {
    setSaving(true); setError("");
    try {
      const response = await fetch("/api/access", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action, email }) });
      const result = await response.json() as AccessData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to update access.");
      setAccessData(result); setLeaderEmail(""); flash(action === "add" ? "Leadership access added." : "Leadership access removed.");
    } catch (accessError) { setError(accessError instanceof Error ? accessError.message : "Unable to update access."); }
    finally { setSaving(false); }
  }

  const draftTotalBps = draftAccounts.reduce((sum, account) => sum + account.allocationBps, 0);
  const warEvents = bridgeInfo.recentEvents
    .filter((event) => ["ranked_war_report", "faction_news", "xanax_use"].includes(event.eventType))
    .sort((a, b) => browserEventTime(b) - browserEventTime(a));
  const ocEvents = bridgeInfo.recentEvents.filter((event) => event.eventType === "oc_credit" || event.category === "crimes");
  const armoryEvents = bridgeInfo.recentEvents.filter((event) => ["armory", "armory_movement", "armory_snapshot", "xanax_use"].includes(event.eventType));
  const visibleArmoryItems = armoryCategory === "all" ? bridgeInfo.armoryItems : bridgeInfo.armoryItems.filter((item) => item.category === armoryCategory);
  const armoryCounts = bridgeInfo.armoryItems.reduce<Record<string, number>>((counts, item) => {
    counts[item.category] = (counts[item.category] ?? 0) + 1;
    return counts;
  }, {});
  const openRequests = memberAdmin.requests.filter((request) => ["pending", "approved"].includes(request.status));

  return (
    <main className="app-shell">
      <header className="topbar"><h1>Blood Coven Treasury</h1><div className="topbar-actions"><button className="button button-secondary" onClick={() => openModal("settings")}>Settings</button><button className="button button-primary" onClick={() => openModal("deposit")} disabled={loading}>+ Add proceeds</button></div></header>
      <section className="balance-panel" aria-label="Treasury balance"><span>Total faction funds</span><strong>{loading ? "--" : money.format(totalBalance)}</strong></section>
      <nav className="main-tabs" aria-label="Treasury sections">{(["accounts", "balances", "armory", "wars", "ocs", "history"] as MainTab[]).map((tab) => <button key={tab} className={mainTab === tab ? "active" : ""} onClick={() => setMainTab(tab)}>{tab === "ocs" ? "OCs" : tab.charAt(0).toUpperCase() + tab.slice(1)}</button>)}</nav>
      {notice && <div className="notice" role="status">{notice}</div>}
      {error && !modal && <div className="page-error" role="alert">{error}<button onClick={() => { setError(""); void Promise.all([loadBudget(), loadWars()]); }}>Try again</button></div>}

      {mainTab === "wars" && <section className="war-center tab-panel" aria-labelledby="war-center-title">
        <div className="section-heading"><div><h2 id="war-center-title">Wars</h2>{lastSyncAt && <small>Updated {formatDate(lastSyncAt)}</small>}</div><button className="text-button" onClick={() => tornKey ? void syncTorn() : openModal("settings", undefined, "torn")} disabled={syncing}>{syncing ? "Syncing..." : tornKey ? "Sync Torn" : "Connect Torn"}</button></div>
        {!tornKey && !wars.activeWar && wars.pendingWars.length === 0 && <div className="war-empty"><span>No Torn key connected on this device.</span><button onClick={() => openModal("settings", undefined, "torn")}>Connect a public key</button></div>}
        {wars.activeWar && <article className="active-war-card">
          <div className="war-title"><div><span className="live-dot" />Active ranked war</div><strong>vs {wars.activeWar.opponentName}</strong></div>
          <div className="war-score"><div><span>Blood Coven</span><b>{integer.format(wars.activeWar.ourScore)}</b></div><em>of {integer.format(wars.activeWar.target)}</em><div><span>{wars.activeWar.opponentName}</span><b>{integer.format(wars.activeWar.theirScore)}</b></div></div>
          <div className="war-metrics"><div><span>Tracked hits</span><b>{integer.format(activeTotals.hits)}</b></div><div><span>Hit energy</span><b>{integer.format(activeTotals.energy)}</b></div><div><span>Xanax used</span><b>{integer.format(activeTotals.xanax)}</b></div><div><span>Refills</span><b>{integer.format(activeTotals.refills)}</b></div></div>
          {wars.activeWar.members.length > 0 && <div className="member-table"><div className="member-row member-head"><span>Member</span><span>Hits</span><span>Xanax</span><span>Energy</span></div>{wars.activeWar.members.slice(0, 14).map((member) => <div className="member-row" key={member.id}><strong>{member.name}</strong><span>{member.hits}</span><span>{member.xanax}</span><span>{integer.format(member.energyEstimate)}</span></div>)}</div>}
          <p className="data-note">Public stat changes since tracking began. Xanax counts consumption, not armory withdrawals. Hit energy is estimated at 25 energy per tracked ranked-war hit.</p>
        </article>}

        {wars.pendingWars.length > 0 && <div className="pending-war-list"><h3>Pending review</h3>{wars.pendingWars.map((war) => <article className="pending-war" key={war.warId}>
          <div className="pending-war-main"><div><span className={`result-tag ${war.won ? "won" : "lost"}`}>{war.won ? "Won" : "Lost"}</span><strong>vs {war.opponentName}</strong><small>Finished {formatUnix(war.endedAt)} · War #{war.warId}</small></div><div className="reward-total"><span>Cache market estimate</span><b>{money.format(war.grossEstimate)}</b></div></div>
          <div className="reward-lines">{war.rewards.map((reward) => <span key={reward.id}>{reward.quantity}x {reward.name}<b>{money.format(reward.value)}</b></span>)}</div>
          <div className="review-row"><label><span>Reviewed gross value</span><div className="compact-money"><b>$</b><input inputMode="numeric" value={reviewValues[war.warId] ?? ""} onChange={(event) => setReviewValues((current) => ({ ...current, [war.warId]: event.target.value }))} onBlur={() => { const value = parseMoney(reviewValues[war.warId] ?? ""); if (value > 0) void warAction({ action: "updateReview", warId: war.warId, amount: value, taxBps: reviewTaxBps[war.warId] ?? war.reviewedTaxBps ?? 2000 }); }} /></div></label><button className="button button-primary" onClick={() => openWarReview(war)}>Review and record</button><button className="button button-secondary" onClick={() => void warAction({ action: "dismiss", warId: war.warId }, "War review dismissed.")}>Dismiss</button></div>
          <details><summary>War payout detail</summary><div className="member-table"><div className="member-row payout-head"><span>Member</span><span>Attacks</span><span>Estimated Pay</span><span>Respect</span></div>{war.members.map((member) => <div className="member-row payout-row" key={member.id}><strong>{member.name}</strong><span>{member.attacks}</span><span>{money.format(pendingWarPayouts.get(war.warId)?.get(member.id) ?? 0)}</span><span>{member.score.toFixed(2)}</span></div>)}</div></details>
        </article>)}</div>}
        {warEvents.length > 0 && <section className="event-history"><div className="section-heading"><h2>War activity</h2></div>{warEvents.map((event) => <article className="event-row" key={event.eventKey}><p>{cleanTornActivitySummary(event.summary)}</p><time dateTime={new Date(browserEventTime(event)).toISOString()}>{formatTornEventDate(event)}</time></article>)}</section>}
      </section>}

      {mainTab === "accounts" && <section className="accounts-section tab-panel"><div className="section-heading"><h2>Accounts</h2></div>{loading ? <div className="loading-card">Loading...</div> : <div className="account-list">{data.accounts.map((account) => <article className="account-row" key={account.id}><div className="account-title"><h3>{account.name}</h3><span>{account.allocationBps / 100}%</span></div><strong className="account-balance">{money.format(account.balance)}</strong><div className="account-actions"><button className="account-action deposit-action" onClick={() => openModal("directDeposit", account.id)} aria-label={`Deposit directly to ${account.name}`} title="Direct deposit"><span aria-hidden="true">↘$</span></button><button className="account-action transfer-action" onClick={() => openModal("transfer", account.id)} aria-label={`Transfer from ${account.name}`} title="Transfer"><span aria-hidden="true">⇄</span></button><button className="account-action spend-action" onClick={() => openModal("spend", account.id)} aria-label={`Spend from ${account.name}`} title="Spend"><span aria-hidden="true">$↗</span></button></div></article>)}</div>}</section>}

      {mainTab === "balances" && <section className="balances-section tab-panel">
        {openRequests.length > 0 && <div className="request-queue"><div className="section-heading"><h2>Balance requests</h2><span>{openRequests.length} open</span></div>{openRequests.map((request) => <article className="request-row" key={request.id}><div><strong>{request.memberName}</strong><p>{request.note || "Member balance request"}</p><time>{formatDate(request.createdAt)} · {request.deliveryPreference === "online" ? "Online only" : request.deliveryPreference === "online_or_travel" ? "Online or travelling" : "Send if offline"}</time></div><div><b>{money.format(request.amount)}</b><span>{request.status}</span></div></article>)}</div>}
        <div className="balance-register"><div className="section-heading"><div><h2>Member balances</h2><small>Updated by visitors to Torn&apos;s faction Funds page</small></div></div>{memberAdmin.balances.length === 0 ? <div className="empty-state">No member balances imported yet.</div> : memberAdmin.balances.map((member) => <div className="balance-register-row" key={member.memberName}><strong>{member.memberName}</strong><span>{money.format(member.balance)}</span></div>)}</div>
      </section>}

      {mainTab === "armory" && <section className="armory-section tab-panel">
        <div className="section-heading"><div><h2>Faction armory</h2><small>Latest Torn inventory snapshots by category, with tracked activity applied between scans</small></div></div>
        <div className="activity-filters" role="tablist" aria-label="Armory category">
          {ARMORY_TABS.map((tab) => {
            const count = tab.key === "all" ? bridgeInfo.armoryItems.length : (armoryCounts[tab.key] ?? 0);
            return <button key={tab.key} role="tab" aria-selected={armoryCategory === tab.key} className={armoryCategory === tab.key ? "active" : ""} onClick={() => setArmoryCategory(tab.key)}>{tab.label}{count > 0 ? ` (${count})` : ""}</button>;
          })}
        </div>
        {bridgeInfo.armoryItems.length === 0 ? <div className="empty-state event-empty">Open a Torn faction Armory category and click the movable BC ↻ button to capture its current inventory.</div> : visibleArmoryItems.length === 0 ? <div className="empty-state event-empty">No current items have been captured in this category. Scan that Torn Armory tab with BC ↻ to populate it.</div> : <div className="vault-grid">{visibleArmoryItems.map((item) => <article className="vault-row" key={`${item.category}:${item.itemName}`}><div><strong>{item.itemName}</strong><small>{item.category} · {item.source === "snapshot" ? "Torn snapshot" : item.source}</small></div><b>{integer.format(item.quantity)}</b></article>)}</div>}
        {armoryEvents.length > 0 && <div className="event-history armory-history"><div className="section-heading"><h2>Armory activity</h2></div>{armoryEvents.slice(0, 40).map((event) => <article className="event-row" key={event.eventKey}><p>{cleanTornActivitySummary(event.summary)}</p><time>{formatTornEventDate(event)}</time></article>)}</div>}
      </section>}

      {mainTab === "history" && <section className="activity-section tab-panel">
        <div className="section-heading"><h2>Transaction history</h2></div><div className="activity-filters" role="group" aria-label="Filter ledger">{["all", "income", "spend", "transfer", "changes"].map((filter) => <button key={filter} className={activityFilter === filter ? "active" : ""} onClick={() => setActivityFilter(filter)}>{filter === "transfer" ? "Moves" : filter.charAt(0).toUpperCase() + filter.slice(1)}</button>)}</div><div className="activity-list">{filteredTransactions.length === 0 ? <div className="empty-state">No matching history.</div> : filteredTransactions.slice(0, 80).map((item) => <article className="activity-item" key={item.id}><div><strong>{transactionLabel(item)}</strong><p>{item.note}</p><time>{formatDate(item.createdAt)} · {item.actorName ?? "Legacy entry"}</time>{item.type === "deposit" && item.details.allocations && <details><summary>View settlement</summary><span>Gross proceeds<b>{money.format(item.details.grossAmount ?? item.amount)}</b></span><span>Player payout<b>{money.format(item.details.playerPayout ?? 0)}</b></span><span>Faction share ({(item.details.taxBps ?? 10000) / 100}%)<b>{money.format(item.details.factionShare ?? item.amount)}</b></span>{item.details.allocations.map((split) => <span className="account-split" key={split.name}>{split.name}<b>{money.format(split.amount)}</b></span>)}</details>}</div>{item.amount > 0 && <b className={`activity-amount ${item.type}`}>{["deposit", "direct_deposit"].includes(item.type) ? "+" : item.type === "spend" ? "-" : ""}{money.format(item.amount)}</b>}</article>)}</div>
      </section>}

      {mainTab === "ocs" && <section className="oc-section tab-panel"><div className="section-heading"><div><h2>Organized crimes</h2><small>Completed OC history is durable server data; browser scans can fill gaps from rendered Torn pages</small></div></div>{bridgeInfo.ocHoldings.length === 0 ? <div className="empty-state event-empty">Sync with a Minimal-or-higher Torn key that has faction API access, or open a completed OC page and click BC ↻.</div> : <div className="oc-holdings">{bridgeInfo.ocHoldings.map((holding) => <article className="oc-holding" key={holding.eventKey}><div><span className={`result-tag ${holding.status === "held" ? "won" : ""}`}>{holding.status === "held" ? "In custody" : holding.status}</span><strong>{holding.crimeName}</strong><small>{holding.occurredAt ? formatDate(holding.occurredAt) : formatDate(holding.createdAt)}</small></div><div className="oc-assets">{holding.cashAmount > 0 && <b>{money.format(holding.cashAmount)}</b>}{holding.items.map((item) => <span key={item.name}>{item.quantity}x {item.name}</span>)}</div></article>)}</div>}{ocEvents.length > 0 && <div className="event-history oc-history"><div className="section-heading"><h2>OC activity</h2></div>{ocEvents.slice(0, 60).map((event) => <article className="event-row" key={event.eventKey}><div><strong>{String(event.payload.crimeName ?? event.payload.memberName ?? "Organized crime")}</strong><p>{cleanTornActivitySummary(event.summary)}</p></div>{Number(event.payload.amount) > 0 && <b>{money.format(Number(event.payload.amount))}</b>}</article>)}</div>}</section>}

      {modal && <div className="modal-backdrop" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && closeModal()}><section className={`modal ${modal === "settings" ? "modal-settings" : ""}`} role="dialog" aria-modal="true" aria-labelledby="modal-title"><button className="modal-close" onClick={closeModal} aria-label="Close">×</button>
        {modal === "settings" ? <div className="settings-layout"><nav className="settings-nav" aria-label="Settings sections">{(["accounts", "policies", "torn", "script", "access", "appearance"] as SettingsSection[]).map((section) => <button key={section} className={settingsSection === section ? "active" : ""} onClick={() => { setError(""); setSettingsSection(section); }}>{section === "torn" ? "Torn API" : section === "script" ? "Browser script" : section.charAt(0).toUpperCase() + section.slice(1)}</button>)}</nav><div className="settings-content">
          {settingsSection === "accounts" && <form onSubmit={saveAllocations}><h2 id="modal-title">Accounts</h2><p className="modal-intro">Divide the faction share between treasury accounts.</p>{draftTotalBps !== 10000 && <p className="allocation-warning">Allocations must total 100%. Currently {draftTotalBps / 100}%.</p>}<div className="allocation-editor">{draftAccounts.map((account) => <div className="allocation-row" key={account.id}><label><span>Account</span><input value={account.name} maxLength={50} onChange={(event) => setDraftAccounts((current) => current.map((item) => item.id === account.id ? { ...item, name: event.target.value } : item))} /></label><label className="percent-field"><span>Share</span><div><input type="number" min="0" max="100" step="0.01" value={account.allocationBps / 100} onChange={(event) => setDraftAccounts((current) => current.map((item) => item.id === account.id ? { ...item, allocationBps: Math.round(Number(event.target.value) * 100) } : item))} /><b>%</b></div></label><button type="button" className="delete-button" onClick={() => void deleteAccount(account)} disabled={account.balance !== 0 || saving}>×</button></div>)}</div><div className="add-account-row"><input value={newAccountName} onChange={(event) => setNewAccountName(event.target.value)} placeholder="New account name" maxLength={50} /><button type="button" onClick={() => void addAccount()} disabled={!newAccountName.trim() || saving}>Add</button></div>{error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button className="button button-primary" disabled={saving || draftTotalBps !== 10000}>{saving ? "Saving..." : "Save accounts"}</button></div></form>}
          {settingsSection === "policies" && <form onSubmit={savePolicies}><h2 id="modal-title">Tax policies</h2><p className="modal-intro">These percentages determine the faction share before account allocation.</p><div className="policy-editor">{draftPolicies.map((policy) => <label key={policy.sourceKey}><span>{policy.label}</span><div><input type="number" min="0" max="100" step="0.01" value={policy.taxBps / 100} onChange={(event) => setDraftPolicies((current) => current.map((item) => item.sourceKey === policy.sourceKey ? { ...item, taxBps: Math.round(Number(event.target.value) * 100) } : item))} /><b>%</b></div></label>)}</div>{error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button className="button button-primary" disabled={saving}>{saving ? "Saving..." : "Save policies"}</button></div></form>}
          {settingsSection === "torn" && <form onSubmit={saveTornKey}><h2 id="modal-title">Torn API</h2><p className="modal-intro">A Public-level key covers member verification, ranked-war history, reward valuation, and public member statistics. A Minimal-or-higher key with faction API access also backfills completed OC history.</p><label className="field"><span>Personal API key</span><input type="password" autoComplete="off" value={tornKeyDraft} onChange={(event) => setTornKeyDraft(event.target.value)} placeholder="Paste a Torn API key" /></label><p className="settings-note api-note">The key is stored only in this browser. It is sent transiently for Torn requests and is never written to the treasury database. Automatic updates run every two minutes while this page is open; each sync advances older war and OC history in bounded batches.</p>{error && <p className="form-error" role="alert">{error}</p>}<div className="api-actions"><button className="button button-primary">{tornKey ? "Update key" : "Save and connect"}</button>{tornKey && <><button type="button" className="button button-secondary" onClick={() => void syncTorn()} disabled={syncing}>{syncing ? "Syncing..." : "Sync now"}</button><button type="button" className="text-button danger-text" onClick={removeTornKey}>Remove from device</button></>}</div>{lastSyncAt && <small className="sync-status">Last synced {formatDate(lastSyncAt)}</small>}</form>}
          {settingsSection === "script" && <section><h2 id="modal-title">Torn browser script</h2><p className="modal-intro">The userscript watches Torn automatically and adds a movable BC ↻ control. Click it on Funds, Armory, completed OC, or ranked-war pages to force a scan and immediately open the Treasury bridge for upload.</p><div className={`bridge-status ${bridgeStatus}`}><span className="bridge-dot" /><div><strong>{bridgeStatus === "connected" ? "Browser script connected" : bridgeStatus === "checking" ? "Checking for browser script..." : "Browser script not detected"}</strong><small>{bridgeStatus === "connected" ? `${bridgePendingCount} event${bridgePendingCount === 1 ? "" : "s"} waiting to import` : bridgeStatus === "missing" ? "No compatible userscript responded on this page." : "Waiting for a Tampermonkey-compatible bridge response."}</small></div></div><p className="settings-note">The browser event journal is only an import/audit channel. Member balances, Armory snapshots, OCs, wars, and treasury account values are stored separately on the server, so trimming old browser events does not roll those values back.</p><div className="api-actions"><a className="button button-primary" href="/blood-coven-treasury.user.js" target="_blank" rel="noreferrer">Install script</a><button type="button" className="button button-secondary" onClick={checkBridge}>Check again</button></div>{bridgeInfo.lastImportedAt && <p className="bridge-import-summary">Last import {formatDate(bridgeInfo.lastImportedAt)} · {integer.format(bridgeInfo.totalEvents)} retained browser events</p>}{bridgeInfo.recentEvents.length > 0 && <div className="bridge-events" aria-label="Recent browser imports">{bridgeInfo.recentEvents.slice(0, 5).map((event) => <div key={event.eventKey}><span>{event.category.replace(/_/g, " ")}</span><strong>{event.summary}</strong><small>{formatDate(event.createdAt)}</small></div>)}</div>}</section>}
          {settingsSection === "access" && <section><h2 id="modal-title">Access</h2><p className="modal-intro">Site sharing controls who may open the app. Treasury roles below control who can see financial data.</p><div className="access-card"><span>Signed in as</span><strong>{data.currentUser?.name ?? "Authorized member"}</strong><small>{data.currentUser?.email}</small></div><div className="leader-editor"><h3>Leadership</h3>{accessData.leaders.map((leader) => <div className="leader-row" key={leader.email}><div><strong>{leader.name || leader.email}</strong><small>{leader.email}</small></div><button type="button" className="text-button danger-text" onClick={() => void updateLeader("remove", leader.email)} disabled={leader.email === data.currentUser?.email || saving}>Remove</button></div>)}<div className="add-leader"><input type="email" value={leaderEmail} onChange={(event) => setLeaderEmail(event.target.value)} placeholder="leader@example.com" /><button type="button" className="button button-secondary" onClick={() => void updateLeader("add", leaderEmail)} disabled={!leaderEmail.trim() || saving}>Add leader</button></div></div>{error && <p className="form-error" role="alert">{error}</p>}<p className="settings-note">Add the same email in the site sharing controls. Members without a leadership role are sent to the balance-only page.</p><div className="api-actions"><button type="button" className="button button-secondary" onClick={copySiteLink}>Copy treasury link</button><button type="button" className="button button-secondary" onClick={copyBalanceLink}>Copy member balance link</button></div></section>}
          {settingsSection === "appearance" && <section><h2 id="modal-title">Appearance</h2><p className="modal-intro">Theme preference is saved on this device.</p><div className="theme-options">{(["light", "dark", "system"] as Theme[]).map((option) => <button key={option} className={theme === option ? "active" : ""} onClick={() => chooseTheme(option)}><strong>{option.charAt(0).toUpperCase() + option.slice(1)}</strong><small>{option === "system" ? "Match this device" : `Always use ${option} mode`}</small></button>)}</div></section>}
        </div></div> : <form onSubmit={submitFinancial}>
          <h2 id="modal-title">{modal === "deposit" ? pendingWarId ? "Review war proceeds" : "Record proceeds" : modal === "directDeposit" ? `Deposit to ${selectedAccount?.name ?? "account"}` : modal === "spend" ? `Spend from ${selectedAccount?.name ?? "account"}` : "Transfer funds"}</h2>
          <p className="modal-intro">{modal === "deposit" ? pendingWarId ? "Confirm the actual gross value after cache sales. Only the faction share is distributed to accounts." : "Enter the full gross value. The policy calculates the player payout and deposits only the faction share." : modal === "directDeposit" ? "Add money directly to this account without applying a proceeds policy." : modal === "spend" ? `Available: ${money.format(selectedAccount?.balance ?? 0)}` : "Move money between treasury accounts."}</p>
          {modal === "deposit" && (pendingWarId ? <><label className="field"><span>Tax Rate</span><select value={warTaxMode} onChange={(event) => { const mode = event.target.value === "custom" ? "custom" : "standard"; setWarTaxMode(mode); const nextTaxBps = mode === "standard" ? 2000 : (Number.isInteger(customWarTaxBps) ? customWarTaxBps : 2000); setReviewTaxBps((current) => ({ ...current, [pendingWarId]: nextTaxBps })); }}><option value="standard">20% (default)</option><option value="custom">Custom</option></select></label>{warTaxMode === "custom" && <label className="field"><span>Custom tax rate</span><div className="percent-input"><input type="number" min="0" max="100" step="0.01" value={customWarTax} onChange={(event) => { const value = event.target.value; setCustomWarTax(value); const nextTaxBps = value.trim() ? Math.round(Number(value) * 100) : Number.NaN; if (Number.isInteger(nextTaxBps) && nextTaxBps >= 0 && nextTaxBps <= 10000) setReviewTaxBps((current) => ({ ...current, [pendingWarId]: nextTaxBps })); }} /><b>%</b></div></label>}</> : <label className="field"><span>Proceeds type</span><select value={sourceKey} onChange={(event) => setSourceKey(event.target.value)}>{data.policies.map((policy) => <option key={policy.sourceKey} value={policy.sourceKey}>{policy.label} — {policy.taxBps / 100}% faction</option>)}</select></label>)}
          {modal === "transfer" && <div className="transfer-grid"><label><span>From</span><select value={fromAccountId ?? ""} onChange={(event) => setFromAccountId(Number(event.target.value))}>{data.accounts.map((account) => <option key={account.id} value={account.id}>{account.name} — {money.format(account.balance)}</option>)}</select></label><span>→</span><label><span>To</span><select value={toAccountId ?? ""} onChange={(event) => setToAccountId(Number(event.target.value))}>{data.accounts.map((account) => <option key={account.id} value={account.id}>{account.name}</option>)}</select></label></div>}
          <label className="field"><span>{modal === "deposit" ? "Gross amount" : "Amount"}</span><div className="money-input"><b>$</b><input autoFocus inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0" required /></div></label>
          <label className="field"><span>{modal === "deposit" ? "Description" : "Note"}</span><input value={note} onChange={(event) => setNote(event.target.value)} maxLength={160} placeholder={modal === "deposit" ? "e.g. Silver ranked war" : modal === "spend" ? "e.g. Xanax restock" : modal === "directDeposit" ? "e.g. opening balance adjustment" : "Optional transfer note"} required={modal === "spend"} /></label>
          {modal === "deposit" && <div className="settlement-preview"><div><span>Gross</span><b>{money.format(grossPreview)}</b></div><div><span>Player payout</span><b>{money.format(playerPreview)}</b></div><div className="faction-row"><span>Faction share ({validModalTaxBps / 100}%)</span><b>{money.format(factionPreview)}</b></div><hr />{data.accounts.map((account) => <div className="account-split" key={account.id}><span>{account.name} <small>{account.allocationBps / 100}%</small></span><b>{money.format(Math.floor(factionPreview * account.allocationBps / 10000))}</b></div>)}</div>}
          {error && <p className="form-error" role="alert">{error}</p>}<div className="modal-actions"><button type="button" className="button button-secondary" onClick={closeModal}>Cancel</button><button className="button button-primary" disabled={saving || !amount}>{saving ? "Saving..." : modal === "deposit" ? pendingWarId ? "Record reviewed proceeds" : "Record and distribute" : modal === "directDeposit" ? "Record deposit" : modal === "spend" ? "Record expense" : "Transfer"}</button></div>
        </form>}
      </section></div>}
    </main>
  );
}
