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
