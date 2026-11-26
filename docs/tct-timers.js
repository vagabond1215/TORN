"use strict";
/* Torn City Time is UTC. This client clock makes no requests.
 * Live personal timers load only by explicit user click through page-scoped
 * Torn API selections (education, virus, cooldowns, OC, rankedwars).
 */
const tornTctClock=(()=>{
  const customKey="torn-city-guide:tct:manual-rw:";
  let opened=false,interval=null,manualRW=null,manualOwner=null,busy=false;
  const get=id=>document.getElementById(id);
  const escape=v=>String(v==null?"":v).replace(/[&<>"']/g,c=>({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  }[c]));
  const seconds=v=>Number.isFinite(Number(v))?Math.max(0,Number(v)):null;
  const clock=()=>{
    const d=new Date();
    return [d.getUTCHours(),d.getUTCMinutes(),d.getUTCSeconds()].map(v=>String(v).padStart(2,"0")).join(":");
  };
  const formatDuration=sec=>{
    if(!Number.isFinite(sec))return "Unavailable";
    if(sec<=0)return "Ready";
    const s=Math.ceil(sec),d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60),r=s%60;
    return (d?d+"d ":"")+String(h).padStart(2,"0")+":"+String(m).padStart(2,"0")+":"+String(r).padStart(2,"0");
  };
  const utcTime=(h,m,weekday=null)=>{
    const d=new Date(),timestamp=Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate(),h,m,0);
    const adjustment=weekday===null?0:(weekday-d.getUTCDay()+7)%7;
    let target=timestamp+adjustment*86400000;
    if(target<=Date.now())target+=(weekday===null?1:7)*86400000;
    return target;
  };
  function parseAbsolute(value){
    if(value instanceof Date)return Number.isFinite(value.getTime())?value.getTime():null;
    if(typeof value==="number"){
      if(value>1e12)return value;
      if(value>1e9)return value*1000;
      return null;
    }
    if(typeof value==="string"&&value.trim()){
      if(/^\d{10,13}$/.test(value))return parseAbsolute(Number(value));
      const time=Date.parse(value);
      return Number.isFinite(time)?time:null;
    }
    return null;
  }
  function findEnd(value,selection){
    if(!value||typeof value!=="object")return null;
    // API may supply either a Unix end timestamp or remaining seconds. Reject
    // small values in absolute-only fields; never guess a fake completion time.
    for(const name of ["until","ends_at","end_at","completion_time","completed_at","finish_time","finish_at","ends","end","completion","finish"]){
      const timestamp=parseAbsolute(value[name]);
      if(timestamp!==null)return timestamp;
    }
    for(const name of ["time_left","timeleft","remaining","remaining_seconds","seconds_left"]){
      const remain=seconds(value[name]);
      if(remain!==null){
        const stamp=Number(tornGuideApi.state.fetchedAt[selection])||Date.now();
        return stamp+remain*1000;
      }
    }
    for(const key of ["current","coding","course","virus","education","organizedcrime","organized_crime"]){
      if(value[key]&&typeof value[key]==="object"){
        const found=findEnd(value[key],selection);if(found!==null)return found;
      }
    }
    return null;
  }
  function getData(section){
    const data=tornGuideApi.state.data[section];
    return data&&typeof data==="object"?(data[section]||data):null;
  }
  function cd(section){
    const data=getData("cooldowns"),v=data&&data[section];
    const remain=v&&typeof v==="object"?(v.remaining??v.time_left??v.seconds):v;
    const numeric=seconds(remain);
    if(numeric===null)return null;
    const stamp=Number(tornGuideApi.state.fetchedAt.cooldowns)||Date.now();
    return stamp+numeric*1000;
  }
  function rwDeadline(){
    const d=getData("factionRankedWars");
    const list=Array.isArray(d)?d:Array.isArray(d?.rankedwars)?d.rankedwars:
      Array.isArray(d?.wars)?d.wars:[];
    const now=Date.now();
    const upcoming=[];
    for(const war of list){
      const start=parseAbsolute(war.start??war.starts_at??war.start_at);
      const end=parseAbsolute(war.end??war.ends_at??war.end_at);
      if(start!==null&&start>now)upcoming.push({at:start,label:"Ranked war starts",kind:"API"});
      else if(end!==null&&end>now)upcoming.push({at:end,label:"Ranked war ends",kind:"API"});
    }
    upcoming.sort((a,b)=>a.at-b.at);
    return upcoming[0]||null;
  }
  function owner(){
    return tornGuideApi.state.identity?.id||"guest";
  }
  function loadManual(){
    const id=owner();
    if(id===manualOwner)return;
    manualOwner=id;manualRW=null;
    try{
      const time=Number(localStorage.getItem(customKey+id));
      if(Number.isFinite(time)&&time>Date.now())manualRW=time;
    }catch{}
  }
  function entries(){
    loadManual();
    const now=Date.now();
    const list=[
      {id:"point",title:"Daily resets & JP usage",at:utcTime(0,0),note:"00:00 TCT • points refill & daily limits"},
      {id:"virusProcess",title:"Virus processing",at:utcTime(3,25),note:"Approx. daily processing window"},
      {id:"addiction",title:"Natural addiction decay",at:utcTime(3,31),note:"Approx. daily decay, not a predicted addiction amount"},
      {id:"company",title:"Company pay, work stats & JP",at:utcTime(18,0),note:"Around 18:00 TCT; processing can run later"},
      {id:"companyStar",title:"Company star review",at:utcTime(18,0,0),note:"Sunday, approximately 18:00 TCT"}
    ];
    const d=tornGuideApi.state.data;
    const bank=getData("money")?.city_bank,bankAt=parseAbsolute(bank?.until);
    list.push({id:"bank",title:"Bank investment matures",
      at:bankAt&&bankAt>now?bankAt:null,
      note:bankAt?"From cached user/money investment":"No active bank maturity in cache"});
    const travel=getData("travel"),arrive=parseAbsolute(travel?.arrival??travel?.until??travel?.timestamp);
    const remaining=seconds(travel?.time_left??travel?.remaining);
    const tripAt=arrive||remaining!==null?arrive||
      (Number(tornGuideApi.state.fetchedAt.travel||Date.now())+remaining*1000):null;
    list.push({id:"flight",title:"Travel arrival",at:tripAt&&tripAt>now?tripAt:null,
      note:travel?"From cached user/travel":"Travel not loaded; use Countdowns Update"});

    for(const [id,title,section] of [
      ["education","Education completion","education"],
      ["virus","Current virus completes","virus"],
      ["oc","Organized crime ready","organizedcrime"]
    ]){
      const obj=getData(section),at=obj?findEnd(obj,section):null;
      list.push({id,title,at:at&&at>now?at:null,
        note:!obj?"Not loaded":at?"From Torn API snapshot":"No active timer supplied by API"});
    }
    for(const key of ["drug","booster","medical"]){
      const at=cd(key);
      list.push({id:key,title:key[0].toUpperCase()+key.slice(1)+" cooldown",
        at:at&&at>now?at:null,note:at===null?"Not loaded":"Last API snapshot; timer counts down locally"});
    }
    const fromApi=rwDeadline();
    list.push({id:"rw",title:fromApi?.label||"Ranked war",at:fromApi?.at||(manualRW&&manualRW>now?manualRW:null),
      note:fromApi?"From faction API":manualRW&&manualRW>now?"Manual TCT start date":"Set a manual date or load faction data"});
    return list;
  }
  function renderRows(){
    const host=get("tct-countdowns");
    if(!host)return;
    const data=entries().filter(item=>!tornRightRail.order.some(([id])=>id===item.id));
    host.innerHTML=data.map(item=>'<div class="tct-row" title="'+escape(item.note)+'">'+
      '<span>'+escape(item.title)+'<small>'+escape(item.note)+'</small></span>'+
      '<strong data-tct-id="'+escape(item.id)+'">'+(item.at?formatDuration((item.at-Date.now())/1000):"Not available")+
      '</strong></div>').join("");
    tick();
  }
  function tick(){
    const time=get("tct-time");if(time)time.textContent=clock();
    if(!opened)return;
    const data=entries();
    for(const item of data){
      const node=document.querySelector('[data-tct-id="'+item.id+'"]');
      if(node)node.textContent=item.at?formatDuration((item.at-Date.now())/1000):
        item.id==="rw"?"Not scheduled":item.id==="education"||item.id==="virus"||item.id==="oc"?"None / not loaded":"Ready / not loaded";
    }
  }
  function open(value){
    const panel=get("tct-dropdown"),button=get("tct-toggle");
    if(!panel||!button)return;
    opened=Boolean(value);panel.hidden=!opened;
    button.setAttribute("aria-expanded",String(opened));
    if(opened)renderRows();
  }
  async function load(){
    if(busy)return;
    const button=get("tct-load"),status=get("tct-load-status");
    if(!tornGuideApi.isConnected()){status.textContent="Connect Torn API first.";return;}
    busy=true;button.disabled=true;status.textContent="Loading timer selections…";
    try{
      const result=await tornGuideApi.loadPage("timers",false);
      status.textContent=result?.skipped?"Cached timers are still fresh.":"Timer selections updated; unavailable fields remain labeled.";
    }catch(error){status.textContent=String(error.message||error);}
    finally{busy=false;button.disabled=false;renderRows();}
  }
  function saveManual(){
    const field=get("tct-manual-rw"),status=get("tct-load-status"),value=field?.value;
    if(typeof tornTrainingRecovery!=="undefined"&&tornTrainingRecovery.journalHeld(localStorage,owner())){status.textContent="Resolve the pending account restore before changing this deadline.";return;}
    if(!value){manualRW=null;try{localStorage.removeItem(customKey+owner());}catch{}
      status.textContent="Manual RW deadline cleared.";renderRows();return;}
    // datetime-local is a wall time string; interpret explicitly as UTC/TCT,
    // not in the browser's local timezone.
    const at=Date.parse(value+":00Z");
    if(!Number.isFinite(at)||at<=Date.now()){
      status.textContent="Enter a future Torn (UTC) date and time.";return;
    }
    manualOwner=owner();manualRW=at;
    try{localStorage.setItem(customKey+owner(),String(at));}catch{}
    status.textContent="Saved manually for this browser. It is not confirmed by Torn.";
    renderRows();
  }
  function init(){
    const button=get("tct-toggle");
    if(!button)return;
    button.addEventListener("click",()=>open(!opened));

    document.addEventListener("click",event=>{
      if(opened&&!event.target.closest("#tct-widget"))open(false);
    });
    document.addEventListener("keydown",event=>{
      if(event.key==="Escape"&&opened)open(false);
    });
    window.addEventListener("torn-guide-sync",()=>{if(opened)renderRows();});
    tick();
    interval=setInterval(tick,1000);
  }
  return {init,tick,entries,formatDuration,utcTime,findEnd,loadManual,renderRows};
})();
