"use client";

import { FormEvent, useEffect, useState } from "react";

type MemberData = {
  member: { id: number; name: string };
  balance: number;
  earnedTotal: number;
  paidTotal: number;
  updatedAt: string | null;
  requests: Array<{ id: number; amount: number; status: string; note: string; createdAt: string }>;
  entries: Array<{ amount: number; kind: string; source: string; summary: string; occurredAt: string | null; createdAt: string }>;
};

const money = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });
const parseMoney = (value: string) => Number(value.replace(/[$,\s]/g, ""));

export default function MemberBalance() {
  const [apiKey, setApiKey] = useState("");
  const [data, setData] = useState<MemberData | null>(null);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    const task = window.setTimeout(() => setApiKey(window.localStorage.getItem("blood-coven-member-key") ?? ""), 0);
    return () => window.clearTimeout(task);
  }, []);

  async function send(action: "verify" | "request") {
    setSaving(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/member-balance", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ action, apiKey, amount: parseMoney(amount), note }),
      });
      const result = await response.json() as MemberData & { error?: string };
      if (!response.ok) throw new Error(result.error || "Unable to load your balance.");
      window.localStorage.setItem("blood-coven-member-key", apiKey);
      setData(result); setAmount(String(result.balance));
      if (action === "request") setNotice("Your payout request is queued for leadership review.");
    } catch (requestError) { setError(requestError instanceof Error ? requestError.message : "Unable to load your balance."); }
    finally { setSaving(false); }
  }

  function verify(event: FormEvent) { event.preventDefault(); void send("verify"); }
  function requestPayout(event: FormEvent) { event.preventDefault(); void send("request"); }
  function disconnect() { window.localStorage.removeItem("blood-coven-member-key"); setApiKey(""); setData(null); setAmount(""); setError(""); }

  return <main className="member-shell">
    <header className="member-header"><h1>Blood Coven balance</h1>{data && <button className="text-button" onClick={disconnect}>Use another key</button>}</header>
    {!data ? <form className="member-card" onSubmit={verify}>
      <span className="eyebrow">Member access</span><h2>Check your faction balance</h2>
      <p>Enter your Torn Public API key to verify your identity and current Blood Coven membership. The key stays on this device and is never stored by the treasury.</p>
      <label className="field"><span>Public API key</span><input type="password" autoComplete="off" value={apiKey} onChange={(event) => setApiKey(event.target.value)} required /></label>
      {error && <p className="form-error" role="alert">{error}</p>}
      <button className="button button-primary" disabled={saving || !apiKey}>{saving ? "Verifying..." : "Verify membership"}</button>
    </form> : <>
      <section className="member-balance"><span>{data.member.name}</span><strong>{money.format(data.balance)}</strong><small>Available faction balance</small></section>
      <form className="member-card" onSubmit={requestPayout}>
        <h2>Request payout</h2>
        <label className="field"><span>Amount</span><div className="money-input"><b>$</b><input inputMode="numeric" value={amount} onChange={(event) => setAmount(event.target.value)} required /></div></label>
        <label className="field"><span>Note (optional)</span><input value={note} onChange={(event) => setNote(event.target.value)} maxLength={160} placeholder="Anything leadership should know" /></label>
        {notice && <p className="member-notice" role="status">{notice}</p>}{error && <p className="form-error" role="alert">{error}</p>}
        <button className="button button-primary" disabled={saving || data.balance <= 0}>{saving ? "Sending..." : "Request balance"}</button>
      </form>
      {data.requests.length > 0 && <section className="member-card member-history"><h2>Requests</h2>{data.requests.map((item) => <div key={item.id}><strong>{money.format(item.amount)}</strong><span>{item.status}</span></div>)}</section>}
    </>}
  </main>;
}
