"use strict";
/* Section revision ancestry. No timestamps as conflict winners.
 * Capture observes changes since the previous snapshot, not every write.
 * Missing untracked sections mean unknown, never a deletion. */
const tornAccountRevisions=(()=>{
  const version=1,maxSections=1500,maxParents=32,hex=/^[0-9a-f]{64}$/,token=/^[0-9a-f]{32}$/;
  const exact=(x,ks)=>x!==null&&typeof x==="object"&&!Array.isArray(x)&&Object.keys(x).length===ks.length&&ks.every(k=>Object.hasOwn(x,k));
  const owner=id=>tornAccountStorage.owner(id);
  const key=id=>"torn-city-guide:account-revisions:v1:"+owner(id);
  const validDigest=x=>x===null||typeof x==="string"&&hex.test(x);
  const validToken=x=>typeof x==="string"&&token.test(x);
  function validate(manifest,id){
    id=owner(id);
    if(!exact(manifest,["version","playerId","entries"])||manifest.version!==version||manifest.playerId!==id||!Array.isArray(manifest.entries)||manifest.entries.length>maxSections)throw Error("Invalid revision manifest or owner");
    const sections=new Set(),revs=new Set();
    for(const e of manifest.entries){
      if(!exact(e,["section","revision","digest","ancestors"])||!tornAccountStorage.knownSection(id,e.section)||sections.has(e.section)||!validToken(e.revision)||revs.has(e.revision)||!validDigest(e.digest)||!Array.isArray(e.ancestors)||e.ancestors.length>maxParents||!e.ancestors.every(validToken)||new Set(e.ancestors).size!==e.ancestors.length||e.ancestors.includes(e.revision))throw Error("Invalid revision entry");
      sections.add(e.section);revs.add(e.revision);
    }
    return manifest;
  }
  function map(m){return new Map(m.entries.map(e=>[e.section,e]));}
  function empty(id){return {version,playerId:owner(id),entries:[]};}
  function read(store,id){const raw=store.getItem(key(id));if(raw===null)return empty(id);if(raw.length>2000000)throw Error("Revision manifest too large");return validate(JSON.parse(raw),id);}
  async function hash(value){
    if(!globalThis.crypto?.subtle)throw Error("Web Crypto unavailable for revision tracking");
    const bytes=await globalThis.crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));
    return Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,"0")).join("");
  }
  function revision(){
    if(!globalThis.crypto?.getRandomValues)throw Error("Secure random unavailable for revision tracking");
    return Array.from(globalThis.crypto.getRandomValues(new Uint8Array(16)),b=>b.toString(16).padStart(2,"0")).join("");
  }
  async function digests(records,id,digest=hash){
    tornAccountStorage.validRecords(records,id);
    const entries=await Promise.all(records.map(async r=>[r.section,await digest(r.value)]));
    if(entries.some(([,v])=>typeof v!=="string"||!hex.test(v)))throw Error("Invalid section digest");
    return new Map(entries);
  }
  async function verify(manifest,records,id,{digest=hash}={}){
    validate(manifest,id);
    const actual=await digests(records,id,digest),entries=map(manifest);
    for(const [section,value] of actual)if(entries.get(section)?.digest!==value)throw Error("Revision digest does not match section: "+section);
    for(const e of manifest.entries)if(e.digest!==null&&!actual.has(e.section)||e.digest===null&&actual.has(e.section))throw Error("Revision presence does not match section: "+e.section);
    return manifest;
  }
  async function observe(previous,snapshot,id,{digest=hash,newRevision=revision}={}){
    validate(previous,id);
    if(!Array.isArray(snapshot?.omitted)||snapshot.omitted.length)throw Error("Cannot track revisions while saved sections are invalid or omitted");
    const actual=await digests(snapshot.records,id,digest),prior=map(previous),sections=new Set([...prior.keys(),...actual.keys()]);
    if(sections.size>maxSections)throw Error("Revision history exceeds section limit; do not discard tombstones");
    const used=new Set(previous.entries.flatMap(e=>[e.revision,...e.ancestors])),entries=[];
    for(const section of [...sections].sort()){
      const old=prior.get(section),value=actual.get(section)??null;
      if(old?.digest===value){entries.push(old);continue;}
      const next=newRevision();
      if(!validToken(next)||used.has(next))throw Error("Revision token collision");
      used.add(next);
      entries.push({section,revision:next,digest:value,ancestors:old?[old.revision,...old.ancestors].slice(0,maxParents):[]});
    }
    return validate({version,playerId:owner(id),entries},id);
  }
  // Ancestry proof is meaningful only within the same section. Truncated
  // ancestry becomes a conflict, not permission to pick a newer timestamp.
  function compare(local,incoming,id){
    validate(local,id);validate(incoming,id);
    const a=map(local),b=map(incoming),sections=new Set([...a.keys(),...b.keys()]);
    return [...sections].sort().map(section=>{
      const left=a.get(section),right=b.get(section);
      let status;
      if(!right)status="local-only";
      else if(!left)status="untracked-incoming";
      else if(left.revision===right.revision)status=left.digest===right.digest&&JSON.stringify(left.ancestors)===JSON.stringify(right.ancestors)?"identical":"conflict";
      else if(left.ancestors.includes(right.revision)&&right.ancestors.includes(left.revision))status="conflict";
      else if(left.ancestors.includes(right.revision))status="local-descendant";
      else if(right.ancestors.includes(left.revision))status="incoming-descendant";
      else status="conflict"; // even identical contents may have diverged
      return {section,status,localDeleted:left?.digest===null,incomingDeleted:right?.digest===null};
    });
  }
  // Observe with optimistic recheck. Cooperating callers use Web Locks.
  // No manifest is written when the snapshot/owner/journal changes.
  async function capture(store,id,isCurrent,options={}){
    id=owner(id);
    if(!isCurrent())throw Error("Account changed before revision capture");
    const raw=store.getItem(key(id)),prior=read(store,id),snap=tornAccountStorage.snapshot(store,id);
    const next=await observe(prior,snap,id,options);
    if(!isCurrent()||store.getItem(key(id))!==raw||JSON.stringify(tornAccountStorage.snapshot(store,id))!==JSON.stringify(snap))throw Error("Account changed during revision capture");
    const encoded=JSON.stringify(next);
    if(encoded.length>2000000)throw Error("Revision manifest too large");
    if(raw!==encoded)store.setItem(key(id),encoded);
    if(store.getItem(key(id))!==encoded)throw Error("Revision manifest write not verified");
    return {...snap,manifest:next};
  }
  return {empty,key,read,validate,verify,observe,compare,capture};
})();
