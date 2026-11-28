"use strict";
/* Isolated encrypted unified Log file. No file I/O, restore, acknowledgment or eviction. */
const tornLogFileCodec=(function codec(records,archive,preview,env){
  const FORMAT="torn-guide-log-archive",VERSION=1,ITERATIONS=600000,MAX_FILE=80*1024*1024,MAX_MANIFEST=8*1024*1024,MAX_PLAIN_CHUNK=384*1024;
  const exact=(v,keys)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
  const int=(v,max=Number.MAX_SAFE_INTEGER)=>Number.isSafeInteger(v)&&v>=0&&v<=max;
  const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const enc=v=>new env.TextEncoder().encode(v),dec=v=>new env.TextDecoder("utf-8",{fatal:true}).decode(v);
  const guardCheck=guard=>{if(typeof guard!=="function"||guard()!==true)throw Error("Archive authorization changed");};
  const b64=v=>{let s="";for(let i=0;i<v.length;i+=8192)s+=String.fromCharCode(...v.subarray(i,i+8192));return env.btoa(s);};
  function un64(v,max){
    if(typeof v!=="string"||v.length>Math.ceil(max/3)*4||v.length%4||/[^A-Za-z0-9+/=]/.test(v))throw Error("Invalid archive encoding");
    let bytes;try{bytes=Uint8Array.from(env.atob(v),c=>c.charCodeAt(0));}catch{throw Error("Invalid archive encoding");}
    if(bytes.length>max||b64(bytes)!==v)throw Error("Invalid archive encoding");
    return bytes;
  }
  function cryptoReady(){
    if(!env.crypto?.subtle||typeof env.crypto.getRandomValues!=="function")throw Error("Secure Web Crypto required");
    return env.crypto;
  }
  async function keyFor(secret,salt){
    if(typeof secret!=="string"||secret.length<12||secret.length>1024)throw Error("Use an independent recovery passphrase of at least 12 characters");
    const c=cryptoReady(),base=await c.subtle.importKey("raw",enc(secret),"PBKDF2",false,["deriveKey"]);
    return c.subtle.deriveKey({name:"PBKDF2",hash:"SHA-256",salt,iterations:ITERATIONS},base,{name:"AES-GCM",length:256},false,["encrypt","decrypt"]);
  }
  const ivFor=(prefix,index)=>{const iv=new Uint8Array(12);iv.set(prefix);new DataView(iv.buffer).setUint32(8,index);return iv;};
  const aad=(h,owner,index)=>enc(JSON.stringify([h.format,h.version,h.kdf,h.iterations,h.salt,h.nonce,owner,index]));
  const hash=async bytes=>b64(new Uint8Array(await cryptoReady().subtle.digest("SHA-256",bytes)));
  async function seal(h,owner,prefix,key,index,bytes){
    return b64(new Uint8Array(await cryptoReady().subtle.encrypt({name:"AES-GCM",iv:ivFor(prefix,index),additionalData:aad(h,owner,index),tagLength:128},key,bytes)));
  }
  async function open(h,owner,prefix,key,index,value,max){
    const bytes=un64(value,max+16);
    if(bytes.length<16)throw Error("Invalid archive ciphertext");
    try{return new Uint8Array(await cryptoReady().subtle.decrypt({name:"AES-GCM",iv:ivFor(prefix,index),additionalData:aad(h,owner,index),tagLength:128},key,bytes));}
    catch{throw Error("Incorrect passphrase, owner or damaged archive");}
  }
  function reviewCheck(review,owner){
    const a=review?.api,c=review?.companion,keys=["playerId","source","version","generation","count","bytes","checkpoint","blocked"];
    if(Object.hasOwn(a??{},"consent"))keys.push("consent");
    if(!exact(review,["api","companion"])||!exact(a,keys)||!exact(c,["playerId","source","version","revision","count","bytes"])||
      a.playerId!==owner||c.playerId!==owner||a.source!=="api-log"||c.source!==records.COMPANION||a.version!==1||c.version!==1||
      !int(a.generation)||!int(c.revision)||!archive.validCheckpoint(a.checkpoint,owner)||
      !(a.blocked===null||typeof a.blocked==="string"&&a.blocked.length>0&&a.blocked.length<=160)||
      Object.hasOwn(a,"consent")&&typeof a.consent!=="boolean"||
      ![a,c].every(s=>int(s.count,archive.MAX_RECORDS)&&int(s.bytes,archive.MAX_BYTES))||
      a.count+c.count>archive.MAX_RECORDS||a.bytes+c.bytes>archive.MAX_BYTES)throw Error("Invalid archive review");
  }
  function checkChunks(chunks,review,owner){
    reviewCheck(review,owner);
    if(!Array.isArray(chunks)||chunks.length>archive.MAX_RECORDS)throw Error("Invalid archive chunks");
    const seen=new Set(),last={},counts={"api-log":0,[records.COMPANION]:0},sizes={"api-log":0,[records.COMPANION]:0};
    let companionStarted=false;
    for(let i=0;i<chunks.length;i++){
      const c=chunks[i];
      if(!exact(c,["index","count","records","source"])||c.index!==i||!["api-log",records.COMPANION].includes(c.source)||!Array.isArray(c.records)||c.count!==c.records.length||!c.count||c.count>preview.MAX_CHUNK_ROWS)throw Error("Invalid archive chunk");
      if(c.source===records.COMPANION)companionStarted=true;
      else if(companionStarted)throw Error("Invalid archive source order");
      let chunkBytes=2;
      for(const row of c.records){
        const valid=c.source==="api-log"?records.validRecord(row,owner):records.validCompanion(row,owner);
        if(!valid)throw Error("Invalid archive record");
        const id=JSON.stringify([c.source,row.sourceId]),prior=last[c.source];
        if(seen.has(id)||prior&&(row.occurredAt>prior.occurredAt||row.occurredAt===prior.occurredAt&&row.sourceId>=prior.sourceId))throw Error("Duplicate or unordered archive record");
        seen.add(id);last[c.source]=row;
        const size=2*JSON.stringify(row).length;
        sizes[c.source]+=size;counts[c.source]++;chunkBytes+=size+2;
        const state=c.source==="api-log"?review.api:review.companion;
        if(counts[c.source]>state.count||sizes[c.source]>state.bytes||chunkBytes>preview.MAX_CHUNK)throw Error("Archive count or size exceeded");
      }
    }
    for(const state of [review.api,review.companion])if(counts[state.source]!==state.count||sizes[state.source]!==state.bytes)throw Error("Archive count or size mismatch");
  }
  async function encode(store,playerId,reviewed,approved,guard,secret,now=Date.now()){
    const owner=records.owner(playerId);
    if(approved!==true)throw Error("Explicit export review required");
    guardCheck(guard);
    if(!int(now,8640000000000000))throw Error("Invalid archive date");
    const snapshot=await preview.prepareUnified(store,owner,reviewed,true,guard);
    const {review,chunks}=snapshot;
    checkChunks(chunks,review,owner);
    const c=cryptoReady(),salt=c.getRandomValues(new Uint8Array(16)),prefix=c.getRandomValues(new Uint8Array(8));
    const h={format:FORMAT,version:VERSION,kdf:"PBKDF2-SHA256",iterations:ITERATIONS,salt:b64(salt),nonce:b64(prefix)};
    const key=await keyFor(secret,salt),parts=[],descriptors=[];
    for(const chunk of chunks){
      guardCheck(guard);
      const bytes=enc(JSON.stringify(chunk));
      if(bytes.length>MAX_PLAIN_CHUNK)throw Error("Archive chunk too large");
      descriptors.push({index:chunk.index,source:chunk.source,count:chunk.count,digest:await hash(bytes)});
      parts.push(await seal(h,owner,prefix,key,chunk.index+1,bytes));
    }
    const manifest=enc(JSON.stringify({playerId:owner,createdAt:now,review,descriptors}));
    if(manifest.length>MAX_MANIFEST)throw Error("Archive manifest too large");
    const text=JSON.stringify({...h,manifest:await seal(h,owner,prefix,key,0,manifest),chunks:parts});
    if(text.length>MAX_FILE)throw Error("Archive file too large");
    guardCheck(guard);
    if(!same(await store.reviewSources(owner,guard),review))throw Error("Archive changed; review export again");
    guardCheck(guard);
    return text;
  }
  async function decode(text,playerId,secret,approved,guard){
    const owner=records.owner(playerId);
    if(approved!==true)throw Error("Explicit archive review required");
    guardCheck(guard);
    if(typeof text!=="string"||text.length>MAX_FILE)throw Error("Archive file too large");
    let h;try{h=JSON.parse(text);}catch{throw Error("Invalid archive file");}
    if(!exact(h,["format","version","kdf","iterations","salt","nonce","manifest","chunks"])||h.format!==FORMAT||h.version!==VERSION||h.kdf!=="PBKDF2-SHA256"||h.iterations!==ITERATIONS||!Array.isArray(h.chunks)||h.chunks.length>archive.MAX_RECORDS)throw Error("Unsupported or invalid archive format");
    const salt=un64(h.salt,16),prefix=un64(h.nonce,8);
    if(salt.length!==16||prefix.length!==8)throw Error("Invalid archive encryption parameters");
    const key=await keyFor(secret,salt);
    guardCheck(guard);
    const m=JSON.parse(dec(await open(h,owner,prefix,key,0,h.manifest,MAX_MANIFEST)));
    if(!exact(m,["playerId","createdAt","review","descriptors"])||m.playerId!==owner||!int(m.createdAt,8640000000000000)||!Array.isArray(m.descriptors)||m.descriptors.length!==h.chunks.length)throw Error("Invalid archive manifest");
    reviewCheck(m.review,owner);
    const chunks=[];
    for(let i=0;i<h.chunks.length;i++){
      guardCheck(guard);
      const d=m.descriptors[i];
      if(!exact(d,["index","source","count","digest"])||d.index!==i||!["api-log",records.COMPANION].includes(d.source)||!int(d.count,preview.MAX_CHUNK_ROWS)||d.count===0||typeof d.digest!=="string")throw Error("Invalid archive descriptor");
      const bytes=await open(h,owner,prefix,key,i+1,h.chunks[i],MAX_PLAIN_CHUNK);
      if(await hash(bytes)!==d.digest)throw Error("Archive chunk digest mismatch");
      const chunk=JSON.parse(dec(bytes));
      if(chunk?.index!==i||chunk.source!==d.source||chunk.count!==d.count)throw Error("Archive descriptor mismatch");
      chunks.push(chunk);
    }
    checkChunks(chunks,m.review,owner);
    guardCheck(guard);
    return {status:"preview",playerId:owner,createdAt:m.createdAt,review:m.review,chunks,count:m.review.api.count+m.review.companion.count,bytes:m.review.api.bytes+m.review.companion.bytes,evictionAllowed:false};
  }
  return Object.freeze({encode,decode,FORMAT,VERSION,MAX_FILE});
})(
  typeof module!=="undefined"&&module.exports?require("./log-records.js"):tornLogRecords,
  typeof module!=="undefined"&&module.exports?require("./log-archive.js"):tornLogArchive,
  typeof module!=="undefined"&&module.exports?require("./log-export-preview.js"):tornLogExportPreview,
  globalThis
);
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogFileCodec;
