"use client";

import { FormEvent, useEffect, useRef, useState } from "react";

type DeliveryPreference = "offline" | "online" | "online_or_travel";
type ArmoryBalance = { balance: number; source: "armory"; updatedAt: string };
type BridgeEvent = { eventKey: string; eventType: string; sourceUrl: string; payload: { members?: Array<{ name?: unknown; balance?: unknown }> } };
type MemberData = {
  member: { id: number; name: string };
  balance: number;
  earnedTotal: number;
  paidTotal: number;
  observedAt?: string | null;
  updatedAt: string | null;
  syncToken?: string;
  requests: Array<{ id: number; amount: number; status: string; note: string; deliveryPreference: DeliveryPreference; createdAt: string }>;
  entries: Array<{ amount: number; kind: string; source: string; summary: string; occurredAt: string | null; createdAt: string }>;
};

const BRIDGE_CHANNEL = "blood-coven-treasury-bridge-v1";
const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const integer = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
const parseMoney = (value: string) => Number(value.replace(/[$,\s]/g, ""));

export default function MemberBalance() {
  const [apiKey, setApiKey] = useState("");
  const [data, setData] = useState<MemberData | null>(null);
  const [observedBalance, setObservedBalance] = useState<ArmoryBalance | null>(null);
  const observedRef = useRef<ArmoryBalance | null>(null);
  const syncBootstrapRef = useRef(false);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [deliveryPreference, setDeliveryPreference] = useState<DeliveryPreference>("offline");
  const [saving, setSaving] = useState(false);
  const [restoring, setRestoring] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  async function send(
    action: "verify" | "request",
    requestedAmount = 0,
    keyOverride = apiKey,
    observation = observedRef.current,
    issueSyncToken = false,
  ) {
    setSaving(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/member-balance", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({
          action,
          apiKey: keyOverride,
          amount: requestedAmount,
          note,
          deliveryPreference,
          observedBalance: observation?.balance,
          observedAt: observation?.updatedAt,
          balanceSource: observation?.source,
          issueSyncToken,
        }),
      });
      const result = await response.json() as MemberData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to load your balance.");
      window.localStorage.setItem("blood-coven-member-key", keyOverride);
      setApiKey(keyOverride); setData(result);
      if (result.syncToken) {
        window.postMessage({ channel: BRIDGE_CHANNEL, kind: "installSyncToken", token: result.syncToken }, window.location.origin);
      }
      if (action === "request") { setAmount(""); setNotice("Your balance request is queued for leadership review."); }
    } catch (requestError) { setError(requestError instanceof Error ? requestError.message : "Unable to load your balance."); }
    finally { setSaving(false); setRestoring(false); }
  }

  async function importBalanceSnapshots(events: BridgeEvent[], key: string) {
    const snapshots = events.filter((event) => event.eventType === "member_balance_snapshot").slice(0, 20);
    if (!key || snapshots.length === 0) return;
    try {
      const response = await fetch("/api/member-balance", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "importSnapshots", apiKey: key, events: snapshots }),
      });
      const result = await response.json() as MemberData & { acceptedKeys?: string[]; error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to import faction balances.");
      setData(result);
      window.postMessage({ channel: BRIDGE_CHANNEL, kind: "ack", eventKeys: result.acceptedKeys ?? [] }, window.location.origin);
    } catch (importError) { setError(importError instanceof Error ? importError.message : "Unable to import faction balances."); }
  }

  useEffect(() => {
    const onBridgeMessage = (event: MessageEvent) => {
      if (event.source !== window || event.origin !== window.location.origin || event.data?.channel !== BRIDGE_CHANNEL) return;
      if (event.data?.kind === "ready") {
        const savedKey = window.localStorage.getItem("blood-coven-member-key") ?? "";
        if (event.data.syncTokenReady === false && savedKey && !syncBootstrapRef.current) {
          syncBootstrapRef.current = true;
          void send("verify", 0, savedKey, observedRef.current, true);
        }
        return;
      }
      if (event.data?.kind === "syncTokenInstalled") {
        syncBootstrapRef.current = true;
        return;
      }
      if (event.data?.kind === "events" && Array.isArray(event.data.events)) {
        const savedKey = window.localStorage.getItem("blood-coven-member-key") ?? "";
        if (savedKey) void importBalanceSnapshots(event.data.events as BridgeEvent[], savedKey);
        return;
      }
      if (event.data?.kind !== "armoryBalance") return;
      const value = event.data.balance as ArmoryBalance | null;
      if (!value || value.source !== "armory" || !Number.isFinite(Number(value.balance))) return;
      if (observedRef.current?.updatedAt === value.updatedAt && observedRef.current.balance === Number(value.balance)) return;
      const observation = { ...value, balance: Math.max(0, Math.trunc(Number(value.balance))) };
      observedRef.current = observation; setObservedBalance(observation);
      const savedKey = window.localStorage.getItem("blood-coven-member-key") ?? "";
      if (savedKey) void send("verify", 0, savedKey, observation);
    };
    window.addEventListener("message", onBridgeMessage);
    window.postMessage({ channel: BRIDGE_CHANNEL, kind: "ping" }, window.location.origin);
    const restoreTask = window.setTimeout(() => {
      const savedKey = window.localStorage.getItem("blood-coven-member-key") ?? "";
      setApiKey(savedKey);
      if (savedKey) void send("verify", 0, savedKey);
      else setRestoring(false);
    }, 0);
    return () => { window.clearTimeout(restoreTask); window.removeEventListener("message", onBridgeMessage); };
  // Restore the device-local key and userscript balance once on popup load.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function verify(event: FormEvent) { event.preventDefault(); syncBootstrapRef.current = true; void send("verify", 0, apiKey, observedRef.current, true); }
  function requestPartial(event: FormEvent) { event.preventDefault(); void send("request", parseMoney(amount)); }
  function disconnect() {
    window.localStorage.removeItem("blood-coven-member-key");
    setApiKey(""); setData(null); setAmount(""); setError(""); setNotice(""); setRestoring(false);
  }

  const serverObservedAt = Date.parse(data?.observedAt ?? data?.updatedAt ?? "") || 0;
  const localObservedAt = Date.parse(observedBalance?.updatedAt ?? "") || 0;
  const displayBalance = data && observedBalance && localObservedAt > serverObservedAt ? observedBalance.balance : (data?.balance ?? observedBalance?.balance ?? 0);

  return <main className="member-shell">
    <header className="member-header"><h1>Blood Coven balance</h1>{data && <button className="text-button" onClick={disconnect}>Use another key</button>}</header>
    {restoring ? <section className="member-card member-loading">Loading balance...</section> : !data ? <form className="member-card" onSubmit={verify}>
      <h2>Verify membership</h2>
      <p>Enter your Torn Public API key once. It remains stored only in this browser and will be reused automatically. If the Blood Coven userscript is installed, verification also authorizes that installation to contribute and receive live balance updates.</p>
      <label className="field"><span>Public API key</span><input type="password" autoComplete="off" value={apiKey} onChange={(event) => setApiKey(event.target.value)} required /></label>
      {error && <p className="form-error" role="alert">{error}</p>}
      <button className="button button-primary" disabled={saving || !apiKey}>{saving ? "Verifying..." : "Verify membership"}</button>
    </form> : <>
      <section className="member-balance"><strong>{money.format(displayBalance)}</strong></section>
      <section className="member-card balance-request-card">
        <h2>Balance Request</h2>
        <label className="field"><span>Delivery preference</span><select value={deliveryPreference} onChange={(event) => setDeliveryPreference(event.target.value as DeliveryPreference)}><option value="offline">Send if offline</option><option value="online">Send only if Online</option><option value="online_or_travel">Send if Online or Travelling</option></select></label>
        <button type="button" className="button button-primary full-balance-button" disabled={saving || displayBalance <= 0} onClick={() => void send("request", displayBalance)}>{saving ? "Sending..." : "Request Full Balance"}</button>
        <div className="request-separator"><span>or request an amount</span></div>
        <form onSubmit={requestPartial}>
          <label className="field"><span>Amount</span><div className="money-input"><b>$</b><input inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value)} onBlur={() => { const value = parseMoney(amount); if (value > 0) setAmount(integer.format(value)); }} placeholder="0" required /></div></label>
          <button className="button button-secondary partial-request-button" disabled={saving || parseMoney(amount) <= 0}>{saving ? "Sending..." : "Request"}</button>
        </form>
        <label className="field request-note"><span>Note (optional)</span><input value={note} onChange={(event) => setNote(event.target.value)} maxLength={160} placeholder="Anything leadership should know" /></label>
        {notice && <p className="member-notice" role="status">{notice}</p>}{error && <p className="form-error" role="alert">{error}</p>}
      </section>
      {data.requests.length > 0 && <section className="member-card member-history"><h2>Requests</h2>{data.requests.map((item) => <div key={item.id}><strong>{money.format(item.amount)}</strong><span>{item.status}</span></div>)}</section>}
    </>}
  </main>;
}
