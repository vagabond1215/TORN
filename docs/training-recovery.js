"use strict";
/* Typed validation for the V1 training session and interrupted-cycle archive.
 * This module validates evidence, not the safety or accuracy of executing it.
 * Nothing here writes to the runnable training-session key. */
const tornTrainingRecovery=(()=>{
  const prefix="torn-city-guide:", maxSeconds=7*86400+3600, maxRows=2000;
  const own=(o,k)=>Object.hasOwn(o,k);
  const obj=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);
  const shape=(x,keys,required=keys)=>obj(x)&&Object.keys(x).every(k=>keys.includes(k))&&required.every(k=>own(x,k));
  const num=(x,lo=0,hi=Number.MAX_SAFE_INTEGER)=>typeof x==="number"&&Number.isFinite(x)&&x>=lo&&x<=hi;
  const int=(x,lo=0,hi=Number.MAX_SAFE_INTEGER)=>num(x,lo,hi)&&Number.isInteger(x);
  const str=(x,max=200)=>typeof x==="string"&&x.length>0&&x.length<=max;
  const opt=(x,fn)=>x===undefined||fn(x);
  const nullable=(x,fn)=>x===null||fn(x);
  const bool=x=>typeof x==="boolean";
  const date=x=>int(x,0,8640000000000000);
  const observed=(x,now)=>date(x)&&x<=now+1000;
  const seconds=x=>num(x,0,maxSeconds);
  const stat=x=>num(x,0,1e24);
  const amount=x=>num(x,0,Number.MAX_SAFE_INTEGER);
  const templates={natural:"Natural training",maxenergy:"Maximum Energy",mini:"Mini jump",low:"Low-stat jump",jump:"Happy jump",maxhappy:"99k Happy jump",custom:"Custom"};
  const names={strength:"Strength",defense:"Defense",speed:"Speed",dexterity:"Dexterity"};
  const actionTypes=["xanax","ecstasy","candy","dvd","train","refill","externalHappy"],costTypes=actionTypes.filter(x=>x!=="train");
  const costs=x=>shape(x,costTypes)&&Object.values(x).every(n=>int(n,0,1e7));
  const state=x=>shape(x,["energy","happy","drug","booster","stat"])&&num(x.energy,0,1e6)&&num(x.happy,0,1e6)&&num(x.drug,0,30*86400)&&num(x.booster,0,30*86400)&&stat(x.stat);
  const waits=x=>Array.isArray(x)&&x.length<=maxRows&&x.every(w=>shape(w,["reason","duration","end"],["duration","end"])&&opt(w.reason,v=>nullable(v,y=>str(y,200)))&&seconds(w.end)&&num(w.duration,Number.MIN_VALUE,w.end));
  function action(a){
    if(!shape(a,["type","at","end","quantity","energy","before","after","reason","midnightRefill","waitsBefore"],["type","at","end","quantity","energy","before","after","reason"])||!actionTypes.includes(a.type)||!seconds(a.at)||!num(a.end,a.at,maxSeconds)||!int(a.quantity,1,10000)||!state(a.before)||!state(a.after)||!nullable(a.reason,x=>str(x,200))||!opt(a.midnightRefill,x=>x===true&&a.type==="refill")||!opt(a.waitsBefore,waits))return false;
    if(a.waitsBefore?.some(w=>w.end>a.at+1e-6))return false;
    if(a.type==="train")return num(a.energy,Number.MIN_VALUE,1e6)&&Math.abs(a.before.energy-a.after.energy-a.energy)<1e-6&&a.after.stat>=a.before.stat;
    return a.energy===null;
  }
  function rows(a){
    return Array.isArray(a)&&a.length<=maxRows&&a.every((x,i)=>action(x)&&(!i||x.at>=a[i-1].end-1e-6));
  }
  function mapOf(x,count,check,complete=false){
    if(!obj(x)||Object.keys(x).length>count)return false;
    if(complete&&Object.keys(x).length!==count)return false;
    return Object.entries(x).every(([k,v])=>/^(0|[1-9][0-9]*)$/.test(k)&&int(Number(k),0,count-1)&&check(v,Number(k)));
  }
  function prefixValid(completed,recovered,count,started,now){
    if(!mapOf(completed,count,x=>x===null||observed(x,now)&&x>=started,true)||!opt(recovered,x=>mapOf(x,count,v=>v===true)))return false;
    let previous=started;
    for(let i=0;i<count;i++){
      const t=completed[i];if(t===null){if(recovered?.[i]!==true)return false;continue;}
      if(t<previous)return false;previous=t;
    }
    return true;
  }
  const period=x=>shape(x,["days","gain","value","energy","costs"])&&[1,7,28].includes(x.days)&&nullable(x.gain,stat)&&nullable(x.value,amount)&&nullable(x.energy,n=>num(n,0,1e8))&&nullable(x.costs,costs);
  const sequence=x=>Array.isArray(x)&&x.length>0&&x.length<=maxRows&&x.every((r,i)=>shape(r,["id","start","at","gain","logStart","used","costs","reason","optimized","partial"],["id","start","at","gain"])&&own(templates,r.id)&&seconds(r.start)&&num(r.at,r.start,maxSeconds)&&stat(r.gain)&&(!i||r.start>=x[i-1].at-1e-6)&&opt(r.logStart,n=>int(n,0,100000))&&opt(r.used,n=>num(n,0,1e8))&&opt(r.costs,costs)&&opt(r.reason,n=>["window","blocked"].includes(n))&&opt(r.optimized,bool)&&opt(r.partial,n=>n===true&&i===x.length-1));
  const timing=x=>shape(x,["xanaxCD","ecstasyCD","boosterCap","candyCD","dvdCD"])&&Object.values(x).every(n=>num(n,0,30*86400));
  function watch(x,index,now){
    if(!shape(x,["index","sample","issue"],["index","sample"])||x.index!==index||!opt(x.issue,y=>str(y,300)))return false;
    const s=x.sample;
    if(s===null)return true;
    return shape(s,["at","barAt","cdAt","statAt","refillAt","energy","cap","happy","maxHappy","drug","booster","stat","refillUsed"])&&["at","barAt","cdAt","statAt","refillAt"].every(k=>observed(s[k],now))&&s.at===Math.min(s.barAt,s.cdAt)&&num(s.energy,0,1e6)&&num(s.cap,1,1e6)&&num(s.happy,0,1e6)&&num(s.maxHappy,0,1e6)&&num(s.drug,0,30*86400)&&num(s.booster,0,30*86400)&&nullable(s.stat,stat)&&nullable(s.refillUsed,bool);
  }
  function validSession(x,now=Date.now()){
    const required=["version","label","source","stat","statKey","budget","excludeOwned","confirmedSpend","periods","drugRisk","started","index","actions","cycleSpend","notBefore","completed","timing","gym","maxEnergy"];
    const keys=[...required,"sequence","deadline","recovered","lastConfirmed","drugUntil","boosterUntil","refillDay","statCheckpoint","watch"];
    if(!shape(x,keys,required)||x.version!==1||!Object.values(templates).includes(x.label)||!["natural","optimal-budget"].includes(x.source)||!own(names,x.statKey)||names[x.statKey]!==x.stat||!nullable(x.budget,amount)||!bool(x.excludeOwned)||!amount(x.confirmedSpend)||!bool(x.drugRisk)||!observed(x.started,now)||!rows(x.actions)||!x.actions.length||!int(x.index,0,x.actions.length)||!nullable(x.cycleSpend,amount)||!date(x.notBefore)||!timing(x.timing)||!shape(x.gym,["name","energy","estimated"],["name","energy"])||!str(x.gym.name,120)||!int(x.gym.energy,1,1000)||!opt(x.gym.estimated,bool)||!int(x.maxEnergy,1,10000))return false;
    if(!Array.isArray(x.periods)||x.periods.length!==3||!x.periods.every(period)||new Set(x.periods.map(p=>p.days)).size!==3||!opt(x.sequence,sequence)||!opt(x.deadline,v=>nullable(v,date)))return false;
    if(x.sequence&&templates[x.sequence[0].id]!==x.label)return false;
    if(x.source==="natural"&&x.label!==templates.natural)return false;
    if(x.actions.some(a=>a.type==="dvd"&&x.label!==templates.jump||a.type==="externalHappy"&&x.label!==templates.maxhappy)||x.drugRisk!==x.actions.some(a=>["xanax","ecstasy"].includes(a.type)))return false;
    if(!prefixValid(x.completed,x.recovered,x.index,x.started,now))return false;
    if(!opt(x.lastConfirmed,v=>observed(v,now)&&v>=x.started)||!opt(x.drugUntil,date)||!opt(x.boosterUntil,date)||!opt(x.refillDay,v=>int(v,0,Math.floor(now/86400000)))||!opt(x.statCheckpoint,v=>shape(v,["actual","projected"])&&stat(v.actual)&&stat(v.projected))||!opt(x.watch,v=>watch(v,x.index,now)))return false;
    if(Object.values(x.completed).some(t=>t!==null&&(x.lastConfirmed===undefined||t>x.lastConfirmed)))return false;
    return true;
  }
  function validHistory(x,now=Date.now()){
    return Array.isArray(x)&&x.length<=30&&new Set(x.map(e=>e?.started)).size===x.length&&x.every(e=>shape(e,["started","ended","reason","label","confirmed","completed","reservedSpend"])&&observed(e.started,now)&&observed(e.ended,now)&&e.ended>=e.started&&e.reason==="activity deadline"&&Object.values(templates).includes(e.label)&&rows(e.confirmed)&&mapOf(e.completed,e.confirmed.length,t=>t===null||date(t)&&t>=e.started&&t<=e.ended,true)&&nullable(e.reservedSpend,amount));
  }
  // The review namespace cannot be consumed by loadTrainingSession. A
  // verified account guard must be supplied by the caller before staging.
  function reviewKey(playerId){
    const id=String(playerId??"");if(!/^[1-9][0-9]{0,14}$/.test(id)||!Number.isSafeInteger(Number(id)))throw Error("Verified player ID required");
    return prefix+"training-session-review:v1:"+id;
  }
  function prepareReview(playerId,session,now=Date.now()){
    const key=reviewKey(playerId);
    if(!validSession(session,now))throw Error("Invalid saved training session; preserve original for review");
    return {key,value:JSON.stringify(session),summary:{label:session.label,stat:session.stat,started:session.started,confirmed:session.index,total:session.actions.length,estimatedCycleSpend:session.cycleSpend,lastConfirmed:session.lastConfirmed??null}};
  }
  function stageValue(playerId,session,createdAt,now=Date.now()){
    prepareReview(playerId,session,now);
    if(!observed(createdAt,now))throw Error("Invalid backup creation time");
    return JSON.stringify({version:1,playerId:String(playerId),backupCreatedAt:createdAt,restoredAt:now,session});
  }
  function parseStage(raw,playerId,now=Date.now()){
    const v=JSON.parse(raw);
    if(!shape(v,["version","playerId","backupCreatedAt","restoredAt","session"])||v.version!==1||v.playerId!==String(playerId)||!observed(v.backupCreatedAt,now)||!observed(v.restoredAt,now)||v.backupCreatedAt>v.restoredAt+1000||!validSession(v.session,now))throw Error("Invalid recovered training record");
    return v;
  }
  function readStage(store,playerId){
    if(!/^[1-9][0-9]{0,14}$/.test(String(playerId??"")))return null;
    try{const raw=store.getItem(reviewKey(playerId));if(raw===null)return null;try{return {...parseStage(raw,playerId),raw};}catch{return {raw,error:"Recovered training record is invalid. Preserve the backup; do not resume."};}}catch{return {error:"Recovery storage unavailable. Check browser storage before training."};}
  }
  function held(store,playerId){
    if(!/^[1-9][0-9]{0,14}$/.test(String(playerId??"")))return false;
    try{return store.getItem(reviewKey(playerId))!==null;}catch{return true;}
  }
  function discardStage(store,playerId,raw,isCurrent){
    if(typeof raw!=="string"||!isCurrent())throw Error("Account changed before review");
    const key=reviewKey(playerId);
    if(store.getItem(key)!==raw||store.getItem(prefix+"training-session:"+playerId)!==null)throw Error("Recovery record changed or a local session exists; preserve both for review");
    store.removeItem(key);
    if(store.getItem(key)!==null)throw Error("Could not release recovery hold");
  }
  return {validSession,validHistory,prepareReview,reviewKey,stageValue,parseStage,readStage,held,discardStage};
})();
