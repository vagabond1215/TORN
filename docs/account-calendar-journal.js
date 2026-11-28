"use strict";
/* P1.3 isolated protected calendar journal. NOT loaded in index.html.
 * V3 shares existing recovery hold; old V1/V2 readers fail closed.
 * Caller authenticates backup envelope(s) and verifies own account.
 * Local journal is not a cryptographic boundary against origin compromise.
 */
const tornCalendarJournal=(()=>{
  const prefix="torn-city-guide:",section="calendar-events",version=3,mutationVersion=4,operationalVersion=5,rehabPlanningVersion=7,limit=6*1024*1024;
  const copy=v=>JSON.parse(JSON.stringify(v));
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const canon=e=>JSON.stringify(Object.keys(e).sort().map(k=>[k,e[k]]));
  const safe=e=>e&&["personal","event"].includes(e.kind)&&e.blocking===false;
  const keys=id=>[prefix+"activity-events:"+id,prefix+"calendar-lineage:v1:"+id,tornAccountRevisions.key(id)];
  const lineageKey=id=>keys(tornAccountStorage.owner(id))[1];
  const held=(store,id)=>store.getItem(prefix+"training-session:"+id)!==null||store.getItem(tornTrainingRecovery.reviewKey(id))!==null;
  function guard(store,id,isCurrent){if(typeof isCurrent!=="function"||isCurrent()!==true||held(store,id))throw Error("Account or training state blocks calendar recovery");}
  function locked(id,locks,fn){if(!locks?.request)throw Error("Web Locks required for calendar recovery");return locks.request(prefix+"account-recovery:"+id,{mode:"exclusive"},fn);}
  // Only for read-only validation during recovery. The true journal stays
  // present; do not give this facade to any writer or other subsystem.
  function snapshot(store,id,raw=null){
    const jk=tornAccountStorage.journalKey(id);
    if(store.getItem(jk)!==raw)throw Error("Calendar journal changed");
    const view={get length(){return store.length;},key:i=>store.key(i),getItem:k=>k===jk?null:store.getItem(k)};
    const snap=tornAccountStorage.snapshot(view,id);
    if(snap.omitted.length)throw Error("Incomplete local account snapshot");
    return snap;
  }
  const sectionValue=s=>s.records.find(r=>r.section===section)?.value??null;
  const other=s=>s.records.filter(r=>r.section!==section);
  function bundle(s,calendar,manifest){
    const records=other(s).concat(calendar===null?[]:[{section,value:calendar}]).sort((a,b)=>a.section.localeCompare(b.section));
    return {records,omitted:[],manifest:JSON.parse(manifest)};
  }
  function parse(raw,id){
    if(typeof raw!=="string"||raw.length>limit)throw Error("Invalid calendar journal size");
    const j=JSON.parse(raw);
    const mutation=[mutationVersion,operationalVersion,rehabPlanningVersion].includes(j?.version);
    if(!exact(j,["version","playerId","createdAt","before","after","markers",...(mutation?["mutation"]:[])])||![version,mutationVersion,operationalVersion,rehabPlanningVersion].includes(j.version)||j.playerId!==id||!Number.isSafeInteger(j.createdAt)||j.createdAt<=0||j.createdAt>Date.now()+1000||!Array.isArray(j.markers)||j.markers.length>1500||new Set(j.markers).size!==j.markers.length||j.markers.some(x=>!tornAccountStorage.knownSection(id,x)))throw Error("Invalid calendar journal");
    if(mutation&&(!exact(j.mutation,["id","kind"])||typeof j.mutation.id!=="string"||!j.mutation.id||j.mutation.id.length>160||!["add","edit","remove"].includes(j.mutation.kind)))throw Error("Invalid calendar mutation journal");
    for(const v of [j.before,j.after]){
      if(!exact(v,["calendar","lineage","manifest"])||!(v.calendar===null||typeof v.calendar==="string"&&v.calendar.length<=500000)||!(v.lineage===null||typeof v.lineage==="string"&&v.lineage.length<=1000000)||typeof v.manifest!=="string"||v.manifest.length>2000000)throw Error("Invalid calendar journal values");
      if(v.calendar!==null)tornAccountStorage.validRecords([{section,value:v.calendar}],id);
      tornAccountRevisions.validate(JSON.parse(v.manifest),id);
    }
    if(j.after.calendar===null||j.after.lineage===null||j.before.calendar===j.after.calendar||j.before.manifest===j.after.manifest)throw Error("Invalid calendar journal transition");
    return j;
  }
  const vals=v=>[v.calendar,v.lineage,v.manifest];
  function status(store,id,raw){
    const j=parse(raw,id),dest=keys(id),before=vals(j.before),after=vals(j.after);
    const rows=dest.map((k,i)=>({section:[section,"calendar-lineage","@revision-manifest"][i],state:store.getItem(k)===after[i]?"matched":store.getItem(k)===before[i]?"previous":"conflict"}));
    if(held(store,id)||!same(tornAccountStorage.deletionMarkers(store,id),j.markers))rows.push({section:"local-account-state",state:"conflict"});
    return {rows,complete:rows.every(x=>x.state==="matched"),conflict:rows.some(x=>x.state==="conflict")};
  }
  function read(store,playerId){
    const id=tornAccountStorage.owner(playerId),raw=store.getItem(tornAccountStorage.journalKey(id));
    if(raw===null)return null;
    return {raw,version:parse(raw,id).version,...status(store,id,raw)};
  }
  // Validate only additions/edits to safe kinds; unchanged operational
  // rows remain byte-for-byte equivalent as parsed records. No removals.
  function validateDelta(before,after){
    const a=new Map(JSON.parse(before??"[]").map(x=>[x.id,x])),b=new Map(JSON.parse(after).map(x=>[x.id,x]));
    for(const [id,row] of a){const next=b.get(id);if(!next||canon(row)!==canon(next)&&(!safe(row)||!safe(next)))throw Error("Protected calendar change");}
    for(const [id,row] of b)if(!a.has(id)&&!safe(row))throw Error("Protected calendar addition");
    if(a.size===b.size&&[...a].every(([id,row])=>canon(row)===canon(b.get(id))))throw Error("No calendar content change");
  }
  // V4 is a single explicitly observed ordinary mutation. It cannot
  // authorize any backup deletion, operational edit, or bulk replacement.
  function validateMutation(before,after,mutation,operational=false){
    const a=new Map(JSON.parse(before??"[]").map(x=>[x.id,x])),b=new Map(JSON.parse(after).map(x=>[x.id,x])),id=mutation.id;
    const old=a.get(id),next=b.get(id);
    for(const key of new Set([...a.keys(),...b.keys()]))if(key!==id&&(!a.has(key)||!b.has(key)||canon(a.get(key))!==canon(b.get(key))))throw Error("Unexpected calendar mutation");
    // V5 is an explicit local planning action, NEVER import authority.
    // Rehab records may carry financial evidence; a distinct operation
    // is required even for a pending reservation.
    const allowed=operational?e=>!!e&&e.kind!=="rehab":safe;
    if(mutation.kind==="add"&&!old&&allowed(next))return [];
    if(mutation.kind==="edit"&&allowed(old)&&allowed(next)&&old.kind===next.kind&&canon(old)!==canon(next))return [];
    if(mutation.kind==="remove"&&allowed(old)&&!next)return [id];
    throw Error("Protected or invalid calendar mutation");
  }
  // V7 planning is not completion, import or financial authority.
  // Only create a pending reservation or cancel before departure.
  // Rescheduling requires explicit cancellation and a new reservation ID.
  function validateRehabPlanning(before,after,mutation,snap,at){
    const a=JSON.parse(before??"[]"),b=JSON.parse(after),old=a.find(x=>x.id===mutation.id),next=b.find(x=>x.id===mutation.id);
    const pending=e=>e?.kind==="rehab"&&e.blocking===true&&!Object.hasOwn(e,"completedAt")&&!Object.hasOwn(e,"rehabCost")&&!Object.hasOwn(e,"recoveryReview");
    const prior=a.filter(x=>x.id!==mutation.id),later=b.filter(x=>x.id!==mutation.id);
    if(!same(prior,later))throw Error("Unexpected rehab planning mutation");
    const spend=JSON.parse(snap.records.find(r=>r.section==="activity-spend")?.value??"[]");
    if(spend.some(x=>x.id==="rehab-"+mutation.id))throw Error("Existing expenditure evidence blocks rehab planning mutation");
    if(mutation.kind==="add"&&!old&&pending(next)){
      if(next.start<at-5000||next.end<=at||!Object.hasOwn(next,"rehabBaseline"))throw Error("Invalid rehab reservation window or baseline");
      if(next.rehabBaseline!==null){
        const v=next.rehabBaseline;
        if(!Number.isSafeInteger(v.at)||v.at<=0||v.at>at||v.at>next.start||at-v.at>30*60000||next.start-v.at>30*60000||!Number.isSafeInteger(v.count)||v.count<0||!(v.cost===null||Number.isSafeInteger(v.cost)&&v.cost>=0))throw Error("Stale or invalid rehab reservation baseline");
      }
      if(prior.some(x=>x.blocking&&next.start<x.end&&next.end>x.start))throw Error("Rehab reservation overlaps a blocking activity");
      return [];
    }
    if(mutation.kind==="remove"&&pending(old)&&!next&&at<old.start)return [mutation.id];
    throw Error("Protected or invalid rehab planning mutation");
  }
  async function validateTransition(j,snap,id,options){
    let removed=[];
    if(j.version===rehabPlanningVersion)removed=validateRehabPlanning(j.before.calendar,j.after.calendar,j.mutation,snap,j.createdAt);
    else if([mutationVersion,operationalVersion].includes(j.version))removed=validateMutation(j.before.calendar,j.after.calendar,j.mutation,j.version===operationalVersion);
    else validateDelta(j.before.calendar,j.after.calendar);
    const a=bundle(snap,j.before.calendar,j.before.manifest),b=bundle(snap,j.after.calendar,j.after.manifest);
    await tornAccountRevisions.verify(a.manifest,a.records,id,options);
    await tornAccountRevisions.verify(b.manifest,b.records,id,options);
    const prior=a.manifest.entries.find(x=>x.section===section),next=b.manifest.entries.find(x=>x.section===section);
    const rest=m=>m.entries.filter(x=>x.section!==section);
    const used=new Set(a.manifest.entries.flatMap(x=>[x.revision,...x.ancestors]));
    if(!prior||!next||used.has(next.revision)||!same(next.ancestors,[prior.revision,...prior.ancestors].slice(0,32))||!same(rest(a.manifest),rest(b.manifest)))throw Error("Calendar journal must create only a local descendant");
    const initial=j.before.lineage===null?await tornCalendarLineage.initialize(a,id,options):await tornCalendarLineage.verify(JSON.parse(j.before.lineage),a,id,options);
    const advanced=await tornCalendarLineage.advance(initial,a,b,id,removed,options);
    if(!same(advanced,JSON.parse(j.after.lineage)))throw Error("Calendar lineage transition mismatch");
  }
  const write=(store,k,v)=>v===null?store.removeItem(k):store.setItem(k,v);
  function assertCurrent(store,id,raw,isCurrent,markers){
    guard(store,id,isCurrent);
    if(store.getItem(tornAccountStorage.journalKey(id))!==raw||!same(tornAccountStorage.deletionMarkers(store,id),markers))throw Error("Calendar journal or deletion markers changed");
  }
  // Explicit review decisions re-verified inside shared account lock.
  // Bootstrap permitted only by explicit caller authorization; lineage
  // cannot reconstruct tombstones predating its installation.
  async function transact(store,id,local,isCurrent,locks,options,choose){
    const {allowBootstrap=false,digest,newRevision}=options;
    const verifyOptions={...(digest?{digest}:{}),...(newRevision?{newRevision}:{})};
    return locked(id,locks,async()=>{
      guard(store,id,isCurrent);
      const jk=tornAccountStorage.journalKey(id),dest=keys(id),snap=snapshot(store,id);
      const markers=tornAccountStorage.deletionMarkers(store,id),before={calendar:sectionValue(snap),lineage:store.getItem(dest[1]),manifest:store.getItem(dest[2])};
      const unchanged=()=>{assertCurrent(store,id,null,isCurrent,markers);if(!same(snapshot(store,id),snap)||!same(dest.map(k=>store.getItem(k)),vals(before)))throw Error("Local account changed; preview again");};
      if(before.manifest!==JSON.stringify(local.manifest)||!same(snap,{records:local.records,omitted:local.omitted??[]}))throw Error("Local account changed; preview again");
      if(markers.some(x=>!local.manifest.entries.some(m=>m.section===x)))throw Error("Uncaptured deletion markers; preview again");
      const chosen=await choose(verifyOptions);
      unchanged();
      if(chosen.value===null)return {status:"unchanged",selected:[]};
      if(before.lineage===null&&allowBootstrap!==true)throw Error("Explicit calendar lineage bootstrap required");
      const initial=before.lineage===null?await tornCalendarLineage.initialize(local,id,verifyOptions):await tornCalendarLineage.verify(JSON.parse(before.lineage),local,id,verifyOptions);
      const records=other(local).concat({section,value:chosen.value}).sort((a,b)=>a.section.localeCompare(b.section));
      const manifest=await tornAccountRevisions.observe(local.manifest,{records,omitted:[]},id,verifyOptions);
      const fresh=manifest.entries.find(x=>x.section===section).revision;
      if(chosen.importedTokens.includes(fresh))throw Error("Calendar revision token collision with imported ancestry");
      const next={records,omitted:[],manifest};
      const lineage=await tornCalendarLineage.advance(initial,local,next,id,chosen.removed,verifyOptions);
      const after={calendar:chosen.value,lineage:JSON.stringify(lineage),manifest:JSON.stringify(manifest)};
      const raw=JSON.stringify({version:chosen.rehabPlanning?rehabPlanningVersion:chosen.mutation?(chosen.operational?operationalVersion:mutationVersion):version,playerId:id,createdAt:chosen.createdAt??Date.now(),before,after,markers,...(chosen.mutation?{mutation:chosen.mutation}:{})});
      const j=parse(raw,id);
      await validateTransition(j,snap,id,verifyOptions);
      unchanged();
      if(chosen.recheck)chosen.recheck();
      store.setItem(jk,raw);
      if(store.getItem(jk)!==raw)throw Error("Could not persist calendar journal");
      try{
        for(let i=0;i<dest.length;i++){
          assertCurrent(store,id,raw,isCurrent,markers);
          if(store.getItem(dest[i])!==vals(before)[i])throw Error("Concurrent calendar write");
          write(store,dest[i],vals(after)[i]);
        }
        assertCurrent(store,id,raw,isCurrent,markers);
        if(!status(store,id,raw).complete||!same(other(snapshot(store,id,raw)),other(snap)))throw Error("Calendar recovery incomplete");
        store.removeItem(jk);
        if(store.getItem(jk)!==null)throw Error("Could not clear calendar journal");
      }catch{throw Error("Calendar write interrupted; journal retained for review");}
      return {status:"applied",selected:chosen.selected};
    });
  }
  async function apply(store,playerId,local,incoming,decisions,isCurrent,locks,options={}){
    const id=tornAccountStorage.owner(playerId),{base=null}=options;
    local=copy(local);incoming=copy(incoming);decisions=copy(decisions);
    const common=base===null?null:copy(base);
    return transact(store,id,local,isCurrent,locks,options,async verifyOptions=>{
      const resolved=await tornCalendarMerge.resolve(local,incoming,id,decisions,{...verifyOptions,base:common});
      return {value:resolved.change?.value??null,selected:resolved.selected,removed:[],mutation:null,importedTokens:[incoming,common].filter(Boolean).flatMap(s=>s.manifest.entries.flatMap(x=>[x.revision,...x.ancestors]))};
    });
  }
  // This is an explicit ordinary local edit path, not a merge decision.
  // Only already tracked snapshots may use it. New account bootstrap
  // and all operational calendar writers still require separate design.
  async function mutateLocal(store,playerId,local,change,isCurrent,locks,options,operational){
    const id=tornAccountStorage.owner(playerId);
    local=copy(local);change=copy(change);
    if(!exact(change,["id","kind","before","after"])||typeof change.id!=="string"||!change.id||!["add","edit","remove"].includes(change.kind))throw Error("Invalid explicit calendar mutation");
    return transact(store,id,local,isCurrent,locks,options,async verifyOptions=>{
      await tornAccountRevisions.verify(local.manifest,local.records,id,verifyOptions);
      const prior=sectionValue(local),rows=JSON.parse(prior??"[]"),existing=rows.find(x=>x.id===change.id)??null;
      if(!same(existing,change.before)||change.after!==null&&change.after?.id!==change.id)throw Error("Calendar mutation changed; review again");
      const next=change.kind==="remove"?rows.filter(x=>x.id!==change.id):existing===null?[...rows,change.after]:rows.map(x=>x.id===change.id?change.after:x);
      if(change.kind==="remove"&&change.after!==null)throw Error("Invalid explicit deletion");
      const value=JSON.stringify(next),mutation={id:change.id,kind:change.kind};
      tornAccountStorage.validRecords(other(local).concat({section,value}),id);
      const removed=validateMutation(prior,value,mutation,operational);
      return {value,selected:[change.id],removed,mutation,operational,importedTokens:[]};
    });
  }
  const mutate=(store,id,local,change,isCurrent,locks,options={})=>mutateLocal(store,id,local,change,isCurrent,locks,options,false);
  // Separate explicit entrypoint. Not callable through the backup merge UI.
  const mutateOperational=(store,id,local,change,isCurrent,locks,options={})=>mutateLocal(store,id,local,change,isCurrent,locks,options,true);
  // The caller supplies an explicit change and, for a non-null baseline,
  // a synchronous owner-bound observation from the verified connection.
  // It must not fetch, mutate storage or return a credential.
  async function planRehab(store,playerId,local,change,getBaseline,isCurrent,locks,options={}){
    const id=tornAccountStorage.owner(playerId);
    local=copy(local);change=copy(change);
    if(!exact(change,["id","kind","before","after"])||typeof change.id!=="string"||!change.id||!["add","remove"].includes(change.kind))throw Error("Explicit rehab reservation or cancellation required");
    return transact(store,id,local,isCurrent,locks,options,async verifyOptions=>{
      await tornAccountRevisions.verify(local.manifest,local.records,id,verifyOptions);
      const createdAt=Date.now(),prior=sectionValue(local),rows=JSON.parse(prior??"[]"),existing=rows.find(x=>x.id===change.id)??null;
      if(!same(existing,change.before)||change.kind==="add"&&(existing!==null||change.after?.id!==change.id)||change.kind==="remove"&&(existing===null||change.after!==null))throw Error("Rehab reservation changed; review again");
      const value=JSON.stringify(change.kind==="add"?[...rows,change.after]:rows.filter(x=>x.id!==change.id)),mutation={id:change.id,kind:change.kind};
      tornAccountStorage.validRecords(other(local).concat({section,value}),id);
      const removed=validateRehabPlanning(prior,value,mutation,local,createdAt);
      const checkBaseline=()=>{
        if(change.kind==="add"&&change.after.rehabBaseline!==null){
          const v=typeof getBaseline==="function"?getBaseline():null,b=change.after.rehabBaseline;
          if(!exact(v,["playerId","count","cost","at"])||v.playerId!==id||v.count!==b.count||v.cost!==b.cost||v.at!==b.at)throw Error("Verified rehab baseline changed or unavailable");
        }
      };
      checkBaseline();
      const recheck=()=>{
        const now=Date.now();
        if(now<createdAt||now-createdAt>5000)throw Error("Rehab planning decision expired; review again");
        checkBaseline();validateRehabPlanning(prior,value,mutation,local,now);
      };
      return {value,selected:[change.id],removed,mutation,rehabPlanning:true,createdAt,recheck,importedTokens:[]};
    });
  }
  async function recover(store,playerId,raw,mode,isCurrent,locks,{digest}={}){
    const id=tornAccountStorage.owner(playerId);
    if(!["finish","rollback"].includes(mode))throw Error("Invalid calendar recovery action");
    return locked(id,locks,async()=>{
      const j=parse(raw,id),jk=tornAccountStorage.journalKey(id),dest=keys(id);
      assertCurrent(store,id,raw,isCurrent,j.markers);
      const initial=status(store,id,raw);
      if(initial.conflict||mode==="finish"&&!initial.complete)throw Error("Conflicting or incomplete calendar journal; preserve for review");
      const snap=snapshot(store,id,raw),values=dest.map(k=>store.getItem(k));
      await validateTransition(j,snap,id,digest?{digest}:{});
      assertCurrent(store,id,raw,isCurrent,j.markers);
      if(!same(values,dest.map(k=>store.getItem(k)))||!same(snap,snapshot(store,id,raw)))throw Error("Local account changed during calendar recovery");
      if(mode==="rollback"){
        for(let i=dest.length-1;i>=0;i--){
          assertCurrent(store,id,raw,isCurrent,j.markers);
          const value=store.getItem(dest[i]);
          if(value!==vals(j.before)[i]&&value!==vals(j.after)[i])throw Error("Concurrent calendar change; journal retained");
          if(value!==vals(j.before)[i])write(store,dest[i],vals(j.before)[i]);
        }
      }
      assertCurrent(store,id,raw,isCurrent,j.markers);
      if(!same(dest.map(k=>store.getItem(k)),vals(mode==="finish"?j.after:j.before))||!same(other(snapshot(store,id,raw)),other(snap)))throw Error("Calendar recovery incomplete; journal retained");
      store.removeItem(jk);
      if(store.getItem(jk)!==null)throw Error("Could not clear calendar journal");
      return {status:mode==="finish"?"finalized":"rolled-back"};
    });
  }
  return Object.freeze({version,mutationVersion,operationalVersion,rehabPlanningVersion,lineageKey,read,apply,mutate,mutateOperational,planRehab,recover});
})();
