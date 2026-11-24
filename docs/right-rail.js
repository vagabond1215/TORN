"use strict";
const tornRightRail=(()=>{
  const order=[["virus","Virus"],["rw","Ranked war"],["flight","Travel"],
    ["bank","Investment"],["education","Education"],["oc","Organized crime"],
    ["drug","Drug CD"],["booster","Booster CD"],["medical","Medical CD"]];
  let busy=false,initialized=false;
  const collapsed=new Set();
  const host=()=>document.getElementById("guide-right-rail");
  function status(entry){
    if(!entry)return "Not loaded";
    if(entry.at&&entry.at>Date.now())return tornTctClock.formatDuration((entry.at-Date.now())/1000);
    if(entry.at)return "Ready";
    if(entry.id==="rw")return "Not scheduled";
    if(entry.id==="bank")return tornGuideApi.state.data.money?"No deposit":"Not loaded";
    if(["drug","booster","medical"].includes(entry.id))
      return tornGuideApi.state.data.cooldowns?"Ready":"Not loaded";
    return /not loaded|not scheduled|manual/i.test(entry.note||"")?"Not loaded":"No active timer";
  }
  function clocks(){
    const entries=new Map(tornTctClock.entries().map(e=>[e.id,e]));
    return '<section class="panel rail-timers"><div class="panel-heading"><h2>Countdowns</h2>'+
      '<button type="button" data-rail-refresh title="Request stale countdown selections">Update</button></div>'+
      '<div class="panel-content"><dl class="rail-timer-list">'+
      order.map(([id,label])=>'<div class="rail-timer-row" title="'+safe(id==="virus"?virusTooltip():entries.get(id)?.note||"Not loaded")+'">'+
        '<dt>'+safe(label)+'</dt><dd data-rail-timer="'+id+'">'+
        safe(status(entries.get(id)))+'</dd></div>').join("")+
      '</dl>'+
      '<span id="rail-refresh-status" class="sr-only" role="status"></span></div></section>';
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
  function render(route=(location.hash||"#home").slice(1)||"home"){
    const el=host();if(!el)return;
    el.hidden=!tornGuideApi.isConnected()||route==="profile";
    if(el.hidden){el.innerHTML="";return;}
    el.innerHTML=collapsible(clocks(),"timers")+collapsible(networthPanel(),"networth")+collapsible(property(),"property");
  }
  function tick(){
    const el=host();if(!el||el.hidden)return;
    const entries=new Map(tornTctClock.entries().map(e=>[e.id,e]));
    for(const n of el.querySelectorAll("[data-rail-timer]")){
      const value=status(entries.get(n.dataset.railTimer));
      if(n.textContent!==value)n.textContent=value;
    }
  }
  async function load(button){
    if(busy||!tornGuideApi.isConnected())return;
    busy=true;button.disabled=true;button.textContent="Updating";
    try{await tornGuideApi.loadPage("railTimers");render();}
    catch(error){const status=document.getElementById("rail-refresh-status");
      if(status)status.textContent=String(error.message||error);}
    finally{busy=false;const btn=host()?.querySelector("[data-rail-refresh]");
      if(btn){btn.disabled=false;btn.textContent="Update";}}
  }
  function init(){
    if(initialized)return;initialized=true;
    host()?.addEventListener("toggle",event=>{const section=event.target;if(!section.matches?.("details[data-rail-section]")||!section.isConnected)return; if(section.open)collapsed.delete(section.dataset.railSection);else collapsed.add(section.dataset.railSection);},true);
    host()?.addEventListener("click",event=>{
      const btn=event.target.closest("[data-rail-refresh]");
      if(btn){event.preventDefault();event.stopPropagation();load(btn);}
    });
  }
  return {init,render,tick,order};
})();
