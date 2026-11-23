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
 const styles=["All","Training","Trade","Travel","Mug","Business","War","Revive","Crime","Racing","Money","Beginner"];
 let selected="All",term="",recommendedOnly=false;
 const esc=v=>String(v==null?"":v).replace(/[&<>"']/g,x=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]));
 function live(){
  const d=tornGuideApi.state.data;
  const j=d.job&&(d.job.job||d.job)||{},w=d.workstats&&(d.workstats.workstats||d.workstats)||{};
  const entries=[
   ["Job / company",j.name||j.company_name||j.company?.name||j.type],
   ["Position",j.position||j.rank||j.title],
   ["Company stars",j.company?.rating||j.rating||j.stars],
   ["Manual Labor",w.manual_labor??w.manual??w.man],
   ["Intelligence",w.intelligence??w.intel??w.int],
   ["Endurance",w.endurance??w.end]
  ];
  return '<section class="panel"><div class="panel-heading"><h2>Your current job</h2></div><div class="panel-content">'+
   '<div class="metric-grid">'+entries.map(([label,value])=>'<div class="metric"><span class="metric-label">'+esc(label)+'</span><strong class="metric-value">'+esc(value==null?"Not yet loaded":value)+'</strong></div>').join("")+'</div>'+
   '<p class="fine-print">Current job and working stats load only while this page is active, then follow their cache intervals. Company stars are shown only when the API actually provides them.</p></div></section>';
 }
 function details(company){
  const f=features.find(x=>x[0]===company.name);
  return '<details class="job-company"><summary><span><strong>'+esc(company.name)+'</strong><small>'+esc(company.styles.join(" · "))+'</small></span>'+
   '<span class="job-topperk">10★ '+esc(company.specials.at(-1).effect)+'</span></summary><div class="job-company-inner">'+
   (f?'<p>'+esc(f[2])+'</p>':'<p>Review the star unlocks and compare training, wages, job points and your long-term goals.</p>')+
   '<table class="job-special-table"><thead><tr><th>Stars</th><th>Special</th><th>JP cost</th><th>Effect</th></tr></thead><tbody>'+
   company.specials.map(x=>'<tr><td>'+x.stars+'★</td><td>'+esc(x.name)+'</td><td>'+esc(x.cost)+'</td><td>'+esc(x.effect)+'</td></tr>').join("")+
   '</tbody></table><p class="fine-print"><a href="'+esc(company.source)+'" target="_blank" rel="noopener noreferrer">Official company list</a></p></div></details>';
 }
 function matches(company){
  if(selected!=="All"&&!company.styles.includes(selected))return false;
  if(recommendedOnly&&!features.some(f=>f[0]===company.name))return false;
  return !term||(company.name+" "+company.styles.join(" ")+company.specials.map(s=>s.name+" "+s.effect).join(" ")).toLowerCase().includes(term);
 }
 function results(){
  const data=tornCompanyCatalog.filter(matches);
  return '<p class="fine-print">'+data.length+' of 39 company types. Click a company for all five star-unlocked specials. Star requirements and job-point costs matter.</p>'+
   '<div class="job-company-list">'+data.map(details).join("")+'</div>';
 }
 function highlights(){
  const list=features.filter(f=>selected==="All"||f[1].split("/").includes(selected));
  return '<div class="job-featured-grid">'+list.map(f=>'<article class="job-featured"><h3>'+esc(f[0])+'</h3><small>'+esc(f[1])+'</small><p>'+esc(f[2])+'</p></article>').join("")+'</div>';
 }
 function render(){
  let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Jobs & Careers</h1><p>Compare starting careers, permanent passives and all 39 player-owned company types.</p></header>';
  if(tornGuideApi.isConnected())out+=live();
  else out+='<section class="panel"><div class="panel-content"><p>Connect your account for current job and working stats. The catalogs below work without logging in.</p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Choose the right career sequence</h2></div><div class="panel-content">'+
   '<p><strong>Before joining:</strong> consider earning <em>The Affronted</em> honor by irritating all six city job interviewers. The faction guide specifically recommends planning this before seriously committing to an employer.</p>'+
   '<p><strong>New players:</strong> seek a player company that offers dependable daily training, realistic entry requirements and immediately useful stars. Ask about free training, wages, job points, addiction expectations and activity. Casino is a valid city-job stepping stone if company offers are poor.</p>'+
   '<p><strong>Permanent passives:</strong> plan Education → Medical → Law, adjusting the order to match your working stats. A training-friendly company may let you enter city careers at higher positions later. Finish Principal, Brain Surgeon and Federal Judge before settling into a long-term specialist job.</p>'+
   '<p><strong>Endgame:</strong> company specials usually require ongoing employment; permanent city-career perks remain after leaving. Owning a company is a business with overhead, personnel and advertising, not a beginner shortcut.</p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Six city jobs</h2></div><div class="panel-content"><div class="job-city-grid">'+city.map(c=>
   '<article class="job-city"><h3>'+esc(c[0])+'</h3><small>'+esc(c[1])+'</small><p>'+esc(c[2])+'</p><p><strong>Career result:</strong> '+esc(c[3])+'</p></article>'
  ).join("")+'</div><p class="fine-print"><a href="https://wiki.torn.com/wiki/Joblist" target="_blank" rel="noopener noreferrer">Official job requirements and rewards</a></p></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Company guidance by gameplay style</h2></div><div class="panel-content">'+
   '<div class="job-filters"><label>Filter by style<select id="job-style">'+styles.map(f=>'<option '+(f===selected?"selected":"")+' value="'+esc(f)+'">'+esc(f)+'</option>').join("")+'</select></label>'+
   '<label>Search perks or companies<input type="search" id="job-search" value="'+esc(term)+'" placeholder="DVD, protection, energy..."></label>'+
   '<label class="job-check"><input type="checkbox" id="job-recommended" '+(recommendedOnly?"checked":"")+'>Featured only</label></div>'+
   '<div id="job-highlights">'+highlights()+'</div></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Complete company catalog</h2></div><div class="panel-content"><div id="job-results">'+results()+'</div></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Before accepting a job</h2></div><div class="panel-content"><p>Check actual unlocked stars, daily training, wages, job-point generation, activity requirements and addiction limits. Compare current needs with long-term growth: a 7★ defense bonus may outperform a higher salary for a defense trainer, while business-class travel or mug protection may be more valuable for a merchant.</p>'+
   '<p class="fine-print">Company perks checked against the <a href="https://wiki.torn.com/wiki/Company/Company_List" target="_blank" rel="noopener noreferrer">official 39-company catalog</a> in November 2026. Gameplay tags and recommendations are editorial.</p></div></section>';
  return out;
 }
 function wire(view){
  if(view.dataset.jobsBound)return;view.dataset.jobsBound="1";
  const redraw=()=>{
   const a=view.querySelector("#job-results"),b=view.querySelector("#job-highlights");
   if(a)a.innerHTML=results();if(b)b.innerHTML=highlights();
  };
  view.addEventListener("change",e=>{
   if(e.target.id==="job-style"){selected=e.target.value;redraw();}
   if(e.target.id==="job-recommended"){recommendedOnly=e.target.checked;redraw();}
  });
  view.addEventListener("input",e=>{
   if(e.target.id==="job-search"){term=e.target.value.trim().toLowerCase();redraw();}
  });
 }
 return {render,wire,city,features,styles,catalog:tornCompanyCatalog};
})();
