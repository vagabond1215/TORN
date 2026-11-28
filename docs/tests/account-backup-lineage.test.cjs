"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const {webcrypto}=require("node:crypto");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {api,r,l}=new Function("globalThis",["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-backup.js"].map(read).join("\n")+"\nreturn {api:tornAccountBackup,r:tornAccountRevisions,l:tornCalendarLineage};")({crypto:webcrypto});
const id=123,section="calendar-events",now=Date.UTC(2026,10,27),pass="fixture independent passphrase";
const event=(id,title)=>({id,title,kind:"personal",start:now,end:now+60000,blocking:false,source:"manual"});
async function make(prior,rows){const records=[{section,value:JSON.stringify(rows)}],omitted=[];return {records,omitted,manifest:await r.observe(prior,{records,omitted},id)};}
async function run(){
 const first=await make(r.empty(id),[event("a","private event"),event("b","deleted private event")]);
 const initial=await l.initialize(first,id);
 const next=await make(first.manifest,[event("a","updated private event")]);
 const lineage=await l.advance(initial,first,next,id,["b"]);
 const codec=api.createLineageCodec(l);
 const text=await codec.encrypt(id,next.records,pass,now,next.manifest,lineage);
 const outer=JSON.parse(text);assert.equal(outer.version,3);assert.ok(!text.includes("private event")&&!text.includes("deletedFrom")&&!text.includes(pass));
 const decoded=await codec.decrypt(text,id,pass);assert.deepEqual(decoded.records,next.records);assert.deepEqual(decoded.manifest,next.manifest);assert.deepEqual(decoded.calendarLineage,lineage);
 await assert.rejects(()=>api.decrypt(text,id,pass),/format/);
 assert.throws(()=>api.encrypt(id,next.records,pass,now,next.manifest,lineage),/explicit lineage codec/);
 await assert.rejects(()=>codec.decrypt(text,456,pass),/different Torn account/);
 await assert.rejects(()=>codec.decrypt(text,id,"wrong independent passphrase"),/Incorrect/);
 for(const version of [1,2])await assert.rejects(()=>codec.decrypt(JSON.stringify({...outer,version}),id,pass),/Incorrect/);
 const corrupt=outer.ciphertext;await assert.rejects(()=>codec.decrypt(JSON.stringify({...outer,ciphertext:(corrupt[0]==="A"?"B":"A")+corrupt.slice(1)}),id,pass),/Incorrect/);
 await assert.rejects(()=>codec.encrypt(id,next.records,pass,now,next.manifest,initial),/binding/);
 await assert.rejects(()=>codec.encrypt(id,next.records,pass,now,next.manifest,{...lineage,entries:lineage.entries.filter(x=>x.id!=="a")}),/digest mismatch/);
 assert.throws(()=>codec.encrypt(id,next.records,pass,now,next.manifest,null),/requires/);
 const v2=await api.encrypt(id,next.records,pass,now,next.manifest);
 const old=await codec.decrypt(v2,id,pass);assert.equal(Object.hasOwn(old,"calendarLineage"),false);
 const v1=await api.encrypt(id,next.records,pass,now);assert.equal(Object.hasOwn(await codec.decrypt(v1,id,pass),"manifest"),false);
 // Authenticated ciphertext is still not sufficient for bad lineage schema.
 // This fixture-only verifier deliberately accepts bad metadata at export;
 // actual verified codec must reject it at import.
 const permissive=api.createLineageCodec({verify:async()=>{}});
 const wrong=await permissive.encrypt(id,next.records,pass,now,next.manifest,{...lineage,playerId:"456"});
 await assert.rejects(()=>codec.decrypt(wrong,id,pass),/binding/);
 console.log("Native Web Crypto V3 lineage roundtrip, V1/V2 compatibility, owner/tamper/downgrade rejection and lineage binding passed.");
}
module.exports=run;
if(require.main===module)run().catch(error=>{console.error(error);process.exitCode=1;});
