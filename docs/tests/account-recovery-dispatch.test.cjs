"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,l,b,d}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-persistence-bootstrap.js","account-recovery-dispatch.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,l:tornCalendarLineage,b:tornPersistenceBootstrap,d:tornRecoveryDispatch};")();
const id="123",prefix="torn-city-guide:",journal=a.journalKey(id),cal=prefix+"activity-events:"+id,note=prefix+"v1:profile:"+id+":notes:gym",manifest=r.key(id);
const yes=()=>true;let locked=false,lockCalls=0;
const locks={request:async(name,opt,fn)=>{assert.equal(name,prefix+"account-recovery:"+id);assert.equal(opt.mode,"exclusive");assert.equal(locked,false);locked=true;lockCalls++;try{return await fn();}finally{locked=false;}}};
function storage(entries={}){const m=new Map(Object.entries(entries));return {get length(){return m.size;},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);},options={digest,newRevision:()=>String(++n).padStart(32,"0")};
async function run(){
 const calls=[],mock=name=>({read:(s,id)=>{const raw=s.getItem(journal),j=JSON.parse(raw);calls.push(["read",name,j.version]);return {raw,version:j.version,rows:[{section:"fixture",state:j.state}],complete:j.state==="matched",conflict:j.state==="conflict"};},recover:async(s,id,raw,mode,current,locks)=>{calls.push(["recover",name,JSON.parse(raw).version,mode]);assert.equal(locked,false);return locks.request(prefix+"account-recovery:"+id,{mode:"exclusive"},()=>{assert.equal(current(),true);assert.equal(s.getItem(journal),raw);return {status:"mock"};});}});
 const router=d.create({calendar:mock("calendar"),rehab:mock("rehab"),bootstrap:mock("bootstrap")});
 const raw=(version,state="matched",owner=id)=>JSON.stringify({version,playerId:owner,state});
 assert.equal(router.inspect(storage(),id),null);
 for(const [version,name] of [[3,"calendar"],[4,"calendar"],[5,"calendar"],[6,"rehab"],[7,"calendar"],[8,"bootstrap"]]){
  const value=raw(version),s=storage({[journal]:value});assert.equal(router.inspect(s,id).version,version);
  assert.equal((await router.recover(s,id,value,"finish",true,yes,locks)).status,"mock");assert.deepEqual(calls.at(-1),["recover",name,version,"finish"]);
 }
 const malformed=storage({[journal]:"{"});assert.throws(()=>router.inspect(malformed,id),/Malformed/);
 for(const version of [0,9,"6",null]){const s=storage({[journal]:raw(version)});assert.throws(()=>router.inspect(s,id),/Unsupported/);assert.equal(s.getItem(journal),raw(version));}
 assert.throws(()=>router.inspect(storage({[journal]:raw(6,"matched","456")}),id),/owner/);
 assert.throws(()=>d.create().inspect(storage({[journal]:raw(8)}),id),/unavailable/);
 const s=storage({[journal]:raw(6)});
 await assert.rejects(()=>router.recover(s,id,s.getItem(journal),"finish",false,yes,locks),/approval/);
 await assert.rejects(()=>router.recover(s,id,s.getItem(journal),"invalid",true,yes,locks),/approval/);
 await assert.rejects(()=>router.recover(s,id,s.getItem(journal),"finish",true,()=>false,locks),/Verified/);
 await assert.rejects(()=>router.recover(s,id,s.getItem(journal),"finish",true,yes,null),/Web Locks/);
 await assert.rejects(()=>router.recover(s,id,raw(7),"finish",true,yes,locks),/changed/);
 for(const state of ["previous","conflict"]){const s=storage({[journal]:raw(6,state)});await assert.rejects(()=>router.recover(s,id,s.getItem(journal),"finish",true,yes,locks),/Conflicting or incomplete/);if(state==="conflict")await assert.rejects(()=>router.recover(s,id,s.getItem(journal),"rollback",true,yes,locks),/Conflicting/);}
 // Actual legacy V1 parser and rollback, no new handler involved.
 const legacy=storage(),remove=legacy.removeItem;legacy.removeItem=k=>{if(k===journal)throw Error("interrupted");remove(k);};
 assert.throws(()=>a.restoreJournaled(legacy,id,[{section:"notes:gym",value:"fixture"}],yes),/journal|interrupted|Restore/);
 legacy.removeItem=remove;
 const real=d.create({bootstrap:b}),legacyInfo=real.inspect(legacy,id);assert.equal(legacyInfo.version,1);assert.equal(legacyInfo.complete,true);
 assert.equal((await real.recover(legacy,id,legacyInfo.raw,"rollback",true,yes,locks)).status,"rolled-back");assert.equal(legacy.getItem(note),null);assert.equal(legacy.getItem(journal),null);
 // Actual V8 interrupted bootstrap, dispatcher delegates locking exactly once.
 const boot=storage(),review=await b.preview(boot,id,yes,options),w=boot.setItem;
 boot.setItem=(k,v)=>{if(k===manifest)throw Error("quota");w(k,v);};
 await assert.rejects(()=>b.apply(boot,id,review.review,true,yes,locks,options),/journal retained/);boot.setItem=w;
 const info=real.inspect(boot,id);assert.equal(info.version,8);assert.equal(info.complete,false);
 const priorCalls=lockCalls;
 assert.equal((await real.recover(boot,id,info.raw,"rollback",true,yes,locks,options)).status,"rolled-back");assert.equal(lockCalls,priorCalls+1);assert.equal(boot.length,0);
 console.log("Recovery dispatcher: exact V1-V8 routing (mock V3-V8 routing, real V1/V8 rollback), no nested locks, unknown/malformed/foreign/stale/denied journal and conflict guards passed.");
}
module.exports=run;
if(require.main===module)run().catch(error=>{console.error(error);process.exitCode=1;});
