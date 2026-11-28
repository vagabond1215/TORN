"use strict";
/* Isolated authoritative-generation prototype; NOT loaded by index.html.
 * One IDB record per verified owner, one readwrite transaction for CAS.
 * Explicit reviewed initialization, allowlisted preference edits and
 * isolated V7 planning and V6 completion. No localStorage mirror,
 * downgrade, automatic migration, general expense authority,
 * deletion/reset, API request or session activation.
 */
const tornAccountTransactionStore=(()=>{
  const DB_NAME="torn-city-guide:account-state",VERSION=1,STORE="accounts";
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const clone=v=>JSON.parse(JSON.stringify(v)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const owner=id=>tornAccountStorage.owner(id);
  const allowed=section=>tornAccountStorage.mergePreference(section);
  const check=guard=>{if(typeof guard!=="function"||guard()!==true)throw Error("Verified account epoch changed");};
  const safeSize=(raw,max)=>typeof raw==="string"&&raw.length<=max;
  // The raw manifest and lineage bytes are retained, not reconstructed.
  // The snapshot contains all registry records; no arbitrary storage keys.
  function shape(bundle,id){
    if(!exact(bundle,["records","omitted","markers","manifestRaw","lineageRaw"])||
      !Array.isArray(bundle.omitted)||bundle.omitted.length||
      !Array.isArray(bundle.markers)||bundle.markers.length>1500||new Set(bundle.markers).size!==bundle.markers.length||
      bundle.markers.some(s=>!tornAccountStorage.knownSection(id,s))||
      !safeSize(bundle.manifestRaw,2000000)||!safeSize(bundle.lineageRaw,1000000))throw Error("Invalid or incomplete reviewed account bundle");
    tornAccountStorage.validRecords(bundle.records,id);
    const manifest=tornAccountRevisions.validate(JSON.parse(bundle.manifestRaw),id);
    if(bundle.records.some(r=>r.section==="training-session-review")||manifest.entries.some(e=>e.section==="training-session-review"&&e.digest!==null))throw Error("Held or active training requires separate review");
    for(const s of ["calendar-events","activity-spend"]){
      if(bundle.markers.includes(s)||!bundle.records.some(r=>r.section===s)||!manifest.entries.some(e=>e.section===s&&e.digest!==null))throw Error("Missing or deleted protected section: "+s);
    }
    if(bundle.markers.some(s=>!manifest.entries.some(e=>e.section===s)))throw Error("Untracked deletion marker");
    return manifest;
  }
  async function verify(bundle,id,options={}){
    const manifest=shape(bundle,id);
    await tornAccountRevisions.verify(manifest,bundle.records,id,options);
    await tornCalendarLineage.verify(JSON.parse(bundle.lineageRaw),{records:bundle.records,omitted:[],manifest},id,options);
    return manifest;
  }
  function readLegacy(store,id,guard){
    check(guard);
    if(tornAccountStorage.journalPending(store,id))throw Error("Account recovery journal pending");
    if(store.getItem("torn-city-guide:training-session:"+id)!==null||store.getItem(tornTrainingRecovery.reviewKey(id))!==null)throw Error("Active or held training requires review");
    const snap=tornAccountStorage.snapshot(store,id);
    const bundle={...snap,markers:tornAccountStorage.deletionMarkers(store,id),manifestRaw:store.getItem(tornAccountRevisions.key(id)),lineageRaw:store.getItem("torn-city-guide:calendar-lineage:v1:"+id)};
    shape(bundle,id);check(guard);return bundle;
  }
  // Review a fully tracked existing V8-compatible source. Read-only;
  // localStorage is NOT a transactional source and this is not cutover.
  async function reviewLegacy(store,playerId,guard,{digest}={}){
    const id=owner(playerId),before=readLegacy(store,id,guard);
    await verify(before,id,digest?{digest}:{});
    if(!same(readLegacy(store,id,guard),before))throw Error("Legacy source changed; review again");
    return {playerId:id,bundle:clone(before)};
  }
  const record=(id,generation,bundle)=>({version:VERSION,playerId:id,generation,bundle});
  function checked(value,id){
    if(value===undefined)return null;
    if(!exact(value,["version","playerId","generation","bundle"])||value.version!==VERSION||value.playerId!==id||!Number.isSafeInteger(value.generation)||value.generation<1)throw Error("Invalid authoritative account record; review required");
    shape(value.bundle,id);return value;
  }
  // Pure transition builder. No generic caller-controlled after snapshot.
  // A preference can be created, replaced or deleted by exact reviewed
  // value. All other sections, tombstones and lineage remain unchanged.
  async function preparePreference(before,id,change,options={}){
    checked(before,id);
    if(!exact(change,["section","before","after"])||!allowed(change.section)||!tornAccountStorage.knownSection(id,change.section)||
      ![change.before,change.after].every(v=>v===null||typeof v==="string")||change.before===change.after)throw Error("Explicit changed preference required");
    const b=before.bundle,prior=await verify(b,id,options);
    const old=b.records.find(r=>r.section===change.section)?.value??null;
    if(old!==change.before)throw Error("Preference changed; review again");
    const records=b.records.filter(r=>r.section!==change.section);
    if(change.after!==null)records.push({section:change.section,value:change.after});
    records.sort((a,b)=>a.section.localeCompare(b.section));
    const markers=[...new Set([...b.markers,...(change.after===null?[change.section]:[])])].sort();
    const manifest=await tornAccountRevisions.observe(prior,{records,omitted:[],deleted:markers},id,options);
    for(const e of prior.entries)if(e.section!==change.section&&!same(e,manifest.entries.find(x=>x.section===e.section)))throw Error("Unrelated revision changed");
    const bundle={records,omitted:[],markers,manifestRaw:JSON.stringify(manifest),lineageRaw:b.lineageRaw};
    await verify(bundle,id,options);
    if(before.generation===Number.MAX_SAFE_INTEGER)throw Error("Account generation exhausted; review required");
    return record(id,before.generation+1,bundle);
  }
  function open({indexedDB=globalThis.indexedDB,name=DB_NAME}={}){
    if(!indexedDB)return Promise.reject(Error("IndexedDB unavailable"));
    return new Promise((resolve,reject)=>{
      let blocked=false;const req=indexedDB.open(name,VERSION);
      req.onupgradeneeded=e=>{if(e.oldVersion!==0){req.transaction.abort();return;}req.result.createObjectStore(STORE,{keyPath:"playerId"});};
      req.onblocked=()=>{blocked=true;reject(Error("Account database upgrade blocked"));};
      req.onerror=()=>reject(req.error??Error("Account database open failed"));
      req.onsuccess=()=>{if(blocked){req.result.close();return;}resolve(connection(req.result));};
    });
  }
  function connection(db){
    let closed=false;const pending=new Set();
    const checkLive=guard=>{if(closed)throw Error("Account database closed");check(guard);};
    const abortPending=()=>{for(const tx of pending)try{tx.abort();}catch{}};
    const close=()=>{closed=true;abortPending();db.close();};
    db.onversionchange=close;
    function run(id,mode,guard,work){
      return new Promise((resolve,reject)=>{
        let tx;try{checkLive(guard);tx=db.transaction(STORE,mode);}catch(e){reject(e);return;}
        pending.add(tx);let result,failure;
        const abort=e=>{failure=e;try{tx.abort();}catch{}};
        tx.onabort=()=>{pending.delete(tx);reject(failure??tx.error??Error("Account transaction aborted"));};
        // A completed transaction is committed even if the epoch has just
        // rotated. Report committed vs current separately; never tell the
        // caller to blindly retry an already committed write.
        tx.oncomplete=()=>{pending.delete(tx);let current=false;try{checkLive(guard);current=true;}catch{}resolve({...result,current});};
        const on=(request,fn)=>{request.onsuccess=()=>{try{checkLive(guard);fn(request.result);}catch(e){abort(e);}};};
        const done=v=>{checkLive(guard);result=v;};
        try{
          checkLive(guard);const store=tx.objectStore(STORE);
          on(store.get(id),v=>work(checked(v,id),store,on,done));
        }catch(e){abort(e);}
      });
    }
    async function read(playerId,guard,{digest}={}){
      const id=owner(playerId),out=await run(id,"readonly",guard,(value,store,on,done)=>done({status:value?"ready":"absent",record:value}));
      if(!out.current)throw Error(closed?"Account database closed":"Verified account epoch changed");
      if(out.record)await verify(out.record.bundle,id,digest?{digest}:{});
      checkLive(guard);return out;
    }
    async function initialize(store,playerId,review,approved,guard,{digest}={}){
      const id=owner(playerId);
      if(approved!==true||!exact(review,["playerId","bundle"])||review.playerId!==id)throw Error("Explicit owner-bound initialization approval required");
      const proposed=clone(review.bundle),options=digest?{digest}:{};
      await verify(proposed,id,options);
      check(guard);
      // Check again INSIDE the IDB transaction. This is a reviewed copy
      // only; a noncooperating legacy tab can still change localStorage.
      return run(id,"readwrite",guard,(current,dest,on,done)=>{
        if(current){done({status:"already-initialized",generation:current.generation});return;}
        if(!same(readLegacy(store,id,guard),proposed))throw Error("Legacy source changed; review again");
        const next=record(id,1,proposed);
        on(dest.add(next),()=>done({status:"committed",generation:1}));
      });
    }
    async function editPreference(playerId,review,change,approved,guard,options={}){
      const id=owner(playerId);
      if(approved!==true)throw Error("Explicit preference approval required");
      check(guard);
      const before=clone(review),mutation=clone(change);
      checked(before,id);
      const next=await preparePreference(before,id,mutation,options);
      check(guard);
      return run(id,"readwrite",guard,(current,store,on,done)=>{
        // Generation AND full exact reviewed bytes are compared within
        // the same authoritative transaction as the write. No await here.
        if(!current||current.generation!==before.generation||!same(current,before)){done({status:"stale",generation:current?.generation??null});return;}
        on(store.put(next),()=>done({status:"committed",generation:next.generation}));
      });
    }
    // Narrow V7 entrypoint. Never accept an arbitrary caller-built
    // candidate or expose a generic write callback. The scheduler module
    // generates the candidate internally from explicit reviewed evidence.
    async function planRehab(playerId,reviewed,change,approved,readContext,guard,options={}){
      const id=owner(playerId);
      checkLive(guard);
      if(typeof tornSchedulerPersistence==="undefined")throw Error("Scheduler policy adapter unavailable");
      const candidate=await tornSchedulerPersistence.prepare(id,reviewed,change,approved,readContext,guard,options);
      const before=candidate.before,next=candidate.after;
      checkLive(guard);
      return run(id,"readwrite",guard,(current,store,on,done)=>{
        if(!current||current.generation!==before.generation||!same(current,before)){done({status:"stale",generation:current?.generation??null});return;}
        candidate.assertCurrent();
        on(store.put(next),()=>{
          // The request has succeeded, but the transaction has not
          // committed yet. Abort if policy or authorization changed.
          candidate.assertCurrent();
          done({status:"committed",generation:next.generation});
        });
      });
    }
    // Narrow V6-style completion: exact calendar and expense evidence
    // advance together or not at all. Never accept an after bundle.
    async function completeRehab(playerId,reviewed,decision,approved,readContext,guard,options={}){
      const id=owner(playerId);checkLive(guard);
      if(typeof tornRehabTransaction==="undefined")throw Error("Rehab completion adapter unavailable");
      const candidate=await tornRehabTransaction.prepare(id,reviewed,decision,approved,readContext,guard,options);
      checkLive(guard);
      if(candidate.status!=="candidate")return candidate;
      const before=candidate.before,next=candidate.after;
      return run(id,"readwrite",guard,(current,store,on,done)=>{
        if(!current||current.generation!==before.generation||!same(current,before)){done({status:"stale",generation:current?.generation??null});return;}
        candidate.assertCurrent();
        on(store.put(next),()=>{
          candidate.assertCurrent();
          done({status:"committed",generation:next.generation,eventId:candidate.eventId,cost:candidate.cost,attribution:candidate.attribution});
        });
      });
    }
    return Object.freeze({read,initialize,editPreference,planRehab,completeRehab,abortPending,close});
  }
  return Object.freeze({open,reviewLegacy,verify,preparePreference,DB_NAME,VERSION});
})();
