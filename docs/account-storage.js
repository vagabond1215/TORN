"use strict";
/* Account recovery schema. Never enumerate arbitrary keys into a backup.
 * Registry IDs are logical sections, not caller-supplied storage paths.
 * Version 1 intentionally restores into empty supported account state only. */
const tornAccountStorage=(()=>{
  const prefix="torn-city-guide:", maxRecords=1500,maxValue=500000,maxBytes=2000000;
  const own=(o,k)=>Object.hasOwn(o,k);
  const obj=v=>v!==null&&typeof v==="object"&&!Array.isArray(v);
  const shape=(v,keys)=>obj(v)&&Object.keys(v).every(k=>keys.includes(k));
  const str=(v,n=200)=>typeof v==="string"&&v.length<=n;
  const num=(v,min=0,max=Number.MAX_SAFE_INTEGER)=>typeof v==="number"&&Number.isFinite(v)&&v>=min&&v<=max;
  const int=(v,min=0,max=Number.MAX_SAFE_INTEGER)=>num(v,min,max)&&Number.isInteger(v);
  const bool=v=>typeof v==="boolean";
  const opt=(v,fn)=>v===undefined||fn(v);
  const list=(v,fn,n=500)=>Array.isArray(v)&&v.length<=n&&v.every(fn);
  const one=(v,values)=>values.includes(v);
  const owner=v=>{const s=String(v??"");if(!/^[1-9][0-9]{0,14}$/.test(s)||!Number.isSafeInteger(Number(s)))throw Error("Verified player ID required");return s;};
  const safeKey=v=>str(v,160)&&v.length>0&&!["__proto__","constructor","prototype"].includes(v);
  const ids=["natural","maxenergy","mini","low","jump","maxhappy","custom"];
  const actions=["externalHappy","xanax","ecstasy","candy","dvd","train","refill","wait"];
  const types=["restock","growth","calendar","consume","crime","education","money"];
  const risks=["low","medium","high"];
  const json=fn=>raw=>{try{return fn(JSON.parse(raw));}catch{return false;}};
  const simple=values=>raw=>values.includes(raw);
  const setList=values=>json(v=>list(v,x=>one(x,values),100)&&new Set(v).size===v.length);
  const action=v=>shape(v,["type","qty","minutes","when","max","candyHappy","untilDrug"])&&one(v.type,actions)&&int(v.qty,0,10000)&&num(v.minutes,0,10080)&&opt(v.when,x=>one(x,["full","drug"]))&&opt(v.max,bool)&&opt(v.candyHappy,x=>x==="any"||num(x,1,99999))&&opt(v.untilDrug,bool);
  const plan=v=>shape(v,["energy","time","actions"])&&one(v.energy,["zero","full","current"])&&int(v.time,0,36000000)&&opt(v.actions,x=>list(x,action,200));
  const plans=v=>shape(v,["selected","expanded","plans","chartMode","chartCycles","continuousDays","cycleOverrides","showOptimal","showOptimalBudget","showManual","showCycleBoundaries","excludedPlans"])&&
    opt(v.selected,x=>list(x,y=>one(y,ids),7))&&opt(v.expanded,x=>list(x,y=>one(y,[...ids,"optimal","optimal-budget"]),9))&&opt(v.plans,x=>shape(x,ids)&&Object.values(x).every(plan))&&opt(v.chartMode,x=>one(x,["cycles","continuous"]))&&opt(v.chartCycles,x=>int(x,1,28))&&opt(v.continuousDays,x=>int(x,1,28))&&opt(v.cycleOverrides,x=>list(x,y=>one(y,["",...ids]),28))&&["showOptimal","showOptimalBudget","showManual","showCycleBoundaries"].every(k=>opt(v[k],bool))&&opt(v.excludedPlans,x=>shape(x,["optimal","budget"])&&Object.values(x).every(y=>list(y,z=>one(z,ids),7)));
  const eventsKinds=["training","rehab","travel","war","chain","oc","racing","education","event","personal","health","collection"];
  const date=v=>int(v,0,8640000000000000);
  const nullableMoney=v=>v===null||num(v);
  const observedDate=v=>date(v)&&v<=Date.now()+1000;
  const rehabBaseline=v=>v===null||shape(v,["count","cost","at"])&&int(v.count)&&nullableMoney(v.cost)&&observedDate(v.at);
  const event=e=>{
    if(!shape(e,["id","kind","title","start","end","blocking","source","rehabBaseline","completedAt","rehabCost","recoveryReview"])||!safeKey(e.id)||!one(e.kind,eventsKinds)||!str(e.title,100)||!e.title.trim()||!date(e.start)||!int(e.end,e.start+1,8640000000000000)||!bool(e.blocking)||e.source!=="manual")return false;
    if(e.kind!=="rehab")return ["rehabBaseline","completedAt","rehabCost","recoveryReview"].every(k=>!own(e,k));
    if(!opt(e.rehabBaseline,rehabBaseline)||e.rehabBaseline&&e.rehabBaseline.at>e.start+1000)return false;
    if(own(e,"completedAt"))return observedDate(e.completedAt)&&e.completedAt>=e.start&&e.end===Math.max(e.start+1,e.completedAt)&&e.blocking===false&&e.rehabBaseline!=null&&own(e,"rehabCost")&&nullableMoney(e.rehabCost)&&!own(e,"recoveryReview");
    return !own(e,"rehabCost")&&(!own(e,"recoveryReview")||e.recoveryReview===true&&e.rehabBaseline!=null);
  };
  const events=v=>list(v,event,300)&&new Set(v.map(e=>e.id)).size===v.length;
  function restoredValue(row){
    if(row.section!=="calendar-events")return row.value;
    const values=JSON.parse(row.value);
    // Old counter snapshots cannot identify actions during disconnected time.
    // Preserve the reservation and evidence, but require manual review.
    let held=false;
    for(const e of values)if(e.kind==="rehab"&&e.rehabBaseline&&!own(e,"completedAt")){e.recoveryReview=true;held=true;}
    return held?JSON.stringify(values):row.value;
  }
  // Preserve the current ledger's exact semantics. Training-spend entries are
  // legacy estimated cycle deductions, NOT verified purchase transactions.
  const trainingSpend=v=>list(v,e=>shape(e,["started","at","cost"])&&observedDate(e.started)&&observedDate(e.at)&&e.at>=e.started&&num(e.cost),2000)&&new Set(v.map(e=>e.started)).size===v.length;
  const activitySpend=v=>list(v,e=>shape(e,["id","kind","at","cost","source"])&&safeKey(e.id)&&one(e.kind,["war","rehab"])&&observedDate(e.at)&&num(e.cost)&&((e.source==="Manual confirmation"&&e.id.startsWith("manual-"))||(e.source==="API counter delta"&&e.kind==="rehab"&&e.id.startsWith("rehab-"))),500)&&new Set(v.map(e=>e.id)).size===v.length;
  const fields=["preferred","recommended","restrict","prewar","travel","rehabMinutes","rehabSessions","sharedBudget","warReserve","rehabReserve","view"];
  const settings=v=>shape(v,fields)&&["preferred","recommended","restrict","prewar"].every(k=>opt(v[k],x=>num(x,0,9)))&&opt(v.travel,x=>one(x,["standard","airstrip","wlt","business"]))&&opt(v.rehabMinutes,x=>num(x,15,180))&&opt(v.rehabSessions,x=>int(x,1,100))&&opt(v.sharedBudget,bool)&&["warReserve","rehabReserve"].every(k=>opt(v[k],x=>num(x,0,1e12)))&&opt(v.view,x=>one(x,["agenda","timeline","week","month"]));
  const focus=v=>shape(v,["priority","risk","odRisk","jailRisk","weeklyBudget"])&&opt(v.priority,x=>one(x,["growth","networth","company","education","completion","crime","money"]))&&["risk","odRisk","jailRisk"].every(k=>opt(v[k],x=>one(x,risks)))&&opt(v.weeklyBudget,x=>x===null||num(x));
  const restock=v=>shape(v,["items","ocBands","forecastDays"])&&opt(v.items,x=>list(x,r=>shape(r,["key","monitored","minimum"])&&safeKey(r.key)&&bool(r.monitored)&&(r.minimum===null||int(r.minimum)),5000))&&opt(v.ocBands,x=>list(x,y=>int(y,1,10),10))&&opt(v.forecastDays,x=>int(x,1,28));
  const obs=v=>obj(v)&&Object.keys(v).length<=100&&Object.entries(v).every(([k,x])=>/^(Search for Cash|Shoplifting)\|[a-z]+\|(meter|phase|grounds|camera|checkpoint|guard)$/.test(k)&&shape(x,["value","at"])&&int(x.at,0,8640000000000000)&&(int(x.value,0,100)||one(x.value,["off","on","rush","inactive","active","enabled","disabled"])));
  const profile=(id,s)=>prefix+"v1:profile:"+id+":"+s;
  const definitions=[
    ["focus",id=>profile(id,"playstyle:preferences"),json(focus)],
    ["activities",id=>profile(id,"playstyle:selection"),setList(["War","Mug","Bounty","Attack","Trade","Travel","Training","Revive","Jail","Business","Crime","OC","Racing","Money","Gambling","Education","Merits","Missions","Career","Faction","Property","Collect"])],
    ["build",id=>prefix+"build:"+id,json(v=>shape(v,["choice","total"])&&one(v.choice,["","balanced","hank-str","hank-def","hank-spd","hank-dex","pair-off","pair-def","baldr-str","baldr-def","baldr-spd","baldr-dex"])&&num(v.total,0,1e15))],
    ["training-templates",id=>prefix+"plan-view:"+id,json(plans)],
    ["comparison-mode",id=>prefix+"comparison-mode:"+id,simple(["live","theoretical"])],
    ["calendar-settings",id=>prefix+"activity-settings:"+id,json(settings)],
    ["calendar-events",id=>prefix+"activity-events:"+id,json(events)],
    ["training-spend-estimates",id=>prefix+"training-spend:"+id,json(trainingSpend)],
    ["activity-spend",id=>prefix+"activity-spend-ledger:"+id,json(activitySpend)],
    ["training-cycle-history",id=>prefix+"activity-training-history:"+id,json(v=>tornTrainingRecovery.validHistory(v))],
    ["restock",id=>prefix+"restock-settings:"+id,json(restock)],
    ["oc-bands",id=>prefix+"oc-bands:"+id,json(v=>list(v,x=>int(x,1,10),10))],
    ["war-settings",id=>prefix+"energy-war:"+id,json(v=>shape(v,["mode","adjustment","lead","version"])&&one(v.mode,["off","scheduled","faction"])&&int(v.adjustment,-120,120)&&int(v.lead,0,120)&&opt(v.version,x=>int(x,1,2)))],
    ["recommendations",id=>prefix+"rec-types:"+id,setList(types)],
    ["expanded",id=>prefix+"rec-expanded:"+id,setList(types)],
    ["growth-tab",id=>prefix+"growth-tab:"+id,simple(["summary","steps","build","collapsed"])],
    ["manual-war",id=>prefix+"tct:manual-rw:"+id,raw=>/^\d{1,16}$/.test(raw)&&int(Number(raw),0,8640000000000000)],
    ["crime-observations",id=>prefix+"crime-observations:v1:"+id,json(obs)],
    ...["growth-exclude-owned","growth-watch","crime-incomplete-uniques","crime-incomplete","crime-uniques","calendar-introduced"].map(k=>[k,id=>prefix+k+":"+id,simple(["true","false"])])
  ];
  const fixed=new Map(definitions.map(d=>[d[0],d]));
  function descriptor(id,section){
    if(section==="training-session-review")return {key:tornTrainingRecovery.reviewKey(id),valid:json(v=>tornTrainingRecovery.validSession(v))};
    const d=fixed.get(section);if(d)return {key:d[1](id),valid:d[2]};
    const m=/^(task|quickstart|notes):([a-z0-9][a-z0-9-]{0,99})$/.exec(section);
    if(!m)return null;
    return {key:profile(id,section),valid:m[1]==="notes"?raw=>str(raw,100000):simple(["done"])};
  }
  function keys(store,id){
    const out=new Map(definitions.map(d=>[d[0],d[1](id)]));
    const base=profile(id,"");
    for(let i=0;i<store.length;i++){const k=store.key(i);if(k?.startsWith(base)){const section=k.slice(base.length);if(descriptor(id,section))out.set(section,k);}}
    return out;
  }
  function validRecords(records,id){
    if(!Array.isArray(records)||records.length>maxRecords)throw Error("Invalid record count");
    let size=0;const seen=new Set();
    for(const row of records){
      if(!shape(row,["section","value"])||!str(row.section,160)||!str(row.value,maxValue)||seen.has(row.section))throw Error("Invalid or duplicate backup section");
      const d=descriptor(id,row.section);
      if(!d||!d.valid(row.value))throw Error("Unsupported or invalid section: "+row.section);
      size+=row.section.length+row.value.length;if(size>maxBytes)throw Error("Backup exceeds size limit");
      seen.add(row.section);
    }
    return records;
  }
  function snapshot(store,playerId){
    const id=owner(playerId),records=[],omitted=[];
    if(journalPending(store,id))throw Error("Resolve the pending restore journal before export or import");
    for(const [section,k] of keys(store,id)){const value=store.getItem(k);if(value===null)continue;const d=descriptor(id,section);if(str(value,maxValue)&&d.valid(value))records.push({section,value});else omitted.push(section);}
    const live=store.getItem(prefix+"training-session:"+id),stage=store.getItem(tornTrainingRecovery.reviewKey(id));
    if(live!==null||stage!==null){
      try{
        if(live!==null&&stage!==null)throw Error("Conflicting session records");
        const value=live??JSON.stringify(tornTrainingRecovery.parseStage(stage,id).session);
        if(!str(value,maxValue)||!descriptor(id,"training-session-review").valid(value))throw Error("Invalid session");
        records.push({section:"training-session-review",value});
      }catch{omitted.push("training-session-review");}
    }
    records.sort((a,b)=>a.section.localeCompare(b.section));validRecords(records,id);
    return {records,omitted};
  }
  function restoreEmpty(store,playerId,records,assertCurrent=()=>true,{createdAt=Date.now()}={}){
    const id=owner(playerId);validRecords(records,id);
    // Reject a non-empty account, even if its sections are not in this file.
    // No additive merge: missing rows may represent intentional deletions.
    const existing=snapshot(store,id);
    if(existing.records.length||existing.omitted.length)throw Error("Account already has supported local data; merge is not available yet");
    // Also protect excluded durable session/history data from partial restore.
    if(store.getItem(prefix+"training-session:"+id)!==null||store.getItem(tornTrainingRecovery.reviewKey(id))!==null)throw Error("Existing training session or recovery hold; merge is not available yet");
    if(!assertCurrent())throw Error("Account changed before restore");
    const added=[];
    const ordered=[...records].sort((a,b)=>Number(b.section==="training-session-review")-Number(a.section==="training-session-review"));
    try{for(const row of ordered){
      const d=descriptor(id,row.section),isSession=row.section==="training-session-review";
      const value=isSession?tornTrainingRecovery.stageValue(id,JSON.parse(row.value),createdAt):restoredValue(row);
      if(!assertCurrent()||store.getItem(d.key)!==null||store.getItem(prefix+"training-session:"+id)!==null||(!isSession&&!d.valid(value)))throw Error("Account changed or record invalid during restore");
      store.setItem(d.key,value);added.push([d.key,value]);
    }}
    catch(error){let rollbackFailed=false;for(const [k,value] of added.reverse())try{if(store.getItem(k)===value)store.removeItem(k);else rollbackFailed=true;}catch{rollbackFailed=true;}if(rollbackFailed)throw Error("Restore incomplete; rollback failed or a concurrent edit was detected. Keep the backup and inspect local storage.");throw error;}
    return records.length;
  }
  const journalKey=id=>prefix+"restore-journal:v1:"+owner(id);
  function journalPending(store,playerId){
    try{return store.getItem(journalKey(playerId))!==null;}catch{return true;}
  }
  // Journal rows contain validated destination values, not arbitrary keys.
  // A pending journal is local recovery data and never exported.
  function parseJournal(raw,id){
    if(typeof raw!=="string"||raw.length>maxBytes*3+100000)throw Error("Invalid restore journal size");
    const j=JSON.parse(raw);
    if(!shape(j,["version","playerId","createdAt","rows"])||j.version!==1||j.playerId!==id||!observedDate(j.createdAt)||!Array.isArray(j.rows)||!j.rows.length||j.rows.length>maxRecords)throw Error("Invalid restore journal");
    let size=0;const seen=new Set();
    for(const row of j.rows){
      if(!shape(row,["section","value"])||!str(row.section,160)||!str(row.value,maxValue+1000)||seen.has(row.section))throw Error("Invalid journal section");
      const d=descriptor(id,row.section);
      if(!d)throw Error("Unknown journal section");
      if(row.section==="training-session-review")tornTrainingRecovery.parseStage(row.value,id);
      else if(!d.valid(row.value))throw Error("Invalid journal value");
      seen.add(row.section);size+=row.section.length+row.value.length;
      if(size>maxBytes+1000)throw Error("Restore journal exceeds size limit");
    }
    return j;
  }
  function readJournal(store,playerId){
    const id=owner(playerId),raw=store.getItem(journalKey(id));
    if(raw===null)return null;
    const j=parseJournal(raw,id);
    const rows=j.rows.map(row=>{
      const key=descriptor(id,row.section).key,current=store.getItem(key);
      return {section:row.section,state:current===null?"missing":current===row.value?"matched":"conflict"};
    });
    // A local runnable session is never part of the journal.
    if(store.getItem(prefix+"training-session:"+id)!==null)rows.push({section:"local-training-session",state:"conflict"});
    return {raw,createdAt:j.createdAt,rows,complete:rows.every(row=>row.state==="matched"),conflict:rows.some(row=>row.state==="conflict")};
  }
  function assertJournal(store,id,raw,isCurrent){
    if(!isCurrent()||store.getItem(journalKey(id))!==raw)throw Error("Account or restore journal changed");
  }
  function finishJournal(store,playerId,raw,isCurrent){
    const id=owner(playerId);assertJournal(store,id,raw,isCurrent);
    const status=readJournal(store,id);
    if(!status?.complete||status.conflict)throw Error("Restore is incomplete or has conflicting changes");
    assertJournal(store,id,raw,isCurrent);store.removeItem(journalKey(id));
    if(journalPending(store,id))throw Error("Restore journal could not be cleared");
  }
  function rollbackJournal(store,playerId,raw,isCurrent){
    const id=owner(playerId);assertJournal(store,id,raw,isCurrent);
    const status=readJournal(store,id);
    if(!status||status.conflict)throw Error("Conflicting changes; preserve the journal and original backup");
    const j=parseJournal(raw,id);
    for(const row of [...j.rows].reverse()){
      assertJournal(store,id,raw,isCurrent);
      const key=descriptor(id,row.section).key,current=store.getItem(key);
      if(current!==null&&current!==row.value)throw Error("Concurrent change during rollback; journal retained");
      if(current!==null)store.removeItem(key);
    }
    assertJournal(store,id,raw,isCurrent);
    if(readJournal(store,id).rows.some(row=>row.state!=="missing"))throw Error("Rollback incomplete; journal retained");
    store.removeItem(journalKey(id));
    if(journalPending(store,id))throw Error("Restore journal could not be cleared");
  }
  function restoreJournaled(store,playerId,records,isCurrent,{createdAt=Date.now()}={}){
    const id=owner(playerId);validRecords(records,id);
    if(!records.length||journalPending(store,id))throw Error("Resolve the pending restore journal first");
    const existing=snapshot(store,id);
    if(existing.records.length||existing.omitted.length||store.getItem(prefix+"training-session:"+id)!==null)throw Error("Account already has local data; merge is not available yet");
    if(!isCurrent())throw Error("Account changed before restore");
    const ordered=[...records].sort((a,b)=>Number(b.section==="training-session-review")-Number(a.section==="training-session-review"));
    const rows=ordered.map(row=>({section:row.section,value:row.section==="training-session-review"?tornTrainingRecovery.stageValue(id,JSON.parse(row.value),createdAt):restoredValue(row)}));
    const raw=JSON.stringify({version:1,playerId:id,createdAt:Date.now(),rows});
    parseJournal(raw,id);
    if(!isCurrent()||journalPending(store,id))throw Error("Account or journal changed before restore");
    // Write-ahead journal: quota failure here leaves destinations untouched.
    store.setItem(journalKey(id),raw);
    assertJournal(store,id,raw,isCurrent);
    try{
      for(const row of rows){
        assertJournal(store,id,raw,isCurrent);
        const key=descriptor(id,row.section).key;
        if(store.getItem(key)!==null||store.getItem(prefix+"training-session:"+id)!==null)throw Error("Concurrent account write");
        store.setItem(key,row.value);
      }
      finishJournal(store,id,raw,isCurrent);
    }catch(error){throw Error("Restore interrupted; journal retained for review. "+String(error?.message??error));}
    return rows.length;
  }
  // Cooperative cross-tab serialization where Web Locks is available.
  // Older scripts and other ordinary writers do not participate yet.
  async function withRecoveryLock(playerId,locks,fn){
    const id=owner(playerId);
    return locks?.request?locks.request(prefix+"account-recovery:"+id,{mode:"exclusive"},fn):fn();
  }
  return {owner,knownSection:(id,section)=>typeof section==="string"&&section.length<=160&&Boolean(descriptor(owner(id),section)),snapshot,validRecords,restoreEmpty,maxBytes,journalKey,journalPending,readJournal,restoreJournaled,finishJournal,rollbackJournal,withRecoveryLock};
})();
