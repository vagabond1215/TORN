"use strict";
const tornRightRail=(()=>{
  const order=[["virus","Virus"],["rw","Ranked war"],["flight","Travel"],
    ["bank","Investment"],["education","Education"],["oc","Organized crime"],
    ["drug","Drug CD"],["booster","Booster CD"],["medical","Medical CD"]];
  let busy=false,initialized=false;
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
      order.map(([id,label])=>'<div class="rail-timer-row" title="'+safe(entries.get(id)?.note||"Not loaded")+'">'+
        '<dt>'+safe(label)+'</dt><dd data-rail-timer="'+id+'">'+
        safe(status(entries.get(id)))+'</dd></div>').join("")+
      '</dl><p class="rail-snapshot-note">Local countdowns · API update on request</p>'+
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
    const total=b||s?((b?base:0)+(s?staff:0)):null;
    return '<section class="panel rail-property"><div class="panel-heading"><h2>Property</h2></div>'+
      '<div class="panel-content"><p class="rail-property-name">'+safe(name)+'</p>'+
      '<dl class="home-stat-list">'+homePair("Daily upkeep",total==null?"Not available":"$"+formatNumber(total))+
      (b?homePair("Property","$"+formatNumber(base)):"")+
      (s?homePair("Staff","$"+formatNumber(staff)):"")+
      '</dl>'+sourceError("property")+'</div></section>';
  }
  function statBlocks(){
    const b=payload("battlestats","battlestats"),w=payload("workstats","workstats"),
      job=payload("job","job");
    const v=k=>homeValue(b?.[k]&&typeof b[k]==="object"?b[k].value:b?.[k]);
    const wv=(...keys)=>{for(const k of keys)if(w?.[k]!=null)return homeValue(w[k]);return "Not available";};
    const jobName=job?.name||job?.company_name||job?.position;
    return '<section class="panel home-battle rail-stats"><div class="panel-heading"><h2>Battle stats <a href="#stats">Calc</a></h2></div>'+
      '<div class="panel-content">'+homeStatList([
        ["Strength",v("strength")],["Defense",v("defense")],["Speed",v("speed")],
        ["Dexterity",v("dexterity")],["Total",v("total")]
      ])+sourceError("battlestats")+'</div></section>'+
      '<section class="panel home-work rail-stats"><div class="panel-heading"><h2>Working stats <a href="#jobs">Jobs</a></h2></div>'+
      '<div class="panel-content">'+homeStatList([
        ["Manual labor",wv("manual_labor","manual","man")],
        ["Intelligence",wv("intelligence","intel","int")],
        ["Endurance",wv("endurance","end")]
      ])+(jobName?'<p class="home-subline">'+safe(jobName)+'</p>':"")+
      sourceError("workstats")+'</div></section>';
  }
  function render(route=(location.hash||"#home").slice(1)||"home"){
    const el=host();if(!el)return;
    el.hidden=!tornGuideApi.isConnected()||route==="profile";
    if(el.hidden){el.innerHTML="";return;}
    el.innerHTML=clocks()+networthPanel()+property()+statBlocks();
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
    host()?.addEventListener("click",event=>{
      const btn=event.target.closest("[data-rail-refresh]");
      if(btn)load(btn);
    });
  }
  return {init,render,tick,order};
})();
