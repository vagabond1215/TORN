"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const a=new Function(read("account-storage.js")+"\nreturn tornAccountStorage;")();
function storage(entries={}){const m=new Map(Object.entries(entries));return {get length(){return m.size},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
const p="torn-city-guide:",id=123,now=Date.now(),start=now-60000;
const pending={id:"rehab-pending",kind:"rehab",title:"Rehab reserved",start,end:now+60000,blocking:true,source:"manual",rehabBaseline:{count:3,cost:750000,at:start-1000}};
const done={...pending,id:"rehab-done",blocking:false,end:now-1000,completedAt:now-1000,rehabCost:250000};
const ledger=[{id:"rehab-rehab-done",kind:"rehab",at:now-1000,cost:250000,source:"API counter delta"},{id:"manual-1",kind:"war",at:now-2000,cost:500,source:"Manual confirmation"}];
const estimates=[{started:start,at:now-1000,cost:999000}];
const source=storage({[p+"activity-events:123"]:JSON.stringify([pending,done]),[p+"activity-spend-ledger:123"]:JSON.stringify(ledger),[p+"training-spend:123"]:JSON.stringify(estimates),[p+"training-spend:456"]:"[]",[p+"training-session:123"]:"{}",[p+"api:v2:remember"]:"secret"});
const snap=a.snapshot(source,id);assert.deepEqual(snap.records.map(x=>x.section),["activity-spend","calendar-events","training-spend-estimates"]);assert.deepEqual(snap.omitted,[]);
const target=storage();assert.equal(a.restoreEmpty(target,id,snap.records),3);
assert.deepEqual(JSON.parse(target.getItem(p+"training-spend:123")),estimates);
assert.deepEqual(JSON.parse(target.getItem(p+"activity-spend-ledger:123")),ledger);
assert.deepEqual(JSON.parse(target.getItem(p+"activity-events:123")),[{...pending,recoveryReview:true},done]);
assert.equal(target.getItem(p+"training-session:123"),null);assert.equal(target.getItem(p+"training-spend:456"),null);assert.equal(target.getItem(p+"api:v2:remember"),null);
assert.deepEqual(a.snapshot(target,id).omitted,[]);assert.throws(()=>a.restoreEmpty(target,id,snap.records),/already/);
for(const [section,value] of [
 ["training-spend-estimates",[{...estimates[0],at:now+60000}]],
 ["activity-spend",[{...ledger[0],kind:"war"}]],
 ["activity-spend",[{...ledger[0],id:"manual-wrong"}]],
 ["calendar-events",[{...pending,kind:"war"}]],
 ["calendar-events",[{...done,blocking:true}]],
 ["calendar-events",[{...pending,rehabBaseline:{...pending.rehabBaseline,key:"secret"}}]],
 ["calendar-events",[{...pending,rehabCost:100}]]
])assert.throws(()=>a.validRecords([{section,value:JSON.stringify(value)}],String(id)),/invalid section/);
const api={state:{identity:{id},data:{rehabStats:{personalstats:{rehabs:4,rehabcost:1000000}},profile:{profile:{status:{state:"Okay"}}}},fetchedAt:{rehabStats:now,profile:now},errors:{}}};
const scheduler=new Function("tornGuideApi","localStorage",read("activity-scheduler.js")+"\nreturn tornActivityScheduler;")(api,target);
assert.equal(scheduler.reconcileRehab(now),null);assert.deepEqual(scheduler.spendLedger(now),ledger);
assert.ok(scheduler.schedule({now}).find(x=>x.id===pending.id).detail.includes("review manually"));
const live=storage({[p+"activity-events:123"]:JSON.stringify([pending])});
const fresh=new Function("tornGuideApi","localStorage",read("activity-scheduler.js")+"\nreturn tornActivityScheduler;")(api,live);
assert.equal(fresh.reconcileRehab(now).cost,250000);assert.equal(fresh.reconcileRehab(now),null);assert.equal(fresh.spendLedger(now).length,1);
const concurrent=storage();let calls=0;const write=concurrent.setItem;
concurrent.setItem=(key,value)=>{if(++calls===2){write(p+"activity-spend-ledger:123","concurrent");throw Error("quota");}write(key,value);};
assert.throws(()=>a.restoreEmpty(concurrent,id,snap.records),/concurrent edit/);assert.equal(concurrent.getItem(p+"activity-spend-ledger:123"),"concurrent");
console.log("Restored rehab review hold, live reconciliation, expense validation and competing-write rollback passed.");
