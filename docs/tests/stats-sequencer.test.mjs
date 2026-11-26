import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const calculator = readFileSync(new URL("../stats-calculator.js", import.meta.url), "utf8");
const sequencer = readFileSync(new URL("../stats-sequencer.js", import.meta.url), "utf8").replace("return {render,wire,simulate,weeklyPrograms,", "return {projectCycles,render,wire,simulate,weeklyPrograms,");
const templates = ["natural", "maxenergy", "mini", "low", "jump", "maxhappy", "custom"];
const items = [
  { id: 1, name: "Xanax", market_value: 900 },
  { id: 2, name: "Ecstasy", market_value: 50 },
  { id: 3, name: "Erotic DVD", market_value: 4000 },
  { id: 4, name: "Birthday Cupcake", market_value: 20 }
];

function fixture(selected, status = "Standard") {
  const storage = JSON.stringify({ selected, expanded: selected, showOptimal: false });
  const data = {
    profile: { donator_status: status },
    itemCatalog: { items },
    pointsCatalog: { pointsmarket: [{ cost: 30 }] }
  };
  const api = { state: { data, fetchedAt: {}, errors: {}, inventoryErrors: {}, inventory: { Candy: [{ name: "Birthday Cupcake", amount: 60 }], Booster: [] } } };
  const sandbox = vm.createContext({
    tornGuideApi: api,
    tornHappinessBook: () => ({ active: false, known: true }),
    tornBookTileStatus: () => "",
    localStorage: { getItem: () => storage },
    payload: (name, field) => data[name]?.[field] ?? data[name]
  });
  const { plan, trainBlock } = vm.runInContext(
    calculator + "\n" + sequencer + "\n({ plan:tornTrainSequence, trainBlock:tornStatPlanner.internal.trainBlock })", sandbox
  );
  const context = {
    state: { statValues: { strength: 1000 }, compareStat: "strength", currentEnergy: 100, happy: 5000, maxHappy: 5000 },
    gym: { energy: 10, strength: 7.3 },
    effectsFor: () => ({ multiplier: 1 }),
    trainBlock
  };
  plan.settings.tornClockMin = 720;
  plan.settings.resetAfterSec = 900;
  const html = plan.render(context, { keepClock: true });
  return { plan, html, api };
}

const types = list => Array.from(list, action => action.type);
const executed = data => data.log.filter(event => event.editable);

// The current chart is cycle-based; fixed-duration comparisons explicitly
// specify their horizon instead of assuming every template is a 24h action list.
const expectedCycleHours={natural:5,maxenergy:7,mini:38100/3600,low:12900/3600,jump:28,maxhappy:28,custom:0};
const expectedEnergy={natural:100,maxenergy:800,mini:770,low:200,jump:1100,maxhappy:1100,custom:100};
for (const id of templates) {
  test(id + " runs alone and in the shared comparison", () => {
    const alone=fixture([id]), comparison=fixture(templates);
    for(const {plan,html} of [alone,comparison]){
      const list=plan.steps[id], data=plan.projectCycles(id,1);
      assert.equal(data.complete,true);
      assert.equal(data.completed,1);
      assert.equal(data.elapsed,expectedCycleHours[id]*3600);
      assert.equal(data.used,expectedEnergy[id]);
      assert.deepEqual(types(executed(data)),types(list));
      assert.ok(data.gain>0 && data.final===data.initial.stat+data.gain);
      assert.equal(data.initial.energy,["natural","jump","maxhappy"].includes(id)?0:100);
      if(id==="low")assert.equal(data.energy,70);else assert.ok(data.energy<10);
      const {xanax,ecstasy,dvd,candy,refill,externalHappy}=data.costs;
      assert.equal(data.money,xanax*900+ecstasy*50+dvd*4000+candy*20+refill*900+externalHappy*200000000);
      assert.match(html,new RegExp('data-ts-timeline="'+id+'"'));
    }
  });
}
test("NAT uses full bars and the available partial bar at the endpoint", () => {
  for(const [status,cap] of [["Standard",100],["Donator",150],["Subscriber",150]]){
    const {plan}=fixture(["natural"],status);
    const data=plan.projectCycles("natural",Infinity,{end:86400,continuous:true});
    assert.deepEqual(Array.from(executed(data),e=>e.end.time/3600),[5,10,15,20]);
    assert.ok(executed(data).every(e=>e.start.energy===cap));
    assert.equal(data.used,cap===100?480:720);
    assert.equal(data.log.at(-1).start.energy,cap===100?80:120);
    assert.equal(data.log.at(-1).editable,false);
    assert.equal(data.elapsed,86400);
  }
});
test("MAX E, MINI and LOW# expose their actual cycle and respect drug timing",()=>{
  const prefixes={maxenergy:["xanax","candy","train","refill","train"],mini:["xanax","candy","ecstasy","train","refill","train"],low:["candy","ecstasy","train","refill","train"]};
  for(const status of ["Standard","Donator"]){
    const {plan}=fixture(Object.keys(prefixes),status);
    for(const [id,prefix] of Object.entries(prefixes)){
      const list=plan.steps[id],data=plan.projectCycles(id,1);
      assert.deepEqual(types(list.slice(0,prefix.length)),prefix);
      const opener=executed(data).slice(0,prefix.length);
      assert.equal(list[prefix.indexOf("candy")].max,true);
      assert.equal(opener[prefix.indexOf("candy")].end.time,id==="mini"?25200:0);
      assert.equal(data.costs.refill,1);
      const followups=executed(data).slice(prefix.length);
      if(id==="low"){
        assert.equal(data.costs.xanax,0);
        assert.equal(data.elapsed,12900);
        assert.deepEqual(types(followups),["wait"]);
        assert.equal(followups[0].end.drug,0);
        assert.equal(data.energy,status==="Standard"?70:105);
        continue;
      }
      assert.deepEqual(types(followups),["xanax","train"]);
      assert.equal(followups[0].start.time,opener.at(-1).end.time+opener.at(-1).end.drug);
      assert.equal(followups[0].start.drug,0);
      assert.equal(followups[1].end.time,followups[0].end.time);
      assert.ok(followups[1].end.stat>followups[0].end.stat);
      assert.ok(followups[0].start.energy<=(status==="Standard"?100:150));
      assert.equal(data.costs.xanax,2);
      assert.equal(data.lostRegen,id==="mini"?(status==="Standard"?140:210):(status==="Standard"?40:60));
    }
  }
});

test("HJ and 99k keep their opener only and use boosters without a one-second delay", () => {
  const { plan } = fixture(["jump", "maxhappy"]);
  for (const [id, booster] of [["jump", "dvd"], ["maxhappy", "externalHappy"]]) {
    const list = plan.steps[id];
    assert.deepEqual(types(list), ["xanax", "xanax", "xanax", "xanax", booster, "ecstasy", "train", "refill", "train"]);
    const data = plan.simulate(list);
    const opening = executed(data);
    assert.deepEqual(Array.from(opening.slice(0, 4), e => e.end.time / 3600), [0, 7, 14, 21]);
    assert.ok(opening.slice(4).every(e => e.end.time === 28 * 3600));
    assert.equal(data.costs.dvd, id === "jump" ? 5 : 0);
    assert.equal(data.peakHappy, id === "jump" ? 35000 : 99999);
  }
});

test("live cooldowns produce delay and hazard notices, and real Happiness resets before training", () => {
  const { plan } = fixture(["mini"]);
  const cooldown = plan.simulate(plan.steps.mini, { startDrugMin: 30 });
  assert.equal(executed(cooldown)[0].end.time, 1800);
  assert.ok(cooldown.notices.some(x => x.critical && x.text.startsWith("DELAY")));
  const candy = plan.simulate([{ type: "candy", max: true }, { type: "wait", minutes: 20 }, { type: "train" }],
    { startEnergy: "full", startBoosterMin: 60, resetAfterSec: 600 });
  assert.ok(candy.notices.some(x => !x.critical && x.text.includes("possible")));
  assert.equal(executed(candy)[0].end.time, 0);
  const reset = candy.log.find(x => x.type === "happyReset");
  assert.equal(reset.end.time, 600);
  assert.ok(reset.start.happy > reset.end.happy);
  assert.equal(executed(candy).at(-1).start.happy, 5000);
  const blocked = plan.simulate([{ type: "xanax" }], { startEnergy: "zero", startDrugMin: 30, autoWait: false });
  assert.equal(blocked.complete, false);
  assert.equal(blocked.log.at(-1).reason, "End of comparison · remaining Energy");
});

test("changing, deleting and moving projected player actions changes the replay", () => {
  const { plan } = fixture(["maxenergy"]);
  const original = plan.steps.maxenergy;
  const baseline = plan.simulate(original, { startEnergy: "full" });
  const xanax = original.findIndex((a, i) => i > 0 && a.type === "xanax");
  const run = list => plan.simulate(list, { startEnergy: "full" });
  const changed = original.map((a, i) => i === xanax ? { type: "wait", minutes: 5 } : a);
  assert.notEqual(run(changed).gain, baseline.gain);
  const deleted = original.filter((_, i) => i !== xanax + 1);
  assert.notEqual(run(deleted).gain, baseline.gain);
  const moved = [...original];
  [moved[xanax], moved[xanax + 1]] = [moved[xanax + 1], moved[xanax]];
  assert.notEqual(run(moved).gain, baseline.gain);
});

test("a shorter replay keeps its action list and still spends usable Energy", () => {
  const { plan } = fixture(["natural", "jump"]);
  const list = plan.steps.natural;
  const saved = JSON.stringify(list);
  const data = plan.projectCycles("natural", Infinity, { end: 86400, continuous: true });
  assert.equal(JSON.stringify(list), saved);
  assert.equal(executed(data).length, 4);
  assert.equal(data.log.at(-1).type, "train");
  assert.equal(data.log.at(-1).editable, false);
  assert.equal(data.log.at(-1).end.time, 86400);
  assert.equal(data.used, 480);
});

test("unavailable inventory leaves the follow-up rows accessible for editing", () => {
  const { plan, api } = fixture(["maxenergy"]);
  const expected = types(plan.steps.maxenergy);
  delete api.state.inventory.Candy;
  plan.render(undefined, { keepClock: true });
  assert.deepEqual(types(plan.steps.maxenergy), expected);
  const data = plan.simulate(plan.steps.maxenergy);
  assert.equal(data.complete, false);
  assert.match(data.errors[0], /MAX requires loaded inventory/);
  assert.equal(data.log.at(-1).end.time, plan.settings.hours*3600);
});
