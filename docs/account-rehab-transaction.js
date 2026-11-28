"use strict";
/* Isolated V6-style completion candidate for the authoritative IDB record.
 * No API requests or writes. Explicit reviewed event, cost and evidence.
 * Counter delta is inferred; unknown cost never creates a ledger row.
 */
const tornRehabTransaction=(()=>{
  const calendar="calendar-events",ledger="activity-spend",minute=60000;
  const copy=v=>JSON.parse(JSON.stringify(v)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const integer=v=>Number.isSafeInteger(v)&&v>=0;
  const clock=now=>{if(!integer(now)||!now||now>Date.now()+1000)throw Error("Invalid rehab decision time");return now;};
  const check=guard=>{if(typeof guard!=="function"||guard()!==true)throw Error("Verified account epoch changed");};
  function context(id,read,guard){
    check(guard);
    if(typeof read!=="function")throw Error("Current rehab context required");
    const raw=read();
    if(!exact(raw,["playerId","record","observation","activeTraining","heldTraining","journalPending"])||raw.playerId!==id)throw Error("Invalid or foreign rehab context");
    if(raw.activeTraining!==false||raw.heldTraining!==false||raw.journalPending!==false)throw Error("Training or recovery hold blocks rehab completion");
    const c=copy(raw);
    if(!exact(c.record,["version","playerId","generation","bundle"])||c.record.version!==1||c.record.playerId!==id||!integer(c.record.generation)||c.record.generation<1)throw Error("Verified transactional account review required");
    check(guard);return c;
  }
  async function prepare(playerId,reviewed,decision,approved,read,guard,{now=Date.now,digest,newRevision}={}){
    const id=tornAccountStorage.owner(playerId);
    if(approved!==true)throw Error("Explicit rehab completion approval required");
    const c=context(id,read,guard),review=copy(decision),at=clock(now());
    if(!same(c,reviewed))throw Error("Rehab context changed; review again");
    if(!exact(review,["eventId","cost","evidence"])||typeof review.eventId!=="string"||!review.eventId||!(review.cost===null||integer(review.cost))||!same(review.evidence,c.observation))throw Error("Exact reviewed event, cost and observation required");
    const options={...(digest?{digest}:{}),...(newRevision?{newRevision}:{})};
    const b=c.record.bundle,prior=await tornAccountTransactionStore.verify(b,id,options);
    const before={records:b.records,omitted:[],manifest:prior};
    const candidate=await tornRehabTransition.prepare(before,id,review.evidence,{...options,now:at});
    if(candidate.status!=="candidate"){check(guard);if(!same(context(id,read,guard),c))throw Error("Rehab context changed; review again");return candidate;}
    if(candidate.eventId!==review.eventId||candidate.cost!==review.cost)throw Error("Rehab event or cost changed; review again");
    const original=JSON.parse(b.records.find(x=>x.section===calendar).value).find(x=>x.id===candidate.eventId);
    if(original.blocking!==true||Object.hasOwn(original,"recoveryReview")||Object.hasOwn(original,"rehabCost"))throw Error("Pending unreviewed rehab reservation required");
    if(c.record.generation===Number.MAX_SAFE_INTEGER)throw Error("Account generation exhausted");
    const manifest=await tornAccountRevisions.observe(prior,{records:candidate.records,omitted:[],deleted:b.markers},id,options);
    const changed=new Set(candidate.changes.map(x=>x.section));
    for(const e of prior.entries){
      const next=manifest.entries.find(x=>x.section===e.section);
      if(changed.has(e.section)){
        if(!next||next.revision===e.revision||!same(next.ancestors,[e.revision,...e.ancestors].slice(0,32)))throw Error("Rehab revision is not an immediate descendant");
      }else if(!same(e,next))throw Error("Unrelated revision changed");
    }
    if(!changed.has(calendar)||changed.has(ledger)!==(candidate.cost!==null)||changed.size!==(candidate.cost===null?1:2))throw Error("Unexpected rehab transition");
    const lineage=await tornCalendarLineage.advance(JSON.parse(b.lineageRaw),before,{records:candidate.records,omitted:[],manifest},id,[],options);
    const bundle={records:candidate.records,omitted:[],markers:b.markers,manifestRaw:JSON.stringify(manifest),lineageRaw:JSON.stringify(lineage)};
    await tornAccountTransactionStore.verify(bundle,id,options);
    const assertCurrent=()=>{
      const time=clock(now());
      if(time<at||time-at>5000||time-review.evidence.statsAt>30*minute||time-review.evidence.profileAt>15*minute||time-original.end>24*60*minute)throw Error("Rehab decision or evidence expired; review again");
      if(!same(context(id,read,guard),c))throw Error("Rehab context changed; review again");
      check(guard);return true;
    };
    assertCurrent();
    return {status:"candidate",before:copy(c.record),after:{version:1,playerId:id,generation:c.record.generation+1,bundle:copy(bundle)},eventId:candidate.eventId,cost:candidate.cost,attribution:candidate.attribution,assertCurrent};
  }
  return Object.freeze({prepare});
})();
