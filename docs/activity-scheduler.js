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
  const journalHeld=()=>typeof tornTrainingRecovery!=="undefined"&&tornTrainingRecovery.journalHeld(localStorage,owner());
  const write=(name,value)=>{if(journalHeld())return false;try{if(typeof tornAccountStorage!=="undefined")tornAccountStorage.trackedWrite(localStorage,owner(),key(name),JSON.stringify(value));else localStorage.setItem(key(name),JSON.stringify(value));return true;}catch{return false;}};
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
    if(journalHeld())return null;
    const cur=rehabSnapshot(now);if(!cur||!activityFresh("profile",now,15*60000))return null;
    const status=String(tornGuideApi.state.data?.profile?.profile?.status?.state??"").toLowerCase();
    if(!["okay","ok"].includes(status))return null;
    const list=events(),eligible=list.filter(e=>e.kind==="rehab"&&!e.completedAt&&!e.recoveryReview&&e.rehabBaseline&&e.start<=now&&cur.at>=e.start&&Number(tornGuideApi.state.fetchedAt.profile)>=e.start&&cur.at>e.rehabBaseline.at&&cur.count>e.rehabBaseline.count);
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
    const list=[...manual.filter(x=>x.end>=now).map(x=>x.recoveryReview?{...x,detail:"Restored reservation · review manually; remove and recreate if still needed"}:x),...apiEvents(now),...externalEvents(now)];
    if(war){
      if(war.phase!=="active"){
        if(war.cutoff>=now)list.push({id:"war-cutoff",kind:"war",title:"Training cutoff / stack begins",start:war.cutoff,end:war.cutoff,source:"Calculated deadline"});
        const prep=preparation??warPreparation(war,null,null,false,now);
        for(const [i,dose] of (prep?.doses??[]).entries()){
          if(dose.at>=now)list.push({id:"war-dose-"+i,kind:"war",title:"War stack · Xanax "+(i+1)+" of "+prep.doses.length,start:dose.at,end:dose.at,drugCooldownSeconds:!war.stale&&Number.isFinite(war.cd)&&war.cd>0?war.cd/1000:null,source:prep.tentative?"Tentative; verify live cooldown":"Projected from current account state",detail:dose.energy==null?"":dose.energy+" E projected"});
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
  // A unified timeline: actual intervals share a ruler, not separate category lanes.
  const timelineIcons={training:"⚡",rehab:"✚",travel:"✈",war:"⚔",chain:"↔",oc:"◆",racing:"⚑",education:"▤",event:"▣",personal:"◉",health:"✚",collection:"◷"};
  function timelineStatus(e){
    if(e.recoveryReview)return "Review required";
    if(e.stale||/last known|stale/i.test(e.source??"")||/last known/i.test(e.title))return "Last known · verify";
    if(e.blocking===true)return "Training reservation";
    if(/proposal|tentative|forecast|projected|estimated|target|calculated/i.test(e.source??""))return "Tentative / calculated";
    return "Scheduled / informational";
  }
  // Display-only intervals: a planned action is not proof of consumption.
  function timelineDrugCooldowns(rows,now,liveDrugSeconds){
    const intervals=[];
    if(Number.isFinite(liveDrugSeconds)&&liveDrugSeconds>0)
      intervals.push({id:"timeline-drug-current",kind:"health",title:"Drug cooldown · remaining",start:now,end:now+liveDrugSeconds*1000,source:"Recent API snapshot",detail:"Remaining cooldown from the current view time; original dose time is unknown. Refresh to verify.",cooldown:true,blocking:false});
    for(const e of rows){
      const seconds=e.drugCooldownSeconds;
      if(e.start!==e.end||e.start<now||!Number.isFinite(seconds)||seconds<=0||e.stale||e.recoveryReview)continue;
      intervals.push({id:"timeline-drug-"+e.id,kind:"health",title:"Drug cooldown · "+e.title,start:e.start,end:e.start+seconds*1000,source:"Projected cooldown · "+(e.source??"Training plan"),detail:"Estimated duration after this planned action, not a confirmed dose. Actual cooldown may vary; gym training is not inherently blocked.",cooldown:true,blocking:false});
    }
    return intervals;
  }
  // View time and source snapshot time are separate: moving the ruler
  // must not move planned events or extend a remaining cooldown.
  const timelineHours=[12,24,36,48],timelineDefaults={hours:12,scroll:true};
  function timelineControlSettings(){
    const saved=read("timeline-controls",null);
    return {hours:timelineHours.includes(saved?.hours)?saved.hours:timelineDefaults.hours,scroll:typeof saved?.scroll==="boolean"?saved.scroll:timelineDefaults.scroll};
  }
  function saveTimelineControls(value){
    if(!timelineHours.includes(value?.hours)||typeof value?.scroll!=="boolean")return false;
    return write("timeline-controls",{hours:value.hours,scroll:value.scroll});
  }
  function timelineWindow(at,hours=timelineDefaults.hours,scroll=timelineDefaults.scroll){
    const minute=Math.floor(at/60000)*60000,day=Math.floor(minute/D)*D;
    const duration=timelineHours.includes(hours)?hours:timelineDefaults.hours,rolling=scroll===true;
    // A fixed 12h window needs a noon boundary as well as midnight to
    // keep NOW in range. All longer fixed ranges start at TCT midnight.
    const start=rolling?minute:duration===12?day+Math.floor((minute-day)/(12*H))*12*H:day;
    return {hours:duration,scroll:rolling,at:minute,start,end:start+duration*H,width:duration*30,days:duration/24};
  }
  function timelineLayout(list,now,days=7,war=null,liveDrugSeconds=null,window=null){
    const start=window?.start??now,end=window?.end??now+days*D,width=window?.width??days*240,bin=48,maxLanes=3;
    const x=at=>Math.max(0,Math.min(width,(at-start)/(end-start)*width));
    const valid=at=>Number.isFinite(at)&&Math.abs(at)<=8640000000000000;
    const redundant=new Set(["api-drug","api-booster","api-medical","war-clear","war-status"]);
    const rows=list.filter(e=>e&&!redundant.has(e.id)&&Object.hasOwn(kinds,e.kind)&&typeof e.title==="string"&&valid(e.start)&&valid(e.end)&&e.end>=e.start).map(e=>({...e}));
    if(war&&valid(war.cutoff)&&valid(war.start)&&war.cutoff<war.start&&war.start>start&&war.cutoff<end)
      rows.push({id:"timeline-war-prep",kind:"war",title:war.stale?"Last known war preparation":"War preparation",start:war.cutoff,end:war.start,blocking:true,stale:!!war.stale,source:war.stale?"Last known schedule":"Calculated training reservation",detail:"Training cutoff to ranked war start; not a confirmed dose schedule"});
    if(war&&valid(war.start)){
      const row=rows.find(e=>e.id==="war-start");
      if(row){row.blocking=true;row.stale=!!war.stale;
        if(!(valid(war.end)&&war.end>war.start)){
          row.originalStart=war.start;row.start=row.end=Math.max(now,war.start);
          row.detail=[row.detail,"War end not supplied"].filter(Boolean).join(" · ");
          if(war.start<=now)row.title=war.stale?"Last known ranked war · end unknown":"Ranked war active · end unknown";
        }
      }
    }
    for(const e of rows)if(e.kind==="racing"&&e.detail==="End not supplied"){e.originalStart=e.start;e.start=e.end=Math.max(now,e.start);}
    rows.push(...timelineDrugCooldowns(rows,now,liveDrugSeconds));
    const visible=rows.filter(e=>valid(e.start)&&valid(e.end)&&e.start<end&&e.end>=start&&!(e.end===start&&e.start<start));
    const spans=[],pins=[],lanes=Array.from({length:maxLanes},()=>[]);
    for(const e of visible.slice().sort((a,b)=>Number(b.blocking===true)-Number(a.blocking===true)||Number(b.cooldown===true)-Number(a.cooldown===true)||a.start-b.start||b.end-a.end||String(a.id).localeCompare(String(b.id)))){
      const left=x(e.start),right=x(e.end),range=e.end>e.start;
      const minWidth=e.cooldown?0:30;
      let lane=range&&right-left>=minWidth?lanes.findIndex(items=>items.every(i=>right+2<=i.left||left>=i.right+2)):-1;
      // Cooldowns remain intervals even at sub-label width. Reserve an extra
      // band for overlapping cooldowns rather than creating a second flag.
      if(e.cooldown&&range&&lane<0){if(lanes.length===maxLanes)lanes.push([]);lane=maxLanes;}
      if(lane>=0){const item={event:e,left,right,lane,clippedStart:e.start<start,clippedEnd:e.end>end};spans.push(item);lanes[lane].push(item);}
      else pins.push({event:e,x:left,range,overflow:range&&right-left>=minWidth});
    }
    // Nearby marker clusters retain separate exact anchors and full event detail.
    const groups=new Map();
    for(const p of pins.sort((a,b)=>a.x-b.x||String(a.event.id).localeCompare(String(b.event.id)))){
      const i=Math.min(Math.ceil(width/bin)-1,Math.floor(p.x/bin));
      if(!groups.has(i))groups.set(i,[]);groups.get(i).push(p);
    }
    // The post, not the label center, is the timestamp. Cluster flags use the
    // first (left post) or last (right post) event anchor; all times remain listed.
    const geometry=(a,w)=>{
      const first=a.items[0].x,last=a.items.at(-1).x;
      const post=first+w<=width?"left":"right",x=post==="left"?first:last;
      return {post,x,labelWidth:w,left:post==="left"?x:x-w,right:post==="left"?x+w:x};
    };
    const annotations=[...groups].map(([i,items])=>({items,side:i%2?"bottom":"top",label:false,...geometry({items},24)}));
    // Reserve all compact flags before growing labels. This preserves exact posts
    // and prevents labels on either edge from hiding a neighboring marker.
    for(const a of annotations){
      const g=geometry(a,112);
      if(g.left<0||g.right>width||annotations.some(b=>b!==a&&b.side===a.side&&g.left<b.right+4&&g.right>b.left-4))continue;
      Object.assign(a,g,{label:true});
    }
    return {now,start,end,width,spans,annotations,laneCount:Math.max(1,...spans.map(i=>i.lane+1)),count:visible.length};
  }
  function timelineDetail(e){
    const timing=e.originalStart!=null?"Start "+time(e.originalStart)+" · end unknown":e.end>e.start?time(e.start)+" → "+time(e.end):time(e.start);
    return '<div class="activity-timeline-detail-row activity-'+e.kind+'"><strong>'+esc(timelineIcons[e.kind]+" "+e.title)+'</strong><span>'+esc(timing)+'</span><small>'+esc(kinds[e.kind]+" · "+timelineStatus(e)+" · "+(e.source??"Not supplied"))+'</small>'+(e.detail?'<small>'+esc(e.detail)+'</small>':"")+'</div>';
  }
  function renderTimeline(list,now,days=7,war=null,liveDrugSeconds=null,showAgenda=true,window=null){
    const layout=timelineLayout(list,now,days,war,liveDrugSeconds,window),{width,start,end}=layout,pct=v=>(v/width*100).toFixed(5)+"%";
    const ticks=[],step=(window?(window.hours===12?2:3):6)*H;
    const position=at=>Math.max(0,Math.min(100,(at-start)/(end-start)*100));
    const nowX=position(window?.at??now);
    for(let at=Math.ceil(start/step)*step;at<end;at+=step){
      const major=at%D===0;
      ticks.push('<span class="activity-time-tick'+(major?' is-day':'')+'" style="--x:'+pct((at-start)/(end-start)*width)+'" aria-hidden="true"><span>'+(major?'<b>'+esc(dateLabel(at).slice(5))+'</b>':"")+esc(shortTime(at))+'</span></span>');
    }
    let seq=0;const templates=[];
    const button=(events,body,cls,style)=>{
      const id=String(seq++),e=events[0],label=events.length===1?e.title+" · "+timelineStatus(e)+" · "+time(e.originalStart??e.start)+(e.end>e.start?" to "+time(e.end):"")+(e.originalStart!=null?" · end unknown":""):events.length+" nearby events; activate to review each time";
      templates.push('<template data-activity-timeline-content="'+id+'">'+events.map(timelineDetail).join("")+'</template>');
      const eventKey=JSON.stringify(events.map(x=>[x.id,x.start,x.end]).sort((a,b)=>String(a[0]).localeCompare(String(b[0]))||a[1]-b[1]||a[2]-b[2]));
      return '<button type="button" class="'+cls+'" style="'+style+'" data-activity-timeline-item="'+id+'" data-activity-event-key="'+esc(eventKey)+'" aria-haspopup="dialog" aria-pressed="false" aria-label="'+esc(label)+'">'+body+'</button>';
    };
    const spans=layout.spans.slice().sort((a,b)=>a.event.start-b.event.start||a.lane-b.lane).map(i=>{
      const e=i.event,cls="activity-time-span activity-"+e.kind+(e.blocking?" is-blocking":" is-advisory")+(e.cooldown?" is-cooldown":"")+(e.stale||e.recoveryReview?" is-review":"")+(i.clippedStart?" continues-left":"")+(i.clippedEnd?" continues-right":"");
      return button([e],'<span aria-hidden="true">'+timelineIcons[e.kind]+'</span><span class="activity-time-span-title">'+esc(e.cooldown?"Drug CD":e.title)+'</span>',cls,"--x:"+pct(i.left)+";--w:"+pct(i.right-i.left)+";--lane:"+i.lane);
    }).join("");
    const markers=layout.annotations.map(a=>{
      const events=a.items.map(i=>i.event),e=events[0],cluster=events.length>1,label=cluster?events.length+" events":e.title;
      const cls="activity-time-pin activity-"+(cluster?"event":e.kind)+" is-"+a.side+" post-"+a.post+(a.label?" has-label":"")+(cluster?" is-cluster":"")+(a.items.some(i=>i.range)?" is-range-flag":"")+(events.some(x=>x.recoveryReview||x.stale)?" is-review":"")+(events.some(x=>x.blocking===true)?" is-reserved":"");
      const anchors=cluster?a.items.filter(i=>i.x!==a.x).map(i=>'<i class="activity-pin-anchor is-'+a.side+' activity-'+i.event.kind+'" style="--x:'+pct(i.x)+'" aria-hidden="true"></i>').join(""):"";
      const body='<span class="activity-time-pin-icon" aria-hidden="true">'+(cluster?String(events.length):a.items[0].range?"↔":timelineIcons[e.kind])+'</span>'+(a.label?'<span class="activity-time-pin-label">'+esc(label)+'</span>':"");
      return anchors+button(events,body,cls,"--x:"+pct(a.x)+";--flag-width:"+a.labelWidth+"px");
    }).join("");
    return '<div class="activity-unified-timeline" data-activity-timeline>'+
      '<div class="activity-timeline-scroll" tabindex="0" role="region" aria-label="Scrollable '+(window?window.hours+' hour':days+' day')+' activity timeline"><div class="activity-time-canvas" style="--canvas-width:'+width+'px;--lanes:'+layout.laneCount+'"><div class="activity-time-ruler">'+ticks.join("")+'</div><div class="activity-time-track"><div class="activity-time-grid" aria-hidden="true">'+ticks.join("")+'</div><div class="activity-time-now'+(nowX>90?' is-near-end':'')+'" style="--now-x:'+nowX+'%" aria-hidden="true"><span>NOW</span></div><div class="activity-time-spans">'+spans+'</div>'+markers+'</div></div></div>'+
      (!layout.count?'<small class="activity-timeline-empty">No scheduled activities in this window.</small>':"")+
      '<div class="activity-timeline-tooltip activity-event-popup" data-activity-timeline-popup role="dialog" aria-label="Activity details" hidden></div>'+templates.join("")+'</div>'+
      (showAgenda?'<details class="activity-timeline-agenda" data-collapse-key="calendar-agenda"><summary>Agenda · all scheduled activities</summary>'+renderAgenda(list.filter(e=>e.start<end&&(e.end>e.start?e.end>start:e.start>=start)))+'</details>':"");
  }
  // Display preferences are account-scoped; only the two schedule snapshots
  // remain in memory. Account changes invalidate every cached view.
  let modeOwner=null,selectedTimelineHours=timelineDefaults.hours,timelineScroll=timelineDefaults.scroll,lastModeTick=null;
  const timelineSnapshots=new Map();
  function ensureTimelineOwner(){
    const id=owner();
    if(id!==modeOwner){modeOwner=id;loadTimelineControls();timelineSnapshots.clear();lastModeTick=null;}
  }
  function loadTimelineControls(){
    const saved=timelineControlSettings();selectedTimelineHours=saved.hours;timelineScroll=saved.scroll;
  }
  const modeButtons=()=>'<div class="activity-timeline-controls"><div class="activity-timeline-modes" role="group" aria-label="Timeline duration">'+timelineHours.map(hours=>'<button type="button" data-activity-timeline-hours="'+hours+'" aria-pressed="'+(hours===selectedTimelineHours)+'">'+hours+'h</button>').join("")+'</div><button type="button" class="activity-scroll-toggle" data-activity-timeline-scroll aria-pressed="'+timelineScroll+'" title="Scroll on: NOW at left edge. Scroll off: fixed TCT window."><svg viewBox="0 0 20 16" width="16" height="13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 3v10M17 8H5m4-4L5 8l4 4"/></svg>Scroll</button></div>';
  function modeContent(snapshot,window){
    return renderTimeline(snapshot.list,snapshot.now,window.days,snapshot.war,snapshot.liveDrugSeconds,snapshot.showAgenda,window);
  }
  function renderModeTimeline(list,now,war=null,liveDrugSeconds=null,scope="home",clock=Date.now(),header=null){
    ensureTimelineOwner();
    loadTimelineControls(); // Re-read on render, including after account recovery.
    if(!["home","calendar"].includes(scope))scope="home";
    const window=timelineWindow(clock,selectedTimelineHours,timelineScroll);
    const snapshot={list,now,war,liveDrugSeconds,showAgenda:scope==="calendar",window};
    timelineSnapshots.set(scope,snapshot);
    const body='<div data-activity-mode-content>'+modeContent(snapshot,window)+'</div>';
    if(scope==="home"&&header)return '<details class="rec-tile home-activity-timeline activity-mode-timeline" data-rec-group="timeline" data-activity-mode-timeline="home" '+(header.open?"open":"")+'><summary class="rec-tile-heading activity-mode-titlebar"><span class="activity-mode-title">Timeline</span>'+modeButtons()+'<span class="rec-header-actions">'+header.actions+'</span></summary><div class="rec-tile-body">'+body+'</div></details>';
    return '<div class="activity-mode-timeline" data-activity-mode-timeline="'+scope+'"><div class="activity-mode-titlebar"><span class="activity-mode-title">Timeline</span>'+modeButtons()+'<span></span></div>'+body+'</div>';
  }
  function redrawMode(root,snapshot,window,resetScroll=false){
    const content=root.querySelector("[data-activity-mode-content]");if(!content)return;
    const oldScroll=content.querySelector(".activity-timeline-scroll"),scroll=oldScroll?.scrollLeft??0;
    const open=content.querySelector(".activity-timeline-agenda")?.open;
    const active=document.activeElement,focusInside=content.contains(active);
    const focusKey=focusInside?active?.dataset?.activityEventKey:null;
    const selectedKey=content.querySelector('[data-activity-event-key][aria-pressed="true"]')?.dataset.activityEventKey;
    content.innerHTML=modeContent(snapshot,window);
    const nextScroll=content.querySelector(".activity-timeline-scroll");
    if(nextScroll)nextScroll.scrollLeft=resetScroll||window.scroll?0:scroll;
    const agenda=content.querySelector(".activity-timeline-agenda");if(agenda&&open)agenda.open=true;
    const controls=[...content.querySelectorAll("[data-activity-event-key]")];
    const selected=selectedKey&&controls.find(b=>b.dataset.activityEventKey===selectedKey);
    if(selected&&!resetScroll)showEventPopup(selected);
    if(focusInside){
      const focused=focusKey&&controls.find(b=>b.dataset.activityEventKey===focusKey);
      (focused??nextScroll)?.focus({preventScroll:true});
    }
    snapshot.window=window;
    for(const b of root.querySelectorAll("[data-activity-timeline-hours]"))b.setAttribute("aria-pressed",String(Number(b.dataset.activityTimelineHours)===window.hours));
    for(const b of root.querySelectorAll("[data-activity-timeline-scroll]"))b.setAttribute("aria-pressed",String(window.scroll));
  }
  // Existing local UI tick: no API, planner or recurring storage writes.
  function tickTimeline(at=Date.now()){
    ensureTimelineOwner();
    if(typeof document==="undefined"||document.visibilityState==="hidden")return;
    const minute=Math.floor(at/60000);
    if(minute===lastModeTick)return;
    lastModeTick=minute;
    for(const root of document.querySelectorAll("[data-activity-mode-timeline]")){
      const snapshot=timelineSnapshots.get(root.dataset.activityModeTimeline);
      if(!snapshot||root.matches("details:not([open])"))continue;
      const window=timelineWindow(at,selectedTimelineHours,timelineScroll),previous=snapshot.window;
      const changed=window.hours!==previous.hours||window.scroll!==previous.scroll;
      if(changed||window.start!==previous.start){
        redrawMode(root,snapshot,window,changed||!window.scroll);continue;
      }
      // Calendar-day modes keep their geometry; only NOW moves.
      const marker=root.querySelector(".activity-time-now");
      if(marker){
        const x=Math.max(0,Math.min(100,(window.at-window.start)/(window.end-window.start)*100));
        marker.style.setProperty("--now-x",x+"%");marker.classList.toggle("is-near-end",x>90);
      }
      snapshot.window=window;
    }
  }
  function chooseTimelineControl(button){
    ensureTimelineOwner();
    const current=timelineControlSettings(),next={...current};
    if(button.hasAttribute("data-activity-timeline-scroll"))next.scroll=!current.scroll;
    else{
      const hours=Number(button.dataset.activityTimelineHours);
      if(!timelineHours.includes(hours))return;
      next.hours=hours;
    }
    const controls=button.closest(".activity-timeline-controls");
    controls?.querySelector("[data-timeline-save-error]")?.remove();
    if(!saveTimelineControls(next)){
      const message=document.createElement("small");message.dataset.timelineSaveError="";message.setAttribute("role","status");message.textContent="Could not save timeline settings.";
      controls?.append(message);return;
    }
    selectedTimelineHours=next.hours;timelineScroll=next.scroll;
    for(const root of document.querySelectorAll("[data-activity-mode-timeline]")){
      const snapshot=timelineSnapshots.get(root.dataset.activityModeTimeline);
      if(snapshot)redrawMode(root,snapshot,timelineWindow(Date.now(),selectedTimelineHours,timelineScroll),true);
    }
  }
  function popupRoot(button){return button?.closest("[data-activity-timeline]");}
  function populateEvent(button,node){
    const template=popupRoot(button)?.querySelector('template[data-activity-timeline-content="'+button.dataset.activityTimelineItem+'"]');
    if(template)node.replaceChildren(template.content.cloneNode(true));
  }
  function positionPopup(button,node){
    const rect=button.getBoundingClientRect(),box=node.getBoundingClientRect(),vw=document.documentElement.clientWidth,vh=document.documentElement.clientHeight;
    node.style.left=Math.max(8,Math.min(vw-box.width-8,rect.left+rect.width/2-box.width/2))+"px";
    const y=rect.bottom+8+box.height<=vh?rect.bottom+8:rect.top-box.height-8;
    node.style.top=Math.max(8,Math.min(vh-box.height-8,y))+"px";
  }
  function closeEventPopups(view,restoreFocus=false){
    for(const popup of view.querySelectorAll("[data-activity-timeline-popup]:not([hidden])")){
      popup.hidden=true;const button=popupRoot(popup)?.querySelector('[data-activity-event-key][aria-pressed="true"]');
      if(button){button.setAttribute("aria-pressed","false");if(restoreFocus)button.focus({preventScroll:true});}
    }
  }
  function showEventPopup(button){
    const popup=popupRoot(button)?.querySelector("[data-activity-timeline-popup]");if(!popup)return;
    populateEvent(button,popup);popup.hidden=false;button.setAttribute("aria-pressed","true");positionPopup(button,popup);
  }
  function timelineInteraction(view){
    const item=e=>e.target?.closest?.("[data-activity-timeline-item]");
    const get=(button,name)=>popupRoot(button)?.querySelector("[data-activity-timeline-"+name+"]");
    const hide=()=>{for(const t of view.querySelectorAll("[data-activity-timeline-tooltip]"))t.hidden=true;};
    function show(button){const tooltip=get(button,"tooltip");if(!tooltip)return;populateEvent(button,tooltip);tooltip.hidden=false;positionPopup(button,tooltip);}
    view.addEventListener("pointerover",e=>{const b=item(e);if(b&&e.pointerType!=="touch"&&!b.contains(e.relatedTarget))show(b);});
    view.addEventListener("pointerout",e=>{const b=item(e);if(b&&!b.contains(e.relatedTarget))hide();});
    view.addEventListener("focusin",e=>{const b=item(e);if(b)show(b);});
    view.addEventListener("focusout",e=>{if(item(e))hide();});
    view.addEventListener("scroll",e=>{hide();if(!e.target?.closest?.("[data-activity-timeline-popup]"))closeEventPopups(view);},true);
    document.addEventListener("pointerdown",e=>{if(!e.target?.closest?.("[data-activity-timeline-popup],[data-activity-event-key]"))closeEventPopups(view);});
    document.addEventListener("keydown",e=>{if(e.key==="Escape"){hide();closeEventPopups(view,true);}});
    view.addEventListener("toggle",e=>{
      if(e.target.matches?.("details[data-activity-mode-timeline]")){
        if(!e.target.open)closeEventPopups(e.target);
        else {const snapshot=timelineSnapshots.get(e.target.dataset.activityModeTimeline);if(snapshot)redrawMode(e.target,snapshot,timelineWindow(Date.now(),selectedTimelineHours,timelineScroll),false);}
      }
    },true);
    view.addEventListener("click",e=>{
      const control=e.target?.closest?.("[data-activity-timeline-hours],[data-activity-timeline-scroll]");
      if(control){e.preventDefault();closeEventPopups(view);chooseTimelineControl(control);return;}
      const b=item(e);if(!b)return;
      if(get(b,"popup")){const wasOpen=b.getAttribute("aria-pressed")==="true";closeEventPopups(view);if(!wasOpen)showEventPopup(b);return;}
      const inspector=get(b,"inspector");if(!inspector)return;
      for(const other of popupRoot(b).querySelectorAll("[data-activity-timeline-item]"))other.setAttribute("aria-pressed",String(other===b));
      populateEvent(b,inspector);hide();
    });
  }
  // Only action starts within the UTC day contribute to planned item use.
  function dailyItemValues(list,at){
    const groups=new Map(),seen=new Set();
    for(const e of list){
      if(!e||!Number.isFinite(e.start)||e.start<at||e.start>=at+D||!Array.isArray(e.items)||seen.has(e.id))continue;
      seen.add(e.id);
      for(const row of e.items){
        if(!row||typeof row.name!=="string"||!row.name.trim()||!Number.isFinite(row.quantity)||row.quantity<=0)continue;
        const price=Number.isFinite(row.price)&&row.price>=0?row.price:null;
        const item=groups.get(row.name)??{name:row.name,quantity:0,known:0,unknownQuantity:0};
        const value=price===null?null:price*row.quantity;
        item.quantity+=row.quantity;
        if(value===null||!Number.isFinite(value))item.unknownQuantity+=row.quantity;
        else item.known+=value;
        groups.set(row.name,item);
      }
    }
    const items=[...groups.values()].sort((a,b)=>a.name.localeCompare(b.name));
    const known=items.reduce((n,i)=>n+i.known,0),complete=items.every(i=>i.unknownQuantity===0);
    return {items,known,total:complete?known:null};
  }
  const itemMoney=n=>"$"+Math.round(n).toLocaleString("en-US");
  const packageIcon='<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 7l9-4 9 4v10l-9 4-9-4zM3 7l9 4 9-4M12 11v10M7.5 5l9 4"/></svg>';
  function dayItemDetail(summary,at){
    const rows=summary.items.map(i=>'<div class="activity-day-item"><span>'+esc(i.name)+' × '+esc(i.quantity.toLocaleString("en-US"))+'</span><strong>'+esc(i.unknownQuantity?i.known?itemMoney(i.known)+" + unknown":"Unknown":itemMoney(i.known))+'</strong></div>').join("");
    return '<div class="activity-day-value"><strong>'+esc(dateLabel(at))+' · Planned item use</strong>'+(rows||'<small>No item use scheduled.</small>')+'<div class="activity-day-item activity-day-total"><strong>Daily total value</strong><strong>'+esc(summary.total===null?(summary.known?itemMoney(summary.known)+" + unknown":"Unknown"):itemMoney(summary.total))+'</strong></div><small>Projected replacement value, including owned supplies; not actual spending or confirmed use.</small></div>';
  }
  function renderGrid(list,now,days){
    const start=Math.floor(now/D)*D,week=days===7,templates=[];
    const tiles=Array.from({length:days},(_,i)=>{
      const at=start+i*D,id="day-"+i,summary=week?dailyItemValues(list,at):null;
      if(week)templates.push('<template data-activity-timeline-content="'+id+'">'+dayItemDetail(summary,at)+'</template>');
      const control=week?'<button type="button" class="activity-day-package" data-activity-timeline-item="'+id+'" aria-pressed="false" aria-label="'+esc(dateLabel(at)+" planned item value: "+(summary.total===null?"incomplete":itemMoney(summary.total)))+'">'+packageIcon+'</button>':"";
      const entries=list.filter(e=>e.start<at+D&&(e.end>e.start?e.end>at:e.start>=at)).slice(0,8);
      return '<section><div class="activity-day-heading"><strong>'+dateLabel(at).slice(5)+'</strong>'+control+'</div>'+entries.map(e=>'<small class="activity-'+esc(e.kind)+'">'+esc(shortTime(Math.max(e.start,at))+" "+e.title)+'</small>').join("")+'</section>';
    }).join("");
    const grid='<div class="activity-grid">'+tiles+'</div>';
    return week?'<div class="activity-week" data-activity-timeline>'+grid+'<div class="activity-timeline-inspector activity-week-inspector" data-activity-timeline-inspector aria-live="polite"><small>Hover or select a package icon for the day’s projected item value.</small></div><div class="activity-timeline-tooltip" data-activity-timeline-tooltip hidden aria-hidden="true"></div>'+templates.join("")+'</div>':grid;
  }
  function render(list,{full=false,homeTile=false,now=Date.now(),view=settings().view,war=null,liveDrugSeconds=null,timelineScope=null}={}){
    const modes=full?["agenda","timeline","week","month"]:homeTile?["agenda","week"]:["agenda","timeline","week"];
    if(!modes.includes(view))view="agenda";
    const visible=list.filter(e=>e.start<now+(view==="month"?30:7)*D&&e.end>=now);
    return '<div class="activity-calendar"><div class="activity-tabs">'+modes.map(m=>'<button type="button" data-activity-view="'+m+'" aria-pressed="'+(view===m)+'">'+m[0].toUpperCase()+m.slice(1)+'</button>').join("")+'</div>'+
      (view==="timeline"?(timelineScope?renderModeTimeline(list,now,war,liveDrugSeconds,timelineScope):renderTimeline(list,now,7,war,liveDrugSeconds)):view==="week"?renderGrid(visible,now,7):!visible.length?'<p class="fine-print">No scheduled activities in this window.</p>':view==="agenda"?renderAgenda(visible):renderGrid(visible,now,30))+
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
    if(view.dataset.activityBound==="1")return;view.dataset.activityBound="1";timelineInteraction(view);
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
  return {settings,events,saveEvent,removeEvent,warWindow,warPreparation,addiction,addictionSnapshot,budget,rehabEstimate,rehabDuration,limits,conflicts,rehabWindow,rehabSnapshot,reconcileRehab,spendLedger,recordSpend,weeklySpend,activityFresh,externalEvents,warAttackSummary,schedule,timelineControlSettings,saveTimelineControls,timelineWindow,timelineLayout,renderTimeline,renderModeTimeline,tickTimeline,dailyItemValues,render,settingsDialog,manualForm,expenseForm,wire,time,kinds};
})();
