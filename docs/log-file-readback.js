"use strict";
/* Isolated manual readback; no write, restore, persisted receipt or eviction. */
const tornLogFileReadback=(function readback(records,preview,codec,env){
  const pending=new WeakMap();
  const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const check=guard=>{if(typeof guard!=="function"||guard()!==true)throw Error("Archive authorization changed");};
  const approved=v=>{if(v!==true)throw Error("Explicit file review required");};
  async function digest(bytes){
    if(!env.crypto?.subtle)throw Error("Secure Web Crypto required");
    return Array.from(new Uint8Array(await env.crypto.subtle.digest("SHA-256",bytes)),b=>b.toString(16).padStart(2,"0")).join("");
  }
  async function current(store,owner,review,guard){
    check(guard);
    const actual=await store.reviewSources(owner,guard);
    check(guard);
    if(!same(actual,review))throw Error("Archive changed; review export again");
  }
  // In-memory staging only: no persisted proof, key, passphrase or file handle.
  async function prepare(store,playerId,reviewed,consent,guard,secret,now=Date.now()){
    approved(consent);check(guard);
    const owner=records.owner(playerId),review=JSON.parse(JSON.stringify(reviewed));
    const text=await codec.encode(store,owner,review,true,guard,secret,now);
    check(guard);
    const bytes=new env.TextEncoder().encode(text);
    if(bytes.length>codec.MAX_FILE)throw Error("Archive file too large");
    const hash=await digest(bytes);
    await current(store,owner,review,guard);check(guard);
    const ticket=Object.freeze({});
    pending.set(ticket,{store,owner,review,guard,hash,size:bytes.length,createdAt:now});
    return {status:"prepared",ticket,text,evictionAllowed:false};
  }
  function cancel(ticket){pending.delete(ticket);}
  async function verify(ticket,file,playerId,secret,consent,guard){
    approved(consent);check(guard);
    const stage=pending.get(ticket),owner=records.owner(playerId);
    if(!stage||stage.owner!==owner)throw Error("Unknown or foreign export review");
    const active=()=>pending.get(ticket)===stage&&stage.guard()===true&&guard()===true;
    check(active);
    // Require a File rather than a string or arbitrary reader callback.
    // A native File can still be constructed in memory: this API does not
    // attest to the physical disk, picker provenance or future availability.
    if(typeof env.File!=="function"||typeof env.Blob!=="function"||!(file instanceof env.File))throw Error("Reselect the encrypted archive file");
    let size;
    try{
      Object.getOwnPropertyDescriptor(env.File.prototype,"name").get.call(file);
      size=Object.getOwnPropertyDescriptor(env.Blob.prototype,"size").get.call(file);
    }catch{throw Error("Invalid archive file");}
    if(!Number.isSafeInteger(size)||size<=0||size>codec.MAX_FILE||size!==stage.size)throw Error("Archive file size mismatch");
    await current(stage.store,owner,stage.review,active);
    const bytes=new Uint8Array(await env.Blob.prototype.arrayBuffer.call(file));
    check(active);
    if(bytes.length!==size||await digest(bytes)!==stage.hash)throw Error("Archive file differs from prepared export");
    check(active);
    const text=new env.TextDecoder("utf-8",{fatal:true,ignoreBOM:true}).decode(bytes);
    if(text.length!==bytes.length)throw Error("Invalid archive file encoding");
    const decoded=await codec.decode(text,owner,secret,true,active);
    check(active);
    if(decoded.createdAt!==stage.createdAt||!same(decoded.review,stage.review))throw Error("Archive manifest differs from reviewed export");
    // Compare exact source records, not just counts, timestamps or IDs.
    const snapshot=await preview.prepareUnified(stage.store,owner,stage.review,true,active);
    check(active);
    if(decoded.count!==snapshot.count||decoded.bytes!==snapshot.bytes||!same(decoded.chunks,snapshot.chunks))throw Error("Archive records differ from reviewed source");
    await current(stage.store,owner,stage.review,active);check(active);
    return {status:"verified-readback",playerId:owner,createdAt:stage.createdAt,review:JSON.parse(JSON.stringify(stage.review)),count:decoded.count,bytes:decoded.bytes,fileDigest:stage.hash,evictionAllowed:false};
  }
  return Object.freeze({prepare,verify,cancel});
})(
  typeof module!=="undefined"&&module.exports?require("./log-records.js"):tornLogRecords,
  typeof module!=="undefined"&&module.exports?require("./log-export-preview.js"):tornLogExportPreview,
  typeof module!=="undefined"&&module.exports?require("./log-file-codec.js"):tornLogFileCodec,
  globalThis
);
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogFileReadback;
