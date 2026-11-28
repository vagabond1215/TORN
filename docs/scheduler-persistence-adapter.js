"use strict";
/* P1.4d.5 isolated reservation decision and transition builder.
 * No storage writes, requests, implicit approvals or live integration.
 * Context reader supplies normalized own-account observations, not secrets.
 * A candidate is not a commit: future IDB CAS must recheck the exact
 * generation AND bytes, and assertCurrent immediately before writing.
 */
const tornSchedulerPersistence=(()=>{
  const minute=60000,week=7*24*60*minute,section="calendar-events";
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const copy=v=>JSON.parse(JSON.stringify(v)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const integer=v=>Number.isSafeInteger(v)&&v>=0;
  const fresh=(at,now,max)=>integer(at)&&at>0&&at<=now&&now-at<=max;
  const clock=now=>{if(!integer(now)||now<=0)throw Error("Invalid scheduler decision time");return now;};
  function checkEpoch(guard){if(typeof guard!=="function"||guard()!==true)throw Error("Verified account epoch changed");}
  function context(read,id,guard){
    checkEpoch(guard);
    if(typeof read!=="function")throw Error("Current scheduler context required");
    const raw=read();
    if(!exact(raw,["playerId","record","activeTraining","heldTraining","journalPending","profile","travel","war","warSettings","health","rehabSettings","actions","baseline"])||raw.playerId!==id)throw Error("Invalid or foreign scheduler context");
    if(raw.activeTraining!==false||raw.heldTraining!==false||raw.journalPending!==false)throw Error("Training or recovery hold blocks reservation changes");
    const c=copy(raw);
    if(!exact(c.record,["version","playerId","generation","bundle"])||c.record.version!==1||c.record.playerId!==id||!integer(c.record.generation)||c.record.generation<1)throw Error("Verified transactional account review required");
    checkEpoch(guard);return c;
  }
  function policy(c,change,now){
    const b=c.record.bundle;
    if(!b||!Array.isArray(b.records))throw Error("Incomplete account review");
    const value=b.records.find(r=>r.section===section)?.value;
    if(typeof value!=="string")throw Error("Tracked calendar required");
    const rows=JSON.parse(value),old=rows.find(x=>x.id===change.id)??null;
    if(!exact(change,["id","kind","before","after"])||typeof change.id!=="string"||!change.id||!["add","remove"].includes(change.kind)||!same(old,change.before))throw Error("Exact reviewed rehab reservation change required");
    if(change.kind==="add"&&(old!==null||change.after?.id!==change.id)||change.kind==="remove"&&(old===null||change.after!==null))throw Error("Reservation changed; review again");
    const next=change.kind==="add"?[...rows,change.after]:rows.filter(x=>x.id!==change.id),after=JSON.stringify(next);
    const records=b.records.filter(r=>r.section!==section).concat({section,value:after}).sort((a,b)=>a.section.localeCompare(b.section));
    tornAccountStorage.validRecords(records,c.playerId);
    // Reuse the V7 exact-domain validator, not a second baseline or
    // cancellation policy. This also rejects existing spend evidence.
    const removed=tornCalendarJournal.validateRehabPlanning(value,after,{id:change.id,kind:change.kind},b,now);
    if(change.kind==="remove")return {records,removed}; // no travel needed to cancel a future pending reservation
    const e=change.after;
    if(e.start<now||e.end>now+week)throw Error("Reservation outside future planning window");
    const profile=c.profile,travel=c.travel,health=c.health,settings=c.rehabSettings,ws=c.warSettings;
    if(!exact(profile,["at","status","level"])||!fresh(profile.at,now,15*minute)||!["okay","ok"].includes(profile.status)||!integer(profile.level)||profile.level<15)throw Error("Fresh available travel-eligible profile required");
    if(!exact(travel,["at","available"])||!fresh(travel.at,now,15*minute)||travel.available!==true)throw Error("Verified travel availability required");
    if(!exact(health,["at","level"])||!fresh(health.at,now,15*minute)||!["preferred","recommended","restricted"].includes(health.level))throw Error("Fresh rehabilitation recommendation required");
    if(!exact(settings,["travel","rehabMinutes","rehabSessions"])||!["standard","airstrip","wlt","business"].includes(settings.travel)||!integer(settings.rehabMinutes)||settings.rehabMinutes<15||settings.rehabMinutes>180||!integer(settings.rehabSessions)||settings.rehabSessions<1||settings.rehabSessions>100)throw Error("Invalid rehabilitation settings");
    if(e.end-e.start!==tornActivityScheduler.rehabDuration(settings))throw Error("Rehabilitation duration changed; review again");
    if(!exact(ws,["mode","adjustment","lead"])||!["off","scheduled","faction"].includes(ws.mode)||!Number.isInteger(ws.adjustment)||ws.adjustment< -120||ws.adjustment>120||!integer(ws.lead)||ws.lead>120)throw Error("Verified war settings required");
    const wars=[];
    if(ws.mode!=="off"){
      const w=c.war;
      if(!exact(w,["at","known","ranked"])||w.known!==true||!fresh(w.at,now,5*minute))throw Error("Fresh ranked war observation required");
      if(w.ranked!==null){
        const r=w.ranked;
        if(!exact(r,["start","end","mode"])||!integer(r.start)||!r.start||!(r.end===null||integer(r.end)&&r.end>r.start)||!(r.mode===null||typeof r.mode==="string"))throw Error("Invalid ranked war observation");
        if(ws.mode!=="faction"||r.mode)wars.push(r);
      }
      for(const r of rows.filter(r=>r.kind==="war"&&r.end>now))wars.push({start:r.start,end:r.end,mode:"manual"});
    }
    const windows=wars.map(w=>tornActivityScheduler.warWindow(w,ws,now)).filter(Boolean);
    if(windows.some(w=>w.phase!=="upcoming"||e.end>w.cutoff))throw Error("Rehabilitation conflicts with war stacking cutoff");
    if(tornActivityScheduler.limits({manual:rows,now}).blocked)throw Error("Current blocking activity prevents rehabilitation");
    if(rows.some(r=>r.kind==="rehab"&&!Object.hasOwn(r,"completedAt")&&r.end>now))throw Error("Existing pending rehabilitation reservation");
    if(!Array.isArray(c.actions)||c.actions.length>1000||!c.actions.every(integer))throw Error("Verified training forecast required");
    if(c.actions.some(at=>at>=e.start&&at<e.end))throw Error("Rehabilitation overlaps planned training; review a new window");
    if(e.rehabBaseline!==null){
      const v=c.baseline;
      if(!exact(v,["playerId","count","cost","at"])||v.playerId!==c.playerId||!same({count:v.count,cost:v.cost,at:v.at},e.rehabBaseline))throw Error("Verified rehab baseline changed or unavailable");
    }else if(c.baseline!==null)throw Error("Available rehab baseline must be reviewed explicitly");
    return {records,removed};
  }
  // Short-lived immutable review. The caller must review and explicitly
  // approve exact action; never fabricate an approval from a forecast.
  async function prepare(playerId,reviewed,change,approved,read,guard,{now=Date.now,digest,newRevision}={}){
    const id=tornAccountStorage.owner(playerId);
    if(approved!==true)throw Error("Explicit reservation approval required");
    const c=context(read,id,guard),original=copy(reviewed),action=copy(change),at=clock(now());
    if(!same(c,original))throw Error("Scheduler context changed; review again");
    const options={...(digest?{digest}:{}),...(newRevision?{newRevision}:{})};
    const prior=await tornAccountTransactionStore.verify(c.record.bundle,id,options);
    const {records,removed}=policy(c,action,at);
    if(c.record.generation===Number.MAX_SAFE_INTEGER)throw Error("Account generation exhausted");
    const manifest=await tornAccountRevisions.observe(prior,{records,omitted:[],deleted:c.record.bundle.markers},id,options);
    const before={records:c.record.bundle.records,omitted:[],manifest:prior},after={records,omitted:[],manifest};
    for(const e of prior.entries)if(e.section!==section&&!same(e,manifest.entries.find(x=>x.section===e.section)))throw Error("Unrelated revision changed");
    const lineage=await tornCalendarLineage.advance(JSON.parse(c.record.bundle.lineageRaw),before,after,id,removed,options);
    const bundle={records,omitted:[],markers:c.record.bundle.markers,manifestRaw:JSON.stringify(manifest),lineageRaw:JSON.stringify(lineage)};
    await tornAccountTransactionStore.verify(bundle,id,options);
    const assertCurrent=()=>{
      const time=clock(now());if(time<at||time-at>5000)throw Error("Scheduler decision expired; review again");
      const latest=context(read,id,guard);
      if(!same(latest,c))throw Error("Scheduler context changed; review again");
      policy(latest,action,time);checkEpoch(guard);return true;
    };
    assertCurrent();
    return {status:"candidate",before:copy(c.record),after:{version:1,playerId:id,generation:c.record.generation+1,bundle:copy(bundle)},change:copy(action),decisionAt:at,assertCurrent};
  }
  return Object.freeze({prepare});
})();
