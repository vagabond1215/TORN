"use strict";
/* L1 pure API-log normalization. No network, persistence, or ledger effects.
 * OpenAPI 6.22.0 UserLog / UserLogsResponse / RequestLinks.
 * Caller supplies a freshly verified player ID; response itself has no owner.
 */
const tornLogRecords=(()=>{
  const VERSION=1,MAX_PAGE=100,EARLIEST=Date.UTC(2004,0,1),LATEST=8640000000000000,SKEW=300000;
  const object=v=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&(Object.getPrototypeOf(v)===Object.prototype||Object.getPrototypeOf(v)===null);
  const own=(v,k)=>Object.hasOwn(v,k);
  const fail=()=>{throw Error("Invalid API log record or page");};
  const owner=v=>typeof v==="number"&&Number.isSafeInteger(v)&&v>0&&v<=999999999999999?String(v):typeof v==="string"&&/^[1-9]\d{0,14}$/.test(v)?v:fail();
  const cursor=v=>typeof v==="string"&&/^\d{1,30}$/.test(v);
  const opaqueId=v=>typeof v==="string"&&/^[\x21-\x7e]{1,200}$/.test(v)&&!v.includes("://");
  const label=(v,n)=>typeof v==="string"&&v.trim().length>0&&v.length<=n&&!/[\x00-\x1f\x7f]/.test(v);
  // Intentionally no arbitrary text, nested data, parameters or raw links.
  // These are lexical numeric candidates, NOT interpreted type semantics.
  // Unknown types remain searchable; L4 must validate exact type/field meaning.
  const fieldNames=Object.freeze(["amount","booster","cost","drug","duration","energy","gym","happiness","happy","item","item_id","medical","money","nerve","points","price","quantity","stat"]);
  function fields(data){
    if(!object(data))fail();
    const out={};
    for(const k of fieldNames){
      if(!own(data,k))continue;
      const v=data[k];
      if(typeof v==="number"&&Number.isFinite(v)&&Math.abs(v)<=Number.MAX_SAFE_INTEGER)out[k]=Object.is(v,-0)?0:v;
    }
    return out;
  }
  const recordKeys=["schemaVersion","decoderVersion","playerId","source","sourceId","occurredAt","typeId","category","title","fields","observedAt"];
  function validRecord(r,playerId){
    return object(r)&&Object.keys(r).length===recordKeys.length&&recordKeys.every(k=>own(r,k))&&r.schemaVersion===VERSION&&r.decoderVersion===VERSION&&r.playerId===playerId&&typeof playerId==="string"&&/^[1-9]\d{0,14}$/.test(playerId)&&r.source==="api-log"&&opaqueId(r.sourceId)&&Number.isSafeInteger(r.observedAt)&&r.observedAt>=EARLIEST&&r.observedAt<=LATEST-SKEW&&Number.isSafeInteger(r.occurredAt)&&r.occurredAt%1000===0&&r.occurredAt>=EARLIEST&&r.occurredAt<=r.observedAt+SKEW&&Number.isInteger(r.typeId)&&r.typeId>0&&r.typeId<=2147483647&&label(r.category,150)&&label(r.title,300)&&object(r.fields)&&Object.entries(r.fields).every(([k,v])=>fieldNames.includes(k)&&typeof v==="number"&&Number.isFinite(v)&&Math.abs(v)<=Number.MAX_SAFE_INTEGER);
  }
  function decodeRow(raw,playerId,now){
    if(!object(raw)||!opaqueId(raw.id)||!Number.isSafeInteger(raw.timestamp)||raw.timestamp<0||!object(raw.details)||!object(raw.params))fail();
    const at=raw.timestamp*1000,d=raw.details;
    if(!Number.isSafeInteger(at)||at<EARLIEST||at>now+SKEW||!Number.isInteger(d.id)||d.id<=0||d.id>2147483647||!label(d.category,150)||!label(d.title,300))fail();
    return {schemaVersion:VERSION,decoderVersion:VERSION,playerId,source:"api-log",sourceId:raw.id,occurredAt:at,typeId:d.id,category:d.category,title:d.title,fields:fields(raw.data),observedAt:now};
  }
  function decodePage(payload,verifiedPlayerId,now=Date.now()){
    const playerId=owner(verifiedPlayerId);
    if(!Number.isSafeInteger(now)||now<EARLIEST||now>LATEST-SKEW||!object(payload)||own(payload,"error")||!Array.isArray(payload.log)||payload.log.length>MAX_PAGE||!object(payload._metadata)||!object(payload._metadata.links))fail();
    const m=payload._metadata,l=m.links,link=v=>v===null||typeof v==="string"&&v.length>0&&v.length<=8192;
    if(!own(l,"prev")||!own(l,"next")||!link(l.prev)||!link(l.next))fail();
    const records=payload.log.map(raw=>decodeRow(raw,playerId,now));
    const ids=new Set();
    for(let i=0;i<records.length;i++){
      if(ids.has(records[i].sourceId)||i>0&&records[i].occurredAt>records[i-1].occurredAt)fail();
      ids.add(records[i].sourceId);
    }
    const exact=cursor(m.nanostamp)?m.nanostamp:null;
    // Only metadata shape is retained, never the URL (may contain credentials).
    // A null older link is a reported terminal hint, not all-time coverage.
    const continuation=l.prev!==null&&exact!==null?"more":l.prev===null&&!own(m,"nanostamp")?"terminal":"unknown";
    return {playerId,source:"api-log",schemaVersion:VERSION,observedAt:now,records,cursor:exact,continuation};
  }
  const identity=r=>JSON.stringify([r.playerId,r.source,r.sourceId]);
  // Compare relevant canonical values, not receipt time. Field order fixed.
  const canonical=r=>JSON.stringify([r.schemaVersion,r.decoderVersion,r.playerId,r.source,r.sourceId,r.occurredAt,r.typeId,r.category,r.title,fieldNames.filter(k=>own(r.fields,k)).map(k=>[k,r.fields[k]])]);
  function classify(existing,incoming){
    if(!existing)return "insert";
    if(identity(existing)!==identity(incoming))throw Error("Log identity mismatch");
    return canonical(existing)===canonical(incoming)?"duplicate":"conflict";
  }
  const text=r=>[r.category,r.title,Object.entries(r.fields).map(([k,v])=>k+": "+v).join(", ")].filter(Boolean).join(" · ");
  // Legacy companion snapshots report a maximum observed multiplicity,
  // not authoritative IDs or complete coverage. Keep source independent.
  const COMPANION="companion-log",MAX_COMPANION_PACKET=2000;
  const cleanCompanion=v=>v.replace(/\s+/g," ").trim()
    .replace(/\b((?:api[ _-]?key|access[ _-]?token|password|session[ _-]?token|authorization|cookie)\s*[:=]\s*)\S+/gi,"$1[redacted]")
    .replace(/\bBearer\s+[^\s,;]+/gi,"Bearer [redacted]")
    .replace(/([?&](?:key|api_key|token|access_token)=)[^\s&#]+/gi,"$1[redacted]");
  const companionKeys=["schemaVersion","playerId","source","sourceId","occurredAt","text","occurrence","observedAt"];
  const hashId=v=>typeof v==="string"&&/^[a-f0-9]{64}$/.test(v);
  function validCompanion(r,playerId){
    return object(r)&&Object.keys(r).length===companionKeys.length&&companionKeys.every(k=>own(r,k))&&r.schemaVersion===VERSION&&r.playerId===playerId&&typeof playerId==="string"&&/^[1-9]\d{0,14}$/.test(playerId)&&r.source===COMPANION&&Number.isSafeInteger(r.observedAt)&&r.observedAt>=EARLIEST&&r.observedAt<=LATEST-SKEW&&Number.isSafeInteger(r.occurredAt)&&r.occurredAt>=EARLIEST&&r.occurredAt<=r.observedAt+SKEW&&Number.isInteger(r.occurrence)&&r.occurrence>=1&&r.occurrence<=MAX_COMPANION_PACKET&&typeof r.sourceId==="string"&&hashId(r.sourceId.split(":")[0])&&r.sourceId===r.sourceId.split(":")[0]+":"+String(r.occurrence).padStart(4,"0")&&typeof r.text==="string"&&r.text.length>0&&r.text.length<=1200&&cleanCompanion(r.text)===r.text;
  }
  async function companionDigest(v){
    const digest=await globalThis.crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));
    return Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,"0")).join("");
  }
  async function decodeCompanion(packet,verifiedPlayerId,now=Date.now(),digest=companionDigest){
    const playerId=owner(verifiedPlayerId);
    if(!Number.isSafeInteger(now)||now<EARLIEST||now>LATEST-SKEW||!object(packet)||packet.version!==1||owner(packet.playerId)!==playerId||!Number.isSafeInteger(packet.capturedAt)||packet.capturedAt<EARLIEST||packet.capturedAt>now+5000||!Array.isArray(packet.rows)||packet.rows.length>MAX_COMPANION_PACKET)throw Error("Invalid or foreign companion snapshot");
    const capturedAt=packet.capturedAt,grouped=new Map();
    for(const raw of packet.rows){
      if(!object(raw)||!Number.isSafeInteger(raw.at)||raw.at<EARLIEST||raw.at>capturedAt+SKEW||typeof raw.text!=="string"||raw.text.length>1200)throw Error("Invalid companion row");
      const text=cleanCompanion(raw.text);
      if(!text||text.length>1200||/[\x00-\x1f\x7f]/.test(text))throw Error("Invalid companion text");
      const key=JSON.stringify([playerId,raw.at,text]);
      if(!grouped.has(key))grouped.set(key,{at:raw.at,text,count:0});
      grouped.get(key).count++;
    }
    const out=[],ids=new Set();
    for(const [key,g] of grouped){
      const hash=await digest(key);
      if(!hashId(hash))throw Error("Invalid companion identity digest");
      for(let occurrence=1;occurrence<=g.count;occurrence++){
        const sourceId=hash+":"+String(occurrence).padStart(4,"0");
        if(ids.has(sourceId))throw Error("Companion identity collision");
        ids.add(sourceId);
        const row={schemaVersion:VERSION,playerId,source:COMPANION,sourceId,occurredAt:g.at,text:g.text,occurrence,observedAt:capturedAt};
        if(!validCompanion(row,playerId))throw Error("Invalid normalized companion record");
        out.push(row);
      }
    }
    return out.sort((a,b)=>b.occurredAt-a.occurredAt||(a.sourceId<b.sourceId?1:a.sourceId>b.sourceId?-1:0));
  }
  function classifyCompanion(existing,incoming){
    if(!existing)return "insert";
    if(identity(existing)!==identity(incoming))throw Error("Companion identity mismatch");
    return existing.occurredAt===incoming.occurredAt&&existing.text===incoming.text&&existing.occurrence===incoming.occurrence?"duplicate":"conflict";
  }
  return Object.freeze({VERSION,MAX_PAGE,owner,cursor,decodePage,validRecord,identity,canonical,classify,text,COMPANION,MAX_COMPANION_PACKET,validCompanion,decodeCompanion,classifyCompanion});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogRecords;
