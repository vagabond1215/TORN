"use strict";
/* Curated read-only Torn resource directory; user-controlled links only. */
const tornToolsGuide=(()=>{
 const devices=["Desktop","Phone","Tablet","All"];
 let device="Desktop",query="";
 const list=[
  ["TornTools","Browser extension with interface improvements, timers, market helpers and scripts.","Desktop","General","https://chromewebstore.google.com/detail/torntools/hjpaapdjcgbmeikfnahipphknonhlhib","Chrome / Chromium; Firefox available separately"],
  ["TornTools for Firefox","Official TornTools Firefox extension.","Desktop","General","https://addons.mozilla.org/en-US/firefox/addon/torn-tools/","Check browser-extension compatibility on your specific device"],
  ["Torn PDA","Mobile-first Torn companion with alerts, scripts, travel and activity tools.","Phone Tablet","General","https://tornpda.com/","iOS and Android. Recommended starting point on phones and compatible tablets"],
  ["Torn PDA for iPhone / iPad","Official iOS and iPadOS App Store listing.","Phone Tablet","General","https://apps.apple.com/us/app/torn-pda/id1510138514","Use the app where its built-in browser and notifications fit your needs"],
  ["Torn PDA for Android","Official Google Play listing.","Phone Tablet","General","https://play.google.com/store/apps/details?id=com.manuito.tornpda","Built-in Torn browsing; support for userscripts differs from desktop extensions"],
  ["Torn City Guide","This guide: checklists, Jobs, Stats simulator and inventory.","Desktop Phone Tablet","General","https://vagabond1215.github.io/TORN/","API-backed sections use separate page-specific cache windows"],
  ["Torn Report","Detailed personal activity histories for Energy, Nerve, drugs, education, racing and crime uniques.","Desktop Phone Tablet","Progress","https://torn.report/","Independent third-party service; use its own permission flow"],
  ["TornStats","Personal, faction and company information and advanced reporting.","Desktop Phone Tablet","Progress","https://www.tornstats.com/","Do not paste a Full Access key into an unknown tool"],
  ["YATA","Torn analytics, NPC loot timing and other utility tools.","Desktop Phone Tablet","General","https://yata.yt/","Useful for loot and account analysis"],
  ["TornW3B","Travel stock, item prices, city and gear insights.","Desktop Phone Tablet","Trade","https://weav3r.dev/travel-stock","Web application; check current stock before committing large cash"],
  ["Torn Travel Planner","Route scheduling and profitability modeling for overseas item runs.","Desktop Phone Tablet","Trade","https://www.torntravel.com/","Plans may include capacity, travel methods and income per hour"],
  ["Torn Exchange","Trader listings, pricing, receipts, quotes and commerce tools.","Desktop Phone Tablet","Trade","https://www.tornexchange.com/","Useful for buyers, sellers and verified-trader workflows"],
  ["TornW3B main","Market, city, gear and travel tools in one website.","Desktop Phone Tablet","Trade","https://weav3r.dev/","Alternative to separately managing several trading sites"],
  ["Clairvoyant","Stock benefit-block comparison and investment-income analysis.","Desktop Phone Tablet","Business","https://torn.marches.cafe/#/income/stock-benefits","Compare marginal benefits before purchasing shares"],
  ["Torn Training Gains Calculator","External stat and gym training estimate with comparison inputs.","Desktop Phone Tablet","Training","https://www.torncalc.site/","Useful cross-check against the guide's estimated gains"],
  ["Torn Intel","Faction intelligence and ranked war analysis tools.","Desktop Phone Tablet","War","https://torn-intel.com/","External paid features may require a separate account"],
  ["CAT Script","Faction war calling and coordination tool.","Desktop","War","https://cat-script.com/","Follow your faction's own rollout instructions"],
  ["FFScouter","Fair-fight and combat scouting support.","Desktop Phone Tablet","War","https://ffscouter.com/","Treat estimates as guidance rather than verified enemy stats"],
  ["Torn PDA source","Open-source mobile project and issue tracker.","Desktop Phone Tablet","Developer","https://github.com/Manuito83/torn-pda","Review compatibility notes and release changes"],
  ["Greasy Fork: Torn scripts","Community userscripts for individual Torn workflow enhancements.","Desktop","Developer","https://greasyfork.org/en/scripts/by-site/torn.com","Read each script's source and permissions before installing"],
  ["Torn Guide manual bridge","Opt-in manual userscript sharing four visible Torn bars with this guide.","Desktop","Developer","https://vagabond1215.github.io/TORN/torn-companion.user.js","Requires Tampermonkey; never automatically scrapes unfocused Torn tabs"],
  ["Official Company Catalog","Current company star perks and job specials.","Desktop Phone Tablet","Business","https://wiki.torn.com/wiki/Company/Company_List","Source for all 39 company-type details"],
  ["Official Torn API","Torn API documentation and account-key guidance.","Desktop Phone Tablet","Developer","https://www.torn.com/swagger.php","Use the narrowest practical API permissions"],
  ["Torn forum beginner guides","Guide index and community discussion of changing Torn mechanics.","Desktop Phone Tablet","General","https://tornindex.com/topics/getting-started/","Verify advice against current official rules"]
 ];
 const esc=v=>String(v==null?"":v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

 // The full directory is not the launcher. Only frequently used web tools
 // are pin-eligible; installers, reference pages and duplicate entry points
 // stay in the directory, not in the global action bar.
 const maxPinned=4;
 const pinNames=new Set([
  "TornW3B","Torn Travel Planner","Torn Exchange","Torn Report",
  "Torn Intel","Clairvoyant","Torn Training Gains Calculator",
  "CAT Script","FFScouter","TornStats","YATA"
 ]);
 const shortNames={
  "TornW3B":"Travel stock","Torn Travel Planner":"Travel planner",
  "Torn Exchange":"Trade","Torn Report":"Reports",
  "Torn Intel":"Torn Intel","Clairvoyant":"Stock benefits",
  "Torn Training Gains Calculator":"Gym check","CAT Script":"War calls",
  "FFScouter":"Scout","TornStats":"TornStats","YATA":"YATA"
 };
 const quickKey="torn-city-guide:quick-links:v1";
 let override=null;
 const stylePresets={
  Trade:["TornW3B","Torn Travel Planner","Torn Exchange","Torn Report"],
  War:["Torn Intel","CAT Script","FFScouter"],
  Mug:["FFScouter","Torn Intel","Torn Exchange"],
  Business:["Clairvoyant","Torn Exchange","Torn Report"],
  Revive:["Torn Report","TornW3B"],
  Training:["Torn Report","Torn Training Gains Calculator"],
  Crime:["Torn Report","YATA"],
  Racing:["Torn Report"]
 };
 function preferredStyle(){
  try{
   const key=typeof activeProfile!=="undefined"&&activeProfile?activeKey("playstyle:selection"):"playstyle:guest";
   const saved=typeof read==="function"?read(key):null;
   const choices=JSON.parse(saved||"[]");
   return Array.isArray(choices)?choices.find(x=>Object.hasOwn(stylePresets,x))||"Balanced":"Balanced";
  }catch{return "Balanced";}
 }
 function validPins(value){
  return Array.isArray(value)?
    [...new Set(value.filter(name=>typeof name==="string"&&pinNames.has(name)))].slice(0,maxPinned):null;
 }
 function pins(){
  if(override!==null)return [...override];
  try{
   const saved=localStorage.getItem(quickKey);
   if(saved!==null){
    const parsed=validPins(JSON.parse(saved));
    if(parsed!==null)return parsed;
   }
  }catch{}
  return [...(stylePresets[preferredStyle()]||["TornW3B","Torn Exchange","Torn Report"])];
 }
 function storePins(values){
  override=validPins(values)||[];
  try{localStorage.setItem(quickKey,JSON.stringify(override));}catch{}
  updateBar();
  return pins();
 }
 function togglePin(name){
  if(!pinNames.has(name))return false;
  const next=pins(),index=next.indexOf(name);
  if(index!==-1)next.splice(index,1);
  else{
   if(next.length>=maxPinned)return false;
   next.push(name);
  }
  storePins(next);
  return true;
 }
 function clearPins(){
  override=null;
  try{localStorage.removeItem(quickKey);}catch{}
  updateBar();
 }
 function entry(name){return list.find(item=>item[0]===name);}
 function quickLinks(){
  const selected=pins().map(entry).filter(Boolean);
  const links=['<a class="quick-link quick-game" href="https://www.torn.com/" target="_blank" rel="noopener noreferrer" title="Open the Torn game">Torn</a>'];
  for(const row of selected){
   links.push('<a class="quick-link" href="'+esc(row[4])+'" target="_blank" rel="noopener noreferrer" title="'+esc(row[1])+'">'+esc(shortNames[row[0]]||row[0])+'</a>');
  }
  return '<div class="quick-inner"><strong>Quick Access</strong><div class="quick-links">'+links.join("")+
    '</div><a class="quick-customize" href="#tools" title="Choose up to four tools for this browser">Customize</a></div>';
 }
 function updateBar(){
  const host=typeof document!=="undefined"&&document.getElementById("tool-quickbar");
  if(host)host.innerHTML=quickLinks();
 }
 function contextLinks(route){
  const routes={
   stats:["Torn Training Gains Calculator","Torn Report"],
   money:["Clairvoyant","Torn Exchange"],
   war:["CAT Script","Torn Intel","FFScouter"],
   attacking:["FFScouter"],
   crime:["Torn Report"],
   racing:["Torn Report"],
   inventory:["Torn Exchange"]
  };
  const names=(routes[route]||[]).filter(name=>!pins().includes(name));
  if(!names.length)return "";
  return '<aside class="tool-context" aria-label="Relevant external tools"><strong>Related tools</strong>'+
    names.map(name=>{
     const item=entry(name);
     return item?'<a href="'+esc(item[4])+'" target="_blank" rel="noopener noreferrer" title="'+esc(item[1])+'">'+esc(shortNames[name]||name)+'</a>':"";
    }).join("")+'</aside>';
 }

 function matches(row){
  const shown=device==="All"||row[2].split(" ").includes(device);
  const found=!query||(row[0]+" "+row[1]+" "+row[3]+" "+row[5]).toLowerCase().includes(query);
  return shown&&found;
 }
 function cardMarkup(row){
  const [name,description,deviceTypes,category,url,note]=row;
  const eligible=pinNames.has(name),picked=pins().includes(name);
  const pin=eligible?
   '<button type="button" class="tool-pin'+(picked?" is-pinned":"")+'" data-tool-pin="'+esc(name)+
   '" aria-label="'+(picked?"Remove ":"Pin ")+esc(name)+(picked?" from":" to")+' Quick Access" aria-pressed="'+picked+'" '+
   (!picked&&pins().length>=maxPinned?'disabled title="Four pinned tools maximum"':'')+'>'+
   (picked?"Pinned":"Pin")+'</button>':"";
  return '<article class="tools-guide-card"><div><strong>'+esc(name)+'</strong><small>'+esc(category)+' · '+esc(deviceTypes.replaceAll(" "," / "))+'</small></div>'+
   '<p>'+esc(description)+'</p><p class="fine-print">'+esc(note)+'</p>'+
   '<div class="tools-card-actions"><a target="_blank" rel="noopener noreferrer" href="'+esc(url)+'">Open tool</a>'+pin+'</div></article>';
 }
 function cards(){
  const selected=list.filter(matches);
  const featured=new Set(["TornTools","Torn PDA","TornW3B","Torn Travel Planner",
   "Torn Exchange","Torn Report","Torn Intel","Clairvoyant"]);
  const main=selected.filter(row=>query||featured.has(row[0])||pins().includes(row[0]));
  const other=query?[]:selected.filter(row=>!main.includes(row));
  return '<p class="fine-print">'+selected.length+' tools match this device/filter. '+
   pins().length+' of '+maxPinned+' external shortcuts pinned. Open links launch the provider in a new tab; no data is sent to it by this guide.</p>'+
   '<div class="tools-guide-grid">'+main.map(cardMarkup).join("")+'</div>'+
   (other.length?'<details class="tools-more"><summary>More specialized tools, setup and references ('+other.length+')</summary>'+
   '<div class="tools-guide-grid">'+other.map(cardMarkup).join("")+'</div></details>':"");
 }
 function render(){
  let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Tools by device</h1><p>Find useful extensions, mobile apps, calculators and specialized Torn services for your setup.</p></header>';
  out+='<section class="panel"><div class="panel-heading"><h2>Quick Access favorites</h2></div><div class="panel-content">'+
   '<p class="fine-print">Use the Pin button on a tool below to add or remove it from the global launcher. Four external favorites maximum. Preferences stay in this browser and do not require an API request.</p>'+
   '<button type="button" class="text-button" data-tool-reset>Restore suggested shortcuts for my gameplay style</button></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Choose your device</h2></div><div class="panel-content">'+
    '<div class="tools-device-controls">'+devices.map(x=>'<button type="button" data-tools-device="'+x+'" class="tools-device '+(x===device?"is-selected":"")+'">'+x+'</button>').join("")+'</div>'+
    '<label class="tools-search">Search tools or use cases<input type="search" id="tools-search" value="'+esc(query)+'" placeholder="travel, market, war, mobile..."></label>'+
    '<div id="tools-cards">'+cards()+'</div></div></section>';
  out+='<section class="panel"><div class="panel-heading"><h2>Setup guidance</h2></div><div class="panel-content"><p><strong>Desktop:</strong> start with TornTools from the official browser extension listing. Add only the other tools that support your activity. Avoid installing conflicting scripts before checking permissions.</p>'+
    '<p><strong>Phone:</strong> Torn PDA is a practical starting point for iOS or Android alerts, built-in browsing and supported scripts. Standard desktop extensions are not the same thing as Torn PDA userscripts.</p>'+
    '<p><strong>Tablet:</strong> start with the compatible Torn PDA version or browser-based tools. Feature support varies by OS and browser; check individual app-store descriptions.</p>'+
    '<p class="fine-print">Detailed per-tool setup walkthroughs can be added later. Before authorizing external services, verify what API-key level they need. The guide does not send your key to these websites.</p></div></section>';
  return out;
 }
 function wire(view){
  if(view.dataset.toolsBound)return;view.dataset.toolsBound="1";
  view.addEventListener("click",e=>{
   const pin=e.target.closest("[data-tool-pin]");
   if(pin){
    togglePin(pin.dataset.toolPin);
    const cardsEl=view.querySelector("#tools-cards");if(cardsEl)cardsEl.innerHTML=cards();
    return;
   }
   if(e.target.closest("[data-tool-reset]")){
    clearPins();
    const cardsEl=view.querySelector("#tools-cards");if(cardsEl)cardsEl.innerHTML=cards();
    return;
   }
   const button=e.target.closest("[data-tools-device]");
   if(!button)return;device=button.dataset.toolsDevice;
   view.querySelectorAll("[data-tools-device]").forEach(el=>el.classList.toggle("is-selected",el.dataset.toolsDevice===device));
   const cardsEl=view.querySelector("#tools-cards");if(cardsEl)cardsEl.innerHTML=cards();
  });
  view.addEventListener("input",e=>{
   if(e.target.id==="tools-search"){query=e.target.value.toLowerCase().trim();const cardsEl=view.querySelector("#tools-cards");if(cardsEl)cardsEl.innerHTML=cards();}
  });
 }
 return {render,wire,list,devices,quickLinks,contextLinks,pins,togglePin,updateBar,clearPins,maxPinned};
})();
