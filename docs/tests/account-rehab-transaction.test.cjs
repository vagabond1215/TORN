"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {r,l,g,tx}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-rehab-transition.js","account-transaction-store.js","account-rehab-transaction.js"].map(read).join("\n")+"\nreturn {r:tornAccountRevisions,l:tornCalendarLineage,g:tornRehabTransaction,tx:tornAccountTransactionStore};")();
const id="123",at=Date.now(),minute=60000,copy=x=>JSON.parse(JSON.stringify(x)),yes=()=>true;
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);};
const options={digest,newRevision:()=>String(++n).padStart(32,"0"),now:()=>at};
const event={id:"fixture",kind:"rehab",title:"Rehab",start:at-2*minute,end:at+minute,blocking:true,source:"manual",rehabBaseline:{count:5,cost:100000,at:at-3*minute}};
const oldSpend={id:"manual-old",kind:"war",at:at-100*86400000,cost:123,source:"Manual confirmation"};
const observation={playerId:id,count:6,cost:350000,statsAt:at-1000,profileAt:at-1000,profileStatus:"okay"};
async function fixture(events=[event],expenses=[oldSpend],obs=observation){
 const records=[{section:"activity-spend",value:JSON.stringify(expenses)},{section:"calendar-events",value:JSON.stringify(events)},{section:"notes:gym",value:"keep"}],omitted=[];
 const manifest=await r.observe(r.empty(id),{records,omitted},id,options),lineage=await l.initialize({records,omitted,manifest},id,options);
 return {playerId:id,record:{version:1,playerId:id,generation:1,bundle:{records,omitted,markers:[],manifestRaw:JSON.stringify(manifest),lineageRaw:JSON.stringify(lineage)}},observation:obs,activeTraining:false,heldTraining:false,journalPending:false};
}
// Controlled IDB callback harness, not native browser acceptance.
const microtask=fn=>Promise.resolve().then(fn);
function fakeDatabase(initial){
 let current=copy(initial),puts=0,afterPut=null;
 const db={close(){},transaction(){
   let staged=current===null?null:copy(current),aborted=false;
   const finish=()=>microtask(()=>{if(!aborted){current=staged;transaction.oncomplete?.();}});
   const request=(value,write=false)=>{
     const req={result:value};microtask(()=>{if(aborted)return;
       const oldPuts=puts;
       if(write&&afterPut)afterPut();
       req.onsuccess?.();
       if(!aborted&&puts===oldPuts)finish();
     });return req;
   };
   const transaction={objectStore:()=>({get:()=>request(staged??undefined),put:value=>{puts++;staged=copy(value);return request(undefined,true);}}),
    abort(){if(aborted)return;aborted=true;microtask(()=>transaction.onabort?.());}};
   return transaction;
 }};
 const indexedDB={open(){const request={result:db};microtask(()=>request.onsuccess?.());return request;}};
 return {indexedDB,get current(){return copy(current)},get puts(){return puts},setAfterPut:fn=>afterPut=fn};
}

async function run(){
 let c=await fixture();const current=()=>c,decision=()=>({eventId:event.id,cost:c.observation.cost===null?null:250000,evidence:copy(c.observation)});
 const prep=(opts=options)=>g.prepare(id,copy(c),decision(),true,current,yes,opts);
 const initial=copy(c),candidate=await prep(),value=(record,section)=>record.bundle.records.find(x=>x.section===section).value;
 assert.equal(candidate.status,"candidate");assert.equal(candidate.after.generation,2);assert.deepEqual(c,initial);
 assert.equal(JSON.parse(value(candidate.after,"calendar-events"))[0].completedAt,at);
 assert.deepEqual(JSON.parse(value(candidate.after,"activity-spend")),[oldSpend,{id:"rehab-fixture",kind:"rehab",at:observation.statsAt,cost:250000,source:"API counter delta"}]);
 assert.equal(value(candidate.after,"notes:gym"),"keep");assert.equal(candidate.assertCurrent(),true);
 const unknown=await fixture([event],[oldSpend],{...observation,cost:null});c=unknown;
 const unpriced=await prep();assert.equal(unpriced.cost,null);assert.equal(value(unpriced.after,"activity-spend"),value(unknown.record,"activity-spend"));
 assert.deepEqual(JSON.parse(unpriced.after.bundle.manifestRaw).entries.find(e=>e.section==="activity-spend"),JSON.parse(unknown.record.bundle.manifestRaw).entries.find(e=>e.section==="activity-spend"));
 c=initial;await assert.rejects(()=>g.prepare(id,copy(c),decision(),false,current,yes,options),/approval/);
 await assert.rejects(()=>g.prepare(id,copy(c),{...decision(),cost:1},true,current,yes,options),/cost changed/);
 c=await fixture([event],[oldSpend,{id:"rehab-fixture",kind:"rehab",at:at-1000,cost:1,source:"API counter delta"}]);assert.equal((await prep()).status,"review");
 c=await fixture([event],Array.from({length:500},(_,i)=>({...oldSpend,id:"manual-old-"+i})));assert.equal((await prep()).status,"review");
 c=await fixture([event,{...event,id:"other"}]);assert.equal((await prep()).status,"review");
 c=await fixture([event],[oldSpend],{...observation,statsAt:at-31*minute});assert.equal((await prep()).status,"review");
 c=initial;let valid=true;await assert.rejects(()=>g.prepare(id,copy(c),decision(),true,current,()=>valid,{...options,digest:async v=>{valid=false;return digest(v)}}),/epoch/);
 let time=at;const timed=await prep({...options,now:()=>time});time=at+5001;assert.throws(()=>timed.assertCurrent(),/expired|time/);
 c=initial;const fake=fakeDatabase(c.record),db=await tx.open({indexedDB:fake.indexedDB});
 const complete=()=>db.completeRehab(id,copy(c),decision(),true,current,yes,options);
 fake.setAfterPut(()=>{c={...c,observation:{...c.observation,count:7}};});
 await assert.rejects(complete,/context changed/);assert.deepEqual(fake.current,initial.record);
 c=initial;fake.setAfterPut(()=>{c={...c,heldTraining:true};});await assert.rejects(complete,/hold/);assert.deepEqual(fake.current,initial.record);
 c=initial;fake.setAfterPut(null);const committed=await complete();assert.equal(committed.status,"committed");assert.equal(committed.cost,250000);
 const result=fake.current;assert.equal(result.generation,2);const stale=await complete();assert.equal(stale.status,"stale");assert.deepEqual(fake.current,result);
 c={...c,record:result};assert.equal((await complete()).status,"review");assert.deepEqual(fake.current,result);
 db.close();console.log("Transactional rehab completion: reviewed counter evidence, old expenses, unknown cost, duplicate/capacity/ambiguity, freshness, epoch, post-put abort, stale CAS and no second charge passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
