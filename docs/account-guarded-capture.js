"use strict";
/* P1.4d.4 isolated guarded capture. Not loaded by index.html.
 * Explicit caller-selected legacy or protected mode; protected calendar
 * and expense bytes may only advance through a reviewed journal writer.
 * Ordinary unrelated preferences remain observable. Never repair lineage,
 * initialize storage, clear markers, or overwrite a pending journal.
 */
const tornGuardedCapture=(()=>{
  const prefix="torn-city-guide:",calendar="calendar-events",ledger="activity-spend",protectedSections=[calendar,ledger];
  const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const lineageKey=id=>prefix+"calendar-lineage:v1:"+id;
  const held=(store,id)=>store.getItem(prefix+"training-session:"+id)!==null||store.getItem(tornTrainingRecovery.reviewKey(id))!==null;
  function check(store,id,isCurrent){
    if(typeof isCurrent!=="function"||isCurrent()!==true)throw Error("Verified account epoch changed");
    if(tornAccountStorage.journalPending(store,id))throw Error("Account recovery journal pending");
    if(held(store,id))throw Error("Active or held training session; capture deferred");
  }
  function readState(store,id,isCurrent){
    check(store,id,isCurrent);
    const raw=store.getItem(tornAccountRevisions.key(id)),lineage=store.getItem(lineageKey(id));
    const snap=tornAccountStorage.snapshot(store,id),markers=tornAccountStorage.deletionMarkers(store,id);
    if(snap.omitted.length)throw Error("Incomplete account snapshot; capture deferred");
    if(lineage!==null&&lineage.length>1000000)throw Error("Calendar lineage too large");
    const prior=tornAccountRevisions.read(store,id);
    return {raw,lineage,snap,markers,prior};
  }
  // Verify the protected projection against the *prior* manifest, not
  // against a freshly observed manifest that could bless unauthorized drift.
  // Unrelated preference records may legitimately differ from that prior.
  function projection(s,id,sections){
    return {records:s.snap.records.filter(r=>sections.includes(r.section)),omitted:[],
      manifest:{...tornAccountRevisions.empty(id),entries:s.prior.entries.filter(e=>sections.includes(e.section))}};
  }
  async function verifyProtected(s,id,options){
    if(s.raw===null||s.lineage===null)throw Error("Protected capture requires tracked calendar lineage and ledger; review migration");
    if(s.markers.some(k=>protectedSections.includes(k)))throw Error("Protected deletion marker requires review");
    const selected=projection(s,id,protectedSections);
    for(const section of protectedSections){
      if(!selected.records.some(r=>r.section===section)||!selected.manifest.entries.some(e=>e.section===section&&e.digest!==null))throw Error("Missing or deleted protected section: "+section);
    }
    await tornAccountRevisions.verify(selected.manifest,selected.records,id,options);
    const c=projection(s,id,[calendar]);
    await tornCalendarLineage.verify(JSON.parse(s.lineage),c,id,options);
  }
  async function capture(store,playerId,isCurrent,locks,{mode,digest,newRevision}={}){
    const id=tornAccountStorage.owner(playerId);
    if(mode!=="legacy"&&mode!=="protected")throw Error("Explicit capture mode required");
    if(typeof locks?.request!=="function")throw Error("Web Locks required for guarded capture");
    check(store,id,isCurrent);
    const options={...(digest?{digest}:{}),...(newRevision?{newRevision}:{})};
    return locks.request(prefix+"account-recovery:"+id,{mode:"exclusive"},async()=>{
      const before=readState(store,id,isCurrent);
      if(mode==="legacy"){
        if(before.lineage!==null)throw Error("Legacy capture refused: calendar lineage installed");
      }else await verifyProtected(before,id,options);
      const next=await tornAccountRevisions.observe(before.prior,{...before.snap,deleted:before.markers},id,options);
      if(mode==="protected"){
        for(const section of protectedSections){
          if(!same(before.prior.entries.find(e=>e.section===section),next.entries.find(e=>e.section===section)))throw Error("Protected revision changed during capture: "+section);
        }
      }
      // Recheck the entire account and exact bytes after every async
      // validation/digest, while holding the cooperative recovery lock.
      if(!same(readState(store,id,isCurrent),before))throw Error("Account changed during guarded capture");
      const encoded=JSON.stringify(next);
      if(encoded.length>2000000)throw Error("Revision manifest too large");
      if(before.raw===null&&!next.entries.length)return {...before.snap,manifest:next,mode,changed:false};
      if(before.raw!==encoded)store.setItem(tornAccountRevisions.key(id),encoded);
      if(store.getItem(tornAccountRevisions.key(id))!==encoded)throw Error("Revision manifest write not verified");
      return {...before.snap,manifest:next,mode,changed:before.raw!==encoded};
    });
  }
  return Object.freeze({capture});
})();
