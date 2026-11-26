"use strict";
const tornRightRail=(()=>{
  const cooldowns=[["medical","Medical"],["drug","Drug"],["booster","Booster"]];
  const timers=[["oc","Organized crime ready"],["rw","Ranked war"],["raid","Raid war"],
    ["virus","Virus completes"],["education","Education completes"],["flight","Travel arrival"],
    ["bank","Bank investment matures"],["point","Daily reset"]];
  const order=[...cooldowns,...timers.filter(([id])=>id!=="point")];
  const tabs=[["cooldowns","Cooldowns"],["timers","Timers"],["stocks","Stocks"]];
  const tabKey="torn-city-guide:right-rail:countdown-tab";
  let busy=false,initialized=false,activeTab="cooldowns",refreshStatus="";
  try{const saved=localStorage.getItem(tabKey);if(tabs.some(([id])=>id===saved))activeTab=saved;}catch{}
  const collapsed=new Set();
  const sectionKey="torn-city-guide:right-rail:hidden:v1";
  const sections=[["timers","Cooldowns, timers and stocks",'<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6M12 2v3"/>'],["networth","Net worth",'<path d="M3 3v18h18M6 15l5-5 4 3 6-8M16 5h5v5"/>'],["property","Property",'<path d="m3 10 9-7 9 7M5 9v12h14V9M10 21v-7h4v7"/>']];
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
    if(cooldowns.some(([id])=>id===entry.id))return entry.note==="Not loaded"?"Not loaded":"Ready";
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
    const rows=(activeTab==="cooldowns"?cooldowns:timers).map(([id,label])=>{
      const entry=entries.get(id);
      return '<div class="rail-timer-row" title="'+safe(id==="virus"?virusTooltip():entry?.note||"Not loaded")+'">'+
        '<dt data-rail-timer-label="'+id+'">'+safe(["rw","raid"].includes(id)?entry?.title??label:label)+'</dt><dd data-rail-timer="'+id+'">'+safe(status(entry))+'</dd></div>';
    }).join("");
    return '<section class="panel rail-section rail-timers" aria-label="Countdowns"><div class="rail-timer-header">'+
      '<div class="rail-timer-tabs" role="group" aria-label="Countdown views">'+tabs.map(([id,label])=>
        '<button type="button" data-rail-tab="'+id+'" aria-controls="rail-timer-content" aria-pressed="'+(activeTab===id)+'">'+label+'</button>').join("")+'</div></div>'+
      '<div class="panel-content" id="rail-timer-content">'+(activeTab==="stocks"?stockTimers():'<dl class="rail-timer-list">'+rows+'</dl>')+
      '<span id="rail-refresh-status" class="sr-only" role="status">'+safe(refreshStatus)+'</span></div></section>';
  }
  function property(){
    const raw=payload("property","property");
    // user/property returns UserPropertyDetails whose property.name is a
    // separate BasicProperty; upkeep is on the details object itself.
    const p=raw?.upkeep?raw:raw?.property?.upkeep?raw.property:raw;
    const name=p?.property?.name??p?.name??"Not loaded";
    const upkeep=p?.upkeep;
    const base=Number(upkeep?.property),staff=Number(upkeep?.staff);
    const b=upkeep?.property!=null&&Number.isFinite(base);
    const s=upkeep?.staff!=null&&Number.isFinite(staff);
    const total=b&&s?base+staff:null;
    const due=upkeep?.total??upkeep?.due??upkeep?.outstanding??p?.upkeep_due;
    const currentTotal=due!=null&&Number.isFinite(Number(due))?Number(due):null;
    return '<section class="panel rail-property"><div class="panel-heading"><h2>Property</h2></div>'+
      '<div class="panel-content"><p class="rail-property-name">'+safe(name)+'</p>'+
      '<dl class="home-stat-list">'+homePair("Daily upkeep",total==null?"Not available":"$"+formatNumber(total))+
      (b?homePair("Property","$"+formatNumber(base)):"")+
      (s?homePair("Staff","$"+formatNumber(staff)):"")+
      homePair("Current total upkeep",currentTotal==null?"Not available":"$"+formatNumber(currentTotal))+
      '</dl>'+sourceError("property")+'</div></section>';
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
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(focus&&(!showFocus||focus.dataset.focusOwner!==owner)){focus.remove();focus=null;}
    if(showFocus&&!focus){
      el.insertAdjacentHTML("afterbegin",tornRoadmap.renderActivities());
      el.querySelector("#home-activities").dataset.focusOwner=owner;
    }
    let content=el.querySelector("[data-rail-content]");
    if(!content){
      content=document.createElement("div");content.dataset.railContent="";
      el.append(content);
    }
    content.hidden=!showSections;
    content.innerHTML=showSections?[["timers",clocks],["networth",networthPanel],["property",property]]
      .filter(([id])=>!hiddenSections.has(id)).map(([id,fn])=>id==="timers"?fn():collapsible(fn(),id)).join(""):"";
  }
  function tick(){
    const el=host();if(!el||el.hidden)return;
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
    });
    tornRoadmap.wireActivities(host());
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
  return {init,render,tick,order,controls};
})();
