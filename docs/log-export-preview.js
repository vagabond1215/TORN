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
  async function prepare(store,playerId,reviewed,approved,guard){
    const player=records.owner(playerId);
    if(approved!==true)throw Error("Explicit export review required");
    guardCheck(guard);
    if(!reviewed||reviewed.playerId!==player||reviewed.source!=="api-log")throw Error("Owner-bound export review required");
    const before=copy(reviewed);
    const check=async()=>{
      guardCheck(guard);
      const actual=await store.state(player,guard);
      guardCheck(guard);
      if(!same(actual,before))throw Error("Archive changed; review export again");
    };
    await check();
    if(!Number.isSafeInteger(before.count)||before.count<0||before.count>archive.MAX_RECORDS||!Number.isSafeInteger(before.bytes)||before.bytes<0||before.bytes>archive.MAX_BYTES||!archive.validCheckpoint(before.checkpoint,player))throw Error("Invalid archive export metadata");
    const chunks=[],seen=new Set();let after=null,previous=null,count=0,bytes=0,chunk=[],chunkBytes=2;
    const flush=()=>{if(!chunk.length)return;chunks.push({index:chunks.length,count:chunk.length,records:chunk});chunk=[];chunkBytes=2;};
    // readPage is descending by [occurredAt, sourceId]. Check every row,
    // exact cursor, total count/estimated bytes and monotonic state.
    do{
      guardCheck(guard);
      const page=await store.readPage(player,guard,{limit:archive.MAX_READ,after});
      guardCheck(guard);
      if(!page||!Array.isArray(page.records)||page.records.length>archive.MAX_READ)throw Error("Invalid archive export page");
      for(const raw of page.records){
        const row=copy(raw);
        if(!records.validRecord(row,player)||seen.has(row.sourceId)||previous&&(row.occurredAt>previous.occurredAt||row.occurredAt===previous.occurredAt&&row.sourceId>=previous.sourceId))throw Error("Invalid, duplicate or unordered archive export record");
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
    return {status:"preview",playerId:player,source:"api-log",generation:before.generation,checkpoint:copy(before.checkpoint),blocked:before.blocked,count,bytes,chunkCount:chunks.length,chunks,
      coverage:"Stored records only; not proof of complete Torn history.",evictionAllowed:false};
  }
  return Object.freeze({prepare,MAX_CHUNK,MAX_CHUNK_ROWS});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogExportPreview;
