"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const data={honors:{honors:[]},honorCatalog:{honors:[{id:888,name:"Nice",description:"Nice",category:"Gym"}]}};
const payload=(k,v)=>data[k]?.[v]??null;
const safe=x=>String(x??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const stats={strength:68,defense:419,speed:1,dexterity:1},gym={id:1,name:"Gym <A>",energy:5,strength:2,defense:2,speed:2,dexterity:2},live={stats,owner:"123",stamp:10,gym,gyms:[gym],unlockListKnown:true,happy:100,energy:5,multipliers:{strength:1,defense:1,speed:1,dexterity:1}};
let input=live;
const railCode=read("right-rail.js").replace("return {init,render,tick,order,controls,propertyModel,","return {init,render,tick,order,controls,propertyModel,merits,collapsible,");
const {rail,m}=new Function("payload","safe","tornStatPlanner",read("nice-merit-planner.js")+"\n"+read("merit-guide.js")+"\n"+railCode+"\nreturn {rail:tornRightRail,m:tornMeritGuide};")(payload,safe,{niceLiveInputs:()=>input,internal:{oneTrain:()=>1}});
let html=rail.collapsible(rail.merits(),"merits");
assert.ok(html.includes('class="rail-nice-badge"')&&html.indexOf('class="rail-nice-badge"')<html.indexOf("</summary>"));
assert.ok(html.includes(">NICE 0/5</span>")&&html.includes("Gym &lt;A&gt;")&&html.includes("Within current Energy"));
assert.ok(html.includes('class="rail-merit-list rail-nice-list"')&&!html.includes('class="rail-nice-notice"'));
assert.ok(html.includes('<strong>STR</strong><span>Gym &lt;A&gt;</span><small>1 train</small>'));
assert.ok(html.includes('<strong>DEF</strong><span>Gym &lt;A&gt;</span><small>1 train</small>'));
assert.equal((html.match(/class="rail-nice-row"/g)||[]).length,4);
input={...live,energy:0};html=rail.merits();assert.ok(html.includes(">NICE 0/5</span>")&&html.includes("More Energy needed"));
input={...live,stats:{...stats,speed:69}};html=rail.merits();assert.ok(html.includes(">NICE 1/5</span>"));
assert.ok(html.includes('<strong>SPD</strong><span><strong class="rail-nice-hold">HOLD</strong></span><small>0 trains</small>'));
assert.ok(!html.includes('<strong>SPD</strong><span>Gym &lt;A&gt;</span>'));
assert.ok(!html.includes("Nice training opportunity")&&!html.includes("Open Nice planner"));
input={...live,reason:"Stale gym"};assert.ok(!rail.merits().includes('class="rail-nice-badge"'));
input=live;data.honors.honors=[888];assert.ok(!rail.merits().includes('class="rail-nice-badge"'));
const api=read("guide-features.js");assert.ok(api.includes("route===routeName()&&!category")&&api.includes("tornRightRail.meritsVisible()")&&api.includes("...meritKeys])].filter(name=>stale(name,force))"));
console.log("Nice rail: actual progress badge, four compact stat/gym/train rows, escaped tooltips, affordability, earned/stale suppression and coordinator routing passed.");

 // Direct actions only; non-actionable milestones require evidence that
 // other confirmed easy honors cover the entire gap, without recursion.
 const c=(name,effort,done=false)=>({name,effort,done,detail:name,link:"#merits"});
 const shortlist=[c("Historian","Quick"),c("Landlord","Coordination"),c("The Affronted","Coordination"),c("Decorated","Progress"),c("Seeker","Progress"),c("Web of Perks","Progress"),c("Worker Bee","Progress"),c("Zero Liability","Progress"),c("10-stack","Progress"),c("Christmas in Torn","Seasonal"),c("Homing","Quick",true),c("Pocket Money","Quick",null)];
 const today=Date.UTC(2026,10,28),names=rows=>rows.map(x=>x.name);
 assert.deepEqual(names(m.railRecommendations([],shortlist,40,today)),["Historian","Landlord","The Affronted"]);
 assert.deepEqual(names(m.railRecommendations([],shortlist,246,today)),["Historian","Landlord","The Affronted"]);
 assert.deepEqual(names(m.railRecommendations([],shortlist,247,today)),["Historian","Landlord","The Affronted","Seeker"]);
 assert.equal(m.railRecommendations([],shortlist,247,today).at(-1).remaining,3);
 assert.ok(names(m.railRecommendations([],shortlist,99,today)).includes("Decorated"));
 assert.ok(!names(m.railRecommendations([],shortlist,null,today)).includes("Decorated"));
 assert.ok(names(m.railRecommendations([],shortlist,246,Date.UTC(2026,11,25))).includes("Seeker"));
 // Real rail render: every merit has its own card; Nice is one card
 // containing the compact four-stat list, not four separate merits.
 input=live;data.honors.honors=[];
 data.honorCatalog.honors.push({id:1,name:"Landlord"},{id:2,name:"The Affronted"},{id:3,name:"Seeker"},{id:4,name:"Web of Perks"});
 html=rail.merits();
 assert.ok(html.includes('class="rail-merit-card rail-nice-card"'));
 assert.ok(html.includes('class="rail-merit-card" aria-label="Landlord"'));
 assert.ok(html.includes('class="rail-merit-card" aria-label="The Affronted"'));
 assert.ok(html.includes("Irritate every city job interviewer."));
 assert.ok(!html.includes("avoid disrupting a current career")&&!html.includes(" · Coordination")&&!html.includes(" · Progress"));
 assert.ok(!html.includes('aria-label="Seeker"')&&!html.includes('aria-label="Web of Perks"'));
 // Count catalog-matched earned awards only when both user award lists
 // are loaded. A stale or absent selection must not unlock checkpoints.
 data.medals={medals:Array.from({length:248},(_,i)=>i+1000)};
 data.medalCatalog={medals:Array.from({length:248},(_,i)=>({id:i+1000,name:"Medal "+i}))};
 html=rail.merits();assert.ok(html.includes('aria-label="Seeker"')&&html.includes("Earn 250 awards"));
 data.medals=null;assert.ok(!rail.merits().includes('aria-label="Seeker"'));
 console.log("Merit rail cards, concise action-only copy, milestone gap, seasonal date and missing award data passed.");
