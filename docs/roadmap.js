"use strict";
/* Step-by-step beginner roadmap. Uses existing per-profile progress keys. */
const tornRoadmap=(()=>{
 const official={
  mission:"https://wiki.torn.com/wiki/New_Player_Missions",job:"https://wiki.torn.com/wiki/Joblist",
  company:"https://wiki.torn.com/wiki/Company/Company_List",education:"https://wiki.torn.com/wiki/Education",
  gym:"https://wiki.torn.com/wiki/Gym",faction:"https://wiki.torn.com/wiki/Faction",
  crime:"https://wiki.torn.com/wiki/Crimes_2.0",bank:"https://wiki.torn.com/wiki/Bank",
  travel:"https://wiki.torn.com/wiki/Travel",property:"https://wiki.torn.com/wiki/Properties",
  merit:"https://wiki.torn.com/wiki/Merit",award:"https://wiki.torn.com/wiki/Award",
  stocks:"https://wiki.torn.com/wiki/Stock_Market",revive:"https://wiki.torn.com/wiki/Revive",
  race:"https://wiki.torn.com/wiki/Raceway",points:"https://wiki.torn.com/wiki/Points"
 };
 const core=[
  ["The first session",
   ["tutorial","Finish beginner missions and protect your one-time rewards","Follow the tutorial and learn how Energy, Nerve, Happiness and cash work. Keep track of any one-time reward, especially Piggy Bank decisions.","mission"],
   ["first-merit","Start with inexpensive honors","Open Awards and identify early low-cost merits. Avoid spending heavily just to collect a single honor.","award"],
   ["affronted","Consider The Affronted before committing to jobs","The six city job interviewers can award The Affronted honor for irritating them. Do it early if you want the honor; verify the steps before changing careers.","job"],
   ["education-start","Enroll in an education course now","Never leave education idle. Early Biology / Intravenous Therapy or work-stat preparation can be valuable; specialize later.","education"],
   ["first-job","Begin a career or apply to a training-friendly player company","Compare daily working-stat training, eligibility, unlocked company stars, job points, addiction requirements and wages. Casino is an accessible alternative while searching.","job"],
   ["faction","Find a helpful and active faction","Ask about faction armory access, new-player guidance, Steadfast gym gains, wars, organized crimes, and medical support.","faction"],
   ["cash-protect","Protect cash and avoid unnecessary retaliation","Use appropriate secure storage and avoid accumulating visible cash. Do not start trouble with active players without a reason or your faction's direction.","bank"]],
  ["First days",
   ["first-property","Rent a realistic happiness upgrade","Better housing boosts early gym training. Compare short rentals of Mansion or Castle against your budget; skip luxury properties that consume your training fund.","property"],
   ["training-habit","Spend Energy intentionally and keep improving gym quality","Train most non-mission / non-war Energy, upgrade gyms as you unlock them, and compare Happy with raw Energy spending before expensive jumps.","gym"],
   ["starter-crimes","Develop Crime Experience with reliable Crimes 2.0 success","Start with Search for Cash / Bootlegging / Graffiti and work upward. Avoid repeated red failures. A safe CE foundation helps later crimes and NNB.","crime"],
   ["equipment","Use inexpensive or faction-supplied gear","Compare armor coverage, weapon damage/accuracy, magazine size, and useful temporary items. Save the bankroll for training, housing and income.","faction"],
   ["company-training","Ask a company about daily trains and achievable perks","Companies are often more useful for work-stat growth or specials than wages. A 3★ Adult Novelties company can exchange job points for eDVDs.","company"],
   ["missions","Progress George and Duke missions sensibly","Learn core mechanics and collect mission credits without wasting Energy on avoidable, high-risk fights. Preserve rare books until you can fully use them.","mission"],
   ["honors","Build a low-cost honor and merit plan","Collect accessible awards from training, city interactions, missions, crimes, jobs, travel and other normal activity.","award"]],
  ["Reach level 15",
   ["level15","Reach level 15 to unlock air travel","Use appropriate leveling targets and choose Leave for experience. Balance fast leveling with enough gym training to survive.","travel"],
   ["travel-income","Begin short profitable overseas runs","Compare flowers, plushies and selected drugs using a trusted stock/profit tool; account for flying time, carried cash and selling risk.","travel"],
   ["stock-ticker","Unlock the 50-point Stock Ticker","The ticker allows stock-market access. This is separate from racing points and Energy refills.","stocks"],
   ["pi-rent","Plan a Private Island rental with airstrip","An airstrip and pilot improve travel efficiency. Rent when affordable; a Castle can be a temporary happiness bridge.","property"],
   ["suitcase","Add a Large Suitcase when extra cargo pays for itself","Large Suitcase currently adds three item slots, subject to Torn's later travel rule changes. Do the payback calculation first.","travel"],
   ["travel-safety","Protect travel profits and avoid OC conflicts","Carry only planned purchase money, avoid returning too late for organized crimes or wars, and store your sale proceeds promptly.","travel"]],
  ["Compound account upgrades",
   ["education-merit","Work toward 10/10 Education Length merits","Each upgrade shortens future courses. Full investment costs 55 merits, so phase it around your award income.","merit"],
   ["workstats","Grow working stats toward top city-career requirements","Use player-company training and relevant education. Work toward Principal, Brain Surgeon and Federal Judge without sacrificing good training opportunities.","job"],
   ["principal","Complete the Education career to Principal","Unlock the permanent 10% future course-time reduction. This complements Education merits and the WSU stock benefit.","job"],
   ["medical-passive","Complete Medical to Brain Surgeon if revives fit your goals","Reviving unlocks at the top of the career. Even a non-reviver may want the permanent capability eventually.","job"],
   ["law-passive","Complete Law to Federal Judge","The current permanent benefit is +5% Crime Experience and Crime Skill growth, not the old guides' crime-success bonus.","job"],
   ["bank-merit","Develop Bank Interest toward 10/10 as capital grows","The value of bank merits rises with your deposits. Do not starve essential early training or rent to rush an empty bank.","bank"],
   ["wsu","Acquire the WSU education stock block when feasible","1 million WSU shares grants a further future-course reduction. Compare the purchase against more urgent income and training goals.","stocks"],
   ["bank-2b","Build sustainable bank and passive income","Gradually work toward the ordinary bank cap while maintaining liquidity for training, traveling and war expenses.","bank"]],
  ["Establish a sustainable midgame",
   ["war-ready","Learn your faction's war preparation and payout rules","Know target rules, medical limits, temporary weapon choices, communications and whether your faction expects Energy stacking.","faction"],
   ["crime-progression","Continue Crimes 2.0 and useful organized crimes","Aim for safe Crime Skill milestones, avoid red failures and pick OC roles you can support without missing travel returns.","crime"],
   ["racing-plan","Race as a long-term side progression","Preserve upgrade points: spend 0 in E and limit D/C/B upgrades so you enter A with a competitive budget.","race"],
   ["pi-buy","Buy a Private Island only after the economics make sense","Treat ownership and improvements as a major purchase, not an early prerequisite for strong happiness or travel.","property"],
   ["build-focus","Revisit your main gameplay style periodically","Choose a sustainable direction for Energy, travel time, work, capital and combat. Hybrid strategies are valid.","faction"]]
 ];
 const branches={
  Trade:[
   ["trade-market","Learn market pricing and safe settlement","Compare dealer margins, market fees and mug risk; use reputation and safe procedures for high-value trades.","travel"],
   ["trade-company","Seek Toy/Flower Shop capacity or Lingerie perks","Plushie / flower capacity is useful to early travel traders; Lingerie offers business-class travel at high stars.","company"],
   ["trade-tools","Set up a stock and route planner","Use Torn PDA, TornW3B or Torn Travel Planner to check destination stock and estimated net profits.","travel"]
  ],
  Mug:[
   ["mug-combat","Build a dedicated PvP stat plan","Prioritize fighting reliability, accuracy, speed, defense and faction instructions before attempting profitable mugs.","gym"],
   ["mug-safety","Review hospital timers and retaliation risk","Do not assume opportunistic mugs are consequence-free; assess target activity, mug protection and your faction rules.","faction"],
   ["mug-gear","Compare mugging-oriented companies and gear","Evaluate combat and stealth utility versus raw training gains and the cost of opportunity.","company"]
  ],
  Business:[
   ["business-education","Plan Business education and work-stat development","The management path needs substantial working stats and knowledge of pricing, role assignment, advertising and staff happiness.","education"],
   ["business-apprentice","Work for an experienced company director first","Observe staff training, profitability, star growth, job specials and employee expectations before risking capital.","company"],
   ["business-capital","Model a company budget before owning one","Keep payroll, advertising, upgrades, employees and investment reserves separate from personal training funds.","company"]
  ],
  War:[
   ["war-stats","Build war-relevant raw gym gains and defensive passives","Ladies Strip Club supports Defense, Gents supports Dexterity, Fitness Center general gym gains; evaluate faction Steadfast too.","company"],
   ["war-medical","Unlock blood-bag handling and prepare medical cooldown","Consider Biology coursework, revive planning, temporary items and the faction armory.","education"],
   ["war-participation","Train and participate within faction war rules","Follow callouts, ranked war schedules, target restrictions and payout policies. Preserve Energy outside planned windows.","faction"]
  ],
  Revive:[
   ["revive-unlock","Complete Medical to Brain Surgeon","Unlock reviving before committing to an Energy-heavy healer lifestyle.","job"],
   ["revive-company","Compare Farm / other Energy-for-JP companies","At 10★ Farm converts a job point into seven Energy; compare real JP generation, medical efficiency and salary.","company"],
   ["revive-economy","Plan repeatable revive economics","Track Energy, cooldown, revive success, skill growth, faction support and hospital needs.","revive"]
  ],
  Crime:[
   ["crime-safe","Raise hidden CE by reliably completing low-risk crimes","High early success rates build CE, CS and crime chains. Avoid avoidable red failures.","crime"],
   ["crime-law","Complete Federal Judge and consider Crime Progression merits","The Law permanent passive increases CE/CS growth, supporting organized-crime roles.","job"],
   ["crime-oc","Choose organized crime roles and schedule travel around them","Coordinate faction OC start times and required items; do not travel when you will miss an activation.","faction"]
  ],
  Racing:[
   ["race-license","Acquire the Racing License and begin official races","You need the Points Building license. Official races award upgrade points; custom races mainly build skill.","race"],
   ["race-budget","Preserve points through E/D/C/B","Default conservation target: 0 points spent in E, ~15 D, ~63 C, ~130 B, leaving about 267 upon reaching A.","race"],
   ["race-job","Consider racing job-point companies","Car Dealership and Mechanic Shop have racing point / car-part specials worth weighing against other growth.","company"]
  ],
  Training:[
   ["train-bonus","Stack real gym-gain benefits, not combat-only passives","Use better gyms, faction Steadfast, Sports Science, happiness and useful company perks.","gym"],
   ["train-compare","Compare Natural Energy and Happy Jumps over equal time","A jump sacrifices natural regeneration while Xanax is stacked. Test item sequences and realistic cooldowns.","gym"],
   ["train-book","Plan 31-day books around cash, perks and activity","Do not activate rare training books without enough funds and Energy to maximize the full effect window.","gym"]
  ]
 };
 let selected=null,selectedFor=null;
 const esc=v=>String(v==null?"":v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
 const activityOptions=[["War","War"],["Mug","Mugging"],["Trade","Trading"],["Travel","Travel"],["Training","Gym training"],["Revive","Reviver"],["Jail","Jail break / busting"],["Business","Business"],["Crime","Crime"],["OC","Organized crimes"],["Racing","Racing"],["Money","Investing"],["Gambling","Gambling"],["Education","Education"],["Merits","Merit hunting"]];
 const styleOptions=activityOptions.map(([id])=>id);
 const activityLabels=Object.fromEntries(activityOptions);
 Object.assign(branches,{
  Travel:[["travel-plan","Plan profitable travel routes","Compare travel time, item prices and carrying capacity.","travel"]],
  Jail:[["jail-bust","Develop busting and jail-release capability","Review Law education, relevant merits and job specials.","job"]],
  OC:[["oc-roles","Prepare organized crime roles","Coordinate with your faction and check required items and scheduling.","crime"]],
  Money:[["invest-plan","Compare bank and stock investments","Balance liquidity, recurring returns and training expenses.","stocks"]],
  Education:[["education-focus","Prioritize useful education effects","Use education paths and reduce future course durations.","education"]],
  Merits:[["merit-focus","Track attainable awards and merits","Prioritize awards that fit your normal activity.","award"]]
 });
 function selectedStyles(){
  const owner=activeProfile||"guest";
  if(selectedFor!==owner){selectedFor=owner;selected=null;}
  if(selected)return selected;
  let data;
  try{data=JSON.parse(read(activeProfile?activeKey("playstyle:selection"):"playstyle:guest")||"[]");}catch{data=[];}
  selected=Array.isArray(data)?[...new Set(data.filter(x=>styleOptions.includes(x)))]:[];
  return selected;
 }
 function preferences(){
  let data={};
  try{data=JSON.parse(read(activeProfile?activeKey("playstyle:preferences"):"playstyle:guest:preferences")||"{}")||{};}catch{}
  return {priority:["growth","networth","company","education","completion"].includes(data.priority)?data.priority:data.priority==="money"?"networth":"growth",risk:["low","medium","high"].includes(data.risk)?data.risk:"low",weeklyBudget:data.weeklyBudget!=null&&Number.isFinite(Number(data.weeklyBudget))?Math.max(0,Number(data.weeklyBudget)):null};
 }
 function renderActivities(){
  const p=preferences();
  const radio=(name,opts,value)=>'<div class="roadmap-styles">'+opts.map(([id,label])=>'<label class="roadmap-style"><input type="radio" name="home-'+name+'" data-home-pref="'+name+'" value="'+id+'" '+(value===id?"checked":"")+'><span>'+esc(label)+'</span></label>').join("")+'</div>';
  return '<section class="panel home-activities"><div class="panel-heading"><h2>Playstyle / activities</h2></div><div class="panel-content"><div class="roadmap-styles">'+activityOptions.map(([id,label])=>'<label class="roadmap-style"><input type="checkbox" data-roadmap-style="'+esc(id)+'" '+(selectedStyles().includes(id)?"checked":"")+'><span>'+esc(label)+'</span></label>').join("")+'</div><div class="home-pref-row"><div class="home-pref-group"><strong>Priority</strong>'+radio("priority",[["growth","Stat Growth"],["networth","Networth"],["company","Company"],["education","Education"],["completion","Completion"]],p.priority)+'</div><div class="home-pref-group"><strong title="Financial exposure: carried cash, trade settlement, gambling losses and investment volatility. Not drug use or training intensity.">Financial risk</strong>'+radio("risk",[["low","Low"],["medium","Medium"],["high","High"]],p.risk)+'</div><label class="home-budget"><strong>Weekly budget</strong><span>$</span><input type="number" min="0" step="any" data-home-pref="weeklyBudget" value="'+(p.weeklyBudget??"")+'" placeholder="Not set" aria-label="Weekly training budget"></label></div></div></section>';
 }
 function wireActivities(view){
  if(view.dataset.activitiesBound==="1")return;
  view.dataset.activitiesBound="1";
  const updateBudget=el=>{
   const p=preferences();p.weeklyBudget=el.value===""?null:Math.max(0,Number(el.value)||0);
   write(activeProfile?activeKey("playstyle:preferences"):"playstyle:guest:preferences",JSON.stringify(p));
   tornCrimeGuide.refreshRecommendations(view);
  };
  view.addEventListener("input",event=>{if(event.target.dataset.homePref==="weeklyBudget"&&event.target.closest(".home-activities")&&event.target.validity.valid)updateBudget(event.target);});
  view.addEventListener("change",event=>{
   const el=event.target,value=el.dataset.roadmapStyle;
   if(!el.closest(".home-activities"))return;
   if(styleOptions.includes(value)){
    selected=selectedStyles().filter(x=>x!==value);
    if(el.checked)selected.push(value);
    write(activeProfile?activeKey("playstyle:selection"):"playstyle:guest",JSON.stringify(selected));
   }else if(el.dataset.homePref==="weeklyBudget"){
    updateBudget(el);return;
   }else if(el.dataset.homePref&&el.checked){
    const p=preferences(),key=el.dataset.homePref;
    if(key==="priority"&&["growth","networth","company","education","completion"].includes(el.value)||key==="risk"&&["low","medium","high"].includes(el.value)){
     p[key]=el.value;write(activeProfile?activeKey("playstyle:preferences"):"playstyle:guest:preferences",JSON.stringify(p));
    }
   }else return;
   tornCrimeGuide.refreshRecommendations(view);
  });
 }
 function all(){
  const common=core.flatMap(([stage,...items])=>items.map(([id,title,detail,source])=>({stage,id,title,detail,source:official[source]})));
  const styles=selectedStyles().filter(x=>x!=="Balanced");
  for(const style of styles)for(const [id,title,detail,source] of branches[style])
   common.push({stage:(activityLabels[style]||style)+" specialization",id,title,detail,source:official[source]});
  return common;
 }
 function verified(id){
  const st=tornGuideApi.state;
  if(id==="level15")return !!(st.identity&&Number(st.identity.level)>=15);
  if(id==="education-start"){
    const course=st.data.education&&(st.data.education.education||st.data.education).current;
    return !!(course&&course.id!=null);
  }
  if(id==="first-property"||id==="pi-rent"){
    const raw=st.data.property&&(st.data.property.property||st.data.property);
    const name=raw&&(raw.name||raw.property?.name);
    if(!name)return false;
    const isPi=/private\s*island/i.test(String(name));
    return id==="pi-rent"?isPi:!/^(shack|trailer)$/i.test(String(name));
  }
  if(id==="bank-2b"){
    const money=st.data.money&&(st.data.money.money||st.data.money);
    return !!(money&&money.city_bank&&Number(money.city_bank.amount)>=2000000000);
  }
  if(id==="stock-ticker"){
    const stocks=st.data.stocks&&(st.data.stocks.stocks||st.data.stocks);
    return Array.isArray(stocks)&&stocks.length>0;
  }
  const legacy=guideSteps.find(step=>step.id===id);
  return !!(legacy && autoDone(legacy));
 }
 function checked(id){return verified(id)||read(stepKey(id))==="done";}
 function render(){
  const entries=all(),done=entries.filter(s=>checked(s.id)).length;
  let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Checklist & beginner roadmap</h1>'+
   '<p>A practical step-by-step progression from the first session to a sustainable midgame, with optional routes for your preferred gameplay style. Your existing Quickstart progress is retained.</p></header>';
  out+='<section class="panel"><div class="panel-heading"><h2>Daily essentials</h2></div><div class="panel-content"><p id="task-progress" role="status"></p>'+
   '<div class="checklist">'+Object.entries(tasks).map(([id,label])=>'<label><input type="checkbox" name="'+esc(id)+'" '+(!activeProfile?"disabled":"")+'><span>'+esc(label)+'</span></label>').join("")+'</div>'+
   '<p class="fine-print">Daily items use your existing checklist. Reopen or uncheck when a new day begins.</p></div></section>';
  out+='<section class="panel roadmap-summary"><div class="panel-content"><strong id="roadmap-progress">'+done+' of '+entries.length+' current milestones complete</strong><div class="roadmap-bar"><span style="width:'+Math.round(done/entries.length*100)+'%"></span></div></div></section>';
  const stages=[...new Set(entries.map(x=>x.stage))];
  for(const [index,stage] of stages.entries()){
   const items=entries.filter(x=>x.stage===stage),doneHere=items.filter(x=>checked(x.id)).length;
   out+='<details class="panel roadmap-stage" '+(index<=1?"open":"")+'><summary><strong>'+esc(stage)+'</strong><small>'+doneHere+' / '+items.length+' complete</small></summary><div class="panel-content roadmap-steps">';
   for(const step of items){
    const auto=verified(step.id),complete=checked(step.id);
    out+='<div class="roadmap-step"><label><input type="checkbox" data-roadmap-step="'+esc(step.id)+'" '+(complete?"checked":"")+' '+(auto?"disabled":"")+'><span><strong>'+esc(step.title)+'</strong><small>'+esc(step.detail)+'</small></span></label>'+
     '<div class="roadmap-step-foot">'+(auto?'<span class="verified">Verified by API</span>':"")+
     '<a href="'+esc(step.source)+'" target="_blank" rel="noopener noreferrer">Reference</a></div></div>';
   }
   out+='</div></details>';
  }
  out+='<section class="panel"><div class="panel-content"><p class="fine-print">Sources: the faction rough beginner guide (May–August 2026), official Torn wiki, and community beginner guides. Progress is personal, not a promise that each milestone is universally optimal. Property and item prices change.</p></div></section>';
  return out;
 }
 function setupDaily(view){
  const boxes=[...view.querySelectorAll('.checklist input[type="checkbox"]')];
  for(const box of boxes)if(activeProfile)box.checked=read(activeKey("task:"+box.name))==="done";
  const status=view.querySelector("#task-progress");
  if(status)status.textContent=boxes.filter(b=>b.checked).length+" of "+boxes.length+" complete";
 }
 function wire(view){
  setupDaily(view);
  if(view.dataset.roadmapBound==="1")return;
  view.dataset.roadmapBound="1";
  view.addEventListener("change",event=>{
   const el=event.target;
   if(el.dataset.roadmapStep){
    write(stepKey(el.dataset.roadmapStep),el.checked?"done":null);
    const entries=all(),count=entries.filter(step=>checked(step.id)).length;
    const progress=view.querySelector("#roadmap-progress");
    if(progress)progress.textContent=count+" of "+entries.length+" current milestones complete";
    const bar=view.querySelector(".roadmap-bar span");
    if(bar)bar.style.width=Math.round(count/entries.length*100)+"%";
   }else if(el.closest(".checklist")&&activeProfile){
    write(activeKey("task:"+el.name),el.checked?"done":null);
    setupDaily(view);
   }
  });
 }
 return {render,wire,core,branches,selectedStyles,all,styleOptions,renderActivities,wireActivities,preferences};
})();
