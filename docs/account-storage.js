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
  const events=v=>list(v,e=>shape(e,["id","kind","title","start","end","blocking","source"])&&safeKey(e.id)&&one(e.kind,eventsKinds)&&str(e.title,100)&&e.title.trim().length>0&&int(e.start,0,8640000000000000)&&int(e.end,e.start+1,8640000000000000)&&bool(e.blocking)&&e.source==="manual",300)&&new Set(v.map(e=>e.id)).size===v.length;
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
    for(const [section,k] of keys(store,id)){const value=store.getItem(k);if(value===null)continue;const d=descriptor(id,section);if(str(value,maxValue)&&d.valid(value))records.push({section,value});else omitted.push(section);}
    records.sort((a,b)=>a.section.localeCompare(b.section));validRecords(records,id);
    return {records,omitted};
  }
  function restoreEmpty(store,playerId,records,assertCurrent=()=>true){
    const id=owner(playerId);validRecords(records,id);
    // Reject a non-empty account, even if its sections are not in this file.
    // No additive merge: missing rows may represent intentional deletions.
    const existing=snapshot(store,id);
    if(existing.records.length||existing.omitted.length)throw Error("Account already has supported local data; merge is not available yet");
    // Also protect excluded durable session/history data from partial restore.
    for(const k of ["training-session","training-spend","activity-spend-ledger","activity-training-history"]){if(store.getItem(prefix+k+":"+id)!==null)throw Error("Existing training or expenditure history; merge is not available yet");}
    if(!assertCurrent())throw Error("Account changed before restore");
    const added=[];
    try{for(const row of records){const d=descriptor(id,row.section);if(!assertCurrent()||store.getItem(d.key)!==null)throw Error("Account changed during restore");store.setItem(d.key,row.value);added.push(d.key);}}
    catch(error){let rollbackFailed=false;for(const k of added.reverse())try{store.removeItem(k);}catch{rollbackFailed=true;}if(rollbackFailed)throw Error("Restore incomplete; rollback failed. Keep the backup and inspect local storage.");throw error;}
    return records.length;
  }
  return {owner,snapshot,validRecords,restoreEmpty,maxBytes};
})();
