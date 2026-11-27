"use strict";
/* P1.1 read-only protected calendar merge planning, never a writer.
 * Section ancestry is not per-record ancestry. No runtime wiring.
 */
const tornCalendarMerge=(()=>{
  const section="calendar-events";
  // Manual war entries can alter deadlines even if not marked blocking.
  const safe=e=>e!==null&&["personal","event"].includes(e.kind)&&e.blocking===false;
  const canonical=e=>e===null?null:JSON.stringify(Object.keys(e).sort().map(k=>[k,e[k]]));
  const eventMap=s=>new Map(JSON.parse(s.records.find(r=>r.section===section)?.value??"[]").map(e=>[e.id,e]));
  // Snapshot copies prevent later caller edits from changing values that
  // have already been asynchronously verified. No storage write follows.
  const copy=s=>JSON.parse(JSON.stringify(s));
  async function preview(local,incoming,playerId,options={}){
    const id=tornAccountStorage.owner(playerId),{base=null,...verifyOptions}=options;
    local=copy(local);incoming=copy(incoming);
    const common=base===null?null:copy(base);
    const plan=await tornAccountRevisions.planMerge(local,incoming,id,verifyOptions);
    const relation=plan.rows.find(x=>x.section===section)?.status??"absent";
    let ancestor=null;
    if(common){
      // The caller supplies a separately authenticated backup; verification
      // here binds its manifest to its records and proves section ancestry.
      // A missing/untracked base or truncated ancestry is not proof.
      const sides=await Promise.all([local,incoming].map(side=>tornAccountRevisions.planMerge(common,side,id,verifyOptions)));
      if(sides.some(side=>!["identical","incoming-descendant"].includes(side.rows.find(x=>x.section===section)?.status)))throw Error("Verified common calendar ancestor required");
      ancestor=eventMap(common);
    }
    const left=eventMap(local),right=eventMap(incoming),rows=[];
    for(const key of [...new Set([...left.keys(),...right.keys()])].sort()){
      const before=left.get(key)??null,after=right.get(key)??null;
      const change=canonical(before)===canonical(after)?"unchanged":before===null?"addition":after===null?"removal":"edit";
      let action="review",reason="Record-level ancestry is not established";
      if(change==="unchanged"){action="unchanged";reason="Same event content";}
      else if(relation==="local-descendant"||relation==="local-only"){action="keep-local";reason="Incoming calendar is older or absent";}
      else {
        const prior=ancestor?.get(key)??null;
        const localChanged=ancestor!==null&&canonical(before)!==canonical(prior);
        const incomingChanged=ancestor!==null&&canonical(after)!==canonical(prior);
        const independent=ancestor!==null&&!localChanged&&incomingChanged&&relation==="conflict";
        if(ancestor!==null&&relation==="conflict"&&!incomingChanged){action="keep-local";reason="Only local event changed from verified base";}
        else if(ancestor!==null&&relation==="conflict"&&localChanged&&incomingChanged)reason="Both event versions changed from verified base; explicit conflict review";
        else if(relation==="incoming-descendant"||independent){
          if((before!==null&&!safe(before))||(after!==null&&!safe(after)))reason="Operational or blocking commitment requires separate review";
          else if(change==="removal")reason="Removal requires record deletion evidence; section absence is not a record tombstone";
          else {action="eligible";reason=independent?"Only incoming nonblocking personal/general event changed from verified base; explicit selection required":"Nonblocking personal/general event in a proven incoming section descendant; explicit selection required";}
        }
      }
      rows.push({id:key,change,action,reason,before,after,...(ancestor!==null?{base:ancestor.get(key)??null}:{})});
    }
    return {playerId:id,relation,commonBase:ancestor!==null,rows,eligible:rows.filter(x=>x.action==="eligible").map(x=>x.id)};
  }
  // Recompute from verified snapshots, not mutable preview rows.
  // Return candidate bytes only. Preserve all unselected local events.
  async function prepare(local,incoming,playerId,selected,options={}){
    local=copy(local);incoming=copy(incoming);
    selected=Array.isArray(selected)?[...selected]:selected;
    const p=await preview(local,incoming,playerId,options);
    if(!Array.isArray(selected)||!selected.length||new Set(selected).size!==selected.length||selected.some(id=>!p.eligible.includes(id)))throw Error("Select only eligible calendar event IDs");
    const before=local.records.find(r=>r.section===section)?.value??null,values=eventMap(local);
    for(const row of p.rows)if(selected.includes(row.id))values.set(row.id,row.after);
    const value=JSON.stringify([...values.values()]);
    tornAccountStorage.validRecords(local.records.filter(r=>r.section!==section).concat({section,value}),p.playerId);
    // Partial selection must get a new local descendant revision, never
    // claim incoming ancestry for records that were not selected.
    return {playerId:p.playerId,change:{section,before,value},selected:[...selected].sort(),relation:p.relation,requiresNewLocalRevision:true};
  }
  return Object.freeze({preview,prepare});
})();
