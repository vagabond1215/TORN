"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,l,g}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-transaction-store.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,l:tornCalendarLineage,g:tornAccountTransactionStore};")();
const id="123",prefix="torn-city-guide:",cal=prefix+"activity-events:"+id,ledger=prefix+"activity-spend-ledger:"+id,lk=prefix+"calendar-lineage:v1:"+id,note=prefix+"v1:profile:"+id+":notes:gym";
function storage(entries={}){const m=new Map(Object.entries(entries));return {get length(){return m.size},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);},options={digest,newRevision:()=>String(++n).padStart(32,"0")};
const yes=()=>true;
async function run(){
 const s=storage({[cal]:"[]",[ledger]:"[]",[note]:"A"});
 const snap=a.snapshot(s,id),manifest=await r.observe(r.empty(id),snap,id,options);
 s.setItem(r.key(id),JSON.stringify(manifest));
 s.setItem(lk,JSON.stringify(await l.initialize({...snap,manifest},id,options)));
 const review=await g.reviewLegacy(s,id,yes,options);
 const before={version:1,playerId:id,generation:1,bundle:review.bundle};
 const change={section:"notes:gym",before:"A",after:"B"};
 const next=await g.preparePreference(before,id,change,options);
 assert.equal(next.generation,2);assert.equal(next.bundle.records.find(x=>x.section==="notes:gym").value,"B");
 assert.equal(next.bundle.lineageRaw,before.bundle.lineageRaw);
 for(const section of ["calendar-events","activity-spend"]){
  assert.deepEqual(next.bundle.records.find(x=>x.section===section),before.bundle.records.find(x=>x.section===section));
  assert.deepEqual(JSON.parse(next.bundle.manifestRaw).entries.find(x=>x.section===section),manifest.entries.find(x=>x.section===section));
 }
 const deleted=await g.preparePreference(next,id,{...change,before:"B",after:null},options);
 assert.equal(deleted.generation,3);assert.ok(deleted.bundle.markers.includes("notes:gym"));
 assert.equal(JSON.parse(deleted.bundle.manifestRaw).entries.find(e=>e.section==="notes:gym").digest,null);
 const recreated=await g.preparePreference(deleted,id,{...change,before:null,after:"C"},options);
 assert.ok(recreated.bundle.markers.includes("notes:gym"));
 await assert.rejects(()=>g.preparePreference(before,id,{section:"calendar-events",before:"[]",after:"[] "},options),/preference/);
 await assert.rejects(()=>g.preparePreference(before,id,{...change,before:"wrong"},options),/review again/);
 await assert.rejects(()=>g.preparePreference(before,"456",change,options),/authoritative/);
 await assert.rejects(()=>g.preparePreference({...before,generation:Number.MAX_SAFE_INTEGER},id,change,options),/generation exhausted/);
 s.setItem(cal,"[] ");await assert.rejects(()=>g.reviewLegacy(s,id,yes,options),/digest/);s.setItem(cal,"[]");
 s.setItem(a.journalKey(id),"{}");await assert.rejects(()=>g.reviewLegacy(s,id,yes,options),/journal pending/);s.removeItem(a.journalKey(id));
 s.setItem(prefix+"training-session:"+id,"{}");await assert.rejects(()=>g.reviewLegacy(s,id,yes,options),/training/);s.removeItem(prefix+"training-session:"+id);
 let valid=true;await assert.rejects(()=>g.reviewLegacy(s,id,()=>valid,{digest:async v=>{valid=false;return digest(v)}}),/epoch/);
 await assert.rejects(()=>g.reviewLegacy(s,id,yes,{digest:async v=>{s.setItem(note,"changed");return digest(v)}}),/source changed/);
 assert.equal(s.getItem(r.key(id)),review.bundle.manifestRaw);
 await assert.rejects(()=>g.open({indexedDB:null}),/IndexedDB unavailable/);
 console.log("Transactional account contract: immutable review, preference ancestry, deletion markers, protected bytes, owner, stale/held/epoch and generation limits passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
