"use strict";
/* L1 pure checkpoint planner. No storage/network; caller must atomically
 * commit accepted records and the proposed checkpoint, after ID conflict check.
 * No all-time completeness assertion, even at an API-reported terminal link.
 */
const tornLogCoverage=(()=>{
  const HEAD_INTERVAL=300000,MAX_CHAIN=2048;
  const anchor=r=>r?{id:r.sourceId,at:r.occurredAt}:null;
  const cursorOk=c=>typeof c==="string"&&/^\d{1,30}$/.test(c);
  const create=playerId=>({version:1,playerId,revision:0,head:null,older:null,olderState:"unstarted",olderTail:null,olderRecent:[],headCheckedAt:null,lastPageAt:null,pending:null,gap:null});
  function task(s,now){
    if(!Number.isSafeInteger(now)||s.gap||s.lastPageAt!==null&&now<s.lastPageAt)return null;
    const make=(kind,cursor)=>({kind,cursor,revision:s.revision,requestedAt:now});
    if(s.pending)return make("catchup",s.pending.cursor);
    if(s.headCheckedAt===null||now-s.headCheckedAt>=HEAD_INTERVAL)return make("head",null);
    if(s.olderState==="more"&&cursorOk(s.older))return make("older",s.older);
    return null;
  }
  const reject=reason=>({ok:false,reason});
  // "more" requires an advancing exact cursor and nonempty page. An empty
  // page with a continuation or a repeating/cyclic cursor is not completion.
  function step(page,used,recent){
    if(page.continuation==="terminal"&&page.cursor===null)return {state:"terminal",cursor:null,recent};
    if(page.continuation!=="more"||!cursorOk(page.cursor)||page.records.length===0)return {state:"unknown",cursor:null,recent};
    if(page.cursor===used||recent.includes(page.cursor))return {state:"unknown",cursor:null,recent};
    if(recent.length>=MAX_CHAIN)return {state:"unknown",cursor:null,recent};
    return {state:"more",cursor:page.cursor,recent:[...recent,page.cursor]};
  }
  function apply(s,t,page){
    if(!t||t.revision!==s.revision||page.playerId!==s.playerId||page.source!=="api-log"||page.schemaVersion!==1||!Array.isArray(page.records)||page.records.length>100||!Number.isSafeInteger(page.observedAt))return reject("stale task or foreign page");
    // Validate task against the current committed checkpoint. A head fetch
    // cannot supersede unfinished catchup. Date comes from decoded receipt.
    if(!Number.isSafeInteger(t.requestedAt)||t.requestedAt>page.observedAt)return reject("invalid request time");
    const expected=task(s,t.requestedAt);
    if(!expected||expected.kind!==t.kind||expected.cursor!==t.cursor)return reject("task no longer current");
    const rows=page.records,first=anchor(rows[0]),last=anchor(rows.at(-1));
    if(rows.some((r,i)=>r.playerId!==s.playerId||r.source!=="api-log"||typeof r.sourceId!=="string"||!Number.isSafeInteger(r.occurredAt)||i>0&&r.occurredAt>rows[i-1].occurredAt))return reject("invalid decoded page");
    const n={...s,revision:s.revision+1,lastPageAt:page.observedAt};
    const gap=reason=>{n.gap=reason;return {ok:true,checkpoint:n,records:rows};};
    const contains=a=>a&&rows.some(r=>r.sourceId===a.id&&r.occurredAt===a.at);
    if(t.kind==="head"){
      const p=step(page,null,[]);
      if(s.headCheckedAt===null||!s.head){
        if(s.headCheckedAt!==null&&!first&&s.olderState!=="terminal")return gap("head coverage unknown");
        n.head=first;n.headCheckedAt=page.observedAt;n.older=p.cursor;n.olderTail=last;n.olderRecent=p.recent;n.olderState=p.state;
        if(p.state==="unknown")return gap("initial cursor unavailable or inconsistent");
      }else if(contains(s.head)){
        n.head=first;n.headCheckedAt=page.observedAt;
        // Head refresh joins the exact previous head. Existing older cursor
        // stays untouched; no unrelated duplicate can certify the bridge.
      }else{
        if(!first||last.at<s.head.at||p.state!=="more")return gap("previous head anchor not reached");
        n.pending={target:s.head,candidate:first,tail:last,cursor:p.cursor,recent:p.recent,headAt:page.observedAt};
      }
    }else if(t.kind==="catchup"){
      const q=s.pending,p=step(page,t.cursor,q.recent);
      if(first&&q.tail&&first.at>q.tail.at)return reject("catchup page out of order");
      if(contains(q.target)){n.head=q.candidate;n.headCheckedAt=q.headAt;n.pending=null;}
      else if(!last||last.at<q.target.at||p.state!=="more")return gap("catchup failed to reach previous head");
      else n.pending={...q,tail:last,cursor:p.cursor,recent:p.recent};
    }else{
      const p=step(page,t.cursor,s.olderRecent);
      if(first&&s.olderTail&&first.at>s.olderTail.at)return reject("older page out of order");
      // Bounded recent-cursor history; stop conservatively at limit rather
      // than forget a cycle. Durable L2 can use a persisted cursor ledger.
      n.older=p.cursor;n.olderState=p.state;n.olderTail=last??s.olderTail;n.olderRecent=p.recent;
      if(p.state==="unknown")return gap("older cursor unavailable, repeated or chain limit");
    }
    return {ok:true,checkpoint:n,records:rows};
  }
  return Object.freeze({HEAD_INTERVAL,MAX_CHAIN,create,task,apply});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogCoverage;
