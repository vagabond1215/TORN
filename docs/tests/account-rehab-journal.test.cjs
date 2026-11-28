"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,l,p,j}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-rehab-transition.js","account-rehab-journal.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,l:tornCalendarLineage,p:tornRehabTransition,j:tornRehabJournal};")();
const id="123",base="torn-city-guide:",cal=base+"activity-events:"+id,ledger=base+"activity-spend-ledger:"+id,lineage=base+"calendar-lineage:v1:"+id,manifest=r.key(id),journal=a.journalKey(id),note=base+"v1:profile:"+id+":notes:gym";
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);},mockOptions={digest,newRevision:()=>String(++n).padStart(32,"0")};
const yes=()=>true,locks={request:async(name,opt,fn)=>{assert.equal(name,base+"account-recovery:"+id);assert.equal(opt.mode,"exclusive");return fn();}};
function storage(entries){const m=new Map(Object.entries(entries));return {get length(){return m.size;},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
async function run({native=false}={}){
  const options=native?{}:mockOptions;
  if(native&&!globalThis.crypto?.subtle)throw Error("Native Web Crypto required");
  const now=Date.now(),event={id:"a",kind:"rehab",title:"Rehab reservation",start:now-120000,end:now+60000,blocking:true,source:"manual",rehabBaseline:{count:5,cost:100000,at:now-180000}};
  const evidence={playerId:id,count:6,cost:350000,statsAt:now-1000,profileAt:now-1000,profileStatus:"okay"};
  const old={id:"manual-old",kind:"war",at:now-100*86400000,cost:7,source:"Manual confirmation"};
  const make=async(withLedger=true,rows=[event],expenses=[old])=>{
    const records=[{section:"calendar-events",value:JSON.stringify(rows)},{section:"notes:gym",value:"keep"},...(withLedger?[{section:"activity-spend",value:JSON.stringify(expenses)}]:[])].sort((x,y)=>x.section.localeCompare(y.section)),omitted=[];
    const local={records,omitted,manifest:await r.observe(r.empty(id),{records,omitted},id,options)};
    const initial=await l.initialize(local,id,options),entries={[cal]:records.find(x=>x.section==="calendar-events").value,[note]:"keep",[manifest]:JSON.stringify(local.manifest),[lineage]:JSON.stringify(initial)};
    if(withLedger)entries[ledger]=JSON.stringify(expenses);
    return {local,entries,store:()=>storage(entries)};
  };
  const f=await make(),review={eventId:"a",cost:250000,evidence},apply=(s=f.store(),opts=options,rv=review,observed=()=>rv.evidence,current=yes,lock=locks,local=f.local)=>j.apply(s,id,local,rv,observed,current,lock,opts);
  const snap=s=>({...a.snapshot(s,id),manifest:r.read(s,id)});
  const verify=async s=>{const snapshot=snap(s);await r.verify(snapshot.manifest,snapshot.records,id,options);await l.verify(JSON.parse(s.getItem(lineage)),snapshot,id,options);};
  const ok=f.store();assert.equal((await apply(ok)).status,"applied");assert.equal(ok.getItem(journal),null);assert.equal(JSON.parse(ok.getItem(cal))[0].blocking,false);assert.deepEqual(JSON.parse(ok.getItem(ledger)),[old,{id:"rehab-a",kind:"rehab",at:evidence.statsAt,cost:250000,source:"API counter delta"}]);await verify(ok);
  const after=snap(ok);assert.equal((await apply(ok,options,review,()=>evidence,yes,locks,after)).status,"review");
  const unknown=f.store(),u={...review,cost:null,evidence:{...evidence,cost:null}};assert.equal((await apply(unknown,options,u)).status,"applied");assert.equal(unknown.getItem(ledger),f.entries[ledger]);await verify(unknown);
  const absent=await make(false);assert.equal((await apply(absent.store(),options,review,()=>evidence,yes,locks,absent.local)).status,"review");
  const absentUnknown=absent.store();assert.equal((await apply(absentUnknown,options,u,()=>u.evidence,yes,locks,absent.local)).status,"applied");assert.equal(absentUnknown.getItem(ledger),null);await verify(absentUnknown);
  const boot=f.store();boot.removeItem(lineage);await assert.rejects(()=>apply(boot),/bootstrap/);assert.equal((await apply(boot,{...options,allowBootstrap:true})).status,"applied");
  const denied=f.store();await assert.rejects(()=>apply(denied,options,review,()=>evidence,()=>false),/training state/);assert.equal(denied.getItem(journal),null);
  await assert.rejects(()=>apply(f.store(),options,review,()=>evidence,yes,null),/Web Locks/);
  const held=f.store();held.setItem(base+"training-session:"+id,"held");await assert.rejects(()=>apply(held),/training state/);
  const stale=f.store();stale.setItem(note,"different");await assert.rejects(()=>apply(stale),/changed/);
  await assert.rejects(()=>apply(f.store(),options,review,()=>({...evidence,count:7})),/observation changed/);
  await assert.rejects(()=>apply(f.store(),options,{...review,cost:1}),/review changed/);
  const duplicate=await make(true,[event],[old,{id:"rehab-a",kind:"rehab",at:evidence.statsAt,cost:1,source:"API counter delta"}]);assert.equal((await apply(duplicate.store(),options,review,()=>evidence,yes,locks,duplicate.local)).status,"review");
  const journalFail=f.store(),jf=journalFail.setItem;journalFail.setItem=(k,v)=>{if(k===journal)throw Error("quota");jf(k,v);};await assert.rejects(()=>apply(journalFail),/quota/);assert.equal(journalFail.getItem(cal),f.entries[cal]);assert.equal(journalFail.getItem(ledger),f.entries[ledger]);
  const interrupt=async(dest)=>{
    const s=f.store(),w=s.setItem;s.setItem=(k,v)=>{if(k===dest)throw Error("quota");w(k,v);};
    await assert.rejects(()=>apply(s),/journal retained/);s.setItem=w;return s;
  };
  for(const dest of [cal,ledger,lineage,manifest]){
    const s=await interrupt(dest),info=j.read(s,id);assert.equal(info.version,6);assert.equal(info.complete,false);assert.equal(info.conflict,false);
    assert.equal(a.journalPending(s,id),true);assert.throws(()=>a.readJournal(s,id),/Invalid restore journal/);assert.throws(()=>a.trackedWrite(s,id,note,"bad"),/pending/);
    await assert.rejects(()=>j.recover(s,id,info.raw,"finish",yes,locks,options),/incomplete/);
    assert.equal((await j.recover(s,id,info.raw,"rollback",yes,locks,options)).status,"rolled-back");
    for(const [key,value] of Object.entries(f.entries))assert.equal(s.getItem(key),value);
    assert.equal(s.getItem(journal),null);
  }
  const complete=f.store(),remove=complete.removeItem;complete.removeItem=k=>{if(k===journal)throw Error("finalization");remove(k);};await assert.rejects(()=>apply(complete),/journal retained/);const done=j.read(complete,id);assert.equal(done.complete,true);complete.removeItem=remove;
  assert.equal((await j.recover(complete,id,done.raw,"finish",yes,locks,options)).status,"finalized");await verify(complete);
  const conflict=await interrupt(manifest);conflict.setItem(ledger,JSON.stringify([old])); // exact before is not a third value
  conflict.setItem(ledger,JSON.stringify([{...old,cost:8}]));assert.equal(j.read(conflict,id).conflict,true);await assert.rejects(()=>j.recover(conflict,id,j.read(conflict,id).raw,"rollback",yes,locks,options),/Conflicting/);assert.ok(conflict.getItem(journal));
  const unrelated=await interrupt(manifest);unrelated.setItem(note,"independent");await assert.rejects(()=>j.recover(unrelated,id,j.read(unrelated,id).raw,"rollback",yes,locks,options),/digest/);assert.ok(unrelated.getItem(journal));
  const tamper=await interrupt(manifest),fake=JSON.parse(tamper.getItem(journal));fake.evidence.cost++;tamper.setItem(journal,JSON.stringify(fake));await assert.rejects(()=>j.recover(tamper,id,tamper.getItem(journal),"rollback",yes,locks,options),/evidence or paired/);assert.ok(tamper.getItem(journal));
  const changed=await interrupt(manifest);await assert.rejects(()=>j.recover(changed,id,j.read(changed,id).raw,"rollback",()=>false,locks,options),/training state/);assert.ok(changed.getItem(journal));
  const epoch=f.store(),w=epoch.setItem;let active=true;epoch.setItem=(k,v)=>{w(k,v);if(k===cal)active=false;};await assert.rejects(()=>apply(epoch,options,review,()=>evidence,()=>active),/journal retained/);assert.ok(epoch.getItem(journal));assert.equal(epoch.getItem(ledger),f.entries[ledger]);
  const foreign=await interrupt(manifest),wrong=JSON.parse(foreign.getItem(journal));wrong.playerId="456";foreign.setItem(journal,JSON.stringify(wrong));await assert.rejects(()=>j.recover(foreign,id,foreign.getItem(journal),"rollback",yes,locks,options),/Invalid rehab journal/);assert.ok(foreign.getItem(journal));
  const markers=await interrupt(manifest);markers.setItem(base+"revision-observed-delete:v1:"+id+":notes:gym","1");assert.equal(j.read(markers,id).conflict,true);await assert.rejects(()=>j.recover(markers,id,j.read(markers,id).raw,"rollback",yes,locks,options),/markers changed/);
  const refreshed=f.store(),rw=refreshed.setItem;let currentEvidence=evidence;refreshed.setItem=(k,v)=>{rw(k,v);if(k===cal)currentEvidence={...evidence,count:7};};await assert.rejects(()=>apply(refreshed,options,review,()=>currentEvidence),/journal retained/);assert.ok(refreshed.getItem(journal));assert.equal(refreshed.getItem(ledger),f.entries[ledger]);
  // Recovery verifies the original decision time, not fresh attribution.
  const late=await interrupt(manifest),originalNow=Date.now;
  try{Date.now=()=>now+7*86400000;assert.equal((await j.recover(late,id,j.read(late,id).raw,"rollback",yes,locks,options)).status,"rolled-back");}finally{Date.now=originalNow;}
  assert.equal(late.getItem(cal),f.entries[cal]);assert.equal(late.getItem(ledger),f.entries[ledger]);
  console.log((native?"Native Web Crypto ":"Deterministic digest ")+"V6 rehab journal: paired completion, unknown cost, bootstrap, stale evidence, lock/hold, duplicate, journal+4 destination faults, finish/rollback, tamper/conflict and epoch interruption passed.");
}
module.exports=run;
if(require.main===module)run().then(()=>run({native:true})).catch(error=>{console.error(error);process.exitCode=1;});
