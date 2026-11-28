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
