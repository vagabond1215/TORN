"use strict";
/* Native-browser fixture, synthetic namespace only. Two separate handles
 * in one context exercise native Web Locks, not independent browser tabs.
 * No API calls or production storage keys are used.
 */
(async()=>{
 const out=document.getElementById("result");
 const assert=(ok,msg)=>{if(!ok)throw Error(msg);};
 const rejects=async(fn,re)=>{let e;try{await fn()}catch(err){e=err}assert(e&&re.test(e.message),"Expected "+re+"; got "+e);};
 let ns=null,names=()=>[];
 try{
  assert(!!crypto?.subtle&&!!crypto.randomUUID,"Native Web Crypto unavailable");
  assert(!!navigator.locks?.request,"Native Web Locks unavailable");
  ns="torn-capture-fixture:"+crypto.randomUUID()+":";
  names=()=>Array.from({length:localStorage.length},(_,i)=>localStorage.key(i)).filter(k=>k?.startsWith(ns));
  const storage=()=>({get length(){return names().length},key:i=>names()[i]?.slice(ns.length)??null,getItem:k=>localStorage.getItem(ns+k),setItem:(k,v)=>localStorage.setItem(ns+k,v),removeItem:k=>localStorage.removeItem(ns+k)});
  const locks={request:(name,opts,fn)=>navigator.locks.request(ns+name,opts,fn)};
  const id="999999992",prefix="torn-city-guide:",r=tornAccountRevisions,a=tornAccountStorage,l=tornCalendarLineage,g=tornGuardedCapture;
  const cal=prefix+"activity-events:"+id,ledger=prefix+"activity-spend-ledger:"+id,lk=prefix+"calendar-lineage:v1:"+id,note=prefix+"v1:profile:"+id+":notes:gym",mk=r.key(id);
  const s=storage(),other=storage(),yes=()=>true,legacy={mode:"legacy"},protectedMode={mode:"protected"};
  s.setItem(cal,"[]");s.setItem(ledger,"[]");s.setItem(note,"A");
  const first=await g.capture(s,id,yes,locks,legacy);
  const lineage=JSON.stringify(await l.initialize(first,id));
  s.setItem(lk,lineage);
  s.setItem(note,"B");
  const results=await Promise.all([g.capture(s,id,yes,locks,protectedMode),g.capture(other,id,yes,locks,protectedMode)]);
  assert(results.filter(x=>x.changed).length===1,"Concurrent captures did not serialize");
  const snap={...a.snapshot(s,id),manifest:r.read(s,id)};
  await r.verify(snap.manifest,snap.records,id);
  await l.verify(JSON.parse(lineage),snap,id);
  assert(s.getItem(lk)===lineage,"Lineage changed during unrelated capture");
  const prior=s.getItem(mk);
  const event=JSON.stringify([{id:"synthetic",kind:"personal",title:"Fixture",start:1000,end:2000,blocking:false,source:"manual"}]);
  s.setItem(cal,event);
  await rejects(()=>g.capture(s,id,yes,locks,protectedMode),/digest/);
  assert(s.getItem(mk)===prior,"Unauthorized calendar change advanced manifest");
  s.setItem(cal,"[]");
  s.setItem(a.journalKey(id),"{}");
  await rejects(()=>g.capture(s,id,yes,locks,protectedMode),/journal pending/);
  s.removeItem(a.journalKey(id));
  // Simulate same-player rotation while real Web Crypto is in flight.
  let current=true;
  const digest=async v=>{const bytes=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));current=false;return Array.from(new Uint8Array(bytes),x=>x.toString(16).padStart(2,"0")).join("");};
  await rejects(()=>g.capture(s,id,()=>current,locks,{...protectedMode,digest}),/epoch/);
  assert(s.getItem(mk)===prior,"Stale epoch advanced manifest");
  a.trackedWrite(s,id,note,null);
  const deleted=await g.capture(s,id,yes,locks,protectedMode);
  assert(deleted.manifest.entries.find(e=>e.section==="notes:gym").digest===null,"Ordinary tombstone missing");
  assert(s.getItem(lk)===lineage,"Lineage changed after ordinary deletion");
  out.textContent="PASS: native crypto, localStorage, Web Locks, protected drift, pending journal, stale epoch and ordinary tombstone.";out.dataset.result="pass";
 }catch(error){out.textContent="FAIL: "+error.message;out.dataset.result="fail";console.error(error);}
 finally{if(ns)for(const k of names())localStorage.removeItem(k);}
})();
