"use strict";
/* P1.2 isolated deletion-lineage contract. No storage, backup-format or
 * writer integration. A lineage value is NOT authenticated by a section
 * manifest alone; future envelope/journal must authenticate it separately.
 */
const tornCalendarLineage=(()=>{
  const section="calendar-events",VERSION=1,MAX_ENTRIES=2000,hex=/^[0-9a-f]{64}$/,token=/^[0-9a-f]{32}$/;
  const exact=(v,keys)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
  const validId=v=>typeof v==="string"&&v.length>0&&v.length<=160&&!["__proto__","constructor","prototype"].includes(v);
  const copy=v=>JSON.parse(JSON.stringify(v));
  const canonical=e=>JSON.stringify(Object.keys(e).sort().map(k=>[k,e[k]]));
  async function hash(value){
    if(!globalThis.crypto?.subtle)throw Error("Web Crypto unavailable for calendar lineage");
    const bytes=await globalThis.crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));
    return Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,"0")).join("");
  }
  async function eventDigest(e,digest){
    const value=await digest(canonical(e));
    if(typeof value!=="string"||!hex.test(value))throw Error("Invalid calendar event digest");
    return value;
  }
  async function checkedSnapshot(snapshot,playerId,digest){
    const id=tornAccountStorage.owner(playerId);
    if(!Array.isArray(snapshot.omitted)||snapshot.omitted.length)throw Error("Incomplete calendar snapshot");
    await tornAccountRevisions.verify(snapshot.manifest,snapshot.records,id,{digest});
    const entry=snapshot.manifest.entries.find(e=>e.section===section);
    if(!entry)throw Error("Tracked calendar section required");
    const rows=JSON.parse(snapshot.records.find(r=>r.section===section)?.value??"[]");
    const live=new Map(await Promise.all(rows.map(async e=>[e.id,await eventDigest(e,digest)])));
    return {id,entry,live};
  }
  function shape(lineage,id,entry){
    if(!exact(lineage,["version","playerId","sectionRevision","sectionDigest","entries"])||lineage.version!==VERSION||lineage.playerId!==id||lineage.sectionRevision!==entry.revision||lineage.sectionDigest!==entry.digest||!Array.isArray(lineage.entries)||lineage.entries.length>MAX_ENTRIES)throw Error("Invalid calendar lineage binding or size");
    const ids=new Set();
    for(const e of lineage.entries){
      if(!exact(e,["id","digest","deletedFrom","deletedAtRevision"])||!validId(e.id)||ids.has(e.id))throw Error("Invalid calendar lineage entry");
      if(e.digest===null){
        if(typeof e.deletedFrom!=="string"||!hex.test(e.deletedFrom)||typeof e.deletedAtRevision!=="string"||!token.test(e.deletedAtRevision))throw Error("Invalid calendar deletion evidence");
      }else if(typeof e.digest!=="string"||!hex.test(e.digest)||e.deletedFrom!==null||e.deletedAtRevision!==null)throw Error("Invalid live calendar lineage");
      ids.add(e.id);
    }
  }
  function verifyLive(lineage,checked){
    shape(lineage,checked.id,checked.entry);
    const byId=new Map(lineage.entries.map(e=>[e.id,e]));
    for(const [id,digest] of checked.live)if(byId.get(id)?.digest!==digest)throw Error("Calendar lineage live digest mismatch");
    for(const e of lineage.entries)if(e.digest!==null&&!checked.live.has(e.id))throw Error("Calendar lineage live record missing");
    return byId;
  }
  const envelope=(checked,entries)=>({version:VERSION,playerId:checked.id,sectionRevision:checked.entry.revision,sectionDigest:checked.entry.digest,entries:[...entries].sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0)});
  const liveEntry=(id,digest)=>({id,digest,deletedFrom:null,deletedAtRevision:null});
  // Bootstrap has no historical deletion knowledge. Never manufacture it
  // from a legacy backup, an empty calendar, or a missing section.
  async function initialize(snapshot,id,{digest=hash}={}){
    const c=await checkedSnapshot(copy(snapshot),id,digest);
    return envelope(c,[...c.live].map(([key,value])=>liveEntry(key,value)));
  }
  async function verify(lineage,snapshot,id,{digest=hash}={}){
    const l=copy(lineage),c=await checkedSnapshot(copy(snapshot),id,digest);
    verifyLive(l,c);return l;
  }
  // Caller must provide trusted previous lineage and explicitly observed
  // deletion IDs from a guarded writer. Do not infer deletes across gaps.
  // For now this pure function only constructs a candidate lineage.
  async function advance(lineage,previous,next,playerId,deletedIds,{digest=hash}={}){
    const l=copy(lineage),before=copy(previous),after=copy(next),ids=copy(deletedIds);
    if(!Array.isArray(ids)||ids.length>300||!ids.every(validId)||new Set(ids).size!==ids.length)throw Error("Invalid explicit calendar deletions");
    const [a,b]=await Promise.all([checkedSnapshot(before,playerId,digest),checkedSnapshot(after,playerId,digest)]);
    const old=verifyLive(l,a),relation=tornAccountRevisions.compare(before.manifest,after.manifest,a.id).find(x=>x.section===section)?.status;
    if(relation!=="identical"&&(relation!=="incoming-descendant"||b.entry.ancestors[0]!==a.entry.revision))throw Error("Calendar lineage requires an immediate proven descendant");
    const removed=[...a.live.keys()].filter(id=>!b.live.has(id)).sort();
    if(JSON.stringify(removed)!==JSON.stringify([...ids].sort()))throw Error("Calendar removal lacks exact explicit deletion evidence");
    const out=new Map(old);
    for(const key of removed)out.set(key,{id:key,digest:null,deletedFrom:a.live.get(key),deletedAtRevision:b.entry.revision});
    for(const [key,value] of b.live){
      if(old.get(key)?.digest===null)throw Error("Deleted calendar ID cannot be reused; create a new ID");
      out.set(key,liveEntry(key,value));
    }
    if(out.size>MAX_ENTRIES)throw Error("Calendar lineage limit reached; preserve tombstones");
    const result=envelope(b,out.values());
    verifyLive(result,b);return result;
  }
  return Object.freeze({VERSION,MAX_ENTRIES,initialize,verify,advance});
})();
