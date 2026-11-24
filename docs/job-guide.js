"use strict";
/* Jobs: city career planner and a filtered, source-backed 39-company catalog. */
const tornJobsGuide=(()=>{
 const city=[
 ["Army","Starter","Build work stats and use military-oriented job points.","No permanent career-wide bonus."],
 ["Grocer","Starter","Accessible entry-level work while exploring player companies.","No permanent career-wide bonus."],
 ["Casino","Starter","One early route for building Intelligence before Education.","No permanent career-wide bonus."],
 ["Education","Permanent unlock","Principal: ~1,500 MAN / 5,000 INT / 1,500 END.","Permanent 10% reduction to future course time."],
 ["Medical","Permanent unlock","Brain Surgeon: ~2,600 MAN / 10,000 INT / 4,000 END.","Revive for 75 Energy before applicable reductions."],
 ["Law","Permanent unlock","Federal Judge: ~6,000 MAN / 9,000 INT / 15,000 END.","Permanent +5% crime experience and crime skill gain."]
 ];
 const features=[
 ["Adult Novelties","Beginner/Training","3★ Erotic DVD for 20 JP; at 10★ DVD happiness doubles."],
 ["Flower Shop","Trade/Travel","7★ adds five travel flowers to capacity."],
 ["Toy Shop","Trade/Travel","7★ adds five travel plushies to capacity."],
 ["Lingerie Store","Trade/Travel","3★ adds two travel slots; 10★ free business-class travel."],
 ["Clothing Store","Trade/War","7★ gives +75% mug protection and lower ranks suit early working stats."],
 ["Ladies Strip Club","War/Training","7★ grants +10% Defense gym gains, plus passive Defense at 3★."],
 ["Gents Strip Club","War/Training","7★ grants +10% Dexterity gym gains."],
 ["Fitness Center","Training/War","3★ halves gym happiness loss; 10★ adds 3% gym gains."],
 ["Music Store","Training/War","3★ boosts gym experience for faster gym unlocks, not raw gym gains."],
 ["Farm","Revive/Training","10★ converts each job point to seven Energy, useful for heavy reviving."],
 ["Grocery Store","Training/Trade","3★ reduces consumable cooldown; 7★ increases consumable effects."],
 ["Restaurant","Training/War","10★ reduces consumable cooldown 25%."],
 ["Car Dealership","Racing/Trade","1★ five JP per racing point; 3★ car-parts discount."],
 ["Mechanic Shop","Racing","Compare racing-point and car-part specials with Car Dealership."],
 ["Oil Rig","Money/Business","Evaluate high-star financial specials against your working-stat goals."],
 ["Law Firm","Crime/War","Crime and organized-crime utility can complement Federal Judge."],
 ["Sweet Shop","Training/Beginner","Compare Energy and consumable rewards with other early companies."],
 ["Private Security Firm","War/Mug","Check current combat and protective perks by company star."]
 ];
 const styles=["All","Training","Trade","Travel","Mug","Business","War","Revive","Crime","Racing","Money","Education","Beginner"];
 let selected="All",term="",recommendedOnly=false,styleOwner=null,lastStyleRaw=null,manualStyle=false;
 function syncRoadmapStyle(){
  const owner=activeProfile||"guest";
  let raw=null;
  try{raw=read(activeProfile?activeKey("playstyle:selection"):"playstyle:guest");}catch{}
  if(styleOwner!==owner){styleOwner=owner;manualStyle=false;lastStyleRaw=null;}
  if(raw===lastStyleRaw||manualStyle)return;
  lastStyleRaw=raw;
  try{
   const list=JSON.parse(raw||"[]");
   const suggested=Array.isArray(list)?list.find(x=>styles.includes(x)&&x!=="Balanced"):null;
   selected=suggested||"All";
  }catch{selected="All";}
 }
 const esc=v=>String(v==null?"":v).replace(/[&<>"']/g,x=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]));

 // Rank data: required MAN/INT/END, daily MAN/INT/END, salary, JP/day,
 // promotion cost from the current rank, and new special (if any).
 // Source: https://wiki.torn.com/wiki/Job
 const cityRanks={
 Army:[
 ["Private",2,2,2,3,1,2,125,1,5,"Strength gain","Variable JP"],
 ["Corporal",50,15,20,5,2,3,150,2,10],
 ["Sergeant",120,35,50,8,3,5,180,3,15,"Random weapon","10 JP"],
 ["Master Sergeant",325,60,115,12,4,7,220,4,20],
 ["Warrant Officer",700,160,300,17,7,10,225,5,25],
 ["Lieutenant",1300,360,595,20,9,11,325,6,30,"Defense gain","Variable JP"],
 ["Major",2550,490,900,24,10,13,550,7,35],
 ["Colonel",4150,600,1100,28,12,15,755,8,40],
 ["Brigadier",7500,1350,2530,33,18,15,1000,9,45],
 ["General",10000,2000,4000,40,25,20,2500,10,null,"Battle-stat spy","10 JP + $5,000"]],
 Grocer:[
 ["Bag Boy",2,2,2,2,1,3,150,1,5,"Cash","1 JP"],
 ["Price Labeller",30,15,50,3,2,5,175,2,10,"Bag of candy","2 JP"],
 ["Cashier",50,35,120,5,3,8,210,3,15,"Bottle of alcohol","5 JP"],
 ["Food Delivery",120,60,225,10,5,15,250,4,20],
 ["Manager",250,200,500,15,10,20,300,5,null,"Energy drink","25 JP"]],
 Casino:[
 ["Dealer",2,2,2,1,2,3,250,1,5,"Tips","1 JP"],
 ["Gaming Consultant",35,50,120,2,3,5,350,2,10,"25 casino tokens","1 JP"],
 ["Marketing Manager",60,115,325,4,7,12,500,3,15],
 ["Revenue Manager",360,595,1300,9,11,20,1000,4,20,"Cash","1 JP"],
 ["Casino Manager",490,900,2550,10,13,24,1750,5,25],
 ["Casino President",755,1100,4150,12,15,28,3500,6,null,"Card counting","10 JP + $100,000"]],
 Medical:[
 ["Medical Student",0,300,0,4,12,7,400,1,5],
 ["Houseman",100,600,150,7,17,10,600,2,10,"Small First Aid Kit","2 JP"],
 ["Senior Houseman",175,1000,275,9,20,11,950,3,15,"First Aid Kit","4 JP"],
 ["GP",300,1500,500,10,24,13,1500,4,20,"Morphine","7 JP"],
 ["Consultant",600,2500,1000,12,28,15,3000,5,25],
 ["Surgeon",1300,5000,2000,18,33,15,5000,6,30],
 ["Brain Surgeon",2600,10000,4000,20,40,25,7000,7,null,"Revive (75E base cost)","Permanent"]],
 Education:[
 ["Recess Supervisor",0,500,0,8,10,9,300,1,5,"+100 MAN","10 JP"],
 ["Substitute Teacher",300,750,500,13,15,14,400,2,10],
 ["Elementary Teacher",600,1000,700,15,20,17,600,3,15,"+100 END","10 JP"],
 ["Secondary Teacher",1000,1300,1000,20,25,20,850,4,20],
 ["Professor",1500,2000,1500,25,30,25,1000,5,25,"+100 INT","10 JP"],
 ["Vice Principal",1500,3000,1500,30,35,30,1750,6,30],
 ["Principal",1500,5000,1500,30,40,30,3250,7,null,"10% shorter education","Permanent"]],
 Law:[
 ["Law Student",0,0,1500,15,15,20,150,1,5,"+3 nerve","5 JP"],
 ["Paralegal",1750,2500,5000,17,20,23,600,2,10,"Cash","100 JP"],
 ["Probate Lawyer",2500,5000,7500,19,23,30,750,3,15],
 ["Trial Lawyer",3500,6500,7750,25,27,35,1500,4,20,"Release someone from jail","15 JP"],
 ["Circuit Court Judge",4000,7250,10000,27,30,38,2500,5,25],
 ["Federal Judge",6000,9000,15000,30,33,45,5000,6,null,"+5% crime experience and skill gains","Permanent"]]
 };
 const norm=v=>String(v??"").toLowerCase().replace(/[^a-z0-9]/g,"");
 const num=v=>v!=null&&v!==""&&Number.isFinite(Number(v))?Number(v):null;
 const fmt=v=>v==null?"—":Number(v).toLocaleString();
 function corePoints(d,career){
   const p=d.jobpoints?.jobpoints??d.jobpoints;
   const jobs=p?.jobs??p?.city_jobs??p?.starter_jobs??p;
   const match=Array.isArray(jobs)?jobs.find(x=>norm(x.name??x.job??x.type)===norm(career)):Object.entries(jobs||{}).find(([k])=>norm(k)===norm(career))?.[1];
   return num(typeof match==="object"?match?.points??match?.jobpoints??match?.job_points:match);
 }
 function coreSpecials(ranks,index){
   return '<table class="job-special-table"><thead><tr><th>Special</th><th>Cost</th><th>Required rank</th><th>Status</th></tr></thead><tbody>'+ranks.map((r,i)=>r[10]?'<tr><td>'+esc(r[10])+'</td><td>'+esc(r[11])+'</td><td>'+esc(r[0])+'</td><td>'+(i<=index?"Unlocked":"Locked")+'</td></tr>':"").join("")+'</tbody></table>';
 }
 function promotion(ranks,index,points,stats){
   const r=ranks[index],next=ranks[index+1];
   if(!next)return '<div class="job-promotion"><strong>Maximum rank reached</strong></div>';
   const requirements=[...next.slice(1,4),r[9]],current=[...stats,points],rates=[...r.slice(4,7),r[8]],labels=["MAN","INT","END","JP"];
   const days=requirements.map((req,i)=>current[i]===null?null:current[i]>=req?0:rates[i]>0?Math.ceil((req-current[i])/rates[i]):Infinity);
   const max=days.some(x=>x===null)?null:Math.max(...days);
   const eta=max===null?"Unknown":max===Infinity?"Blocked":max===0?"Ready to promote":max+" daily payouts";
   return '<div class="job-promotion"><h3>Next promotion: '+esc(next[0])+' <small>'+esc(eta)+'</small></h3><div class="job-promotion-grid">'+labels.map((label,i)=>'<div><strong>'+label+'</strong> '+fmt(current[i])+' / '+fmt(requirements[i])+' <small class="'+(days[i]===0?"tc-pos":"")+'">'+(days[i]===null?"Unknown":days[i]===0?"Ready":days[i]===Infinity?"Blocked":days[i]+"d")+'</small></div>').join("")+'</div></div>';
 }
 function live(){
  const d=tornGuideApi.state.data;
  const j=d.job&&(d.job.job||d.job)||{},w=d.workstats&&(d.workstats.workstats||d.workstats)||{};
  const career=Object.keys(cityRanks).find(k=>[j.name,j.type,j.company_name].some(v=>norm(v)===norm(k)));
  const ranks=career?cityRanks[career]:null;
  const index=ranks?ranks.findIndex(r=>norm(r[0])===norm(j.position??j.rank??j.title)):-1;
  const rank=index>=0?ranks[index]:null;
  const points=career?corePoints(d,career):null;
  const stats=[num(w.manual_labor??w.manual??w.man),num(w.intelligence??w.intel??w.int),num(w.endurance??w.end)];
  const rating=j.company?.rating??j.rating??j.stars;
  const stars=rating!=null&&rating!==""&&Number.isFinite(Number(rating))?Number(rating):null;
  const jobRows=[
   ["Job / company",j.name||j.company_name||j.company?.name||j.type],
   ["Position",j.position||j.rank||j.title],
   ...(career?[["Job points",points],["Daily JP",rank?.[8]],["Daily pay",rank?"$"+fmt(rank[7]):null]]:[["Company stars",stars],["Daily JP",stars]])
  ];
  const statRows=["Manual labor","Intelligence","Endurance"].map((name,i)=>[name,stats[i]===null?null:fmt(stats[i])+(rank?" (+"+rank[4+i]+"/day)":"")]);
  const list=rows=>'<dl class="home-stat-list">'+rows.map(([label,value])=>
   '<div class="home-pair"><dt>'+esc(label)+'</dt><dd>'+esc(value==null?"Not yet loaded":value)+'</dd></div>').join("")+'</dl>';
  const perks=d.perks&&(d.perks.perks||d.perks);
  const jobPerks=perks?.job??perks?.job_perks;
  const livePerks=Array.isArray(jobPerks)?jobPerks.map(x=>typeof x==="string"?x:x?.description??x?.effect??x?.name).filter(Boolean):[];
  const candidates=[j.company?.type?.name,j.company?.type,j.company_type?.name,j.company_type,j.type?.name,j.type,j.name,j.company_name,j.company?.name].filter(x=>typeof x==="string");
  const company=tornCompanyCatalog.find(c=>candidates.some(n=>norm(n)===norm(c.name)));
  const specials=company?'<table class="job-special-table"><thead><tr><th>Stars</th><th>Special</th><th>JP cost</th><th>Effect</th><th>Status</th></tr></thead><tbody>'+company.specials.map(x=>'<tr><td>'+x.stars+'★</td><td>'+esc(x.name)+'</td><td>'+esc(x.cost)+'</td><td>'+esc(x.effect)+'</td><td>'+(/temporarily unavailable/i.test(x.effect)?"Unavailable":stars===null?"Unknown":stars>=x.stars?"Unlocked":"Locked")+'</td></tr>').join("")+'</tbody></table>':"";
  const perkMarkup='<div class="job-current-perks"><h3>Current job specials</h3>'+(rank?coreSpecials(ranks,index):specials||'<p class="fine-print">Job specials unavailable.</p>')+'</div>'+
   (livePerks.length?'<div class="job-current-perks"><h3>API-reported career perks</h3><ul class="job-perk-list">'+livePerks.map(x=>'<li>'+esc(x)+'</li>').join("")+'</ul></div>':"");
  return '<section class="panel"><div class="panel-heading"><h2>Your current job</h2></div>'+
    '<div class="panel-content"><div class="job-live-columns">'+
      '<div><h3>Job details</h3>'+list(jobRows)+'</div>'+
      '<div><h3>Working stats</h3>'+list(statRows)+'</div>'+
    '</div>'+(rank?promotion(ranks,index,points,stats):'')+perkMarkup+'</div></section>';
 }
 // One catalog, one filter, one set of benefit descriptions for both sections.
 const featuredNames=new Set(features.map(f=>f[0]));
 const patterns={
  Training:/gym|happiness|happy|energy|erotic dvd|candy|consumable|addiction|overdose|console|^(strength|defense|speed|dexterity)$/i,
  Travel:/travel|abroad|foreign|country|countries|flight|hunting|cayman/i,
  Trade:/item market|special flower|special plushie|travel items|abroad|foreign item|advertising|business class|property|candy|energy drink|ammunition|weapon|plushies|flowers/i,
  Mug:/mug|money on hand|money|investment account|stealth|spy|spies|bounty|someone's stats|employment and faction/i,
  Business:/company|productivity|financial|advertising|investment|property|money/i,
  War:/damage|accuracy|armor|armour|passive|stealth|life|health|weapon|ammunition|enemy|faction respect|mission|bounty|epinephrine|tyrosine|serotonin|attack/i,
  Revive:/energy/i,
  Crime:/nerve|crime|criminal|bust|bail|arrest|alcohol|virus|fraud|counterfeit|hacking|stealth/i,
  Racing:/racing|car parts|driving|random car|crashing/i,
  Money:/money|bank|investment|interest|property|upkeep|hunting|funds|erotic dvd|energy drink/i,
  Education:/education/i,
  Beginner:/experience|happiness|happy|energy|endurance|candy|awareness|special flower|special plushie|mug protection|education/i
 };
 function relevant(company){
  const pattern=patterns[selected];
  const eligible=company.specials.filter(x=>! /temporarily unavailable/i.test(x.effect));
  const matched=pattern?eligible.filter(x=>pattern.test(x.effect)):eligible;
  return matched.length?matched:eligible;
 }
 function perkText(x){
  return x.stars+"★ "+x.effect+" ("+(String(x.cost).toLowerCase()==="passive"?"Passive":x.cost+" JP")+")";
 }
 function details(company){
  const perks=relevant(company);
  return '<details class="job-company"><summary><span><strong>'+esc(company.name)+'</strong><small>'+esc(company.styles.join(" · "))+'</small></span>'+
   '<span class="job-topperk">'+esc(perkText(perks[0]))+'</span></summary><div class="job-company-inner">'+
   '<p>'+perks.map(x=>esc(perkText(x))).join(" · ")+'</p>'+
   '<table class="job-special-table"><thead><tr><th>Stars</th><th>Special</th><th>JP cost</th><th>Effect</th></tr></thead><tbody>'+
   company.specials.map(x=>'<tr><td>'+x.stars+'★</td><td>'+esc(x.name)+'</td><td>'+esc(x.cost)+'</td><td>'+esc(x.effect)+'</td></tr>').join("")+
   '</tbody></table><p class="fine-print"><a href="'+esc(company.source)+'" target="_blank" rel="noopener noreferrer">Official company list</a></p></div></details>';
 }
 function matches(company){
  if(selected!=="All"&&!company.styles.includes(selected))return false;
  if(recommendedOnly&&!featuredNames.has(company.name))return false;
  return !term||(company.name+" "+company.styles.join(" ")+company.specials.map(s=>s.name+" "+s.effect+" "+s.stars+" "+s.cost).join(" ")).toLowerCase().includes(term);
 }
 function filtered(){return tornCompanyCatalog.filter(matches);}
 function results(){
  const data=filtered();
  return '<p class="fine-print">'+data.length+' of '+tornCompanyCatalog.length+' company types. Click a company for all star-unlocked specials.</p>'+
   '<div class="job-company-list">'+data.map(details).join("")+'</div>';
 }
 function highlights(){
  const data=filtered();
  return '<div class="job-featured-grid">'+data.map(company=>'<article class="job-featured"><h3>'+esc(company.name)+'</h3><small>'+esc(company.styles.join(" · "))+'</small><p>'+relevant(company).map(x=>esc(perkText(x))).join("<br>")+'</p></article>').join("")+'</div>';
 }
 const collapsedPanels=new Set();
 function render(){
  syncRoadmapStyle();
  let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Jobs & Careers</h1><p>Compare starting careers, permanent passives and all 39 player-owned company types.</p></header>';
  if(tornGuideApi.isConnected())out+=live();
  else out+='<section class="panel"><div class="panel-content"><p>Connect your account for current job and working stats. The catalogs below work without logging in.</p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Choose the right career sequence</h2></div><div class="panel-content">'+
   '<p><strong>Before joining:</strong> consider earning <em>The Affronted</em> honor by irritating all six city job interviewers. The faction guide specifically recommends planning this before seriously committing to an employer.</p>'+
   '<p><strong>New players:</strong> seek a player company that offers dependable daily training, realistic entry requirements and immediately useful stars. Ask about free training, wages, job points, addiction expectations and activity. Casino is a valid city-job stepping stone if company offers are poor.</p>'+
   '<p><strong>Permanent passives:</strong> plan Education → Medical → Law, adjusting the order to match your working stats. A training-friendly company may let you enter city careers at higher positions later. Finish Principal, Brain Surgeon and Federal Judge before settling into a long-term specialist job.</p>'+
   '<p><strong>Endgame:</strong> company specials usually require ongoing employment; permanent city-career perks remain after leaving. Owning a company is a business with overhead, personnel and advertising, not a beginner shortcut.</p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Before accepting a job</h2></div><div class="panel-content"><p>Check actual unlocked stars, daily training, wages, job-point generation, activity requirements and addiction limits. Compare current needs with long-term growth: a 7★ defense bonus may outperform a higher salary for a defense trainer, while business-class travel or mug protection may be more valuable for a merchant.</p>'+
   '<p class="fine-print">Company perks checked against the <a href="https://wiki.torn.com/wiki/Company/Company_List" target="_blank" rel="noopener noreferrer">official 39-company catalog</a> in November 2026. Gameplay tags and recommendations are editorial.</p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Six city jobs</h2></div><div class="panel-content"><div class="job-city-grid">'+city.map(c=>
   '<article class="job-city"><h3>'+esc(c[0])+'</h3><small>'+esc(c[1])+'</small><p>'+esc(c[2])+'</p><p><strong>Career result:</strong> '+esc(c[3])+'</p></article>'
  ).join("")+'</div><p class="fine-print"><a href="https://wiki.torn.com/wiki/Joblist" target="_blank" rel="noopener noreferrer">Official job requirements and rewards</a></p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Company guidance by gameplay style</h2></div><div class="panel-content">'+
   '<div class="job-filters"><label>Filter by style<select id="job-style">'+styles.map(f=>'<option '+(f===selected?"selected":"")+' value="'+esc(f)+'">'+esc(f)+'</option>').join("")+'</select></label>'+
   '<label>Search perks or companies<input type="search" id="job-search" value="'+esc(term)+'" placeholder="DVD, protection, energy..."></label>'+
   '<label class="job-check"><input type="checkbox" id="job-recommended" '+(recommendedOnly?"checked":"")+'>Featured only</label></div>'+
   '<div id="job-highlights">'+highlights()+'</div></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Complete company catalog</h2></div><div class="panel-content"><div id="job-results">'+results()+'</div></div></section>';
  return out.replace(/<section class="panel"><div class="panel-heading"><h2>(.*?)<\/h2><\/div>([\s\S]*?)<\/section>/g,(_,title,body)=>'<details class="panel job-section" data-job-panel="'+esc(title)+'" '+(collapsedPanels.has(title)?"":"open")+'><summary class="panel-heading"><h2>'+title+'</h2></summary>'+body+'</details>');
 }
 function wire(view){
  if(view.dataset.jobsBound)return;view.dataset.jobsBound="1";
  view.addEventListener("toggle",e=>{const el=e.target;if(!el.matches?.("[data-job-panel]")||!el.isConnected)return;if(el.open)collapsedPanels.delete(el.dataset.jobPanel);else collapsedPanels.add(el.dataset.jobPanel);},true);
  const redraw=()=>{
   const a=view.querySelector("#job-results"),b=view.querySelector("#job-highlights");
   if(a)a.innerHTML=results();if(b)b.innerHTML=highlights();
  };
  view.addEventListener("change",e=>{
   if(e.target.id==="job-style"){selected=e.target.value;manualStyle=true;redraw();}
   if(e.target.id==="job-recommended"){recommendedOnly=e.target.checked;redraw();}
  });
  view.addEventListener("input",e=>{
   if(e.target.id==="job-search"){term=e.target.value.trim().toLowerCase();redraw();}
  });
 }
 return {render,wire,city,features,styles,catalog:tornCompanyCatalog};
})();
