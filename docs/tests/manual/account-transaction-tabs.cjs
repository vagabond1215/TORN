"use strict";
// Native acceptance candidate, synthetic data only. Separate Chrome pages
// share the SAME IndexedDB origin. No localStorage source is authoritative
// after initialization. No API, no production account, no unsafe flags.
const assert=require("node:assert/strict");
const {randomBytes,randomUUID}=require("node:crypto");
const {mkdtemp,readFile,rm}=require("node:fs/promises");
const {createServer}=require("node:http");
const {tmpdir}=require("node:os");
const {join}=require("node:path");
const {setTimeout:delay}=require("node:timers/promises");
const {chromium}=require("playwright-core");
const modules=["training-recovery","account-storage","account-revisions","account-calendar-lineage","account-transaction-store","account-calendar-merge","account-calendar-journal","activity-scheduler","scheduler-persistence-adapter"];
const assets=new Map(modules.map(n=>["/"+n+".js",n+".js"]));
const server=createServer(async(req,res)=>{
 if(req.url==="/"){res.writeHead(200,{"Content-Type":"text/html"}).end("<!doctype html><title>Transactional account test</title>");return;}
 const asset=assets.get(req.url);if(!asset){res.writeHead(404).end();return;}
 try{res.writeHead(200,{"Content-Type":"text/javascript"}).end(await readFile(join(__dirname,"../..",asset)));}
 catch{res.writeHead(500).end();}
});
async function loadPage(tab,origin){
 await tab.goto(origin);
 for(const module of modules)await tab.addScriptTag({url:origin+module+".js"});
}
async function probe(context,origin,{lifecycle=false,quota=false,rehab=false}={}){
 const tabs=await Promise.all([context.newPage(),context.newPage()]);
 const name="torn-transaction-fixture:"+randomUUID(),id="999999913";
 await Promise.all(tabs.map(async tab=>{
  await loadPage(tab,origin);
  await tab.evaluate(async({name,id})=>{
   const a=tornAccountStorage,r=tornAccountRevisions,l=tornCalendarLineage,g=tornAccountTransactionStore;
   const prefix="torn-city-guide:",note=prefix+"v1:profile:"+id+":notes:gym";
   const m=new Map(),source={get length(){return m.size},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};
   let valid=true,db=await g.open({name});const guard=()=>valid;
   window.fixture={
    review:async()=>{
     source.setItem(prefix+"activity-events:"+id,"[]");source.setItem(prefix+"activity-spend-ledger:"+id,"[]");source.setItem(note,"before");
     const snap=a.snapshot(source,id),manifest=await r.observe(r.empty(id),snap,id);
     source.setItem(r.key(id),JSON.stringify(manifest));source.setItem(prefix+"calendar-lineage:v1:"+id,JSON.stringify(await l.initialize({...snap,manifest},id)));
     return g.reviewLegacy(source,id,guard);
    },
    loadSource:review=>{for(const row of review.bundle.records){
      const key=row.section==="calendar-events"?prefix+"activity-events:"+id:row.section==="activity-spend"?prefix+"activity-spend-ledger:"+id:note;
      source.setItem(key,row.value);
    }source.setItem(r.key(id),review.bundle.manifestRaw);source.setItem(prefix+"calendar-lineage:v1:"+id,review.bundle.lineageRaw);},
    initialize:review=>db.initialize(source,id,review,true,guard),
    read:options=>db.read(id,guard,options),
    edit:({before,after})=>db.editPreference(id,before,{section:"notes:gym",before:before.bundle.records.find(r=>r.section==="notes:gym")?.value??null,after},true,guard),
    rehab:({record,change,at,holdAfterPut=false})=>{
     let policy={playerId:id,record,activeTraining:false,heldTraining:false,journalPending:false,
       profile:{at,status:"okay",level:15},travel:{at,available:true},war:{at,known:true,ranked:null},
       warSettings:{mode:"scheduled",adjustment:60,lead:120},health:{at,level:"recommended"},
       rehabSettings:{travel:"wlt",rehabMinutes:30,rehabSessions:1},actions:[],baseline:null};
     const original=IDBObjectStore.prototype.put;
     if(holdAfterPut)IDBObjectStore.prototype.put=function(...args){
       const req=original.apply(this,args);req.addEventListener("success",()=>{policy={...policy,heldTraining:true};},{once:true});return req;
     };
     return db.planRehab(id,policy,change,true,()=>policy,guard).finally(()=>{if(holdAfterPut)IDBObjectStore.prototype.put=original;});
    },
    rejectProtected:before=>db.editPreference(id,before,{section:"calendar-events",before:"[]",after:"[] "},true,guard),
    mutateOldSource:()=>source.setItem(prefix+"activity-events:"+id,"[] "),
    ownerRead:()=>db.read("999999914",guard),
    rotate:()=>{valid=false;db.abortPending();},
    authorize:()=>{valid=true;},
    close:()=>db.close(),
    reopen:async()=>{db=await g.open({name});}
   };
  },{name,id});
 }));
 const [a,b]=tabs;
 const review=await a.evaluate(()=>fixture.review());
 await b.evaluate(review=>fixture.loadSource(review),review);
 const initial=await Promise.all(tabs.map(t=>t.evaluate(review=>fixture.initialize(review),review)));
 assert.equal(initial.filter(r=>r.status==="committed").length,1);
 assert.equal(initial.filter(r=>r.status==="already-initialized").length,1);
 const copies=await Promise.all(tabs.map(t=>t.evaluate(()=>fixture.read())));
 assert.deepEqual(copies[0].record,copies[1].record);
 const before=copies[0].record;
 assert.equal(before.generation,1);
 // Competing children of the same generation must not both commit.
 const outcomes=await Promise.all([a.evaluate(before=>fixture.edit({before,after:"tab A"}),before),b.evaluate(before=>fixture.edit({before,after:"tab B"}),before)]);
 assert.equal(outcomes.filter(r=>r.status==="committed").length,1);
 assert.equal(outcomes.filter(r=>r.status==="stale").length,1);
 const after=await Promise.all(tabs.map(t=>t.evaluate(()=>fixture.read())));
 assert.deepEqual(after[0].record,after[1].record);
 const winning=after[0].record;
 assert.equal(winning.generation,2);
 const winner=outcomes[0].status==="committed"?"tab A":"tab B";
 assert.equal(winning.bundle.records.find(r=>r.section==="notes:gym").value,winner);
 assert.equal(winning.bundle.lineageRaw,before.bundle.lineageRaw);
 // Old-source divergence cannot affect authoritative state or revisions.
 await b.evaluate(()=>fixture.mutateOldSource());
 assert.deepEqual((await b.evaluate(()=>fixture.read())).record,winning);
 // A stale same-generation review with forged different bytes must fail.
 const altered=structuredClone(winning);
 altered.bundle.manifestRaw+=" ";
 const exact=await a.evaluate(before=>fixture.edit({before,after:"must not commit"}),altered);
 assert.equal(exact.status,"stale");
 assert.equal((await a.evaluate(()=>fixture.ownerRead())).status,"absent");
 await b.evaluate(()=>fixture.rotate());
 await assert.rejects(()=>b.evaluate(before=>fixture.edit({before,after:"stale epoch"}),winning),/epoch/);
 await b.evaluate(()=>fixture.authorize());
 // Reopen and verify the acknowledged winner remains durable.
 await b.evaluate(()=>fixture.close());await b.evaluate(()=>fixture.reopen());
 assert.deepEqual((await b.evaluate(()=>fixture.read())).record,winning);
 const removed=await a.evaluate(before=>fixture.edit({before,after:null}),winning);
 assert.equal(removed.status,"committed");
 const final=(await b.evaluate(()=>fixture.read())).record;
 assert.equal(final.generation,3);assert.ok(final.bundle.markers.includes("notes:gym"));
 assert.equal(JSON.parse(final.bundle.manifestRaw).entries.find(e=>e.section==="notes:gym").digest,null);
 for(const section of ["calendar-events","activity-spend"]){
  assert.deepEqual(final.bundle.records.find(r=>r.section===section),before.bundle.records.find(r=>r.section===section));
  assert.deepEqual(JSON.parse(final.bundle.manifestRaw).entries.find(r=>r.section===section),JSON.parse(before.bundle.manifestRaw).entries.find(r=>r.section===section));
 }
 if(rehab)await probeRehab(a,b,final);
 if(lifecycle)await probeLifecycle(a,b,name,final);
 if(quota)await probeQuota(context,a,b,origin,final);
 await Promise.all(tabs.map(t=>t.evaluate(()=>fixture.close())));
 return {name,id,record:final};
}
async function probeRehab(a,b,record){
 const at=Date.now(),start=at+60000,duration=(Math.ceil(2*83*1.03)+30)*60000;
 const event={id:"rehab-fixture",kind:"rehab",title:"Rehabilitation",start,end:start+duration,blocking:true,source:"manual",rehabBaseline:null};
 const add={id:event.id,kind:"add",before:null,after:event};
 const args={record,change:add,at};
 const outcomes=await Promise.all([a.evaluate(args=>fixture.rehab(args),args),b.evaluate(args=>fixture.rehab(args),args)]);
 assert.equal(outcomes.filter(x=>x.status==="committed").length,1);
 assert.equal(outcomes.filter(x=>x.status==="stale").length,1);
 const left=(await a.evaluate(()=>fixture.read())).record,right=(await b.evaluate(()=>fixture.read())).record;
 assert.deepEqual(left,right);assert.equal(left.generation,record.generation+1);
 assert.deepEqual(JSON.parse(left.bundle.records.find(x=>x.section==="calendar-events").value),[event]);
 assert.equal(left.bundle.records.find(x=>x.section==="activity-spend").value,record.bundle.records.find(x=>x.section==="activity-spend").value);
 const cancel={id:event.id,kind:"remove",before:event,after:null};
 await assert.rejects(()=>a.evaluate(args=>fixture.rehab(args),{record:left,change:cancel,at,holdAfterPut:true}),/hold/);
 assert.deepEqual((await b.evaluate(()=>fixture.read())).record,left);
 const canceled=await b.evaluate(args=>fixture.rehab(args),{record:left,change:cancel,at});
 assert.equal(canceled.status,"committed");
 const final=(await a.evaluate(()=>fixture.read())).record;
 assert.equal(final.generation,left.generation+1);
 assert.equal(JSON.parse(final.bundle.lineageRaw).entries.find(e=>e.id===event.id).digest,null);
 await assert.rejects(()=>a.evaluate(args=>fixture.rehab(args),{record:final,change:add,at}),/Deleted calendar ID/);
 console.log("PASS native V7-style reservation contention, exact ledger preservation, post-put policy abort, cancellation and no ID reuse");
}
async function probeLifecycle(a,b,name,record){
 await assert.rejects(()=>a.evaluate(record=>fixture.rejectProtected(record),record),/preference/);
 // Stop a native IDB transaction after its put request succeeds and before
 // the transaction commits. The controlled insertion point makes the test deterministic.
 await assert.rejects(()=>a.evaluate(async record=>{
  const original=IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put=function(...args){
   const request=original.apply(this,args);
   request.addEventListener("success",()=>fixture.rotate(),{once:true});
   return request;
  };
  try{return await fixture.edit({before:record,after:"aborted"});}
  finally{IDBObjectStore.prototype.put=original;fixture.authorize();}
 },record),/epoch|aborted/i);
 assert.deepEqual((await b.evaluate(()=>fixture.read())).record,record);
 console.log("PASS pending epoch rotation aborts a native write and preserves the exact prior generation");

 const completion=await a.evaluate(async record=>{
  const original=IDBDatabase.prototype.transaction;
  IDBDatabase.prototype.transaction=function(...args){
   const tx=original.apply(this,args);
   if(tx.mode==="readwrite")tx.addEventListener("complete",()=>fixture.rotate(),{once:true});
   return tx;
  };
  try{return await fixture.edit({before:record,after:"committed before rotation"});}
  finally{IDBDatabase.prototype.transaction=original;fixture.authorize();}
 },record);
 assert.deepEqual(completion,{status:"committed",generation:record.generation+1,current:false});
 const committed=(await b.evaluate(()=>fixture.read())).record;
 assert.equal(committed.generation,completion.generation);
 assert.equal(committed.bundle.records.find(x=>x.section==="notes:gym").value,"committed before rotation");
 console.log("PASS epoch rotation at native completion reports committed and stale, and the other tab reads the commit");

 await a.evaluate(()=>{
  let release;
  const gate=new Promise(resolve=>{release=resolve;});
  window.releaseAccountDigest=release;
  window.pendingAccountRead=fixture.read({digest:async raw=>{
   window.accountDigestStarted=true;
   await gate;
   const bytes=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(raw));
   return Array.from(new Uint8Array(bytes),n=>n.toString(16).padStart(2,"0")).join("");
  }});
  window.pendingAccountRead.catch(()=>{});
 });
 await a.waitForFunction(()=>window.accountDigestStarted);
 try{
  await b.evaluate(name=>new Promise((resolve,reject)=>{
   const request=indexedDB.open(name,2);
   request.onerror=()=>reject(request.error);
   request.onblocked=()=>reject(Error("Version change blocked"));
   request.onsuccess=()=>{request.result.close();resolve();};
  }),name);
 }finally{await a.evaluate(()=>window.releaseAccountDigest());}
 await assert.rejects(()=>a.evaluate(()=>window.pendingAccountRead),/closed/);
 await assert.rejects(()=>b.evaluate(()=>fixture.read()),/closed/);
 await assert.rejects(()=>b.evaluate(()=>fixture.reopen()),/version/i);
 console.log("PASS native versionchange closes both tabs, invalidates an in-flight verified read and refuses downgrade");
}
async function probeQuota(context,a,b,origin,record){
 const devtools=await context.newCDPSession(a);
 const securityOrigin=new URL(origin).origin;
 const note=randomBytes(67500).toString("base64");
 try{
  await devtools.send("Storage.overrideQuotaForOrigin",{origin:securityOrigin,quotaSize:4096});
  const usage=await devtools.send("Storage.getUsageAndQuota",{origin:securityOrigin});
  assert.equal(usage.overrideActive,true);
  assert.equal(usage.quota,4096);
  // Chromium can reuse an earlier IndexedDB quota calculation for 30 seconds.
  await delay(31000);
  await assert.rejects(()=>a.evaluate(({record,note})=>fixture.edit({before:record,after:note}),{record,note}),/QuotaExceededError/i);
  assert.deepEqual((await b.evaluate(()=>fixture.read())).record,record);
 }finally{
  try{await devtools.send("Storage.overrideQuotaForOrigin",{origin:securityOrigin});}
  finally{await devtools.detach();}
 }
 assert.equal((await a.evaluate(({record,note})=>fixture.edit({before:record,after:note}),{record,note})).status,"committed");
 console.log("PASS Chrome-enforced IndexedDB quota abort preserves the exact prior record under a DevTools quota override");
}
const chrome={channel:"chrome",ignoreDefaultArgs:["--no-sandbox"]};
async function probeRestart(origin){
 const profile=await mkdtemp(join(tmpdir(),"torn-transaction-restart-"));
 let context;
 try{
  context=await chromium.launchPersistentContext(profile,chrome);
  const {name,id,record}=await probe(context,origin);
  await context.close();
  context=await chromium.launchPersistentContext(profile,chrome);
  const tab=await context.newPage();
  await loadPage(tab,origin);
  const recovered=await tab.evaluate(async({name,id})=>{
   const db=await tornAccountTransactionStore.open({name});
   try{return (await db.read(id,()=>true)).record;}
   finally{db.close();}
  },{name,id});
  assert.deepEqual(recovered,record);
  console.log("PASS exact acknowledged generation survives a full Chrome restart using a disposable on-disk profile");
 }finally{
  try{await context?.close();}
  finally{await rm(profile,{recursive:true,force:true,maxRetries:5});}
 }
}
async function main(){
 const stage=process.argv[2]??"20",lifecycle=stage==="--lifecycle",quota=stage==="--quota",restart=stage==="--restart",rehab=stage==="--rehab";
 const trials=lifecycle||quota||restart||rehab?1:Number(stage);assert.ok(Number.isInteger(trials)&&trials>=1&&trials<=100);
 let browser,failures=0;
 try{
  await new Promise((resolve,reject)=>server.listen(0,"127.0.0.1",resolve).once("error",reject));
  const origin="http://127.0.0.1:"+server.address().port+"/";
  if(restart){await probeRestart(origin);return;}
  browser=await chromium.launch(chrome);
  for(let i=1;i<=trials;i++){
   const context=await browser.newContext();
   try{await probe(context,origin,{lifecycle,quota,rehab});console.log("PASS trial "+i);}
   catch(e){failures++;console.error("FAIL trial "+i,e.message);}
   finally{await context.close();}
  }
  console.log("Chrome "+browser.version()+": "+(trials-failures)+"/"+trials+" transactional trials passed");
  if(failures)process.exitCode=1;
 }finally{try{await browser?.close();}finally{await new Promise(resolve=>server.close(resolve));}}
}
main().catch(e=>{console.error(e);process.exitCode=1});
