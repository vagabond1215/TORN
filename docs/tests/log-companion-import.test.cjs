"use strict";
const assert=require("node:assert/strict"),r=require("../log-records.js");
const now=Date.UTC(2026,10,28),id="1",hashes=new Map(),digest=async key=>{if(!hashes.has(key))hashes.set(key,String(hashes.size+1).padStart(64,"0"));return hashes.get(key);};
const packet=rows=>({version:1,playerId:1,capturedAt:now,rows});
const row={at:now,text:"You trained strength"},other={at:now,text:"Another event"};
async function run(){
 const first=await r.decodeCompanion(packet([row,row,other]),id,now,digest);
 assert.equal(first.length,3);assert.equal(new Set(first.map(v=>v.sourceId)).size,3);
 assert.ok(first.every(v=>r.validCompanion(v,id)));
 const reordered=await r.decodeCompanion({...packet([other,row,row]),capturedAt:now+1000},id,now+1000,digest);
 assert.deepEqual(first.map(v=>v.sourceId),reordered.map(v=>v.sourceId));
 assert.ok(reordered.every(v=>r.classifyCompanion(first.find(x=>x.sourceId===v.sourceId),v)==="duplicate"));
 const increased=await r.decodeCompanion(packet([row,row,row,other]),id,now,digest);
 assert.equal(increased.filter(v=>!first.some(x=>x.sourceId===v.sourceId)).length,1);
 const fewer=await r.decodeCompanion(packet([row]),id,now,digest);
 assert.equal(fewer[0].sourceId,first.find(v=>v.text===row.text&&v.occurrence===1).sourceId);
 const sanitized=await r.decodeCompanion(packet([{at:now,text:"api key: secret Bearer abc"}]),id,now,digest);
 assert.equal(sanitized[0].text,"api key: [redacted] Bearer [redacted]");
 assert.equal(r.classifyCompanion(first[0],{...first[0],text:"different"}),"conflict");
 await assert.rejects(()=>r.decodeCompanion(packet([row]),"2",now,digest),/foreign/);
 await assert.rejects(()=>r.decodeCompanion(packet(Array(2001).fill(row)),id,now,digest),/snapshot/);
 await assert.rejects(()=>r.decodeCompanion(packet([row,{at:now,text:""}]),id,now,digest),/text/);
 await assert.rejects(()=>r.decodeCompanion(packet([row,other]),id,now,async()=>"a".repeat(64)),/collision/);
 console.log("Companion normalization: stable source-local identities, maximum observed multiplicity, repeated imports, redaction, owner and collision refusal passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
