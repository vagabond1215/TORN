"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=name=>fs.readFileSync(path.join(__dirname,"..",name),"utf8");
const seq=new Function(read("stats-sequencer.js")+"\nreturn tornTrainSequence;")();
const now=Date.UTC(2026,10,26,12),stamp=now-60000;
const state={fetchedAt:{bars:stamp,cooldowns:stamp,refills:stamp},errors:{},data:{bars:{bars:{energy:{current:540,maximum:150},happy:{current:5000,maximum:5000}}},cooldowns:{cooldowns:{drug:{remaining:3600},booster:120}},refills:{refills:{energy_refill_used:false}}}};
const project=(key,bar,at,time)=>({current:bar.current,maximum:bar.maximum,observedAt:at,at:time});
let x=seq.liveInputs(state,now,project);
assert.equal(x.energy.current,540);assert.equal(x.happy.current,5000);assert.equal(x.drug,3540);assert.equal(x.booster,60);assert.equal(x.refillUsed,false);
state.bridge={timestamp:now,fields:["happy"]};x=seq.liveInputs(state,now,project);assert.equal(x.energy.observedAt,stamp);assert.equal(x.happy.observedAt,now);
state.fetchedAt.bars=now-300001;x=seq.liveInputs(state,now,project);assert.equal(x.energy,null);assert.ok(x.happy);
state.errors.cooldowns="failed";assert.equal(seq.liveInputs(state,now,project).drug,null);delete state.errors.cooldowns;
state.data.cooldowns.cooldowns.drug=null;assert.equal(seq.liveInputs(state,now,project).drug,null);
state.fetchedAt.refills=now-86400000;assert.equal(seq.liveInputs(state,now,project).refillUsed,null);
state.fetchedAt.refills=now;delete state.data.refills.refills.energy_refill_used;assert.equal(seq.liveInputs(state,now,project).refillUsed,null);
// Wiring guards: live mode must delegate, never use the chart optimizer.
const calc=read("stats-calculator.js"),crime=read("crime-guide.js");
assert.ok(calc.includes("tornCrimeGuide.trainingRecommendationContext()"));
assert.ok(calc.includes('comparisonMode==="live"?liveComparison():'));
assert.ok(crime.includes("const context=liveOptimizationContext(prefs,now)"));
assert.ok(crime.includes("liveInputs:inputs"));
assert.ok(crime.includes("tornStatPlanner.homeTrainingAdvice(budget,prefs.risk,options)"));
console.log("Live snapshot freshness, field-specific bridge, cooldown/refill unknowns and shared entrypoint assertions passed.");

// Fixed-clock real weekly optimizer: hypothetical candy/cooldown/cap settings
// cannot influence a live natural plan or erase a held stack.
const liveState={identity:{id:1},data:{profile:{donator_status:"Donator"},bars:{bars:{energy:{current:540,maximum:150},happy:{current:5000,maximum:5000}}},cooldowns:{cooldowns:{drug:3600,booster:120}},refills:{refills:{energy_refill_used:false}}},fetchedAt:{bars:now,cooldowns:now,refills:now},errors:{},inventory:{},inventoryErrors:{}};
const storage={getItem:()=>null,setItem:()=>{}};
const api={state:liveState};
const optimizer=new Function("tornGuideApi","localStorage","payload","tornHappinessBook","tornBookTileStatus",read("stats-sequencer.js")+"\nreturn tornTrainSequence;")(api,storage,(name,field)=>liveState.data[name]?.[field]??liveState.data[name],()=>({active:false}),()=>"");
const live=optimizer.liveInputs(liveState,now,project);
const ctx={state:{statValues:{strength:175058},compareStat:"strength",currentEnergy:540,maxEnergy:150,happy:5000,maxHappy:5000},gym:{energy:10,strength:10},effectsFor:()=>({multiplier:1}),trainBlock:(stat,happy,energy)=>({stat:stat+Math.floor(energy/10)*(10+happy/1000),happy,used:Math.floor(energy/10)*10})};
const options={liveInputs:live,naturalOnly:true,deadline:now+4*3600000};
const a=optimizer.weeklyPrograms(ctx,0,"low",options)[0];
assert.ok(a);assert.ok(a.used>=540);assert.equal(a.generatedAt,now);
optimizer.settings.startDrugMin=999;optimizer.settings.startBoosterMin=999;optimizer.settings.candyHappy=25;optimizer.settings.boosterCapH=48;
const b=optimizer.weeklyPrograms(ctx,0,"low",options)[0];
assert.equal(JSON.stringify(a),JSON.stringify(b));
assert.equal(optimizer.settings.candyHappy,25);assert.equal(optimizer.settings.boosterCapH,48);
assert.equal(optimizer.weeklyPrograms(ctx,0,"low",{...options,liveInputs:{...live,energy:null}}).length,0);
console.log("Fixed-clock weekly optimization preserves live stack and isolates hypothetical controls.");

// API tick phase remains available even when the bar is capped. The live
// engine uses the reported phase and increment rather than a reset clock.
const barsSrc=read("guide-features.js");
const projectReal=new Function("tornHappinessBook",barsSrc.slice(barsSrc.indexOf("function tornBarProjection("),barsSrc.indexOf("function homeCountdown("))+"\nreturn tornBarProjection;")(()=>({active:false}));
const cap=projectReal("energy",{current:150,maximum:150,tick_time:90,interval:600,increment:5},now,now);
assert.equal(cap.until,0);assert.equal(cap.nextTick,90);
assert.equal(projectReal("energy",{current:145,maximum:150,tick_time:90,interval:600,increment:5},now,now+100000).nextTick,590);
liveState.data.money={money:{points:60,wallet:250000}};liveState.fetchedAt.money=now;
const money=optimizer.liveInputs(liveState,now,project);
assert.equal(money.points,60);assert.equal(money.wallet,250000);
liveState.fetchedAt.money=now-900001;
assert.equal(optimizer.liveInputs(liveState,now,project).points,null);
liveState.fetchedAt.money=now;
const phaseCtx={...ctx,state:{...ctx.state,currentEnergy:140,maxEnergy:150}};
const phased={...live,energy:{current:140,maximum:150,interval:600,step:5,nextTick:90,phaseSource:"API"}};
const timed=optimizer.weeklyPrograms(phaseCtx,0,"low",{liveInputs:phased,naturalOnly:true,deadline:now+900000})[0];
assert.ok(timed);assert.equal(timed.execution.find(x=>x.type==="train").at,690);assert.equal(timed.used,150);
// With 30 owned points, a refill needs no point purchase; a second one needs
// exactly 30 purchased points. Reserved Xanax stays excluded from owned stock.
const costsSource=read("stats-sequencer.js").replace("return {render,wire,simulate,weeklyPrograms,","return {trainingPurchases,marketInputs,render,wire,simulate,weeklyPrograms,");
liveState.data.pointsCatalog={pointsmarket:[{cost:30}]};
liveState.data.itemCatalog={items:[{name:"Xanax",id:1,market_value:900}]};
liveState.inventory.Drug=[{name:"Xanax",amount:5}];
const costSeq=new Function("tornGuideApi","payload",costsSource+"\nreturn tornTrainSequence;")(api,(name,field)=>liveState.data[name]?.[field]??liveState.data[name]);
costSeq.marketInputs();
const purchases=costSeq.trainingPurchases(30,{reserveXanax:4});
assert.equal(purchases({refill:1,xanax:1}).cost,0);
assert.equal(purchases({refill:2,xanax:2}).cost,1800);
console.log("Observed regeneration phase, capped tick, verified points/wallet freshness, and reserved inventory pricing passed.");
