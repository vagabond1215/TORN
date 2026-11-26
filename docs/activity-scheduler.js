"use strict";
// TORN shared, read-only activity scheduling. All persisted dates are UTC ms.
const tornActivityScheduler=(()=>{
  const H=3600000,D=24*H, W=7*D;
  const defaults={preferred:2,recommended:3,restrict:5,prewar:0,travel:"standard",rehabMinutes:30,rehabSessions:1,sharedBudget:false,warReserve:0,rehabReserve:0,view:"agenda"};
  const travelTimes={standard:166,airstrip:116,wlt:83,business:50};
  const kinds={training:"Training",rehab:"Rehab",travel:"Travel",war:"War",chain:"Chain",oc:"Organized crime",racing:"Racing",education:"Education",event:"Event",personal:"Personal",health:"Health",collection:"Collection"};
  const esc=x=>String(x??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const owner=()=>String(tornGuideApi.state.identity?.id??"guest");
  const key=(name)=>"torn-city-guide:activity-"+name+":"+owner();
  const read=(name,fallback)=>{try{return JSON.parse(localStorage.getItem(key(name)))??fallback;}catch{return fallback;}};
  const write=(name,value)=>{try{localStorage.setItem(key(name),JSON.stringify(value));return true;}catch{return false;}};
  const bounded=(n,lo,hi,fallback)=>n!=null&&Number.isFinite(Number(n))?Math.max(lo,Math.min(hi,Number(n))):fallback;
  function settings(){
    const s=read("settings",{}),p=bounded(s.preferred,0,9,defaults.preferred),r=bounded(s.recommended,p,9,Math.max(p,defaults.recommended));
    return {...defaults,preferred:p,recommended:r,restrict:bounded(s.restrict,r,9,Math.max(r,defaults.restrict)),prewar:bounded(s.prewar,0,9,0),
      travel:Object.hasOwn(travelTimes,s.travel)?s.travel:defaults.travel,rehabMinutes:bounded(s.rehabMinutes,15,180,30),rehabSessions:Math.round(bounded(s.rehabSessions,1,100,1)),
      sharedBudget:s.sharedBudget===true,warReserve:bounded(s.warReserve,0,1e12,0),rehabReserve:bounded(s.rehabReserve,0,1e12,0),view:["agenda","timeline","week","month"].includes(s.view)?s.view:"agenda"};
  }
  function events(){
    const list=read("events",[]);
    return Array.isArray(list)?list.filter(e=>typeof e.id==="string"&&Object.hasOwn(kinds,e.kind)&&typeof e.title==="string"&&Number.isFinite(e.start)&&Number.isFinite(e.end)&&e.end>e.start).slice(0,300):[];
  }
  function saveEvent(e){
    const list=events().filter(x=>x.id!==e.id);
    if(!Object.hasOwn(kinds,e.kind)||!e.title.trim()||!Number.isFinite(e.start)||!Number.isFinite(e.end)||e.end<=e.start||list.length>=300)return false;
    list.push({...e,title:e.title.trim().slice(0,100),blocking:e.blocking===true,source:"manual"});
    return write("events",list);
  }
  const removeEvent=id=>write("events",events().filter(e=>e.id!==id));
  const time=at=>new Date(at).toISOString().slice(0,16).replace("T"," ")+" TCT";
  const shortTime=at=>new Date(at).toISOString().slice(11,16);
  function warWindow(war,warSettings,now=Date.now()){
    if(!war||!Number.isFinite(war.start)||war.start<=0||war.end>0&&war.end<=now||warSettings.mode==="off")return null;
    const cd=(420+bounded(warSettings.adjustment,-120,120,60))*60000;
    const buffer=bounded(warSettings.lead,0,120,120)*60000,clear=war.start-buffer,cutoff=clear-4*cd;
    return {...war,cd,buffer,clear,cutoff,phase:now>=war.start?"active":now>=cutoff?"stacking":"upcoming"};
  }
  // A shared, pure projection for Energy and Calendar. Held Energy is not
  // evidence of how many Xanax were taken. Only future doses are forecast.
  function warPreparation(war,live,held,avoidDrugs=false,now=Date.now()){
    if(!war)return null;
    const first=war.cutoff,interval=war.cd,desiredClear=war.clear;
    const base={first,due:null,doses:[],clearAt:null,energy:null,remaining:null,projectedEnergy:null,phase:war.phase,bufferReduced:false};
    if(now>=war.start)return {...base,phase:"active",label:"War active · reserve Energy for faction combat"};
    if(now<first)return {...base,due:first,remaining:4,projectedEnergy:1000,clearAt:desiredClear,label:"Training until stacking deadline",tentative:true,doses:Array.from({length:4},(_,i)=>({at:first+i*interval,energy:null}))};
    if(!live||!Number.isFinite(live.energy)||live.energy<0||!Number.isFinite(live.drug)||live.drug<0)
      return {...base,phase:"stacking",label:"Refresh to verify Energy and drug cooldown"};
    const energy=Math.min(1000,live.energy),remaining=Math.ceil((1000-energy)/250),ready=now+live.drug*1000;
    const known={...base,phase:"stacking",energy,remaining,projectedEnergy:energy,clearAt:ready};
    if(!remaining)return {...known,due:live.drug>0?ready:war.start,label:ready>war.start?"Hold 1,000 E · cooldown may extend into war":live.drug>0?"Hold 1,000 E · drug cooldown":"Hold 1,000 E for war",bufferReduced:ready>desiredClear};
    if(avoidDrugs)return {...known,due:war.start,label:"Preserve Energy · drug use excluded by Focus or addiction restrictions"};
    if(!Number.isFinite(held)||held<0)return {...known,label:"Refresh to verify Xanax inventory"};
    const fit=Math.max(0,Math.floor((war.start-ready)/interval)),count=Math.min(remaining,Math.floor(held),fit);
    if(!count)return {...known,due:war.start,label:held===0?"No Xanax on hand · preserve Energy for war":"Preserve Energy · another dose cannot clear before war"};
    const due=Math.max(ready,desiredClear-count*interval),clearAt=due+count*interval,projectedEnergy=Math.min(1000,energy+count*250),bufferReduced=clearAt>desiredClear;
    return {...known,due,clearAt,projectedEnergy,bufferReduced,doses:Array.from({length:count},(_,i)=>({at:due+i*interval,energy:Math.min(1000,energy+(i+1)*250)})),
      label:(due>now+1000?"Wait, then ":"")+"Take Xanax · "+count+" of "+remaining+" remaining doses fit"+(bufferReduced?" · clearance buffer reduced":"")};
  }
  function addictionSnapshot(now=Date.now(),s=settings(),war=null){
    const st=tornGuideApi.state,icons=st.data?.icons?.icons;
    const fresh=!!icons&&activityFresh("icons",now,15*60000);
    const texts=fresh?Object.values(icons).map(x=>typeof x==="string"?x:[x?.title,x?.name,x?.description,x?.text].filter(Boolean).join(" ")):[];
    return {...addiction(fresh,texts,s,war),fresh};
  }
  function addiction(iconFresh,iconTexts,s=settings(),war=null){
    const relevant=iconTexts.filter(x=>/addict/i.test(x));
    const values=relevant.map(x=>x.match(/(?:reduced by|reduction of|[-−])\s*(\d+(?:\.\d+)?)\s*%/i)?.[1]).filter(x=>x!=null).map(Number);
    const penalty=!iconFresh||relevant.length&&!values.length?null:values.length?Math.max(...values):0;
    const prewar=war&&war.phase!=="active"&&penalty!=null&&penalty>s.prewar;
    const level=penalty==null?"unknown":penalty>=s.restrict?"restricted":penalty>=s.recommended||prewar?"recommended":penalty>=s.preferred?"preferred":"normal";
    return {penalty,level,prewar:!!prewar,blockDrugs:level==="restricted"};
  }
  function budget(remaining,s,war,health){
    const warReserve=s.sharedBudget&&war?s.warReserve:0,rehabReserve=s.sharedBudget&&health&&["preferred","recommended","restricted"].includes(health.level)?Math.max(s.rehabReserve,rehabEstimate(s)):0;
    return {remaining,warReserve,rehabReserve,training:remaining==null?null:Math.max(0,remaining-warReserve-rehabReserve),shortfall:remaining!=null&&warReserve+rehabReserve>remaining};
  }
  function rehabEstimate(s){return s.rehabSessions*250000+(s.travel==="standard"?54000:0);}
  function rehabDuration(s){return (Math.ceil(2*travelTimes[s.travel]*1.03)+s.rehabMinutes)*60000;}
  function limits({war,manual=events(),now=Date.now(),extra=[]}={}){
    const reservations=[...manual,...extra].filter(e=>e.blocking&&e.end>now).map(e=>({...e}));
    if(war)reservations.push({id:"war-reservation",title:"War preparation / active war",kind:"war",start:war.cutoff,end:war.end>now?war.end:Infinity,blocking:true});
    const next=reservations.sort((a,b)=>a.start-b.start).find(e=>e.end>now&&e.start<now+W);
    return {deadline:next?Math.max(now,next.start):null,blocked:!!next&&next.start<=now,reason:next?.title??null,reservations};
  }
  function conflicts(rows,deadline,now=Date.now(),drugClear=true,xanaxMs=8*H){
    if(deadline==null)return false;
    return rows.some(({step,done,due})=>!done&&(!Number.isFinite(due)||due>=deadline||
      drugClear&&["xanax","ecstasy"].includes(step.type)&&Math.max(due,now)+(step.type==="xanax"?xanaxMs:Math.max(4*H,(step.after?.drug??0)*1000))>deadline));
  }
  function rehabWindow({now=Date.now(),health,war,manual=events(),actions=[],drugReady=null,s=settings(),travelAvailable=false}={}){
    if(!health||!["preferred","recommended","restricted"].includes(health.level)||!travelAvailable||war&&war.phase!=="upcoming")return null;
    const duration=rehabDuration(s),end=Math.min(now+W,war?.cutoff??Infinity);
    const busy=manual.filter(x=>x.blocking&&x.end>now);
    const fits=(start,finish)=>finish<=end&&!busy.some(x=>start<x.end&&finish>x.start);
    const times=[now,...new Set(actions.filter(x=>Number.isFinite(x)&&x>=now&&x<end))].sort((a,b)=>a-b);
    if(Number.isFinite(drugReady)&&drugReady>now)times.push(drugReady);
    times.sort((a,b)=>a-b);
    const unique=[...new Set(times)];
    for(let i=0;i<unique.length;i++){
      const start=unique[i]+(actions.some(at=>Math.abs(at-unique[i])<1000)?60000:0),finish=start+duration,next=unique[i+1]??end;
      if(finish<=next&&fits(start,finish))return {start,end:finish,duration,cost:rehabEstimate(s),type:s.travel,source:"proposal",overlapsCooldown:Number.isFinite(drugReady)&&finish<=drugReady};
    }
    // Critical rehab may require pausing training rather than fitting a gap.
    if(health.level==="restricted"&&fits(now,now+duration))return {start:now,end:now+duration,duration,cost:rehabEstimate(s),type:s.travel,source:"proposal",requiresPause:true};
    return null;
  }
  // Rehab confirmation uses fresh cumulative counters, never a happiness
  // change or natural addiction decay. All expenses are locally scoped.
  function activityFresh(key,now,age){const at=Number(tornGuideApi.state.fetchedAt?.[key]||0);return at>0&&at<=now+1000&&now-at<=age&&!tornGuideApi.state.errors?.[key];}
  function rehabSnapshot(now=Date.now()){
    if(!activityFresh("rehabStats",now,30*60000))return null;
    const root=tornGuideApi.state.data?.rehabStats?.personalstats;
    let count=null,cost=null;
    const num=x=>x!=null&&Number.isFinite(Number(x))&&Number(x)>=0?Number(x):null;
    const visit=(x,depth=0)=>{
      if(!x||typeof x!=="object"||depth>7)return;
      if(x.name==="rehabs")count=num(x.value);
      if(x.name==="rehabcost")cost=num(x.value);
      if(Object.hasOwn(x,"rehabs"))count=num(x.rehabs);
      if(Object.hasOwn(x,"rehabcost"))cost=num(x.rehabcost);
      const rehab=x.rehabilitations??x.rehabilitation;
      if(rehab&&typeof rehab==="object"){
        count=num(rehab.amount??rehab.count)??count;
        cost=num(rehab.fees??rehab.cost)??cost;
      }
      for(const y of Object.values(x))if(typeof y==="object")visit(y,depth+1);
    };
    visit(root);
    return count===null?null:{count,cost,at:Number(tornGuideApi.state.fetchedAt.rehabStats)};
  }
  function spendLedger(now=Date.now()){
    const list=read("spend-ledger",[]);
    return Array.isArray(list)?list.filter(e=>typeof e.id==="string"&&["war","rehab"].includes(e.kind)&&Number.isFinite(e.at)&&e.at<=now+1000&&e.at>now-90*D&&Number.isFinite(e.cost)&&e.cost>=0):[];
  }
  function recordSpend(e){
    if(!["war","rehab"].includes(e.kind)||!Number.isFinite(e.at)||e.at>Date.now()+1000||!Number.isFinite(e.cost)||e.cost<0)return false;
    const list=spendLedger();if(list.some(x=>x.id===e.id))return true;
    return write("spend-ledger",[...list,e].slice(-500));
  }
  function weeklySpend(now=Date.now()){return spendLedger(now).filter(e=>e.at>now-W).reduce((a,e)=>a+e.cost,0);}
  function reconcileRehab(now=Date.now()){
    const cur=rehabSnapshot(now);if(!cur||!activityFresh("profile",now,15*60000))return null;
    const status=String(tornGuideApi.state.data?.profile?.profile?.status?.state??"").toLowerCase();
    if(!["okay","ok"].includes(status))return null;
    const list=events(),eligible=list.filter(e=>e.kind==="rehab"&&!e.completedAt&&e.rehabBaseline&&e.start<=now&&cur.at>=e.start&&Number(tornGuideApi.state.fetchedAt.profile)>=e.start&&cur.at>e.rehabBaseline.at&&cur.count>e.rehabBaseline.count);
    if(eligible.length!==1)return null;
    const e=eligible[0],base=e.rehabBaseline,cost=cur.cost!=null&&base.cost!=null&&cur.cost>=base.cost?cur.cost-base.cost:null;
    if(cost!=null&&!recordSpend({id:"rehab-"+e.id,kind:"rehab",at:Math.min(now,cur.at),cost,source:"API counter delta"}))return null;
    e.completedAt=now;e.blocking=false;e.end=Math.max(e.start+1,now);e.rehabCost=cost;
    if(!write("events",list))return null;
    return {event:e,cost,count:cur.count-base.count};
  }
  // Verified v2 schemas: https://www.torn.com/swagger/openapi.json
  const absolute=v=>{if(v==null)return null;const n=Number(v);return Number.isFinite(n)&&n>=1e9?(n>=1e12?n:n*1000):null;};
  function externalEvents(now=Date.now()){
    const st=tornGuideApi.state,rows=[];
    const chainKey=activityFresh("factionChain",now,5*60000)?"factionChain":activityFresh("bars",now,5*60000)?"bars":null;
    if(chainKey){
      const chain=chainKey==="bars"?st.data?.bars?.bars?.chain:st.data?.factionChain?.chain;
      const deadline=Number(st.fetchedAt[chainKey])+Number(chain?.timeout)*1000;
      if(Number(chain?.current)>0&&Number(chain?.timeout)>0&&deadline>now)
        rows.push({id:"chain-"+(chain.id??"current"),kind:"chain",title:"Active chain · "+chain.current+"/"+chain.max+" hits",start:now,end:deadline,source:"API · next-hit deadline",detail:"Not a predicted chain end",blocking:false});
    }
    if(activityFresh("races",now,30*60000)){
      const races=st.data?.races?.races;
      if(Array.isArray(races))for(const race of races){
        const start=absolute(race.schedule?.start),end=absolute(race.schedule?.end);
        if(start===null||!["open","in_progress"].includes(race.status)||race.status==="open"&&start<now||end!=null&&end<now)continue;
        rows.push({id:"race-"+race.id,kind:"racing",title:race.title||"Race "+race.id,start,end:end>start?end:Math.max(start,now),source:"API · "+race.status,detail:end?"":"End not supplied",blocking:false});
      }
    }
    if(activityFresh("calendarCatalog",now,24*H)){
      const calendar=st.data?.calendarCatalog?.calendar,slot=activityFresh("calendar",now,24*H)?st.data?.calendar?.calendar?.start_time:null;
      const clock=typeof slot==="string"&&slot.match(/^(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*TCT)?$/i);
      const minutes=clock?Number(clock[1])*60+Number(clock[2]):null;
      const entries=[...(Array.isArray(calendar?.events)?calendar.events:[]),...(Array.isArray(calendar?.competitions)?calendar.competitions:[])];
      for(const [i,e] of entries.entries()){
        let start=absolute(e.start),end=absolute(e.end),personal=false;
        if(start===null||end===null||end<=start||typeof e.title!=="string")continue;
        const earliest=absolute(e.earliest_start),latest=absolute(e.latest_end);
        if(e.fixed_start_time===false&&minutes!==null&&minutes>=0&&minutes<1440&&earliest!==null&&latest!==null){
          const adjusted=Math.floor(earliest/D)*D+minutes*60000,finish=adjusted+(end-start);
          if(adjusted>=earliest&&finish<=latest){start=adjusted;end=finish;personal=true;}
        }
        if(end<now)continue;
        rows.push({id:"season-"+i+"-"+start,kind:"event",title:e.title,start,end,source:e.fixed_start_time===true?"Torn Calendar API":personal?"Torn Calendar · personal TCT slot":"Torn Calendar · verify personal slot",detail:e.fixed_start_time===true||personal?"":slot?"Personal slot: "+slot:"Personal slot unavailable",blocking:false});
      }
    }
    return rows;
  }
  function warAttackSummary(war,now=Date.now()){
    if(!war||war.phase!=="active"||!activityFresh("warAttacks",now,10*60000))return null;
    const attacks=tornGuideApi.state.data?.warAttacks?.attacks,ownerId=Number(tornGuideApi.state.identity?.id);
    if(!Array.isArray(attacks)||!ownerId)return null;
    const own=attacks.filter(a=>Number(a.attacker?.id)===ownerId&&absolute(a.started)>=war.start&&a.is_ranked_war===true);
    return {attacks:own.length,respect:own.reduce((n,a)=>n+(Number(a.respect_gain)||0),0),at:Number(tornGuideApi.state.fetchedAt.warAttacks),limited:attacks.length>=100||!!tornGuideApi.state.data.warAttacks?._metadata?.links?.next};
  }
  function apiEvents(now=Date.now()){
    if(typeof tornTctClock==="undefined")return [];
    const map={point:"collection",addiction:"health",company:"collection",companyStar:"collection",bank:"collection",flight:"travel",education:"education",virus:"event",oc:"oc",drug:"health",booster:"health",medical:"health"};
    return tornTctClock.entries().filter(x=>map[x.id]&&Number.isFinite(x.at)&&x.at>=now).map(x=>({id:"api-"+x.id,kind:map[x.id],title:x.title,start:x.at,end:x.at,source:x.note?.includes("API")?"API / cached":"Timer estimate",detail:x.note,blocking:false}));
  }
  function schedule({now=Date.now(),war=null,preparation=null,health=null,rehab=null,training=[],manual=events(),limit=null}={}){
    const list=[...manual.filter(x=>x.end>=now),...apiEvents(now),...externalEvents(now)];
    if(war){
      if(war.phase!=="active"){
        if(war.cutoff>=now)list.push({id:"war-cutoff",kind:"war",title:"Training cutoff / stack begins",start:war.cutoff,end:war.cutoff,source:"Calculated deadline"});
        const prep=preparation??warPreparation(war,null,null,false,now);
        for(const [i,dose] of (prep?.doses??[]).entries()){
          if(dose.at>=now)list.push({id:"war-dose-"+i,kind:"war",title:"War stack · Xanax "+(i+1)+" of "+prep.doses.length,start:dose.at,end:dose.at,source:prep.tentative?"Tentative; verify live cooldown":"Projected from current account state",detail:dose.energy==null?"":dose.energy+" E projected"});
        }
        if(prep?.clearAt!=null&&prep.clearAt>=now&&prep.clearAt<=war.start)
          list.push({id:"war-clear",kind:"war",title:"Projected drug cooldown clear",start:prep.clearAt,end:prep.clearAt,source:prep.tentative?"Target":prep.bufferReduced?"Estimated · clearance buffer reduced":"Estimated"});
        if(!prep?.tentative&&!prep?.doses?.length&&prep?.label)list.push({id:"war-status",kind:"war",title:prep.label,start:now,end:now,source:"Current preparation status"});
      }
      if(war.source!=="Manual Calendar war")list.push({id:"war-start",kind:"war",title:war.stale?"Last known ranked war schedule":war.phase==="active"?"Ranked war active":"Ranked war begins",start:war.start,end:war.end>now?war.end:war.start,source:war.source??"Faction API"});
    }
    if(rehab)list.push({id:"rehab-proposal",kind:"rehab",title:"Suggested Switzerland rehabilitation",start:rehab.start,end:rehab.end,source:"Proposal · not booked",detail:"Estimated $"+rehab.cost.toLocaleString("en-US")});
    for(const x of training)if(x.start>=now-60000&&(limit==null||x.start<limit))list.push(x);
    return list.sort((a,b)=>a.start-b.start||a.title.localeCompare(b.title));
  }
  const dateLabel=at=>new Date(at).toISOString().slice(0,10);
  function renderAgenda(list){
    let day="";
    return '<div class="activity-agenda">'+list.map(e=>{
      const date=dateLabel(e.start),heading=date===day?"":'<h4>'+esc(date)+' · TCT</h4>';day=date;
      return heading+'<div class="activity-event activity-'+esc(e.kind)+'"><time>'+shortTime(e.start)+(e.end>e.start?'–'+shortTime(e.end):"")+'</time><div><strong>'+esc(e.title)+'</strong><small>'+esc(e.source??"Manual")+(e.detail?" · "+esc(e.detail):"")+'</small></div>'+(e.source==="manual"?'<button type="button" data-activity-remove="'+esc(e.id)+'" aria-label="Remove '+esc(e.title)+'">×</button>':"")+'</div>';
    }).join("")+'</div>';
  }
  function renderTimeline(list,now,days=7){
    const end=now+days*D;
    return '<div class="activity-timeline">'+Object.entries(kinds).map(([kind,label])=>{
      const rows=list.filter(e=>e.kind===kind&&e.start<end&&e.end>=now);if(!rows.length)return "";
      return '<div class="activity-lane"><strong>'+esc(label)+'</strong><div>'+rows.map(e=>{const x=Math.max(0,Math.min(99,(e.start-now)/(end-now)*100)),w=Math.min(100-x,Math.max(1,(e.end-Math.max(now,e.start))/(end-now)*100));return '<span class="activity-'+kind+'" title="'+esc(time(e.start)+" "+e.title)+'" style="left:'+x+'%;width:'+w+'%"></span>';}).join("")+'</div></div>';
    }).join("")+'</div><small>Next '+days+' days · hover markers for details</small>'+renderAgenda(list.filter(e=>e.start<end));
  }
  function renderGrid(list,now,days){
    const start=Math.floor(now/D)*D;
    return '<div class="activity-grid">'+Array.from({length:days},(_,i)=>{const at=start+i*D;return '<section><strong>'+dateLabel(at).slice(5)+'</strong>'+list.filter(e=>e.start<at+D&&e.end>=at).slice(0,8).map(e=>'<small class="activity-'+esc(e.kind)+'">'+esc(shortTime(Math.max(e.start,at))+" "+e.title)+'</small>').join("")+'</section>';}).join("")+'</div>';
  }
  function render(list,{full=false,now=Date.now(),view=settings().view}={}){
    const modes=full?["agenda","timeline","week","month"]:["agenda","timeline","week"];
    if(!modes.includes(view))view="agenda";
    const visible=list.filter(e=>e.start<now+(view==="month"?30:7)*D&&e.end>=now);
    return '<div class="activity-calendar"><div class="activity-tabs">'+modes.map(m=>'<button type="button" data-activity-view="'+m+'" aria-pressed="'+(view===m)+'">'+m[0].toUpperCase()+m.slice(1)+'</button>').join("")+'</div>'+
      (!visible.length?'<p class="fine-print">No scheduled activities in this window.</p>':view==="agenda"?renderAgenda(visible):view==="timeline"?renderTimeline(visible,now):renderGrid(visible,now,view==="month"?30:7))+
      '<small>Forecasts are tentative. The Energy tile remains the action and confirmation interface.</small></div>';
  }
  function settingsDialog(onChange,button){
    if(document.querySelector(".activity-settings-dialog[open]"))return;
    const s=settings(),id=owner(),d=document.createElement("dialog");
    d.className="restock-settings-dialog activity-settings-dialog";
    const field=(label,k,min,max)=>'<label>'+label+' <input type="number" name="'+k+'" min="'+min+'" max="'+max+'" value="'+s[k]+'" required></label>';
    d.innerHTML='<form><header><h2>Activity scheduling</h2><button type="button" data-close aria-label="Close">×</button></header><div class="activity-settings-fields">'+
      field("Rehab preferred (%)","preferred",0,9)+field("Rehab recommended (%)","recommended",0,9)+field("Restrict drugs (%)","restrict",0,9)+field("Pre-war penalty target (%)","prewar",0,9)+
      '<label>Switzerland travel <select name="travel">'+Object.keys(travelTimes).map(k=>'<option value="'+k+'" '+(k===s.travel?"selected":"")+'>'+k+' ('+travelTimes[k]+' min each way)</option>').join("")+'</select></label>'+
      field("Rehab / return allowance (min)","rehabMinutes",15,180)+field("Estimated rehab sessions","rehabSessions",1,100)+
      '<label><input type="checkbox" name="sharedBudget" '+(s.sharedBudget?"checked":"")+'> Reserve war and rehab expenses from weekly training budget</label>'+
      field("War cash reserve ($)","warReserve",0,1e12)+field("Rehab cash reserve ($)","rehabReserve",0,1e12)+
      '<small>Travel mode and rehab session count are user estimates. Rehab does not clear drug cooldown. No trips or game actions are executed automatically.</small></div><footer><small role="status"></small><button type="submit">Save</button></footer></form>';
    document.body.append(d);d.querySelector("[data-close]").onclick=()=>d.close();d.addEventListener("close",()=>{d.remove();button?.focus();},{once:true});
    d.querySelector("form").onsubmit=e=>{e.preventDefault();if(id!==owner()){d.close();return;}const f=new FormData(e.currentTarget),v={...s};for(const k of ["preferred","recommended","restrict","prewar","rehabMinutes","rehabSessions","warReserve","rehabReserve"])v[k]=Number(f.get(k));v.travel=f.get("travel");v.sharedBudget=f.has("sharedBudget");if(v.preferred>v.recommended||v.recommended>v.restrict){d.querySelector('[role="status"]').textContent="Use ascending thresholds.";return;}if(!write("settings",v)){d.querySelector('[role="status"]').textContent="Could not save.";return;}d.close();onChange();};
    d.showModal();
  }
  function expenseForm(){
    const entries=spendLedger().filter(e=>e.at>Date.now()-W).sort((a,b)=>b.at-a.at);
    return '<form class="activity-manual-form" data-activity-spend><strong>Record actual war / rehab expense</strong><label>Category <select name="kind"><option value="war">War</option><option value="rehab">Rehab</option></select></label><label>Cash spent ($) <input name="cost" type="number" min="0" step="1" required></label><button type="submit">Record expense</button><small>Do not duplicate rehab fees already confirmed by the API.</small><small role="status"></small></form><div class="activity-agenda">'+entries.map(e=>'<div class="activity-event activity-'+esc(e.kind)+'"><time>'+esc(dateLabel(e.at))+'</time><div><strong>$'+e.cost.toLocaleString("en-US")+'</strong><small>'+esc(kinds[e.kind]+" · "+e.source)+'</small></div></div>').join("")+'</div>';
  }
  function manualForm(){
    return '<form class="activity-manual-form" data-activity-form><label>Activity <input name="title" maxlength="100" required placeholder="Faction chain"></label><label>Category <select name="kind">'+Object.entries(kinds).map(([id,label])=>'<option value="'+id+'">'+label+'</option>').join("")+'</select></label><label>Start (TCT) <input type="datetime-local" name="start" required></label><label>End (TCT) <input type="datetime-local" name="end" required></label><label><input type="checkbox" name="blocking" checked> Reserve time (pause training)</label><small>Manual War activities also calculate a four-Xanax preparation cutoff when automatic war mode is enabled.</small><button type="submit">Add activity</button><small role="status"></small></form>';
  }
  function wire(view,onChange){
    if(view.dataset.activityBound==="1")return;view.dataset.activityBound="1";
    view.addEventListener("click",e=>{
      const mode=e.target.closest("[data-activity-view]"),remove=e.target.closest("[data-activity-remove]");
      if(mode){write("settings",{...settings(),view:mode.dataset.activityView});onChange();}
      else if(remove){removeEvent(remove.dataset.activityRemove);onChange();}
    });
    view.addEventListener("submit",e=>{
      if(e.target.matches("[data-activity-spend]")){
        e.preventDefault();const f=new FormData(e.target),cost=Number(f.get("cost"));
        if(recordSpend({id:"manual-"+Date.now(),kind:f.get("kind"),at:Date.now(),cost,source:"Manual confirmation"}))onChange();else e.target.querySelector('[role="status"]').textContent="Unable to save expense.";
        return;
      }
      if(!e.target.matches("[data-activity-form]"))return;e.preventDefault();const f=new FormData(e.target),start=Date.parse(f.get("start")+"Z"),end=Date.parse(f.get("end")+"Z");
      if(saveEvent({id:"manual-"+Date.now(),title:String(f.get("title")),kind:f.get("kind"),start,end,blocking:f.has("blocking")}))onChange();else e.target.querySelector('[role="status"]').textContent="Check the times and storage availability.";
    });
  }
  return {settings,events,saveEvent,removeEvent,warWindow,warPreparation,addiction,addictionSnapshot,budget,rehabEstimate,rehabDuration,limits,conflicts,rehabWindow,rehabSnapshot,reconcileRehab,spendLedger,recordSpend,weeklySpend,activityFresh,externalEvents,warAttackSummary,schedule,render,settingsDialog,manualForm,expenseForm,wire,time,kinds};
})();
