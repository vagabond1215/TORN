"use strict";
/* Isolated V6 evidence-bound rehab completion. NOT loaded by index.html.
 * LocalStorage journal is recoverable, not physically atomic. Never use
 * an API key or a network fetch here. Caller supplies current verified
 * nonsecret observations and an owner/epoch guard. Recovery is explicit.
 */
const tornRehabJournal=(()=>{
  const version=6,calendar="calendar-events",ledger="activity-spend",prefix="torn-city-guide:",limit=6*1024*1024;
  const copy=v=>JSON.parse(JSON.stringify(v)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const keys=id=>[prefix+"activity-events:"+id,prefix+"activity-spend-ledger:"+id,prefix+"calendar-lineage:v1:"+id,tornAccountRevisions.key(id)];
  const fields=["calendar","ledger","lineage","manifest"],sections=[calendar,ledger,"calendar-lineage","@revision-manifest"];
  const vals=v=>fields.map(k=>v[k]);
  const held=(store,id)=>store.getItem(prefix+"training-session:"+id)!==null||store.getItem(tornTrainingRecovery.reviewKey(id))!==null;
  const write=(store,k,v)=>v===null?store.removeItem(k):store.setItem(k,v);
  const validTime=v=>Number.isSafeInteger(v)&&v>0&&v<=Date.now()+1000;
  const value=(snap,section)=>snap.records.find(r=>r.section===section)?.value??null;
  const other=snap=>snap.records.filter(r=>r.section!==calendar&&r.section!==ledger);
  function guard(store,id,isCurrent,raw,markers){
    if(typeof isCurrent!=="function"||isCurrent()!==true||held(store,id))throw Error("Account or training state blocks rehab recovery");
    if(store.getItem(tornAccountStorage.journalKey(id))!==raw)throw Error("Rehab journal changed or pending");
    if(!same(tornAccountStorage.deletionMarkers(store,id),markers))throw Error("Account deletion markers changed");
  }
  function locked(id,locks,fn){
    if(!locks?.request)throw Error("Web Locks required for rehab recovery");
    return locks.request(prefix+"account-recovery:"+id,{mode:"exclusive"},fn);
  }
  function snapshot(store,id,raw=null){
    const jk=tornAccountStorage.journalKey(id);
    if(store.getItem(jk)!==raw)throw Error("Rehab journal changed or pending");
    // Read-only facade for verification; never used by a writer.
    const view={get length(){return store.length;},key:i=>store.key(i),getItem:k=>k===jk?null:store.getItem(k)};
    const snap=tornAccountStorage.snapshot(view,id);
    if(snap.omitted.length)throw Error("Incomplete local account snapshot");
    return snap;
  }
  function bundle(snap,v){
    const records=other(snap).concat([{section:calendar,value:v.calendar},...(v.ledger===null?[]:[{section:ledger,value:v.ledger}])]).sort((a,b)=>a.section.localeCompare(b.section));
    return {records,omitted:[],manifest:JSON.parse(v.manifest)};
  }
  function parse(raw,id){
    if(typeof raw!=="string"||raw.length>limit)throw Error("Invalid rehab journal size");
    const j=JSON.parse(raw);
    if(!exact(j,["version","playerId","createdAt","eventId","evidence","before","after","markers"])||j.version!==version||j.playerId!==id||!validTime(j.createdAt)||typeof j.eventId!=="string"||!j.eventId||j.eventId.length>160||!exact(j.evidence,["playerId","count","cost","statsAt","profileAt","profileStatus"])||j.evidence.playerId!==id||!Array.isArray(j.markers)||j.markers.length>1500||new Set(j.markers).size!==j.markers.length||j.markers.some(x=>!tornAccountStorage.knownSection(id,x)))throw Error("Invalid rehab journal");
    for(const v of [j.before,j.after]){
      if(!exact(v,fields)||typeof v.calendar!=="string"||v.calendar.length>500000||!(v.ledger===null||typeof v.ledger==="string"&&v.ledger.length<=500000)||!(v.lineage===null||typeof v.lineage==="string"&&v.lineage.length<=1000000)||typeof v.manifest!=="string"||v.manifest.length>2000000)throw Error("Invalid rehab journal values");
      tornAccountStorage.validRecords([{section:calendar,value:v.calendar},...(v.ledger===null?[]:[{section:ledger,value:v.ledger}])],id);
      tornAccountRevisions.validate(JSON.parse(v.manifest),id);
    }
    if(j.after.lineage===null||j.before.calendar===j.after.calendar||j.before.manifest===j.after.manifest||j.before.ledger===null&&j.after.ledger!==null)throw Error("Invalid rehab journal transition; ledger bootstrap is separate");
    return j;
  }
  function status(store,id,raw){
    const j=parse(raw,id),before=vals(j.before),after=vals(j.after);
    const rows=keys(id).map((k,i)=>({section:sections[i],state:store.getItem(k)===after[i]?"matched":store.getItem(k)===before[i]?"previous":"conflict"}));
    if(held(store,id)||!same(tornAccountStorage.deletionMarkers(store,id),j.markers))rows.push({section:"local-account-state",state:"conflict"});
    return {rows,complete:rows.every(x=>x.state==="matched"),conflict:rows.some(x=>x.state==="conflict")};
  }
  function read(store,playerId){
    const id=tornAccountStorage.owner(playerId),raw=store.getItem(tornAccountStorage.journalKey(id));
    if(raw===null)return null;
    return {raw,version,...status(store,id,raw)};
  }
  // Re-derive exact domain effects at the original decision time, not at
  // reload time. A late recovery never discovers or charges a new event.
  async function validateTransition(j,snap,id,options){
    const a=bundle(snap,j.before),b=bundle(snap,j.after);
    await tornAccountRevisions.verify(a.manifest,a.records,id,options);
    await tornAccountRevisions.verify(b.manifest,b.records,id,options);
    if(j.markers.some(x=>!a.manifest.entries.some(m=>m.section===x)))throw Error("Uncaptured deletion markers");
    const candidate=await tornRehabTransition.prepare(a,id,j.evidence,{now:j.createdAt,...options});
    if(candidate.status!=="candidate"||candidate.eventId!==j.eventId||!same(candidate.records,b.records))throw Error("Rehab journal evidence or paired effects mismatch");
    const changed=new Set(candidate.changes.map(x=>x.section));
    const oldTokens=new Set(a.manifest.entries.flatMap(e=>[e.revision,...e.ancestors]));
    const afterBySection=new Map(b.manifest.entries.map(e=>[e.section,e]));
    if(a.manifest.entries.length!==b.manifest.entries.length)throw Error("Unexpected rehab revision sections");
    for(const old of a.manifest.entries){
      const next=afterBySection.get(old.section);
      if(!next)throw Error("Unexpected rehab revision sections");
      if(!changed.has(old.section)){if(!same(old,next))throw Error("Unrelated revision change");continue;}
      if(next.digest===old.digest||oldTokens.has(next.revision)||!same(next.ancestors,[old.revision,...old.ancestors].slice(0,32)))throw Error("Rehab revision must be a fresh immediate descendant");
    }
    if([...changed].some(s=>!a.manifest.entries.some(e=>e.section===s)))throw Error("Tracked rehab sections required");
    const initial=j.before.lineage===null?await tornCalendarLineage.initialize(a,id,options):await tornCalendarLineage.verify(JSON.parse(j.before.lineage),a,id,options);
    const next=await tornCalendarLineage.advance(initial,a,b,id,[],options);
    if(!same(next,JSON.parse(j.after.lineage)))throw Error("Rehab calendar lineage mismatch");
  }
  // Explicit reviewed candidate; caller must read the current nonsecret
  // observation from its verified connection under the recovery lock.
  // getObservation is synchronous and MUST NOT request API data.
  async function apply(store,playerId,local,review,getObservation,isCurrent,locks,{allowBootstrap=false,digest,newRevision}={}){
    const id=tornAccountStorage.owner(playerId);
    local=copy(local);review=copy(review);
    if(!exact(review,["eventId","cost","evidence"])||typeof getObservation!=="function")throw Error("Explicit rehab review and observation required");
    const options={...(digest?{digest}:{}),...(newRevision?{newRevision}:{})};
    return locked(id,locks,async()=>{
      const jk=tornAccountStorage.journalKey(id),dest=keys(id),markers=tornAccountStorage.deletionMarkers(store,id);
      guard(store,id,isCurrent,null,markers);
      const snap=snapshot(store,id),before={calendar:value(snap,calendar),ledger:value(snap,ledger),lineage:store.getItem(dest[2]),manifest:store.getItem(dest[3])};
      const currentEvidence=()=>{if(!same(getObservation(),review.evidence))throw Error("Rehab observation changed; review again");};
      const unchanged=()=>{
        guard(store,id,isCurrent,null,markers);currentEvidence();
        if(!same(snap,snapshot(store,id))||!same(dest.map(k=>store.getItem(k)),vals(before)))throw Error("Local account changed; review again");
      };
      if(before.calendar===null||before.manifest!==JSON.stringify(local.manifest)||!same(snap,{records:local.records,omitted:local.omitted}))throw Error("Tracked local snapshot changed; review again");
      if(markers.some(x=>!local.manifest.entries.some(m=>m.section===x)))throw Error("Uncaptured deletion markers");
      currentEvidence();
      const createdAt=Date.now();
      const candidate=await tornRehabTransition.prepare(local,id,review.evidence,{...options,now:createdAt});
      if(candidate.status!=="candidate")return candidate;
      if(candidate.eventId!==review.eventId||candidate.cost!==review.cost)throw Error("Rehab review changed; review again");
      if(candidate.cost!==null&&before.ledger===null)return {status:"review",reason:"Explicit expenditure ledger bootstrap required"};
      if(before.lineage===null&&allowBootstrap!==true)throw Error("Explicit calendar lineage bootstrap required");
      const initial=before.lineage===null?await tornCalendarLineage.initialize(local,id,options):await tornCalendarLineage.verify(JSON.parse(before.lineage),local,id,options);
      const manifest=await tornAccountRevisions.observe(local.manifest,{records:candidate.records,omitted:[]},id,options);
      const next={records:candidate.records,omitted:[],manifest};
      const lineage=await tornCalendarLineage.advance(initial,local,next,id,[],options);
      const after={calendar:value(next,calendar),ledger:value(next,ledger),lineage:JSON.stringify(lineage),manifest:JSON.stringify(manifest)};
      const raw=JSON.stringify({version,playerId:id,createdAt,eventId:candidate.eventId,evidence:review.evidence,before,after,markers});
      await validateTransition(parse(raw,id),snap,id,options);
      unchanged();
      // Prevent an arbitrarily slow crypto or capture operation from using
      // an old decision. Check the evidence again immediately before write.
      const now=Date.now();
      const original=JSON.parse(before.calendar).find(e=>e.id===candidate.eventId);
      if(now<createdAt||now-createdAt>5000||now-review.evidence.statsAt>30*60000||now-review.evidence.profileAt>15*60000||now-original.end>86400000)return {status:"review",reason:"Rehab observation or reservation expired during review"};
      store.setItem(jk,raw);
      if(store.getItem(jk)!==raw)throw Error("Could not persist rehab journal");
      try{
        for(let i=0;i<dest.length;i++){
          guard(store,id,isCurrent,raw,markers);currentEvidence();
          if(store.getItem(dest[i])!==vals(before)[i])throw Error("Concurrent rehab write");
          if(vals(before)[i]!==vals(after)[i])write(store,dest[i],vals(after)[i]);
        }
        guard(store,id,isCurrent,raw,markers);currentEvidence();
        if(!status(store,id,raw).complete||!same(other(snapshot(store,id,raw)),other(snap)))throw Error("Rehab recovery incomplete");
        store.removeItem(jk);
        if(store.getItem(jk)!==null)throw Error("Could not clear rehab journal");
      }catch{throw Error("Rehab write interrupted; journal retained for review");}
      return {status:"applied",eventId:candidate.eventId,cost:candidate.cost,attribution:candidate.attribution};
    });
  }
  async function recover(store,playerId,raw,mode,isCurrent,locks,{digest}={}){
    const id=tornAccountStorage.owner(playerId);
    if(!["finish","rollback"].includes(mode))throw Error("Invalid rehab recovery action");
    return locked(id,locks,async()=>{
      const j=parse(raw,id),jk=tornAccountStorage.journalKey(id),dest=keys(id);
      guard(store,id,isCurrent,raw,j.markers);
      const state=status(store,id,raw);
      if(state.conflict||mode==="finish"&&!state.complete)throw Error("Conflicting or incomplete rehab journal; preserve for review");
      const snap=snapshot(store,id,raw),values=dest.map(k=>store.getItem(k));
      await validateTransition(j,snap,id,digest?{digest}:{});
      guard(store,id,isCurrent,raw,j.markers);
      if(!same(values,dest.map(k=>store.getItem(k)))||!same(snap,snapshot(store,id,raw)))throw Error("Local account changed during rehab recovery");
      if(mode==="rollback"){
        for(let i=dest.length-1;i>=0;i--){
          guard(store,id,isCurrent,raw,j.markers);
          const current=store.getItem(dest[i]);
          if(current!==vals(j.before)[i]&&current!==vals(j.after)[i])throw Error("Concurrent rehab change; journal retained");
          if(current!==vals(j.before)[i])write(store,dest[i],vals(j.before)[i]);
        }
      }
      guard(store,id,isCurrent,raw,j.markers);
      if(!same(dest.map(k=>store.getItem(k)),vals(mode==="finish"?j.after:j.before))||!same(other(snapshot(store,id,raw)),other(snap)))throw Error("Rehab recovery incomplete; journal retained");
      store.removeItem(jk);
      if(store.getItem(jk)!==null)throw Error("Could not clear rehab journal");
      return {status:mode==="finish"?"finalized":"rolled-back"};
    });
  }
  return Object.freeze({version,read,apply,recover});
})();
