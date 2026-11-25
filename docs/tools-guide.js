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
  ["TornW3B","Foreign-stock availability, item prices and per-trip profit comparisons.","Desktop Phone Tablet","Trade","https://weav3r.dev/travel-stock","Web application; check current stock before committing large cash"],
  ["Torn Travel Planner","Plan multiple flights around available hours, cargo limits and projected profits.","Desktop Phone Tablet","Trade","https://www.torntravel.com/","Plans may include capacity, travel methods and income per hour"],
  ["Torn Exchange","Trader listings, price lists and receipts for safer buying and selling.","Desktop Phone Tablet","Trade","https://www.tornexchange.com/","Useful for buyers, sellers and verified-trader workflows"],
  ["TornW3B main","Market, city, gear and travel tools in one website.","Desktop Phone Tablet","Trade","https://weav3r.dev/","Alternative to separately managing several trading sites"],
  ["Clairvoyant","Stock benefit-block comparison and investment-income analysis.","Desktop Phone Tablet","Business","https://torn.marches.cafe/#/income/stock-benefits","Compare marginal benefits before purchasing shares"],
  ["Torn Training Gains Calculator","External stat and gym training estimate with comparison inputs.","Desktop Phone Tablet","Training","https://www.torncalc.site/","Useful cross-check against the guide's estimated gains"],
  ["Torn Intel","Faction/war intelligence plus foreign stocks, travel timing and item alerts.","Desktop Phone Tablet","War","https://torn-intel.com/","Several features need a separate account; overlaps with travel and stock tools"],
  ["CAT Script","Real-time faction target calls and shared ranked-war coordination.","Desktop","War","https://cat-script.com/","Follow your faction's own rollout instructions"],
  ["FFScouter","Estimate opponent battle strength using Fair Fight data.","Desktop Phone Tablet","War","https://ffscouter.com/","Treat estimates as uncertain; check TornTools integration before adding another script"],
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
 // One representative per external service. Installers and duplicate pages
 // remain in the directory rather than occupying permanent launcher space.
 const launcherNames=[
  "TornW3B","Torn Travel Planner","Torn Exchange","Torn Report",
  "Torn Intel","Clairvoyant","Torn Training Gains Calculator",
  "CAT Script","FFScouter","TornStats","YATA"
 ];
 const maxPinned=launcherNames.length,quickKey="torn-city-guide:quick-links:hidden:v2";
 const pinNames=new Set(launcherNames);
 let override=null;
 // Primary images are requested directly from the individual sites. If a
 // provider changes the favicon path or blocks hotlinking, browser-level error
 // handling tries a cached copy of that site's favicon, then the prior SVG.
 const siteFavicons=Object.freeze({
  "TornW3B":"https://weav3r.dev/favicon.ico",
  "Torn Travel Planner":"https://www.torntravel.com/favicon.ico",
  "Torn Exchange":"https://www.tornexchange.com/favicon.ico",
  "Torn Report":"https://torn.report/favicon.ico",
  "Torn Intel":"https://torn-intel.com/favicon.ico",
  "Clairvoyant":"https://torn.marches.cafe/favicon.ico",
  "Torn Training Gains Calculator":"https://www.torncalc.site/favicon.ico",
  "CAT Script":"https://cat-script.com/favicon.ico",
  "FFScouter":"https://ffscouter.com/favicon.ico",
  "TornStats":"https://www.tornstats.com/favicon.ico",
  "YATA":"https://yata.yt/favicon.ico"
 });
 const icons={
  "TornW3B":'<path d="M3 20 21 11 3 3l4 8 14 0-14 1z"/>',
  "Torn Travel Planner":'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 10h18M8 15h3m3 0h3"/>',
  "Torn Exchange":'<path d="M2 12 8 6l4 2 4-2 6 6-5 5-4-2-3 3-3-2z"/><path d="m8 12 4 3m4-3-4 3"/>',
  "Torn Report":'<path d="M4 20h16M6 17v-6m6 6V4m6 13v-9"/>',
  "Torn Intel":'<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/><path d="M12 3v3m0 12v3m9-9h-3M6 12H3m9 0 7-5"/>',
  "Clairvoyant":'<path d="M3 17 9 11l4 4 8-9"/><path d="M15 6h6v6M3 21h18"/>',
  "Torn Training Gains Calculator":'<path d="m6 7 12 10M4 5l-2 2 4 4 2-2m8 8-2 2 4 4 2-2M7 4l2 2m8 10 2 2"/>',
  "CAT Script":'<path d="m3 3 18 18M21 3 3 21"/><path d="m5 5 4-1m10 2-3-2M5 19l4 1m10-2-3 2"/>',
  "FFScouter":'<path d="M12 2 4 5v7c0 5 3 8 8 10 5-2 8-5 8-10V5z"/><path d="m8 12 3 3 5-6"/>',
  "TornStats":'<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 17v-4m5 4V7m5 10v-7"/>',
  "YATA":'<circle cx="12" cy="12" r="9"/><path d="m15 9-2 5-4 1 2-5z"/>'
 };
 const contexts={
  home:["Torn Report","TornStats","YATA"],
  checklist:["Torn Report","TornW3B","Torn Travel Planner"],
  faction:["Torn Intel","CAT Script","Torn Report"],
  jobs:["TornStats","Torn Report"],
  stats:["Torn Training Gains Calculator","Torn Report"],
  racing:["Torn Report"],
  crime:["Torn Report","YATA"],
  attacking:["FFScouter","Torn Intel"],
  war:["CAT Script","Torn Intel","FFScouter","Torn Report"],
  inventory:["Torn Exchange","TornW3B"],
  money:["Clairvoyant","Torn Exchange","TornW3B"],
  travel:["TornW3B","Torn Travel Planner","Torn Exchange","Torn Intel"],
  profile:["Torn Report","TornStats"],
  tools:launcherNames
 };
 const hiddenNames=()=>{
  if(override!==null)return [...override];
  try{
   const stored=JSON.parse(localStorage.getItem(quickKey)||"[]");
   return Array.isArray(stored)?[...new Set(stored.filter(n=>pinNames.has(n)))]:[];
  }catch{return [];}
 };
 function pins(){const hidden=new Set(hiddenNames());return launcherNames.filter(n=>!hidden.has(n));}
 function persistHidden(names){
  override=[...new Set(names.filter(n=>pinNames.has(n)))];
  try{localStorage.setItem(quickKey,JSON.stringify(override));}catch{}
  updateBar();
 }
 function togglePin(name){
  if(!pinNames.has(name))return false;
  const hidden=hiddenNames(),index=hidden.indexOf(name);
  if(index<0)hidden.push(name);else hidden.splice(index,1);
  persistHidden(hidden);return true;
 }
 function clearPins(){
  override=null;
  try{localStorage.removeItem(quickKey);}catch{}
  updateBar();
 }
 function entry(name){return list.find(item=>item[0]===name);}
 function svg(name){
  return '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+
    (icons[name]||'<circle cx="12" cy="12" r="8"/>')+'</svg>';
 }
 function siteIcon(name){
  const site=siteFavicons[name];
  if(!site)return svg(name);
  return '<img class="quick-site-favicon" src="'+esc(site)+'" width="22" height="22" '+
    'loading="lazy" decoding="async" referrerpolicy="no-referrer" '+
    'data-site-favicon="'+esc(name)+'" alt="" aria-hidden="true">'+
    '<span class="quick-favicon-fallback" hidden>'+svg(name)+'</span>';
 }
 let iconHandlerBound=false,currentBarRoute=null;
 function iconError(event){
  const img=event?.target;
  const name=img?.dataset?.siteFavicon;
  if(!pinNames.has(name))return;
  const fallback=img.dataset.faviconFallback;
  if(!fallback){
    // The fallback is still the same site's own favicon, retrieved from an
    // independent favicon cache. It never sees account data or API keys.
    const domain=new URL(entry(name)[4]).hostname;
    img.dataset.faviconFallback="cache";
    img.src="https://www.google.com/s2/favicons?domain="+encodeURIComponent(domain)+"&sz=64";
  }else{
    img.style.display="none";
    const symbol=img.nextElementSibling;
    if(symbol)symbol.hidden=false;
  }
 }
 function ensureIconHandler(){
  if(iconHandlerBound||typeof document==="undefined")return;
  document.addEventListener("error",iconError,true);
  iconHandlerBound=true;
 }
 function quickLinks(route){
  const context=route||(typeof location!=="undefined"?(location.hash||"#home").slice(1):"home");
  const contextual=typeof tornGuidePreferences!=="undefined"&&tornGuidePreferences.get("contextualQuickAccess");
  const allowed=contextual?new Set(contexts[context]||contexts.home):new Set(launcherNames);
  const selected=pins().filter(name=>allowed.has(name));
  const links=selected.map(name=>{
    const row=entry(name);if(!row)return "";
    return '<a class="quick-link" href="'+esc(row[4])+'" target="_blank" rel="noopener noreferrer"'+
      ' title="'+esc(name)+'" aria-label="Open '+esc(name)+'" data-tooltip="'+esc(name)+'">'+siteIcon(name)+'</a>';
  }).join("");
  const rail=tornRightRail.controls();
  const open=tornRoadmap.activitiesOpen();
  const gear=context==="home"?'<button type="button" class="rail-visibility-toggle" data-home-activities-toggle aria-controls="home-activities" aria-label="Playstyle and recommendation settings" title="Playstyle and recommendation settings" aria-pressed="'+open+'" aria-expanded="'+open+'"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M10 3h4l.6 2.4 2 .9 2.2-1.2 2.8 2.8-1.2 2.2.9 2L23 12l-1.7 2.9-.9 2 1.2 2.2-2.8 2.8-2.2-1.2-2 .9L14 23h-4l-.6-2.4-2-.9-2.2 1.2-2.8-2.8 1.2-2.2-.9-2L1 12l2.7-1.9.9-2-1.2-2.2L6.2 3.1l2.2 1.2 1.6-1.3z" transform="translate(1 1) scale(.91)"/></svg></button>':"";
  return '<div class="quick-inner"><div class="quick-links">'+links+'</div>'+ (gear?'<div class="home-settings-toggle-wrap">'+gear+'</div>':"")+rail+'</div>';
 }
 function updateBar(route){
  ensureIconHandler();
  if(route)currentBarRoute=route;
  const host=typeof document!=="undefined"&&document.getElementById("tool-quickbar");
  if(host){host.innerHTML=quickLinks(currentBarRoute);host.querySelector("[data-home-activities-toggle]")?.addEventListener("click",()=>tornRoadmap.toggleActivities());}
 }
 // Contextual page suggestions are deliberately suppressed: when enabled,
 // the global icon bar already reflects the current page, without duplicate rows.
 function contextLinks(){return "";}
 function matches(row){
  const shown=device==="All"||row[2].split(" ").includes(device);
  const found=!query||(row[0]+" "+row[1]+" "+row[3]+" "+row[5]).toLowerCase().includes(query);
  return shown&&found;
 }
 function cardMarkup(row){
  const [name,description,deviceTypes,category,url,note]=row;
  const eligible=pinNames.has(name),visible=pins().includes(name);
  const toggle=eligible?
   '<button type="button" class="tool-pin'+(visible?" is-pinned":"")+'" data-tool-pin="'+esc(name)+
   '" aria-label="'+(visible?"Hide ":"Show ")+esc(name)+' in Quick Access" aria-pressed="'+visible+'">'+
   (visible?"Visible":"Hidden")+'</button>':"";
  return '<article class="tools-guide-card"><div><strong>'+esc(name)+'</strong><small>'+esc(category)+' · '+esc(deviceTypes.replaceAll(" "," / "))+'</small></div>'+
   '<p>'+esc(description)+'</p><p class="fine-print">'+esc(note)+'</p>'+
   '<div class="tools-card-actions"><a target="_blank" rel="noopener noreferrer" href="'+esc(url)+'">Open tool</a>'+toggle+'</div></article>';
 }
 function cards(){
  const selected=list.filter(matches);
  const featured=new Set(["TornTools","Torn PDA",...launcherNames]);
  const main=selected.filter(row=>query||featured.has(row[0]));
  const other=query?[]:selected.filter(row=>!main.includes(row));
  return '<p class="fine-print">'+selected.length+' tools match this device/filter. '+
   pins().length+' of '+maxPinned+' launchable sites visible. All are shown by default; hide any you do not use.</p>'+
   '<div class="tools-guide-grid">'+main.map(cardMarkup).join("")+'</div>'+
   (other.length?'<details class="tools-more"><summary>Installers, references and other resources ('+other.length+')</summary>'+
   '<div class="tools-guide-grid">'+other.map(cardMarkup).join("")+'</div></details>':"");
 }
 function render(){
  let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Tools by device</h1><p>Find useful extensions, mobile apps, calculators and specialized Torn services for your setup.</p></header>';
  out+='<section class="panel"><div class="panel-heading"><h2>Quick Access favorites</h2></div><div class="panel-content">'+
   '<p class="fine-print">All launchable sites appear as icons by default, once per site. Use Visible / Hidden to customize the bar. Turn on Contextual Quick Access in the top-right settings to show only tools relevant to your current page.</p>'+
   '<button type="button" class="text-button" data-tool-reset>Show all launchable sites</button></div></section>';
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
 return {render,wire,list,devices,quickLinks,contextLinks,pins,togglePin,updateBar,clearPins,maxPinned,launcherNames,contexts,siteFavicons};
})();
