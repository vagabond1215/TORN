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
  return Object.freeze({VERSION,MAX_PAGE,owner,cursor,decodePage,validRecord,identity,canonical,classify,text});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogRecords;
