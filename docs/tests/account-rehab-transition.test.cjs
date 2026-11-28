"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {r,p}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-rehab-transition.js"].map(read).join("\n")+"\nreturn {r:tornAccountRevisions,p:tornRehabTransition};")();
const id="123",now=Date.UTC(2026,10,27),cal="calendar-events",ledger="activity-spend";
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);};
const options={digest,newRevision:()=>String(++n).padStart(32,"0")},ev={id:"a",kind:"rehab",title:"Rehab reservation",start:now-120000,end:now+60000,blocking:true,source:"manual",rehabBaseline:{count:5,cost:100000,at:now-180000}};
const observed={playerId:id,count:6,cost:350000,statsAt:now-1000,profileAt:now-1000,profileStatus:"okay"};
const spend={id:"manual-old",kind:"war",at:now-100*86400000,cost:7,source:"Manual confirmation"};
async function make(rows,expenses=[]){const records=[{section:ledger,value:JSON.stringify(expenses)},{section:cal,value:JSON.stringify(rows)}],omitted=[];return {records,omitted,manifest:await r.observe(r.empty(id),{records,omitted},id,options)};}
async function run(){
 const local=await make([ev],[spend]),old=JSON.stringify(local);
 const prep=(s=local,o=observed)=>p.prepare(s,id,o,{now,digest});
 const candidate=await prep();assert.equal(candidate.status,"candidate");assert.equal(candidate.cost,250000);assert.equal(candidate.changes.length,2);
 const done=JSON.parse(candidate.changes[0].value)[0];assert.equal(done.completedAt,now);assert.equal(done.blocking,false);assert.equal(done.rehabCost,250000);
 assert.deepEqual(JSON.parse(candidate.changes[1].value),[spend,{id:"rehab-a",kind:"rehab",at:observed.statsAt,cost:250000,source:"API counter delta"}]);
 assert.equal(JSON.stringify(local),old);assert.equal(candidate.requiresJournal,true);
 for(const bad of [{...observed,playerId:"456"},{...observed,count:7},{...observed,count:5},{...observed,cost:1},{...observed,statsAt:now-31*60000},{...observed,profileStatus:"traveling"},{...observed,profileAt:now-16*60000},{...observed,statsAt:now+1}])assert.equal((await prep(local,bad)).status,"review");
 const unknown=await prep(local,{...observed,cost:null});assert.equal(unknown.status,"candidate");assert.equal(unknown.cost,null);assert.equal(unknown.changes.length,1);
 assert.deepEqual(unknown.records.find(x=>x.section===ledger),local.records[0]);
 const duplicate=await make([ev],[{id:"rehab-a",kind:"rehab",at:now-1000,cost:1,source:"API counter delta"}]);
 assert.equal((await prep(duplicate)).status,"review");
 const held=await make([{...ev,recoveryReview:true}]);assert.equal((await prep(held)).status,"review");
 const ambiguous=await make([ev,{...ev,id:"b",recoveryReview:true}]);assert.equal((await prep(ambiguous)).status,"review");
 const overlap=await make([ev,{...ev,id:"b",blocking:false,completedAt:now-1000,end:now-1000,rehabCost:1}]);assert.equal((await prep(overlap)).status,"review");
 const cap=await make([ev],Array.from({length:500},(_,i)=>({...spend,id:"manual-"+i})));assert.equal((await prep(cap)).status,"review");
 const completed=await make([done],JSON.parse(candidate.changes[1].value));assert.equal((await prep(completed)).status,"review");
 await assert.rejects(()=>prep({...local,records:local.records.map(x=>x.section===cal?{...x,value:"[]"}:x)}),/digest/);
 console.log("Rehab candidate calendar/ledger pairing, ambiguous evidence, duplicate and capacity protection, unknown cost, prior history and stale/foreign observations passed.");
}
module.exports=run;
if(require.main===module)run().catch(error=>{console.error(error);process.exitCode=1;});
