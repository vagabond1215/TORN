"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {nice,train}=new Function(read("nice-merit-planner.js")+"\n"+read("stats-calculator.js")+"\nreturn {nice:tornNiceMerit,train:tornStatPlanner.internal};")();
const stats=(strength,defense,speed,dexterity)=>({strength,defense,speed,dexterity});
const gym={name:"fixture",energy:5,...stats(2,2,2,2)},multipliers=stats(1,1,1,1);
assert.deepEqual(nice.count(4206969.99),{n69:2,n420:1,total:3,mask:3});
assert.equal(nice.count(123.69420).total,0);assert.equal(nice.count(69420).total,2);
assert.equal(nice.count(Number.MAX_SAFE_INTEGER),null);assert.equal(nice.count(-1),null);
assert.equal(nice.inspect(stats(696969,42069,1,1)).met,true);
assert.equal(nice.inspect(stats(6969696969,1,1,1)).met,false);
assert.equal(nice.inspect(stats(420420420420420,1,1,1)).met,false);
assert.equal(nice.inspect(stats(6,9,420,696969)).met,false);
const gain=()=>1,base=stats(42068,68,69,68);
const plan=nice.solve({stats:base,happy:100,gym,multipliers,maxTrains:5},gain);
assert.equal(plan.status,"plan");assert.equal(plan.trains,3);assert.equal(plan.energy,15);
assert.deepEqual(plan.rows.map(r=>r.trains),[1,1,0,1]);assert.equal(plan.result.met,true);
assert.equal(nice.solve({stats:base,happy:100,gym,multipliers,maxTrains:2},gain).status,"not-found");
assert.equal(nice.solve({stats:base,happy:100,gym:{...gym,strength:0},multipliers,maxTrains:5},gain).status,"not-found");
assert.equal(nice.solve({stats:stats(696969,42069,1,1)},gain).status,"met");
assert.equal(nice.solve({stats:stats(1,2,3,4),happy:null,gym,multipliers},gain).status,"unavailable");
// Verify changing Happiness across stats, not independent fixed-happy gains.
const changing=nice.solve({stats:stats(42068,68,69,68),happy:100,gym,multipliers,maxTrains:5},(s,h)=>h>=90?1:10);
assert.equal(changing.status,"plan");assert.equal(changing.result.met,true);
// Cross-check against brute force using the actual shared gain model.
function brute(input){
 let best=Infinity;
 function visit(i,used,values){
  if(i===nice.order.length){if(nice.inspect(values).met)best=Math.min(best,used);return;}
  const stat=nice.order[i];let v=input.stats[stat],happy=Math.max(0,input.happy-used*input.gym.energy*.5);
  for(let n=0;n<=input.maxTrains-used;n++){
   visit(i+1,used+n,{...values,[stat]:v});
   v+=train.oneTrain(v,happy,input.gym[stat],input.gym.energy,input.multipliers[stat],stat);happy=Math.max(0,happy-input.gym.energy*.5);
  }
 }
 visit(0,0,{});return best;
}
for(const values of [stats(42068,68,69,68),stats(420690,69000,6969,420),stats(69600,42000,69000,68000),stats(123456,234567,345678,456789)]){
 const input={stats:values,happy:4500,gym,multipliers,maxTrains:9},out=nice.solve(input,train.oneTrain),expected=brute(input);
 assert.equal(out.status==="met"?0:out.status==="plan"?out.trains:Infinity,expected);
 if(out.status==="plan"){
  let h=input.happy;
  for(const row of out.rows){const r=train.trainBlock(row.value,h,row.energy,gym,row.stat,multipliers[row.stat]);assert.equal(r.stat,row.after);h=r.happy;}
  assert.equal(out.result.met,true);
 }
}
console.log("Nice honor integer patterns, both types, per-stat boundary, minimum bounded trains, restricted gym, shared Happiness and gain replay passed.");

const unlocked=train.niceUnlockedGyms([
 {id:1,name:"A",energy:5},{id:2,name:"B",energy:10},{id:3,name:"C",energy:25},{id:4,name:"D",energy:10}
],{gym:{active_gym:{id:1},unlocked_gyms:[{id:1,available:true},{id:2,available:true},{id:3,available:false},{id:999,available:true}]}},{id:1,name:"A",energy:5});
assert.deepEqual(unlocked.gyms.map(g=>g.id),[1,2]);assert.equal(unlocked.unavailable,1);assert.equal(unlocked.unresolved,1);
assert.equal(train.niceUnlockedGyms([{id:1,name:"A"},{id:2,name:"B"}],{gym:{active_gym:1}},{id:1,name:"A"}).unlockListKnown,false);
const multi=nice.opportunities({stats:stats(68,419,69,0),happy:100,energy:5,gyms:[{id:1,...gym},{id:2,...gym,name:"second",energy:10,strength:0}],multipliers,maxTrains:3},gain);
assert.equal(multi.checked,7);
assert.ok(multi.rows.some(r=>r.stat==="strength"&&r.pattern==="69"&&r.trains===1&&r.affordable));
assert.ok(multi.rows.some(r=>r.stat==="defense"&&r.pattern==="420"&&r.gymId==="2"&&r.trains===1&&!r.affordable));
assert.ok(!multi.rows.some(r=>r.stat==="strength"&&r.gymId==="2"));
assert.ok(!multi.rows.some(r=>r.stat==="speed"&&r.trains===0));
const preserved=nice.opportunities({stats:stats(6900,1,1,1),happy:100,energy:0,gyms:[{id:1,...gym}],multipliers,maxTrains:1},gain);
assert.ok(preserved.rows.some(r=>r.stat==="strength"&&!r.improved&&r.affordable===false));
assert.equal(nice.opportunities({stats:base,happy:null,gyms:[gym],multipliers},gain).status,"unavailable");
console.log("Nice unlocked gym availability, individual independent stat hits, affordability, existing-match distinction and stale input guard passed.");

 // Display projection selects the nearest HIGHER integer value, not the
 // first sorted alert (which may prioritize progress/completion or energy).
 const nearGym={...gym,id:10,name:"Slow gym",energy:10,strength:1,defense:0,speed:0,dexterity:0};
 const farGym={...gym,id:11,name:"Fast gym",energy:5,strength:2,defense:0,speed:0,dexterity:0};
 const valueGain=(s,h,d)=>d===1?0.5:351;
 const next=nice.opportunities({stats:stats(68.1,1,1,1),happy:100,energy:5,gyms:[farGym,nearGym],multipliers,maxTrains:3},valueGain);
 assert.deepEqual(next.nextByStat.map(x=>x.stat),nice.order);
 assert.equal(next.nextByStat[0].hit.gymId,"10");
 assert.equal(Math.floor(next.nextByStat[0].hit.after),69);
 assert.equal(next.nextByStat[0].hit.trains,2);
 assert.ok(next.nextByStat.slice(1).every(x=>x.hit===null));
 // Matching only the original integer is not the next occurrence.
 const fractional=nice.opportunities({stats:stats(6900.1,1,1,1),happy:100,gyms:[nearGym],multipliers,maxTrains:3},()=>0.5);
 assert.ok(fractional.rows.some(r=>r.stat==="strength"&&Math.floor(r.after)===6900));
 assert.equal(Math.floor(fractional.nextByStat[0].hit.after),6901);
 const tied=nice.opportunities({stats:stats(68,1,1,1),happy:100,gyms:[nearGym,{...nearGym,id:12,name:"Cheaper",energy:5}],multipliers,maxTrains:1},gain);
 assert.equal(tied.nextByStat[0].hit.gymId,"12");
 const noNext=nice.opportunities({stats:stats(6900.1,1,1,1),happy:100,gyms:[nearGym],multipliers,maxTrains:1},()=>0.1);
 assert.equal(noNext.nextByStat[0].hit,null);
 console.log("Nice display: one nearest higher whole-number endpoint per stat, gym tie-break and no-match rows passed.");

 // Combined all-gym search: neither gym can train every required stat.
 const strengthGym={id:51,name:"Strength gym",energy:5,...stats(2,0,0,0)};
 const otherGym={id:52,name:"Other gym",energy:10,...stats(0,2,2,2)};
 const multiInput={stats:base,happy:100,gyms:[strengthGym,otherGym],multipliers,maxTrains:5};
 const combined=nice.solveAcrossGyms(multiInput,gain);
 assert.equal(combined.status,"plan");assert.equal(combined.trains,3);assert.equal(combined.energy,25);
 assert.deepEqual(combined.rows.map(r=>r.gymId),["51","52",null,"52"]);
 assert.equal(combined.result.met,true);assert.equal(combined.finalHappy,87.5);
 const only=nice.solveAcrossGyms({...multiInput,gyms:[strengthGym]},gain);
 assert.equal(only.status,"partial");assert.equal(only.result.total,3);
 // Partial routes should populate the top table rather than return blanks.
 const partial=nice.solveAcrossGyms({stats:stats(68,419,68,68),happy:100,gyms:[strengthGym,otherGym],multipliers,maxTrains:4},gain);
 assert.equal(partial.status,"partial");assert.equal(partial.result.total,4);assert.equal(partial.result.n420,1);
 assert.equal(partial.trains,4);
 const no=nice.solveAcrossGyms({stats:stats(1,1,1,1),happy:100,gyms:[strengthGym,otherGym],multipliers,maxTrains:1},gain);
 assert.equal(no.status,"not-found");assert.equal(no.energy,0);assert.equal(no.rows.length,4);
 assert.ok(no.rows.every(r=>r.trains===0&&r.after===r.value));
 // Happiness MUST be replayed through each selected block, including
 // different gym costs; do not combine independent opportunity endpoints.
 const differentHappy=(s,h,d,c,_,stat)=>stat==="strength"?1:h===97.5?1:10;
 const coupled=nice.solveAcrossGyms({stats:stats(42068,68,69,69),happy:100,gyms:[strengthGym,otherGym],multipliers,maxTrains:2},differentHappy);
 assert.equal(coupled.status,"plan");assert.equal(coupled.energy,15);assert.equal(coupled.result.met,true);
 // Validate actual calculator replay for synthetic gyms and integer stats
 // from the reported screenshot; no claims about actual account perks.
 const fixtureGyms=[{id:1,name:"Premier Fitness",energy:5,...stats(2,2,2,2)},{id:2,name:"Average Joes",energy:5,...stats(2.4,2.8,2.4,2.4)},{id:5,name:"Silver Gym",energy:5,...stats(3.4,3.4,3.6,3.2)},{id:12,name:"Core",energy:10,...stats(5,5,5.2,5)},{id:18,name:"Gun Shop",energy:10,...stats(6.6,6.2,6.4,6.2)}];
 const screenshot={stats:stats(207649,723888,200065,51400),happy:4376,gyms:fixtureGyms,multipliers,maxTrains:200};
 const screenshotPlan=nice.solveAcrossGyms(screenshot,train.oneTrain);
 assert.ok(["plan","partial"].includes(screenshotPlan.status));
 let h=screenshot.happy,spent=0,trained=0;
 for(const row of screenshotPlan.rows){
   if(!row.trains){assert.equal(row.after,row.value);continue;}
   const g=fixtureGyms.find(g=>String(g.id)===row.gymId);
   assert.ok(g);const replay=train.trainBlock(row.value,h,row.energy,g,row.stat,multipliers[row.stat]);
   assert.equal(replay.stat,row.after);h=replay.happy;spent+=replay.used;trained+=row.trains;
 }
 assert.equal(spent,screenshotPlan.energy);assert.equal(trained,screenshotPlan.trains);assert.equal(h,screenshotPlan.finalHappy);
 assert.equal(nice.inspect(Object.fromEntries(screenshotPlan.rows.map(r=>[r.stat,r.after]))).total,screenshotPlan.result.total);
 console.log("Combined Nice route: mixed gyms, partial and no-progress states, cumulative Happiness and actual shared-model replay passed.");
