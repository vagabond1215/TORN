"use strict";
const tornRightRail=(()=>{
  const cooldowns=[["medical","Medical"],["drug","Drug"],["booster","Booster"]];
  const timers=[["oc","Organized crime ready"],["rw","Ranked war"],["raid","Raid war"],
    ["virus","Virus completes"],["education","Education completes"],["flight","Travel arrival"],
    ["bank","Bank investment matures"],["point","Daily reset"]];
  // Keep cooldowns excluded from the left timer list: they live in the global sub-bar.
  const order=[...cooldowns,...timers.filter(([id])=>id!=="point")];
  const tabs=[["timers","Timers"],["stocks","Stocks"]];
  const tabKey="torn-city-guide:right-rail:countdown-tab";
  let busy=false,initialized=false,activeTab="timers",refreshStatus="";
  try{const saved=localStorage.getItem(tabKey);if(tabs.some(([id])=>id===saved))activeTab=saved;}catch{}
  const collapsed=new Set();
  const sectionKey="torn-city-guide:right-rail:hidden:v1";
  const sections=[["timers","Timers and stocks",'<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6M12 2v3"/>'],["networth","Net worth",'<path d="M3 3v18h18M6 15l5-5 4 3 6-8M16 5h5v5"/>'],["property","Property",'<path d="m3 10 9-7 9 7M5 9v12h14V9M10 21v-7h4v7"/>'],["merits","Merits",'<circle cx="12" cy="8" r="5"/><path d="m8 12-2 10 6-4 6 4-2-10"/>']];
  const hiddenSections=new Set();
  try{const saved=JSON.parse(localStorage.getItem(sectionKey)||"[]");if(Array.isArray(saved))for(const [id] of sections)if(saved.includes(id))hiddenSections.add(id);}catch{}
  function controls(){
    return '<div class="rail-visibility-controls" role="group" aria-label="Right pane visibility">'+sections.map(([id,label,icon])=>'<button type="button" class="rail-visibility-toggle" data-rail-visibility="'+id+'" aria-pressed="'+!hiddenSections.has(id)+'" aria-label="Toggle '+label+'" title="Toggle '+label+'"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+icon+'</svg></button>').join("")+'</div>';
  }
  function syncControls(){
    const controls=document.querySelector(".rail-visibility-controls");
    if(!controls)return;
    controls.hidden=!tornGuideApi.isConnected();
    for(const btn of controls.querySelectorAll("[data-rail-visibility]")){
      const enabled=!hiddenSections.has(btn.dataset.railVisibility);
      btn.setAttribute("aria-pressed",String(enabled));
    }
  }
  const host=()=>document.getElementById("guide-right-rail");
  function status(entry){
    if(!entry)return "Not loaded";
    if(entry.at&&entry.at>Date.now())return tornTctClock.formatDuration((entry.at-Date.now())/1000);
    if(entry.at)return "Ready";
    if(["rw","raid"].includes(entry.id))return entry.fighting?"Active":entry.loaded===false?"Not loaded":"Not scheduled";
    if(entry.id==="bank")return tornGuideApi.state.data.money?"No deposit":"Not loaded";
    return /not loaded|not scheduled|manual/i.test(entry.note||"")?"Not loaded":"No active timer";
  }
  function timerEntries(){
    const entries=new Map(tornTctClock.entries().map(entry=>[entry.id,entry]));
    const wars=tornGuideApi.state.errors?.factionWars?null:payload("factionWars","wars");
    const now=Date.now();
    function warTimer(id,label,records){
      const live=records.filter(war=>war&&Number(war.start)>0&&!(Number(war.end)>0&&Number(war.end)*1000<=now)&&!(Number(war.winner)>0))
        .map(war=>({start:Number(war.start)*1000,end:Number(war.end)*1000}));
      const upcoming=live.filter(war=>war.start>now).sort((a,b)=>a.start-b.start)[0];
      const fighting=live.find(war=>war.start<=now);
      const at=upcoming?.start??(fighting?.end>now?fighting.end:null);
      return {id,title:label+(upcoming?" starts":fighting&&at?" ends":""),at,fighting:!!fighting,loaded:!!wars,note:"Faction wars API"};
    }
    if(wars?.ranked)entries.set("rw",warTimer("rw","Ranked war",[wars.ranked]));
    entries.set("raid",warTimer("raid","Raid war",Array.isArray(wars?.raids)?wars.raids:[]));
    const oc=payload("organizedcrime","organizedcrime"),readyAt=Number(oc?.ready_at??oc?.crime?.ready_at);
    if(readyAt>0&&!tornGuideApi.state.errors?.organizedcrime){
      const status=String(oc?.status??oc?.crime?.status??"").toLowerCase();
      if(!["successful","failure","failed","expired","completed"].includes(status)){
        entries.set("oc",{id:"oc",at:readyAt*1000,note:"Organized crime readiness from Torn"});
      }
    }
    return entries;
  }
  function stockTimers(){
    if(!tornGuideApi.state.data.stocks||tornGuideApi.state.errors?.stocks)return '<p class="rail-snapshot-note">Stock holdings unavailable.</p>';
    if(!tornGuideApi.state.data.stockCatalog||tornGuideApi.state.errors?.stockCatalog)return '<p class="rail-snapshot-note">Stock benefit catalog unavailable.</p>';
    const stocks=stockRows().filter(stock=>stock.active&&!stock.passive&&stock.freq>0)
      .sort((a,b)=>Number(b.ready)-Number(a.ready)||(a.days??Infinity)-(b.days??Infinity)||a.ticker.localeCompare(b.ticker));
    if(!stocks.length)return '<p class="rail-snapshot-note">No active dividend benefits.</p>';
    return '<dl class="rail-timer-list">'+stocks.map(stock=>{
      const days=Math.ceil(stock.days);
      const remaining=stock.ready?"Ready":days>0?days+"d":"Timing unavailable";
      return '<div class="rail-timer-row" title="'+safe(stock.name+' · '+stock.description)+'"><dt><a href="#stocks">'+
        safe(stock.ticker)+'</a> · '+safe(stock.description)+'</dt><dd>'+remaining+'</dd></div>';
    }).join("")+'</dl>';
  }
  function clocks(){
    const entries=timerEntries();
    const rows=timers.map(([id,label])=>{
      const entry=entries.get(id);
      return '<div class="rail-timer-row" title="'+safe(id==="virus"?virusTooltip():entry?.note||"Not loaded")+'">'+
        '<dt data-rail-timer-label="'+id+'">'+safe(["rw","raid"].includes(id)?entry?.title??label:label)+'</dt><dd data-rail-timer="'+id+'">'+safe(status(entry))+'</dd></div>';
    }).join("");
    return '<section class="panel rail-timers"><div class="panel-heading"><h2>Timers &amp; stocks</h2></div><div class="rail-timer-header">'+
      '<div class="rail-timer-tabs" role="group" aria-label="Countdown views">'+tabs.map(([id,label])=>
        '<button type="button" data-rail-tab="'+id+'" aria-controls="rail-timer-content" aria-pressed="'+(activeTab===id)+'">'+label+'</button>').join("")+'</div></div>'+
      '<div class="panel-content" id="rail-timer-content">'+(activeTab==="stocks"?stockTimers():'<dl class="rail-timer-list">'+rows+'</dl>')+
      '<span id="rail-refresh-status" class="sr-only" role="status">'+safe(refreshStatus)+'</span></div></section>';
  }
  function niceRailMarkup(notice){
    const alert=notice?'<div class="rail-nice-notice"><strong>'+safe(notice.met?"Nice requirement predicted":notice.improved?"Nice training opportunity":"Nice digit match predicted")+'</strong><small>'+safe(notice.detail)+'</small><small>'+safe((notice.ready?"Within current Energy. ":"More Energy or Energy unverified. ")+(notice.verified?"":"Honor status unverified. ")+(notice.reference?"Reference gym values. ":"")+"Estimate only; check after each train.")+'</small><a href="#merits">See all gym options</a></div>':"";
    const badge=notice?'<span class="rail-nice-badge" title="'+safe(notice.detail)+'" aria-label="'+safe(notice.detail)+'">'+safe(notice.tag)+'</span>':"";
    return {alert,badge};
  }
  function merits(){
    const rows=tornMeritGuide.recommendations(),{alert,badge}=niceRailMarkup(tornMeritGuide.niceNotice());
    const body=rows.length?'<ul class="rail-merit-list">'+rows.map(x=>'<li><div class="rail-merit-row"><div><strong>'+safe(x.name)+'</strong><small>'+safe(x.detail)+' · '+safe(x.effort)+'</small></div>'+(x.link?'<a href="'+safe(x.link)+'" aria-label="View '+safe(x.name)+'">View</a>':"")+'</div>'+tornMeritGuide.affrontedDetails(x.name,"rail")+'</li>').join("")+'</ul>':'<p class="rail-snapshot-note">No confirmed unearned recommendations loaded. Open Merits or use the main Refresh button.</p>';
    return '<section class="panel rail-merits"><div class="panel-heading"><h2>Merits</h2><span data-nice-rail-badge '+(badge?"":"hidden")+'>'+badge+'</span><a href="#merits">View all</a></div><div class="panel-content"><div data-nice-rail-alert '+(alert?"":"hidden")+'>'+alert+'</div>'+body+'</div></section>';
  }
  // The documented v2 user/property upkeep object contains daily property
  // and staff charges, not accumulated debt. Never substitute one for the other.
  function propertyModel(raw,icons=null){
    const p=raw?.upkeep?raw:raw?.property?.upkeep?raw.property:raw;
    const money=v=>v!==null&&v!==undefined&&v!==""&&(typeof v==="number"||typeof v==="string"&&/^\d+$/.test(v))&&Number.isSafeInteger(Number(v))&&Number(v)>=0?Number(v):null;
    const upkeep=p?.upkeep,base=money(upkeep?.property),staff=money(upkeep?.staff);
    const daily=base!==null&&staff!==null?base+staff:null;
    // Accept explicitly named outstanding balances if a future API response
    // or compatible cached response actually supplies one; total is ambiguous.
    let due=[upkeep?.due,upkeep?.outstanding,p?.upkeep_due].map(money).find(x=>x!==null)??null;
    let indicator=null;
    for(const icon of Object.values(icons??{})){
      const value=typeof icon==="string"?icon:[icon?.title,icon?.name,icon?.description,icon?.text].filter(Boolean).join(" ");
      if(!/\bupkeep\b/i.test(value)||!/\b(?:due|owed|unpaid|outstanding)\b/i.test(value))continue;
      // Only an explicitly labeled dollar amount, never percentage bands
      // or daily costs, is an exact unpaid balance.
      const m=value.match(/\b(?:upkeep\s+(?:due|owed|unpaid|outstanding)|(?:unpaid|outstanding)\s+upkeep)\s*[:=-]?\s*\$([\d,]+)(?![\d,.])/i);
      if(due===null&&m)due=money(m[1].replace(/,/g,""));
      const band=value.match(/\b(\d+(?:\.\d+)?(?:\s*[-–]\s*\d+(?:\.\d+)?)?)\s*%/);
      if(band)indicator=band[1]+"% due (icon)";
    }
    return {name:p?.property?.name??p?.name??"Not loaded",base,staff,daily,due,indicator};
  }
  function property(){
    const state=tornGuideApi.state,raw=payload("property","property");
    const iconStamp=Number(state.fetchedAt?.icons||0),iconFresh=!state.errors?.icons&&iconStamp>0&&Date.now()-iconStamp>=0&&Date.now()-iconStamp<15*60000;
    const p=propertyModel(state.errors?.property?null:raw,iconFresh?payload("icons","icons"):null);
    const price=value=>value==null?"Not available":"$"+formatNumber(value);
    return '<section class="panel rail-property"><div class="panel-heading"><h2>Property</h2><a class="rail-upkeep-link" href="https://www.torn.com/properties.php#/p=options&amp;tab=upkeep" target="_blank" rel="noopener noreferrer">Upkeep</a></div>'+
      '<div class="panel-content"><p class="rail-property-name">'+safe(p.name)+'</p>'+
      '<dl class="home-stat-list">'+homePair("Daily upkeep",price(p.daily))+
      (p.base!==null?homePair("Property",price(p.base)):"")+
      (p.staff!==null?homePair("Staff",price(p.staff)):"")+
      homePair("Current total upkeep",p.due!==null?price(p.due):"Not reported")+
      (p.indicator?homePair("Upkeep indicator",p.indicator):"")+
      '</dl>'+(p.due===null?'<p class="rail-snapshot-note">Torn API reports daily charges, not the outstanding balance. Open Upkeep to view the amount owed.</p>':"")+sourceError("property")+'</div></section>';
  }
  function virusTooltip(){
    const raw=payload("virus","virus"), v=raw?.coding??raw?.current??raw?.virus??raw;
    if(!v)return "Not loaded";
    const item=v.item??v, id=item.id??v.item_id??v.virus_id;
    const name=item.name??v.name??(typeof v.type==="string"?v.type:null);
    const catalog=payload("itemCatalog","items");
    const list=Array.isArray(catalog)?catalog:Object.entries(catalog||{}).map(([key,value])=>({...value,id:value?.id??key}));
    const match=list.find(x=>(id!=null&&String(x.id)===String(id))||(name&&String(x.name).toLowerCase()===String(name).toLowerCase()));
    const label=match?.name??name;
    const price=match?.market_value??match?.value?.market_price??match?.value?.market_value??match?.market_price??item.market_value;
    return label?label+(price!=null&&Number.isFinite(Number(price))?" $"+formatNumber(price):" · Value unavailable"):"No active virus";
  }
  function collapsible(markup,key){
    return markup.replace(/<section class="([^"]+)"><div class="panel-heading"><h2>(.*?)<\/h2>(.*?)<\/div>/,
      (_,classes,title,actions)=>'<details class="'+classes+' rail-section" data-rail-section="'+key+'" '+(collapsed.has(key)?"":"open")+'><summary class="panel-heading"><span class="rail-section-title">'+title+'</span>'+actions+'</summary>')
      .replace(/<\/section>$/,"</details>");
  }
  function render(){
    const el=host();if(!el)return;
    syncControls();
    const connected=tornGuideApi.isConnected();
    const showFocus=tornRoadmap.activitiesOpen();
    const showSections=connected&&sections.some(([id])=>!hiddenSections.has(id));
    el.hidden=!showFocus&&!showSections;
    let focus=el.querySelector("#home-activities");
    const owner=tornRoadmap.focusOwner();
    if(focus&&focus.dataset.focusOwner!==owner){focus.remove();focus=null;}
    if(showFocus&&!focus){
      el.insertAdjacentHTML("afterbegin",tornRoadmap.renderActivities());
      el.querySelector("#home-activities").dataset.focusOwner=owner;
    }
    if(focus)focus.hidden=!showFocus;
    let content=el.querySelector("[data-rail-content]");
    if(!content){
      content=document.createElement("div");content.dataset.railContent="";
      el.append(content);
    }
    content.hidden=!showSections;
    content.innerHTML=showSections?[["timers",clocks],["networth",networthPanel],["property",property],["merits",merits]]
      .filter(([id])=>!hiddenSections.has(id)).map(([id,fn])=>collapsible(fn(),id)).join(""):"";
  }
  let lastNiceTick=0;
  function tick(){
    const el=host();if(!el||el.hidden)return;
    // Local-only recheck at most once per minute, including when timers
    // are hidden. Expire stale alerts and reflect projected bar changes
    // without rebuilding (or reopening) any disclosure.
    const minute=Math.floor(Date.now()/60000);
    if(minute!==lastNiceTick){
      lastNiceTick=minute;
      const badge=el.querySelector("[data-nice-rail-badge]"),alert=el.querySelector("[data-nice-rail-alert]");
      if(badge&&alert){
        const next=niceRailMarkup(tornMeritGuide.niceNotice());
        if(badge.innerHTML!==next.badge)badge.innerHTML=next.badge;
        if(alert.innerHTML!==next.alert)alert.innerHTML=next.alert;
        badge.hidden=!next.badge;alert.hidden=!next.alert;
      }
    }
    const clocks=el.querySelectorAll("[data-rail-timer]");
    if(!clocks.length)return;
    const entries=timerEntries();
    for(const n of clocks){
      const id=n.dataset.railTimer,entry=entries.get(id),value=status(entry);
      if(n.textContent!==value)n.textContent=value;
      if(["rw","raid"].includes(id)&&entry?.title){
        const label=n.previousElementSibling;
        if(label&&label.textContent!==entry.title)label.textContent=entry.title;
      }
    }
  }
  async function load(){
    if(busy||!tornGuideApi.isConnected())return;
    busy=true;refreshStatus="Updating countdowns";render();
    try{await tornGuideApi.loadPage(activeTab==="stocks"?"stocks":"railTimers",true);refreshStatus="Countdowns updated";}
    catch(error){refreshStatus=String(error.message||error);}
    finally{busy=false;render();}
  }
  function init(){
    if(initialized)return;initialized=true;
    document.getElementById("tool-quickbar")?.addEventListener("click",event=>{
      const btn=event.target.closest("[data-rail-visibility]");if(!btn)return;
      const id=btn.dataset.railVisibility;if(!sections.some(([key])=>key===id))return;
      if(hiddenSections.has(id))hiddenSections.delete(id);else hiddenSections.add(id);
      try{localStorage.setItem(sectionKey,JSON.stringify([...hiddenSections]));}catch{}
      render();
      if(id==="merits"&&!hiddenSections.has(id)&&tornGuideApi.isConnected())void tornGuideApi.refresh({route:tornGuideApi.routeName(),includeMerits:true}).catch(()=>{});
    });
    tornRoadmap.wireActivities(host());
    if(host())tornMeritGuide.wireAffronted(host());
    host()?.addEventListener("toggle",event=>{const section=event.target;if(!section.matches?.("details[data-rail-section]")||!section.isConnected)return; if(section.open)collapsed.delete(section.dataset.railSection);else collapsed.add(section.dataset.railSection);},true);
    host()?.addEventListener("click",event=>{
      const tab=event.target.closest("[data-rail-tab]");
      if(tab){
        activeTab=tab.dataset.railTab;
        try{localStorage.setItem(tabKey,activeTab);}catch{}
        render();host()?.querySelector('[data-rail-tab="'+activeTab+'"]')?.focus({preventScroll:true});
        if(activeTab==="stocks"&&(!tornGuideApi.state.data.stocks||!tornGuideApi.state.data.stockCatalog))void load();
        return;
      }
    });
  }
  return {init,render,tick,order,controls,propertyModel,meritsVisible:()=>!hiddenSections.has("merits")};
})();
