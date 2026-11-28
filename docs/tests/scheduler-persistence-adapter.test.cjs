"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,l,g,s}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-merge.js","account-calendar-lineage.js","account-calendar-journal.js","account-transaction-store.js","activity-scheduler.js","scheduler-persistence-adapter.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,l:tornCalendarLineage,g:tornSchedulerPersistence,s:tornActivityScheduler};")();
const id="123",at=Date.now(),minute=60000,copy=x=>JSON.parse(JSON.stringify(x)),yes=()=>true;
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);};
const options={digest,newRevision:()=>String(++n).padStart(32,"0"),now:()=>at};
const settings={travel:"wlt",rehabMinutes:30,rehabSessions:1},baseline={count:2,cost:500000,at:at-1000};
const event={id:"rehab-fixture",kind:"rehab",title:"Rehabilitation",start:at+minute,end:at+minute+s.rehabDuration(settings),blocking:true,source:"manual",rehabBaseline:baseline};
const change={id:event.id,kind:"add",before:null,after:event};
async function fixture(events=[],spend=[]){
 const records=[{section:"activity-spend",value:JSON.stringify(spend)},{section:"calendar-events",value:JSON.stringify(events)},{section:"notes:gym",value:"keep"}],omitted=[];
 const manifest=await r.observe(r.empty(id),{records,omitted},id,options),lineage=await l.initialize({records,omitted,manifest},id,options);
 return {playerId:id,record:{version:1,playerId:id,generation:1,bundle:{records,omitted,markers:[],manifestRaw:JSON.stringify(manifest),lineageRaw:JSON.stringify(lineage)}},activeTraining:false,heldTraining:false,journalPending:false,
 profile:{at:at-1000,status:"okay",level:15},travel:{at:at-1000,available:true},war:{at:at-1000,known:true,ranked:null},warSettings:{mode:"scheduled",adjustment:60,lead:120},
 health:{at:at-1000,level:"recommended"},rehabSettings:settings,actions:[],baseline:{playerId:id,...baseline}};
}
async function run(){
 let c=await fixture(),readCurrent=()=>c;
 const prepare=(action=change,opts=options)=>g.prepare(id,copy(c),action,true,readCurrent,yes,opts);
 const initial=copy(c),candidate=await prepare();
 assert.equal(candidate.status,"candidate");assert.equal(candidate.after.generation,2);assert.deepEqual(c,initial);assert.equal(candidate.assertCurrent(),true);
 assert.deepEqual(JSON.parse(candidate.after.bundle.records.find(r=>r.section==="calendar-events").value),[event]);
 assert.equal(candidate.after.bundle.records.find(r=>r.section==="activity-spend").value,"[]");
 assert.deepEqual(JSON.parse(candidate.after.bundle.manifestRaw).entries.find(e=>e.section==="activity-spend"),JSON.parse(c.record.bundle.manifestRaw).entries.find(e=>e.section==="activity-spend"));
 c={...c,record:candidate.after};assert.throws(()=>candidate.assertCurrent(),/changed/);
 const cancellation={id:event.id,kind:"remove",before:event,after:null};
 const removed=await prepare(cancellation);assert.equal(removed.after.generation,3);
 assert.equal(JSON.parse(removed.after.bundle.lineageRaw).entries.find(e=>e.id===event.id).digest,null);
 c={...c,record:removed.after};await assert.rejects(()=>prepare(),/Deleted calendar ID/);
 c=await fixture();
 await assert.rejects(()=>g.prepare(id,copy(c),change,false,readCurrent,yes,options),/approval/);
 for(const [patch,re] of [[{activeTraining:true},/hold/],[{heldTraining:true},/hold/],[{journalPending:true},/hold/],[{profile:{...c.profile,at:at-16*minute}},/profile/],[{travel:{...c.travel,available:false}},/travel/],[{war:{...c.war,known:false}},/war observation/],[{health:{...c.health,level:"low"}},/recommendation/],[{actions:[event.start+minute]},/planned training/],[{baseline:{...c.baseline,count:3}},/baseline/]]){
  const previous=c;c={...c,...patch};await assert.rejects(()=>prepare(),re);c=previous;
 }
 const lateWar={start:event.end+34*60*minute-1,end:null,mode:null};
 c={...c,war:{...c.war,ranked:lateWar}};await assert.rejects(()=>prepare(),/war stacking cutoff/);
 c={...c,war:{...c.war,ranked:{...lateWar,start:event.end+34*60*minute}}};assert.equal((await prepare()).status,"candidate");
 const busy={id:"busy",kind:"personal",title:"Busy",start:event.start+1,end:event.end,blocking:true,source:"manual"};
 c=await fixture([busy]);await assert.rejects(()=>prepare(),/overlaps a blocking/);
 c=await fixture([], [{id:"rehab-"+event.id,kind:"rehab",at:at-1000,cost:1,source:"API counter delta"}]);await assert.rejects(()=>prepare(),/expenditure evidence/);
 c=await fixture();let current=true;
 await assert.rejects(()=>g.prepare(id,copy(c),change,true,readCurrent,()=>current,{...options,digest:async v=>{current=false;return digest(v)}}),/epoch/);
 c=await fixture();await assert.rejects(()=>prepare(change,{...options,digest:async v=>{c={...c,actions:[event.start]};return digest(v)}}),/context changed/);
 c=await fixture();let now=at;const timed=await prepare(change,{...options,now:()=>now});now=at+5001;assert.throws(()=>timed.assertCurrent(),/expired/);
 c=await fixture([event]);c={...c,profile:null,travel:null,health:null,war:null};assert.equal((await prepare(cancellation)).status,"candidate");
 console.log("Scheduler persistence adapter: approval, immutable candidate, shared war cutoff, freshness, holds, overlap, baseline, stale context, cancellation and ID tombstone passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
