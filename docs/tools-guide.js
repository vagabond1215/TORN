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
 const reportDefaults=["energy","nerve","education","drugs","racing","uniques","trains","oc","travel","crimes"];
 let reportOpenFallback=true,reportEdit=false;
 function reportPrefs(){
   let open=reportOpenFallback,pins=reportDefaults;
   try{open=localStorage.getItem("torn-city-guide:reports-open")!=="false";const saved=JSON.parse(localStorage.getItem("torn-city-guide:report-pins")||"null");if(Array.isArray(saved))pins=saved.filter(id=>Object.hasOwn(tornReportCatalog,id));}catch{}
   return {open,pins};
 }
 function reportIcon(d){return '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+esc(d)+'"/></svg>';}
 function reportStrip(){
   const {open,pins}=reportPrefs(),version=tornGuideApi.crimeVersion?.()??null;
   const available=Object.entries(tornReportCatalog).filter(([id])=>id!=="crimes"||version!==2).filter(([id])=>id!=="uniques"||version!==1);
   const buttons=available.filter(([id])=>pins.includes(id)).map(([id,[label,,tip,d]])=>'<button class="report-icon" type="button" data-report="'+esc(id)+'" aria-label="'+esc(label)+'" title="'+esc(tip)+'">'+reportIcon(d)+'</button>').join("");
   return '<section id="torn-reports-strip" class="torn-reports-strip" '+(open?"":"hidden")+' aria-label="Torn Reports"><div class="quick-inner report-inner"><strong>Torn Reports</strong><div class="report-icon-list">'+buttons+'</div><button class="report-icon" type="button" data-report-customize aria-expanded="'+reportEdit+'" title="Customize report buttons" aria-label="Customize report buttons">'+reportIcon("M4 6h16M4 12h16M4 18h16 M8 3v6m8 0v6m-6 0v6")+'</button></div>'+(reportEdit?'<div class="quick-inner report-customize">'+available.map(([id,[label,,,d]])=>'<label title="'+esc(label)+'"><input type="checkbox" data-report-pin="'+esc(id)+'" '+(pins.includes(id)?"checked":"")+'>'+reportIcon(d)+'<span>'+esc(label)+'</span></label>').join("")+'</div>':"")+'</section>';
 }
 // Global quick bar: cached account status, no additional polling.
 const statusIcons={
   addiction:'<path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2"/><circle cx="12" cy="12" r="7"/><path d="M9 11h.01M15 11h.01M9 15h6"/>',
   travel:'<path d="M17 21v-8l-5-3V4a2 2 0 0 0-4 0v6l-5 3v8l7-4z" transform="translate(2 0)"/><path d="M10 17v5"/>',
   racing:'<path d="M4.5 19a10 10 0 1 1 15 0zM12 15l4-5M6 12h.01M12 6h.01M18 12h.01"/><circle cx="12" cy="15" r="1"/>',
   drug:'<path d="M5 19a5 5 0 0 1 0-7l7-7a5 5 0 0 1 7 7l-7 7a5 5 0 0 1-7 0zM8 9l7 7"/>',
   booster:'<path d="m13 2-9 12h7l-1 8 10-12h-7l1-8z"/>',
   medical:'<path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"/>',
   refresh:'<path d="M20 7v5h-5M4 17v-5h5M6 8a7 7 0 0 1 12-2l2 6M18 16a7 7 0 0 1-12 2l-2-6"/>',
   tools:'<path d="M4 6h16M4 12h16M4 18h16"/>'
 };
 const timeValue=v=>{if(v==null||v==="")return null;const n=Number(v);return Number.isFinite(n)&&n>=1e9?(n>=1e12?n:n*1000):null;};
 const nonnegative=v=>v!=null&&v!==""&&Number.isFinite(Number(v))&&Number(v)>=0?Number(v):null;
 const ttlStatus={icons:900000,travel:900000,races:1800000,cooldowns:120000};
 function quickStatusModel(state,health,now=Date.now(),decayAt=null,connected=true){
   const data=key=>state.data?.[key]?.[key]??null;
   const age=key=>now-Number(state.fetchedAt?.[key]||0);
   const present=key=>connected&&Number(state.fetchedAt?.[key]||0)>0&&age(key)>=-1000&&!state.errors?.[key]&&data(key)!=null;
   const fresh=key=>present(key)&&age(key)<ttlStatus[key];
   const old=key=>fresh(key)?"":" · Cached; refresh to verify";
   const unknown=(id,label,href)=>({id,label,href,value:"—",tone:"unknown",tip:label+" unavailable; refresh status or check API access"});
   const item=(id,label,value,tip,href,tone="normal")=>({id,label,value,tip,href,tone});
   const duration=at=>tornTctClock.formatDuration((at-now)/1000);
   const items=[];
   if(connected&&health.penalty!=null&&fresh("icons")){
     const p=health.penalty,level=health.level,detail=level==="restricted"?"Drug recommendations restricted":level==="recommended"?"Rehab recommended":level==="preferred"?"Rehab preferred":"Observed battle-stat penalty";
     items.push(item("addiction","Addiction",p+"%"+(decayAt&&decayAt>now?" · "+duration(decayAt):""), "Addiction penalty "+p+"% · "+detail+(decayAt?" · Next approximate natural decay in "+duration(decayAt):"")+" · Open Calendar for rehab", "#calendar",level==="restricted"?"danger":["preferred","recommended"].includes(level)?"warning":"ready"));
   }else items.push(unknown("addiction","Addiction","#calendar"));
   // One stable slot: a reported flight takes precedence over cached race data.
   // An expired flight is not proof of arrival; wait for a new snapshot.
   const travel=data("travel"),remaining=nonnegative(travel?.time_left??travel?.remaining??travel?.remaining_seconds);
   const travelStamp=Number(state.fetchedAt?.travel||0);
   const arrival=timeValue(travel?.arrival_at??travel?.arrival??travel?.until??travel?.timestamp??travel?.arrives_at)??(remaining!==null?travelStamp+remaining*1000:null);
   const destination=typeof travel?.destination==="string"?travel.destination:typeof travel?.destination?.name==="string"?travel.destination.name:"Unknown destination";
   const returning=destination.trim().toLowerCase()==="torn";
   const flightLabel=returning?"Returning to Torn":"In flight - "+destination;
   const activity=(icon,label,value,tip,href,tone="normal")=>({...item("activity",label,value,tip,href,tone),icon});
   const flight=present("travel")&&remaining!==0&&arrival!=null&&arrival>travelStamp;
   const noFlight=fresh("travel")&&(remaining===0||arrival!=null&&arrival<=travelStamp);
   if(flight&&arrival>now){
     items.push(activity("travel","Travel",flightLabel+(returning?" - ":" ")+duration(arrival),flightLabel+" · Arrival countdown from last API snapshot"+old("travel"),"#calendar",fresh("travel")?"normal":"stale"));
   }else if(flight&&arrival<=now){
     items.push(activity("travel","Travel","Verify arrival","Estimated arrival passed; refresh to confirm arrival","#calendar","stale"));
   }else{
     const races=data("races");
     const pending=present("races")&&Array.isArray(races)?races.filter(x=>["open","in_progress"].includes(x.status)).sort((a,b)=>(a.status==="in_progress"?0:1)-(b.status==="in_progress"?0:1)||(timeValue(a.schedule?.start)??Infinity)-(timeValue(b.schedule?.start)??Infinity)):[];
     const race=pending[0],start=timeValue(race?.schedule?.start),end=timeValue(race?.schedule?.end);
     if(race?.status==="open"&&start!=null&&start>now)items.push(activity("racing","Racing","Race starts - "+duration(start),(race.title||"Race")+" · Until start"+old("races"),"#racing",fresh("races")?"normal":"stale"));
     else if(race?.status==="in_progress"&&end!=null&&end>now)items.push(activity("racing","Racing","Racing - "+duration(end),(race.title||"Race")+" · Until reported finish"+old("races"),"#racing",fresh("races")?"normal":"stale"));
     else if(race?.status==="in_progress"&&end==null&&fresh("races"))items.push(activity("racing","Racing","Racing",(race.title||"Race")+" · No finish time supplied","#racing"));
     else if(race)items.push(activity("racing","Racing","Verify race","Race start or finish needs a fresh API snapshot","#racing","stale"));
     else if(noFlight&&fresh("races")&&Array.isArray(races))items.push(activity("racing","Racing","Not Racing","No active flight or scheduled race reported","#racing","ready"));
     else items.push(activity("racing","Racing / travel","Not Racing","Default display · Racing or flight status not verified; refresh to check","#racing","unknown"));
   }
   const cooldowns=data("cooldowns");
   for(const id of ["drug","booster","medical"]){
     const label=id[0].toUpperCase()+id.slice(1)+" cooldown",raw=cooldowns?.[id],left=nonnegative(raw&&typeof raw==="object"?raw.remaining??raw.time_left??raw.seconds:raw);
     if(!present("cooldowns")||left==null){items.push(unknown(id,label,"#calendar"));continue;}
     const at=Number(state.fetchedAt.cooldowns)+left*1000;
     items.push(item(id,label,duration(at),label+" · From last API snapshot"+old("cooldowns"),"#calendar",!fresh("cooldowns")?"stale":at<=now?"ready":"normal"));
   }
   return items;
 }
 function statusRows(now=Date.now()){
   const connected=tornGuideApi.isConnected(),health=typeof tornActivityScheduler==="undefined"?{penalty:null}:tornActivityScheduler.addictionSnapshot(now);
   const decayAt=tornTctClock.utcTime(3,31);
   return quickStatusModel(tornGuideApi.state,health,now,decayAt,connected);
 }
 function statusMarkup(){
   return '<div class="quick-status-strip" aria-label="Account status">'+statusRows().map(x=>'<a class="quick-status" data-quick-status="'+x.id+'" data-status-icon="'+(x.icon??x.id)+'" data-tone="'+x.tone+'" href="'+x.href+'" title="'+esc(x.tip)+'" aria-label="'+esc(x.label+": "+x.value+" · "+x.tip)+'">'+reportIcon(statusIcons[x.icon??x.id])+'<span>'+esc(x.value)+'</span></a>').join("")+'</div><button type="button" class="rail-visibility-toggle quick-status-refresh" data-quick-status-refresh title="Refresh addiction, travel, racing and cooldowns" aria-label="Refresh account status" '+(!tornGuideApi.isConnected()||tornGuideApi.state.loading?"disabled":"")+'>'+reportIcon(statusIcons.refresh)+'</button>';
 }
 function tickStatus(){
   const host=document.getElementById("tool-quickbar");if(!host)return;
   for(const x of statusRows()){
     const node=host.querySelector('[data-quick-status="'+x.id+'"]');if(!node)continue;
     const icon=x.icon??x.id;
     if(node.dataset.statusIcon!==icon){node.querySelector("svg")?.remove();node.insertAdjacentHTML("afterbegin",reportIcon(statusIcons[icon]));node.dataset.statusIcon=icon;}
     if(node.getAttribute("href")!==x.href)node.setAttribute("href",x.href);
     const span=node.querySelector("span");
     if(span.textContent!==x.value)span.textContent=x.value;
     if(node.dataset.tone!==x.tone)node.dataset.tone=x.tone;
     if(node.title!==x.tip)node.title=x.tip;
     const label=x.label+": "+x.value+" · "+x.tip;if(node.getAttribute("aria-label")!==label)node.setAttribute("aria-label",label);
   }
   const refresh=host.querySelector("[data-quick-status-refresh]");if(refresh)refresh.disabled=!tornGuideApi.isConnected()||tornGuideApi.state.loading;
 }
 let toolsOpen=false,toolsMenuBound=false;
 function setToolsOpen(open,focus=false){
   toolsOpen=!!open;
   const host=document.getElementById("tool-quickbar"),button=host?.querySelector("[data-tools-toggle]"),panel=host?.querySelector("#quick-tools-menu");
   if(!button||!panel)return;
   button.setAttribute("aria-expanded",String(toolsOpen));panel.hidden=!toolsOpen;
   if(focus)button.focus({preventScroll:true});
 }
 function ensureToolsMenu(){
   if(toolsMenuBound)return;toolsMenuBound=true;
   document.addEventListener("click",event=>{if(toolsOpen&&!event.target.closest(".quick-tools"))setToolsOpen(false);});
   document.addEventListener("keydown",event=>{if(event.key==="Escape"&&toolsOpen){event.preventDefault();setToolsOpen(false,true);}});
 }
 function quickLinks(route){
  const context=route||(typeof location!=="undefined"?(location.hash||"#home").slice(1):"home");
  const contextual=typeof tornGuidePreferences!=="undefined"&&tornGuidePreferences.get("contextualQuickAccess");
  const allowed=contextual?new Set(contexts[context]||contexts.home):new Set(launcherNames);
  const selected=pins().filter(name=>allowed.has(name));
  const links=selected.map(name=>{
    const row=entry(name);if(!row)return "";
    return '<a class="quick-tool-bookmark" href="'+esc(row[4])+'" target="_blank" rel="noopener noreferrer"'+
      ' title="'+esc(name)+'">'+siteIcon(name)+'<span>'+esc(name)+'</span></a>';
  }).join("");
  const rail=tornRightRail.controls();
  const reportToggle=context==="home"?'<button type="button" class="rail-visibility-toggle" data-report-toggle aria-controls="torn-reports-strip" aria-label="Torn Reports" title="Torn Reports" aria-pressed="'+reportPrefs().open+'">'+reportIcon("M4 3h16v18H4z M8 16v-4m4 4V8m4 8v-6")+'</button>':"";
  const open=tornRoadmap.activitiesOpen();
  const gear='<button type="button" class="rail-visibility-toggle" data-home-activities-toggle aria-controls="home-activities" aria-label="Focus" title="Focus" aria-pressed="'+open+'" aria-expanded="'+open+'"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.09a2 2 0 0 1 1 1.73v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.09a2 2 0 0 1-1-1.74v-.51a2 2 0 0 1 1-1.73l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg></button>';
  return '<div class="quick-inner"><div class="quick-tools"><button class="quick-tools-toggle" type="button" data-tools-toggle aria-controls="quick-tools-menu" aria-expanded="'+toolsOpen+'">'+reportIcon(statusIcons.tools)+'<span>Tools</span><span class="quick-tools-chevron" aria-hidden="true">▾</span></button><div id="quick-tools-menu" class="quick-tools-menu" '+(toolsOpen?"":"hidden")+' aria-label="Quick access bookmarks">'+(links||'<small>No pinned tools for this page.</small>')+'<a class="quick-tools-manage" href="#tools">Manage bookmarks</a></div></div>'+statusMarkup()+'<div class="home-settings-toggle-wrap">'+reportToggle+gear+'</div>'+rail+'</div>';
 }
 function updateBar(route){
  ensureIconHandler();ensureToolsMenu();
  if(route&&route!==currentBarRoute){toolsOpen=false;currentBarRoute=route;}
  const host=document.getElementById("tool-quickbar"),dock=document.getElementById("reports-dock");
  if(host){
    host.innerHTML=quickLinks(currentBarRoute);
    host.querySelector("[data-tools-toggle]")?.addEventListener("click",()=>setToolsOpen(!toolsOpen));
    host.querySelector("#quick-tools-menu")?.addEventListener("click",event=>{if(event.target.closest("a"))setToolsOpen(false);});
    host.querySelector("[data-quick-status-refresh]")?.addEventListener("click",async()=>{
      if(!tornGuideApi.isConnected()||tornGuideApi.state.loading)return;
      try{await tornGuideApi.loadPage("quickStatus",true);}catch{}finally{tickStatus();}
    });
    host.querySelector("[data-home-activities-toggle]")?.addEventListener("click",()=>tornRoadmap.toggleActivities());
    host.querySelector("[data-report-toggle]")?.addEventListener("click",()=>{reportOpenFallback=!reportPrefs().open;try{localStorage.setItem("torn-city-guide:reports-open",String(reportOpenFallback));}catch{}updateBar();});
  }
  if(dock){
    dock.hidden=currentBarRoute!=="home"||!reportPrefs().open;
    dock.innerHTML=currentBarRoute==="home"?reportStrip():"";
    dock.querySelector("[data-report-customize]")?.addEventListener("click",()=>{reportEdit=!reportEdit;updateBar();});
    for(const el of dock.querySelectorAll("[data-report-pin]"))el.addEventListener("change",()=>{const pins=new Set(reportPrefs().pins);if(el.checked)pins.add(el.dataset.reportPin);else pins.delete(el.dataset.reportPin);try{localStorage.setItem("torn-city-guide:report-pins",JSON.stringify([...pins]));}catch{}updateBar();dock.querySelector('[data-report-pin="'+el.dataset.reportPin+'"]')?.focus();});
  }
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
 return {render,wire,list,devices,quickLinks,tickStatus,quickStatusModel,contextLinks,pins,togglePin,updateBar,clearPins,maxPinned,launcherNames,contexts,siteFavicons};
})();
