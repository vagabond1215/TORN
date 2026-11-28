"use strict";
/* Isolated read-only snapshot for future encrypted file export.
 * No download, encryption, import, acknowledgment or eviction authority.
 * Bounded by the existing durable archive limits; never use this on a tick.
 */
const tornLogExportPreview=(()=>{
  const records=typeof module!=="undefined"&&module.exports?require("./log-records.js"):tornLogRecords;
  const archive=typeof module!=="undefined"&&module.exports?require("./log-archive.js"):tornLogArchive;
  const copy=x=>JSON.parse(JSON.stringify(x)),same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const guardCheck=guard=>{if(typeof guard!=="function"||guard()!==true)throw Error("Archive authorization changed");};
  const MAX_CHUNK=256*1024,MAX_CHUNK_ROWS=100;
  async function collect(store,playerId,reviewed,approved,guard,{source="api-log",read="readPage",state="state",validate=records.validRecord}={}){
    const player=records.owner(playerId);
    if(approved!==true)throw Error("Explicit export review required");
    guardCheck(guard);
    if(!reviewed||reviewed.playerId!==player||reviewed.source!==source)throw Error("Owner-bound export review required");
    const before=copy(reviewed);
    const check=async()=>{
      guardCheck(guard);
      const actual=await store[state](player,guard);
      guardCheck(guard);
      if(!same(actual,before))throw Error("Archive changed; review export again");
    };
    await check();
    if(!Number.isSafeInteger(before.count)||before.count<0||before.count>archive.MAX_RECORDS||!Number.isSafeInteger(before.bytes)||before.bytes<0||before.bytes>archive.MAX_BYTES||(source==="api-log"?!archive.validCheckpoint(before.checkpoint,player):!Number.isSafeInteger(before.revision)||before.revision<0))throw Error("Invalid archive export metadata");
    const chunks=[],seen=new Set();let after=null,previous=null,count=0,bytes=0,chunk=[],chunkBytes=2;
    const flush=()=>{if(!chunk.length)return;chunks.push({index:chunks.length,count:chunk.length,records:chunk});chunk=[];chunkBytes=2;};
    // readPage is descending by [occurredAt, sourceId]. Check every row,
    // exact cursor, total count/estimated bytes and monotonic state.
    do{
      guardCheck(guard);
      const page=await store[read](player,guard,{limit:archive.MAX_READ,after});
      guardCheck(guard);
      if(!page||!Array.isArray(page.records)||page.records.length>archive.MAX_READ)throw Error("Invalid archive export page");
      for(const raw of page.records){
        const row=copy(raw);
        if(!validate(row,player)||seen.has(row.sourceId)||previous&&(row.occurredAt>previous.occurredAt||row.occurredAt===previous.occurredAt&&row.sourceId>=previous.sourceId))throw Error("Invalid, duplicate or unordered archive export record");
        seen.add(row.sourceId);previous=row;
        const size=2*JSON.stringify(row).length;
        count++;bytes+=size;
        if(count>before.count||bytes>before.bytes||size+2>MAX_CHUNK)throw Error("Archive export size or count changed");
        if(chunk.length>=MAX_CHUNK_ROWS||chunkBytes+size+2>MAX_CHUNK)flush();
        chunk.push(row);chunkBytes+=size+2;
      }
      if(page.after!==null&&(!page.records.length||!same(page.after,{at:previous.occurredAt,id:previous.sourceId})||same(page.after,after)))throw Error("Invalid archive export cursor");
      after=page.after;
      // A successful read is not a stable snapshot if another tab has
      // committed or purged since review. Never offer partial as complete.
      await check();
    }while(after!==null);
    if(count!==before.count||bytes!==before.bytes)throw Error("Archive export count or bytes mismatch");
    flush();await check();
    return {status:"preview",playerId:player,source,...(source==="api-log"?{generation:before.generation,checkpoint:copy(before.checkpoint),blocked:before.blocked}:{revision:before.revision}),count,bytes,chunkCount:chunks.length,chunks,
      coverage:"Stored records only; not proof of complete Torn history.",evictionAllowed:false};
  }
  const prepare=(store,player,reviewed,approved,guard)=>collect(store,player,reviewed,approved,guard);
  // Source partitions are independently paginated. Every source read is
  // fenced by the exact combined state, including API consent and purge.
  // No cross-source deduplication: equal timestamp/text is not identity.
  async function prepareUnified(store,playerId,reviewed,approved,guard){
    const player=records.owner(playerId);
    if(approved!==true)throw Error("Explicit export review required");
    guardCheck(guard);
    if(!reviewed||reviewed.api?.playerId!==player||reviewed.companion?.playerId!==player||reviewed.api.source!=="api-log"||reviewed.companion.source!==records.COMPANION)throw Error("Owner-bound unified export review required");
    const before=copy(reviewed);
    const check=async()=>{
      guardCheck(guard);
      const actual=await store.reviewSources(player,guard);
      guardCheck(guard);
      if(!same(actual,before))throw Error("Archive changed; review export again");
      return actual;
    };
    await check();
    if(!Number.isSafeInteger(before.api.count)||!Number.isSafeInteger(before.companion.count)||!Number.isSafeInteger(before.api.bytes)||!Number.isSafeInteger(before.companion.bytes)||before.api.count+before.companion.count>archive.MAX_RECORDS||before.api.bytes+before.companion.bytes>archive.MAX_BYTES)throw Error("Combined archive exceeds retention bounds");
    const sourceStore={
      state:async()=> (await check()).api,
      companionState:async()=> (await check()).companion,
      readPage:(p,g,o)=>store.readPage(p,g,o),
      readCompanionPage:(p,g,o)=>store.readCompanionPage(p,g,o)
    };
    const api=await collect(sourceStore,player,before.api,true,guard);
    const companion=await collect(sourceStore,player,before.companion,true,guard,{source:records.COMPANION,state:"companionState",read:"readCompanionPage",validate:records.validCompanion});
    await check();
    const chunks=[...api.chunks.map(c=>({...c,source:api.source})),...companion.chunks.map(c=>({...c,source:companion.source}))].map((c,index)=>({...c,index}));
    return {status:"preview",playerId:player,source:"unified-log",review:before,count:api.count+companion.count,bytes:api.bytes+companion.bytes,chunkCount:chunks.length,chunks,sourceCounts:{api:api.count,companion:companion.count},coverage:"Stored source records only; not proof of complete or unique Torn activity.",evictionAllowed:false};
  }
  return Object.freeze({prepare,prepareUnified,MAX_CHUNK,MAX_CHUNK_ROWS});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogExportPreview;
