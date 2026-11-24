"use strict";
/* Torn Racing guide: curated static reference, no API keys, no network calls.
   Reviewed against Torn Raceway wiki and Torning / Torn Index, November 2026. */
const tornRacingGuide=(()=>{
  const tracks=[
    ["Uptown","Tarmac","2.25","Lambrini Torobravo","TL3","Veloria LFA also competitive"],
    ["Withdrawal","Tarmac","3.40","Veloria LFA","TL3","The same LFA setup works on Speedway"],
    ["Underdog","Tarmac","1.73","Edomondo NSX","TS3","Shared short-ratio T3 build; T2 offers only a small specialization advantage"],
    ["Parkland","Dirt","3.43","Edomondo NSX","DS3","Versatile first dirt car"],
    ["Docks","Tarmac","3.81","Volt GT","TL3","Lolo 458 and Veloria LFA are serviceable until then"],
    ["Commerce","Tarmac","1.09","Edomondo NSX","TS3","Use shared tarmac T3 NSX; dedicated T2 is optional"],
    ["Two Islands","Dirt","2.71","Edomondo NSX","DL3","Long-ratio dirt setup"],
    ["Industrial","Tarmac","1.35","Edomondo NSX","TS3","Same car as Vector and Meltdown"],
    ["Vector","Tarmac","1.16","Edomondo NSX","TS3","Same car as Industrial and Meltdown"],
    ["Mudpit","Dirt","1.06","Colina Tanprice","DL3","Class B car worth keeping for Class A"],
    ["Hammerhead","Dirt","1.16","Edomondo NSX","DS3","Shared dirt T3 NSX; specialized dirt T2 is optional"],
    ["Sewage","Tarmac","1.50","Edomondo NSX","TS3","Shared tarmac T3 NSX; skip near-duplicate T2 build"],
    ["Meltdown","Tarmac","1.20","Edomondo NSX","TS3","Same car as Industrial and Vector"],
    ["Speedway","Tarmac","0.90","Veloria LFA","TL3","High-speed tarmac; same setup as Withdrawal"],
    ["Stone Park","Dirt","2.08","Echo R8","DS3","Dirt NSX works while saving for this specialist"],
    ["Convict","Tarmac","1.64","Mercia SLR","TL3","LFA works as an interim car"]
  ].map(([name,surface,miles,car,tune,note])=>({name,surface,miles,car,tune,note}));
  const classes=[
    {cls:"E",threshold:0,car:"Edomondo Localé (or Stålhög 860)",spend:0,detail:"Stay stock. No points spent in E; optional 1-point Strip Out only if you need help placing."},
    {cls:"D",threshold:25,car:"Tabata RM2",spend:15,detail:"Strip Out, Fast Road Tyres, Polished Throttle Body, Uprated Air Filter Element, Back Box. Avoid extra spending."},
    {cls:"C",threshold:100,car:"Chevalier CZ06 (or Bavaria Z8)",spend:63,detail:"Strip Out, Track/Rally Tyres, Competition Polished Throttle Body, Full Exhaust, Uprated Air Filter, Stage One Turbo, Grooved & Drilled Brake Discs, Competition Racing Fuel Pump, Uprated Forged Pistons, Ultra-Light Flywheel, Fixed Rear Spoiler, Ported & Polished Head."},
    {cls:"B",threshold:250,car:"Colina Tanprice (or Echo S4)",spend:130,detail:"Strip Out and suitable Rally/Track Tyres first; then engine/throttle, exhaust/forced induction, turbo, adjustable spoiler, matching gearbox/suspension, brakes, and weight reduction. Buy only the high-return parts until ~130 points spent. The Tanprice can be retained for Mudpit."},
    {cls:"A",threshold:475,car:"Lolo 458 (Ferrari 458), or Edomondo NSX",spend:266,detail:"Use ~266 points on one competitive tarmac build (Tarmac, Short Ratio, Turbo 3), with no safety-only upgrades. A 267-point reserve gives a fully upgraded first car and 1 point spare."}
  ];
  const config={
    filter:"All",search:"",
    spend:{E:0,D:15,C:63,B:130}
  };
  const esc=x=>String(x==null?"":x).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  function readableTune(tune){return (tune[0]==="T"?"Tarmac":"Dirt")+" · "+(tune[1]==="L"?"Long ratio":"Short ratio")+" · Turbo "+tune[2];}
  function partList(tune){
    const road=tune[0]==="T";
    return (road?["Track Tyres","Paddle Shift Gearbox","Adjustable Coil-over Suspension"]:["Rally Tyres","Rally Gearbox","Group N Rally Suspension"])
      .map(x=>x+(x.toLowerCase().includes("gearbox")?" ("+(tune[1]==="L"?"long":"short")+" ratio)":""))
      .concat(["Stage "+tune[2]+" Turbo","Stage Three ECU Remap"]);
  }
  function budget(){
    const at=classes.map((c,i)=>({
      ...c,
      arrival:c.threshold - classes.slice(0,i).reduce((sum,previous)=>sum+config.spend[previous.cls],0),
      remaining:c.threshold - classes.slice(0,i+1).reduce((sum,previous)=>sum+config.spend[previous.cls],0)
    }));
    return at;
  }
  function scoreMarkup(){
    const info=budget(),atA=info.find(x=>x.cls==="A"),spare=atA.arrival-266;
    let out='<div class="rg-result-row"><div class="rg-result"><small>Class A starting reserve</small><strong>'+atA.arrival.toLocaleString()+' points</strong></div>'+
      '<div class="rg-result"><small>First A-class build (~266)</small><strong class="'+(spare<0?"rg-warn":"rg-good")+'">'+(spare>=0?"+"+spare+" spare":Math.abs(spare)+" short")+'</strong></div></div>';
    out+='<table class="rg-table"><thead><tr><th>Class</th><th>Earned to reach</th><th>Held on arrival</th><th>Spend in class</th><th>Balance after</th></tr></thead><tbody>';
    for(const row of info)out+='<tr><th>'+row.cls+'</th><td>'+row.threshold+'</td><td>'+row.arrival+'</td><td>'+ (row.cls==="A"?"~266":config.spend[row.cls])+'</td><td>'+(row.cls==="A"?row.arrival-266:row.remaining)+'</td></tr>';
    out+='</tbody></table>';
    if(info.some(x=>x.arrival<0||x.remaining<0&&x.cls!=="A"))out+='<p class="rg-warn">Your spending budget goes negative before the next promotion. Reduce spending in earlier classes.</p>';
    out+='<p class="fine-print">Based on 475 points earned through official racing, with no crash losses or other spending. Spending does not reduce earned points used to determine class. Company-bought points do not count toward promotion.</p>';
    return out;
  }
  function render(){
    let output='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Racing guide</h1><p>Reach Class A with a competitive car, minimal early upgrades and a track-specific garage plan.</p></header>';
    output+='<section class="panel"><div class="panel-heading"><h2>Golden rule: spend points in the next class</h2></div><div class="panel-content">'+
      '<div class="rg-rule">E: <strong>0</strong> upgrades · Use E earnings in D · D earnings in C · C earnings in B · Save B earnings for A.</div>'+
      '<p>Racing points, not Energy, are the currency used to upgrade cars. Official races award <strong>3 / 2 / 1</strong> points for 1st / 2nd / 3rd. Race points already spent still count toward class advancement, but can no longer fund the next car.</p>'+
      '<p class="fine-print">Class thresholds (total earned): E 0, D 25, C 100, B 250, A 475. To start racing, buy a 50-point Racing License and a Class E car. The license cost is Points Building currency, separate from racing upgrade points.</p></div></section>';
    output+='<section class="panel"><div class="panel-heading"><h2>Class-by-class minimal upgrade plan</h2></div><div class="panel-content"><div class="rg-class-grid">';
    for(const c of classes){
      output+='<article class="rg-class-card"><div class="rg-class-top"><span class="rg-class">'+c.cls+'</span><strong>'+esc(c.car)+'</strong></div>'+
        '<p><strong>Target spend: '+(c.cls==="A"?"about ":"")+c.spend+' racing points</strong></p><p>'+esc(c.detail)+'</p></article>';
    }
    output+='</div><p class="fine-print">If you are already winning easily in a class, skip nonessential upgrades. Save enough for an A-class build, ideally 266 points. Safety-only parts do not make you faster, and un-enlisting removes the upgrades you bought.</p></div></section>';
    output+='<section class="panel"><div class="panel-heading"><h2>Racing point conservation calculator</h2></div><div class="panel-content"><p class="fine-print">Adjust how many racing points you spend in each class. Arrival balances update instantly.</p><div class="rg-input-grid">';
    for(const c of classes.slice(0,4)){
      output+='<label class="rg-input">Spend in class '+c.cls+'<input type="number" min="0" max="475" step="1" data-rg-spend="'+c.cls+'" value="'+config.spend[c.cls]+'"></label>';
    }
    output+='</div><div id="rg-budget">'+scoreMarkup()+'</div></div></section>';
    output+='<section class="panel"><div class="panel-heading"><h2>Best cars and upgrade setup for all 16 tracks</h2></div><div class="panel-content">'+
      '<p class="fine-print">Practical shared Class A setups with minimal duplicate cars, not promises of winning against drivers with higher racing skill. A dedicated Turbo 2 can perform slightly better on some tighter tracks; this plan prioritizes versatility and racing-point efficiency. For lower classes, use the one-car progression above. Tarmac uses Track Tyres, Paddle Shift Gearbox and Adjustable Coil-over Suspension; dirt uses Rally Tyres, Rally Gearbox and Group N Rally Suspension. Use Stage Three ECU Remap even on Turbo 2 builds.</p>'+
      '<div class="rg-filter"><div role="group" aria-label="Track surface">'+["All","Tarmac","Dirt"].map(surface=>'<button type="button" data-rg-filter="'+surface+'" class="rg-filter-btn '+(config.filter===surface?"is-selected":"")+'">'+surface+'</button>').join("")+'</div>'+
      '<label class="rg-search">Find track or car<input type="search" data-rg-search placeholder="e.g. Docks, NSX, dirt" value="'+esc(config.search)+'"></label></div>'+
      '<div id="rg-tracks">'+tracksMarkup()+'</div></div></section>';
    output+='<section class="panel"><div class="panel-heading"><h2>First Class A cars to build</h2></div><div class="panel-content"><ol class="rg-build-order">'+
      '<li><strong>Lolo 458</strong>, Tarmac / Short / Turbo 3: a practical all-tarmac first car.</li>'+
      '<li><strong>Veloria LFA</strong>, Tarmac / Long / Turbo 3: Withdrawal, Speedway, and competitive on other faster tarmac tracks.</li>'+
      '<li><strong>Edomondo NSX · Tarmac / Short / Turbo 3:</strong> one speed-focused setup for Industrial, Vector, Meltdown, Underdog, Commerce and Sewage. A second T2 NSX brings too little benefit to justify prioritizing it.</li>'+
      '<li><strong>Edomondo NSX · Dirt / Short / Turbo 3:</strong> a separate NSX configured for dirt, primarily Parkland and a practical alternative on Hammerhead and other dirt tracks.</li>'+
      '<li>Only then add specialists for individual tracks, such as a dirt Long-ratio NSX for Two Islands. Keep your Class B Colina Tanprice for Mudpit.</li></ol></div></section>';
    output+='<section class="panel"><div class="panel-heading"><h2>Racing habits and points efficiency</h2></div><div class="panel-content"><ul class="rg-tips">'+
      '<li><strong>Race frequently:</strong> official races award points and double racing-skill gains; custom races earn skill but no upgrade points.</li>'+
      '<li><strong>Skill matters:</strong> run long multi-driver custom races when not racing official events. Higher placements and more competitors help skill gain.</li>'+
      '<li><strong>Keep upgrades focused:</strong> Strip Out, correct tyres, aero and performance parts first; avoid safety-only upgrades when optimizing for pace.</li>'+
      '<li><strong>Choose terrain correctly:</strong> rally setup for dirt tracks, track tyres and road suspension for tarmac. Pick long ratio for straights and short for tight tracks.</li>'+
      '<li><strong>Do not un-enlist an upgraded car:</strong> upgrades disappear. A crash can remove parts; restore missing performance parts.</li>'+
      '<li><strong>Watch timing:</strong> only one race at a time, no travel during a race, and a 15-minute wait after leaving an official race.</li>'+
      '<li><strong>Companies:</strong> some Mechanic Shops or Car Dealerships can exchange job points for racing points; those do not advance class, but can finance upgrades.</li></ul>'+
      '<p class="fine-print">References: <a target="_blank" rel="noopener noreferrer" href="https://wiki.torn.com/wiki/Raceway">Official Raceway wiki</a> · <a target="_blank" rel="noopener noreferrer" href="https://www.torn.ing/guides/racing-complete-guide">Torning 2026 racing guide</a> · <a target="_blank" rel="noopener noreferrer" href="https://tornindex.com/guides/racing/">Torn Index upgrade progression</a>. Vehicle names use Torn’s renamed catalog (Lolo 458 was Ferrari 458, Chevalier CZ06 was Corvette Z06).</p></div></section>';
    return output;
  }
  function tracksMarkup(){
    const query=config.search.trim().toLowerCase();
    const filtered=tracks.filter(t=>(config.filter==="All"||t.surface===config.filter) &&
      (!query || (t.name+" "+t.car+" "+t.surface+" "+readableTune(t.tune)).toLowerCase().includes(query)));
    if(!filtered.length)return '<p class="fine-print">No tracks match that filter.</p>';
    return '<div class="rg-track-scroll"><table class="rg-table rg-track-table"><thead><tr><th>Track</th><th>Terrain</th><th>Preferred car</th><th>Setup & critical parts</th><th>Alternatives / notes</th></tr></thead><tbody>'+
      filtered.map(t=>'<tr><th>'+esc(t.name)+'<small>'+esc(t.miles)+' mi</small></th><td>'+esc(t.surface)+'</td>'+
        '<td><strong>'+esc(t.car)+'</strong></td><td><strong>'+esc(readableTune(t.tune))+'</strong><small>'+esc(partList(t.tune).join(" · "))+'</small></td>'+
        '<td>'+esc(t.note)+'</td></tr>').join("")+'</tbody></table></div>';
  }
  function wire(view){
    if(view.dataset.rgBound)return;
    view.dataset.rgBound="yes";
    view.addEventListener("change",event=>{
      const el=event.target;
      if(el.dataset.rgSpend){
        const cls=el.dataset.rgSpend;
        config.spend[cls]=Math.min(475,Math.max(0,Math.floor(Number(el.value)||0)));
        el.value=config.spend[cls];
        const target=view.querySelector("#rg-budget");
        if(target)target.innerHTML=scoreMarkup();
      }
    });
    view.addEventListener("click",event=>{
      const el=event.target.closest("[data-rg-filter]");
      if(!el)return;
      config.filter=el.dataset.rgFilter;
      for(const b of view.querySelectorAll("[data-rg-filter]"))b.classList.toggle("is-selected",b===el);
      view.querySelector("#rg-tracks").innerHTML=tracksMarkup();
    });
    view.addEventListener("input",event=>{
      if(!event.target.hasAttribute("data-rg-search"))return;
      config.search=event.target.value;
      view.querySelector("#rg-tracks").innerHTML=tracksMarkup();
    });
  }
  return {render,wire,tracks,classes,config,budget,tracksMarkup};
})();
