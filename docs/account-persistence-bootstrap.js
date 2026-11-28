"use strict";
/* Isolated V8 explicit missing-section bootstrap. NOT loaded in index.html.
 * Initializes only never-tracked calendar/expense sections and missing
 * lineage. Existing values and revision history are preserved. Bootstrap
 * cannot recover historical deletions predating lineage installation.
 */
const tornPersistenceBootstrap=(()=>{
  const version=8,prefix="torn-city-guide:",calendar="calendar-events",ledger="activity-spend",limit=6*1024*1024;
  const fields=["calendar","ledger","lineage","manifest"],sections=[calendar,ledger,"calendar-lineage","@revision-manifest"];
  const keys=id=>[prefix+"activity-events:"+id,prefix+"activity-spend-ledger:"+id,prefix+"calendar-lineage:v1:"+id,tornAccountRevisions.key(id)];
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const copy=v=>JSON.parse(JSON.stringify(v)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const vals=v=>fields.map(k=>v[k]);
  const held=(store,id)=>store.getItem(prefix+"training-session:"+id)!==null||store.getItem(tornTrainingRecovery.reviewKey(id))!==null;
  const other=s=>s.records.filter(r=>r.section!==calendar&&r.section!==ledger);
  const value=(s,section)=>s.records.find(r=>r.section===section)?.value??null;
  const write=(store,k,v)=>v===null?store.removeItem(k):store.setItem(k,v);
  const locked=(id,locks,fn)=>{if(!locks?.request)throw Error("Web Locks required for persistence bootstrap");return locks.request(prefix+"account-recovery:"+id,{mode:"exclusive"},fn);};
  function guard(store,id,isCurrent,raw,markers){
    if(typeof isCurrent!=="function"||isCurrent()!==true||held(store,id))throw Error("Account or training state blocks bootstrap");
    if(store.getItem(tornAccountStorage.journalKey(id))!==raw)throw Error("Bootstrap journal changed or pending");
    if(!same(tornAccountStorage.deletionMarkers(store,id),markers))throw Error("Account deletion markers changed");
  }
  function snapshot(store,id,raw=null){
    const jk=tornAccountStorage.journalKey(id);
    if(store.getItem(jk)!==raw)throw Error("Bootstrap journal changed or pending");
    const view={get length(){return store.length;},key:i=>store.key(i),getItem:k=>k===jk?null:store.getItem(k)};
    const snap=tornAccountStorage.snapshot(view,id);
    if(snap.omitted.length)throw Error("Incomplete local account snapshot");
    return snap;
  }
  function state(store,id,raw=null){
    const snap=snapshot(store,id,raw),dest=keys(id),markers=tornAccountStorage.deletionMarkers(store,id);
    const before={calendar:value(snap,calendar),ledger:value(snap,ledger),lineage:store.getItem(dest[2]),manifest:store.getItem(dest[3])};
    return {snap,before,markers};
  }
  function bundle(snap,v,id){
    const records=other(snap).concat(v.calendar===null?[]:[{section:calendar,value:v.calendar}],v.ledger===null?[]:[{section:ledger,value:v.ledger}]).sort((a,b)=>a.section.localeCompare(b.section));
    return {records,omitted:[],manifest:v.manifest===null?tornAccountRevisions.empty(id):JSON.parse(v.manifest)};
  }
  function validValues(v,id){
    if(!exact(v,fields)||!(v.calendar===null||typeof v.calendar==="string"&&v.calendar.length<=500000)||!(v.ledger===null||typeof v.ledger==="string"&&v.ledger.length<=500000)||!(v.lineage===null||typeof v.lineage==="string"&&v.lineage.length<=1000000)||!(v.manifest===null||typeof v.manifest==="string"&&v.manifest.length<=2000000))throw Error("Invalid bootstrap values");
    tornAccountStorage.validRecords([...(v.calendar===null?[]:[{section:calendar,value:v.calendar}]),...(v.ledger===null?[]:[{section:ledger,value:v.ledger}])],id);
    if(v.manifest!==null)tornAccountRevisions.validate(JSON.parse(v.manifest),id);
  }
  // Never interpret missing tracked data as a new empty section.
  // Nonempty legacy data must first be captured/reviewed separately.
  async function inspect(snap,before,markers,id,options){
    validValues(before,id);
    if(!Array.isArray(markers)||markers.length>1500||new Set(markers).size!==markers.length||markers.some(x=>!tornAccountStorage.knownSection(id,x)))throw Error("Invalid bootstrap deletion markers");
    if(markers.includes(calendar)||markers.includes(ledger))throw Error("Calendar or ledger deletion history requires review");
    const a=bundle(snap,before,id);
    if(before.manifest===null&&(a.records.length||markers.length||before.lineage!==null))throw Error("Capture or review existing account data before bootstrap");
    await tornAccountRevisions.verify(a.manifest,a.records,id,options);
    if(markers.some(x=>!a.manifest.entries.some(e=>e.section===x)))throw Error("Uncaptured deletion markers");
    const missing=[];
    for(const [field,section] of [["calendar",calendar],["ledger",ledger]]){
      if(before[field]!==null)continue;
      if(a.manifest.entries.some(e=>e.section===section))throw Error("Tracked missing section requires review");
      missing.push(section);
    }
    if(before.lineage!==null){
      if(before.calendar===null)throw Error("Existing lineage without calendar requires review");
      await tornCalendarLineage.verify(JSON.parse(before.lineage),a,id,options);
    }else missing.push("calendar-lineage");
    return {a,missing};
  }
  async function preview(store,playerId,isCurrent,{digest}={}){
    const id=tornAccountStorage.owner(playerId),s=state(store,id);
    guard(store,id,isCurrent,null,s.markers);
    const result=await inspect(s.snap,s.before,s.markers,id,digest?{digest}:{});
    guard(store,id,isCurrent,null,s.markers);
    if(!same(state(store,id),s))throw Error("Local account changed; review again");
    return {status:result.missing.length?"review":"unchanged",missing:result.missing,review:s,warning:"Bootstrap cannot reconstruct historical calendar deletions."};
  }
  function parse(raw,id){
    if(typeof raw!=="string"||raw.length>limit)throw Error("Invalid bootstrap journal size");
    const j=JSON.parse(raw);
    if(!exact(j,["version","playerId","createdAt","before","after","markers"])||j.version!==version||j.playerId!==id||!Number.isSafeInteger(j.createdAt)||j.createdAt<=0||j.createdAt>Date.now()+1000||!Array.isArray(j.markers)||j.markers.length>1500||new Set(j.markers).size!==j.markers.length||j.markers.some(x=>!tornAccountStorage.knownSection(id,x)))throw Error("Invalid bootstrap journal");
    validValues(j.before,id);validValues(j.after,id);
    if(j.after.calendar===null||j.after.ledger===null||j.after.lineage===null||j.after.manifest===null||same(j.before,j.after))throw Error("Invalid bootstrap transition");
    return j;
  }
  async function validateTransition(j,snap,id,options){
    const {a,missing}=await inspect(snap,j.before,j.markers,id,options);
    if(!missing.length||j.after.calendar!==(j.before.calendar??"[]")||j.after.ledger!==(j.before.ledger??"[]"))throw Error("Bootstrap may initialize missing sections only");
    const b=bundle(snap,j.after,id);
    await tornAccountRevisions.verify(b.manifest,b.records,id,options);
    const old=new Map(a.manifest.entries.map(e=>[e.section,e])),next=new Map(b.manifest.entries.map(e=>[e.section,e]));
    const added=missing.filter(s=>s!== "calendar-lineage");
    if(next.size!==old.size+added.length)throw Error("Unexpected bootstrap revision sections");
    for(const [section,e] of old)if(!same(next.get(section),e))throw Error("Existing revision changed during bootstrap");
    const used=new Set(a.manifest.entries.flatMap(e=>[e.revision,...e.ancestors]));
    for(const section of added){
      const e=next.get(section);
      if(!e||e.digest===null||e.ancestors.length||used.has(e.revision))throw Error("Invalid new bootstrap revision");
    }
    const lineage=j.before.lineage??JSON.stringify(await tornCalendarLineage.initialize(b,id,options));
    if(j.after.lineage!==lineage)throw Error("Unexpected bootstrap lineage");
    await tornCalendarLineage.verify(JSON.parse(j.after.lineage),b,id,options);
  }
  function status(store,id,raw){
    const j=parse(raw,id),before=vals(j.before),after=vals(j.after);
    const rows=keys(id).map((k,i)=>({section:sections[i],state:store.getItem(k)===after[i]?"matched":store.getItem(k)===before[i]?"previous":"conflict"}));
    if(held(store,id)||!same(tornAccountStorage.deletionMarkers(store,id),j.markers))rows.push({section:"local-account-state",state:"conflict"});
    return {rows,complete:rows.every(x=>x.state==="matched"),conflict:rows.some(x=>x.state==="conflict")};
  }
  function read(store,playerId){
    const id=tornAccountStorage.owner(playerId),raw=store.getItem(tornAccountStorage.journalKey(id));
    return raw===null?null:{raw,version,...status(store,id,raw)};
  }
  async function apply(store,playerId,review,approved,isCurrent,locks,{digest,newRevision}={}){
    const id=tornAccountStorage.owner(playerId);
    if(approved!==true)throw Error("Explicit bootstrap approval required");
    review=copy(review);
    const options={...(digest?{digest}:{}),...(newRevision?{newRevision}:{})};
    return locked(id,locks,async()=>{
      const s=state(store,id),jk=tornAccountStorage.journalKey(id),dest=keys(id);
      guard(store,id,isCurrent,null,s.markers);
      if(!same(review,s))throw Error("Local account changed; review again");
      const {a,missing}=await inspect(s.snap,s.before,s.markers,id,options);
      if(!missing.length)return {status:"unchanged",initialized:[]};
      const after={...s.before,calendar:s.before.calendar??"[]",ledger:s.before.ledger??"[]"};
      const records=bundle(s.snap,after,id).records;
      const manifest=await tornAccountRevisions.observe(a.manifest,{records,omitted:[]},id,options);
      after.manifest=JSON.stringify(manifest);
      const next={records,omitted:[],manifest};
      after.lineage=s.before.lineage??JSON.stringify(await tornCalendarLineage.initialize(next,id,options));
      const raw=JSON.stringify({version,playerId:id,createdAt:Date.now(),before:s.before,after,markers:s.markers});
      await validateTransition(parse(raw,id),s.snap,id,options);
      guard(store,id,isCurrent,null,s.markers);
      if(!same(state(store,id),s))throw Error("Local account changed; review again");
      store.setItem(jk,raw);
      if(store.getItem(jk)!==raw)throw Error("Could not persist bootstrap journal");
      try{
        for(let i=0;i<dest.length;i++){
          guard(store,id,isCurrent,raw,s.markers);
          if(store.getItem(dest[i])!==vals(s.before)[i])throw Error("Concurrent bootstrap write");
          if(vals(s.before)[i]!==vals(after)[i])write(store,dest[i],vals(after)[i]);
        }
        guard(store,id,isCurrent,raw,s.markers);
        if(!status(store,id,raw).complete||!same(other(snapshot(store,id,raw)),other(s.snap)))throw Error("Bootstrap recovery incomplete");
        store.removeItem(jk);
        if(store.getItem(jk)!==null)throw Error("Could not clear bootstrap journal");
      }catch{throw Error("Bootstrap write interrupted; journal retained for review");}
      return {status:"applied",initialized:missing};
    });
  }
  async function recover(store,playerId,raw,mode,isCurrent,locks,{digest}={}){
    const id=tornAccountStorage.owner(playerId);
    if(!["finish","rollback"].includes(mode))throw Error("Invalid bootstrap recovery action");
    return locked(id,locks,async()=>{
      const j=parse(raw,id),dest=keys(id),jk=tornAccountStorage.journalKey(id);
      guard(store,id,isCurrent,raw,j.markers);
      const state=status(store,id,raw);
      if(state.conflict||mode==="finish"&&!state.complete)throw Error("Conflicting or incomplete bootstrap journal; preserve for review");
      const snap=snapshot(store,id,raw),values=dest.map(k=>store.getItem(k));
      await validateTransition(j,snap,id,digest?{digest}:{});
      guard(store,id,isCurrent,raw,j.markers);
      if(!same(values,dest.map(k=>store.getItem(k)))||!same(snap,snapshot(store,id,raw)))throw Error("Local account changed during bootstrap recovery");
      if(mode==="rollback"){
        for(let i=dest.length-1;i>=0;i--){
          guard(store,id,isCurrent,raw,j.markers);
          const current=store.getItem(dest[i]);
          if(current!==vals(j.before)[i]&&current!==vals(j.after)[i])throw Error("Concurrent bootstrap change; journal retained");
          if(current!==vals(j.before)[i])write(store,dest[i],vals(j.before)[i]);
        }
      }
      guard(store,id,isCurrent,raw,j.markers);
      if(!same(dest.map(k=>store.getItem(k)),vals(mode==="finish"?j.after:j.before))||!same(other(snapshot(store,id,raw)),other(snap)))throw Error("Bootstrap recovery incomplete; journal retained");
      store.removeItem(jk);
      if(store.getItem(jk)!==null)throw Error("Could not clear bootstrap journal");
      return {status:mode==="finish"?"finalized":"rolled-back"};
    });
  }
  return Object.freeze({version,preview,apply,read,recover});
})();
