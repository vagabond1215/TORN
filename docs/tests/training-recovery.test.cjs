"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const recovery=new Function(read("training-recovery.js")+"\nreturn tornTrainingRecovery;")();
const now=Date.UTC(2026,10,26,12);
const state={identity:{id:1},data:{profile:{donator_status:"Donator"},bars:{bars:{energy:{current:540,maximum:150},happy:{current:5000,maximum:5000}}},cooldowns:{cooldowns:{drug:3600,booster:120}},refills:{refills:{energy_refill_used:false}}},fetchedAt:{bars:now,cooldowns:now,refills:now},errors:{},inventory:{},inventoryErrors:{}};
const storage={getItem:()=>null,setItem:()=>{}};
const optimizer=new Function("tornGuideApi","localStorage","payload","tornHappinessBook","tornBookTileStatus",read("stats-sequencer.js")+"\nreturn tornTrainSequence;")({state},storage,(name,field)=>state.data[name]?.[field]??state.data[name],()=>({active:false}),()=>"");
const live=optimizer.liveInputs(state,now,(key,bar,at,time)=>({current:bar.current,maximum:bar.maximum,observedAt:at,at:time}));
const ctx={state:{statValues:{strength:175058},compareStat:"strength",currentEnergy:540,maxEnergy:150,happy:5000,maxHappy:5000},gym:{energy:10,strength:10},effectsFor:()=>({multiplier:1}),trainBlock:(stat,happy,energy)=>({stat:stat+Math.floor(energy/10)*(10+happy/1000),happy,used:Math.floor(energy/10)*10})};
const p=optimizer.weeklyPrograms(ctx,0,"low",{liveInputs:live,naturalOnly:true,deadline:now+4*3600000})[0];
assert.ok(p);
const crime=read("crime-guide.js"),actions=new Function(crime.slice(crime.indexOf("  const actionable="),crime.indexOf("  function sessionSchedule("))+crime.slice(crime.indexOf("  function sessionActions("),crime.indexOf("  function sessionWaitText("))+"\nreturn sessionActions;")();
const session=JSON.parse(JSON.stringify({version:1,label:p.label,source:p.source,sequence:p.sequence,deadline:p.deadline,stat:"Strength",statKey:"strength",budget:0,excludeOwned:true,confirmedSpend:0,periods:p.periods,drugRisk:p.drugRisk,started:now,index:0,actions:actions(p.cycleExecution),cycleSpend:p.cycleSpend,notBefore:0,completed:{},timing:p.timing,gym:{name:"Gun Shop",energy:10,estimated:false},maxEnergy:150,watch:{index:0,sample:null}}));
assert.ok(recovery.validSession(session,now));
const prepared=recovery.prepareReview(1,session,now);assert.equal(prepared.key,"torn-city-guide:training-session-review:v1:1");assert.deepEqual(JSON.parse(prepared.value),session);assert.equal(prepared.summary.confirmed,0);
const done={...session,index:1,completed:{0:now+100},lastConfirmed:now+100,watch:{index:1,sample:null}};
assert.ok(recovery.validSession(done,now+100));
assert.ok(recovery.validSession({...done,completed:{0:null},recovered:{0:true}},now+100));
for(const bad of [{...done,completed:{}},{...done,completed:{0:null}},{...done,completed:{0:now+100,1:now+100}},{...done,completed:{0:now-1}},{...done,statKey:"defense"},{...done,watch:{index:0,sample:null}},{...done,actions:[{...done.actions[0],energy:999}]},{...session,actions:[{...session.actions[0],type:"dvd",energy:null}]},{...session,apiKey:"secret"},{...session,actions:[{...session.actions[0],after:{...session.actions[0].after,secret:"no"}}]}])assert.equal(recovery.validSession(bad,now+100),false);
const archive={started:now,ended:now+100,reason:"activity deadline",label:session.label,confirmed:session.actions.slice(0,1),completed:{0:now+100},reservedSpend:0};
assert.ok(recovery.validHistory([archive],now+100));
assert.equal(recovery.validHistory([archive,archive],now+100),false);
assert.equal(recovery.validHistory([{...archive,completed:{}}],now+100),false);
assert.throws(()=>recovery.prepareReview("guest",session,now),/Verified/);
assert.throws(()=>recovery.prepareReview(1,{...session,index:999},now),/Invalid saved/);
console.log("Producer-generated training cycle, partial sequence, immutable confirmed prefix, evidence validation and isolated review staging contract passed.");

// Use the actual single-cycle simulator and trainingExecution conversion
// for all existing templates; no hand-authored action sequences.
const items=[{id:1,name:"Xanax",market_value:900},{id:2,name:"Ecstasy",market_value:50},{id:3,name:"Erotic DVD",market_value:4000},{id:4,name:"Birthday Cupcake",market_value:20}];
const data={profile:{donator_status:"Donator"},itemCatalog:{items},pointsCatalog:{pointsmarket:[{cost:30}]}};
const all=["natural","maxenergy","mini","low","jump","maxhappy","custom"],labels=["Natural training","Maximum Energy","Mini jump","Low-stat jump","Happy jump","99k Happy jump","Custom"];
const sandbox={state:{data,fetchedAt:{},errors:{},inventoryErrors:{},inventory:{Candy:[{name:"Birthday Cupcake",amount:60}],Booster:[]}}};
const renderSource=read("stats-sequencer.js").replace("return {render,wire,simulate,weeklyPrograms,","return {projectCycles,trainingExecution,render,wire,simulate,weeklyPrograms,");
const {plan,trainBlock}=new Function("tornGuideApi","tornHappinessBook","tornBookTileStatus","localStorage","payload",read("stats-calculator.js")+"\n"+renderSource+"\nreturn {plan:tornTrainSequence,trainBlock:tornStatPlanner.internal.trainBlock};")(sandbox,()=>({active:false,known:true}),()=>"",{getItem:()=>JSON.stringify({selected:all,expanded:all,showOptimal:false})},(name,field)=>data[name]?.[field]??data[name]);
plan.settings.tornClockMin=720;plan.settings.resetAfterSec=900;
plan.render({state:{statValues:{strength:1000},compareStat:"strength",currentEnergy:150,happy:5000,maxHappy:5000},gym:{energy:10,strength:7.3},effectsFor:()=>({multiplier:1}),trainBlock},{keepClock:true});
let paid=0,refillSeen=false;
for(let i=0;i<all.length;i++){
 const id=all[i],projection=plan.projectCycles(id,1),cycleActions=actions(plan.trainingExecution(projection.log));
 assert.ok(projection.complete&&cycleActions.length>0,"simulated "+id);
 const s=JSON.parse(JSON.stringify({...session,label:labels[i],source:id==="natural"?"natural":"optimal-budget",sequence:[{id,start:0,at:projection.elapsed,gain:projection.gain}],deadline:null,periods:[1,7,28].map(days=>({days,gain:projection.gain,value:projection.money,energy:projection.used,costs:projection.costs})),drugRisk:projection.costs.xanax+projection.costs.ecstasy>0,budget:projection.money,cycleSpend:projection.money,actions:cycleActions}));
 assert.ok(recovery.validSession(s,now),"validator accepts simulator-generated "+id);
 if(id!=="natural"&&id!=="custom")paid++;
 if(cycleActions.some(a=>a.type==="refill"))refillSeen=true;
 if(id==="jump")assert.ok(cycleActions.some(a=>a.type==="dvd"));
 if(id==="maxhappy")assert.ok(cycleActions.some(a=>a.type==="externalHappy"));
 const first=cycleActions[0];
 const observation={at:now,barAt:now,cdAt:now,statAt:now,refillAt:now,energy:first.before.energy,cap:150,happy:first.before.happy,maxHappy:5000,drug:first.before.drug,booster:first.before.booster,stat:first.before.stat,refillUsed:false};
 assert.ok(recovery.validSession({...s,watch:{index:0,sample:observation}},now),"watch "+id);
 assert.equal(recovery.validSession({...s,watch:{index:0,sample:{...observation,barAt:now+10000}}},now),false);
}
assert.equal(paid,5);assert.equal(refillSeen,true);
console.log("All seven simulator-generated templates, premium action separation, refill rows and stale/future watch evidence checks passed.");

// The simulator fixture has a fixed clock; inject the same clock into the
// registry and stage adapter rather than relaxing observed-time validation.
const fixedDate=class extends Date{static now(){return now+1000;}};
const stagedAPI=new Function("Date",read("training-recovery.js")+"\n"+read("account-storage.js")+"\nreturn {registry:tornAccountStorage,recovery:tornTrainingRecovery};")(fixedDate);
const registry=stagedAPI.registry,stageAPI=stagedAPI.recovery;
function memory(entries={}){const m=new Map(Object.entries(entries));return {get length(){return m.size},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
const key="torn-city-guide:training-session:1",historyKey="torn-city-guide:activity-training-history:1";
const source=memory({[key]:JSON.stringify(session),[historyKey]:JSON.stringify([archive]),"torn-city-guide:training-session:2":JSON.stringify(session)});
const snap=registry.snapshot(source,1);assert.deepEqual(snap.records.map(x=>x.section),["training-cycle-history","training-session-review"]);
const target=memory();assert.equal(registry.restoreEmpty(target,1,snap.records,()=>true,{createdAt:now}),2);
assert.equal(target.getItem(key),null);assert.equal(stageAPI.held(target,1),true);assert.equal(stageAPI.held(target,2),false);
const stage=stageAPI.readStage(target,1);assert.deepEqual(stage.session,session);assert.equal(stage.backupCreatedAt,now);
assert.deepEqual(JSON.parse(target.getItem(historyKey)),[archive]);assert.deepEqual(registry.snapshot(target,1).records,snap.records);
assert.throws(()=>registry.restoreEmpty(target,1,snap.records),/already/);
assert.throws(()=>stageAPI.discardStage(target,1,stage.raw,()=>false),/changed/);
assert.equal(stageAPI.held(target,1),true);
stageAPI.discardStage(target,1,stage.raw,()=>true);assert.equal(stageAPI.held(target,1),false);assert.equal(target.getItem(key),null);
const conflict=memory({[key]:JSON.stringify(session),[stageAPI.reviewKey(1)]:stage.raw});
assert.deepEqual(registry.snapshot(conflict,1).omitted,["training-session-review"]);
const damaged=memory({[stageAPI.reviewKey(1)]:"bad"});assert.equal(stageAPI.held(damaged,1),true);assert.ok(stageAPI.readStage(damaged,1).error);
assert.ok(crime.includes("skipPrograms:recoveryHeld||")&&crime.includes("if(trainingRecoveryHeld())return recoveryHoldPanel()"));
console.log("Portable training/history round trip, staged-only restore, account isolation, hold, re-export, conflicting records and explicit discard passed.");

const current=now+1000,required=["bars","cooldowns","battlestats","profile","gym","perks","icons","refills"];
const currentState={identity:{id:1},data:{battlestats:{battlestats:{strength:{value:175058}}},profile:{profile:{faction_id:12}}},fetchedAt:Object.fromEntries(required.map(k=>[k,current])),errors:{},cachedSources:{}};
const currentLive={owner:1,energy:{source:"API",current:540},happy:{source:"API",current:5000},drug:0,booster:0,refillUsed:false,account:{blocked:false},criticalIssues:[],sources:{factionWars:{ready:false}}};
const evidence=stageAPI.evidenceReport(stage,currentLive,currentState,current,current);
assert.equal(evidence.stat,175058);assert.equal(evidence.confirmed,0);assert.equal(evidence.savedCheckpoint,null);assert.equal(evidence.warVerified,false);
for(const bad of [{...currentLive,owner:2},{...currentLive,energy:{source:"bridge",current:540}},{...currentLive,refillUsed:null},{...currentLive,account:{blocked:true}}])assert.throws(()=>stageAPI.evidenceReport(stage,bad,currentState,current,current));
assert.throws(()=>stageAPI.evidenceReport(stage,currentLive,{...currentState,cachedSources:{bars:true}},current,current),/incomplete/);
assert.throws(()=>stageAPI.evidenceReport(stage,currentLive,{...currentState,fetchedAt:{...currentState.fetchedAt,battlestats:current-1}},current,current),/incomplete/);
// Exercise the actual session loader/ledger/guard bodies with isolated storage.
const body=crime.slice(crime.indexOf("  let sessionOwner=null"),crime.indexOf("  const actionable="));
const active=memory({[key]:JSON.stringify(session),"torn-city-guide:training-spend:1":JSON.stringify([{started:now,at:now,cost:123}])});
const stateApi={state:{identity:{id:1}}};
const runtime=new Function("localStorage","tornGuideApi","tornTrainingRecovery",body+"\nreturn {loadTrainingSession,saveTrainingSession,accountForCycle,trainingSpend,trainingRecoveryHeld};")(active,stateApi,stageAPI);
assert.equal(runtime.loadTrainingSession().started,now);
active.setItem(stageAPI.reviewKey(1),stage.raw);
assert.equal(runtime.loadTrainingSession(),null);assert.equal(runtime.trainingSpend(current)[0].cost,123);
runtime.accountForCycle({...session,cycleSpend:999});assert.equal(runtime.trainingSpend(current).length,1);
runtime.saveTrainingSession();assert.equal(active.getItem(key),JSON.stringify(session));
stateApi.state.identity.id=2;assert.equal(runtime.trainingRecoveryHeld(),false);assert.equal(runtime.trainingSpend(current).length,0);
assert.ok(read("guide.js").includes('window.addEventListener("storage"'));
console.log("Fresh API-only evidence, stale/account mismatch rejection, live-loader hold, preserved ledger identity and blocked spend/write passed.");
