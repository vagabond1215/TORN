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
  async function preview(local,incoming,playerId,options={}){
    const id=tornAccountStorage.owner(playerId);
    const plan=await tornAccountRevisions.planMerge(local,incoming,id,options);
    const relation=plan.rows.find(x=>x.section===section)?.status??"absent";
    const left=eventMap(local),right=eventMap(incoming),rows=[];
    for(const key of [...new Set([...left.keys(),...right.keys()])].sort()){
      const before=left.get(key)??null,after=right.get(key)??null;
      const change=canonical(before)===canonical(after)?"unchanged":before===null?"addition":after===null?"removal":"edit";
      let action="review",reason="Record-level ancestry is not established";
      if(change==="unchanged"){action="unchanged";reason="Same event content";}
      else if(relation==="local-descendant"||relation==="local-only"){action="keep-local";reason="Incoming calendar is older or absent";}
      else if(relation==="incoming-descendant"){
        if((before!==null&&!safe(before))||(after!==null&&!safe(after)))reason="Operational or blocking commitment requires separate review";
        else if(change==="removal")reason="Removal requires record deletion evidence; section absence is not a record tombstone";
        else {action="eligible";reason="Nonblocking personal/general event in a proven incoming section descendant; explicit selection required";}
      }
      rows.push({id:key,change,action,reason,before,after});
    }
    return {playerId:id,relation,rows,eligible:rows.filter(x=>x.action==="eligible").map(x=>x.id)};
  }
  // Recompute from verified snapshots, not mutable preview rows.
  // Return candidate bytes only. Preserve all unselected local events.
  async function prepare(local,incoming,playerId,selected,options={}){
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
