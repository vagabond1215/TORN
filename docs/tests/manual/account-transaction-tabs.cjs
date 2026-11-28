"use strict";
// Native acceptance candidate, synthetic data only. Separate Chrome pages
// share the SAME IndexedDB origin. No localStorage source is authoritative
// after initialization. No API, no production account, no unsafe flags.
const assert=require("node:assert/strict");
const {randomUUID}=require("node:crypto");
const {readFile}=require("node:fs/promises");
const {createServer}=require("node:http");
const {join}=require("node:path");
const {chromium}=require("playwright-core");
const modules=["training-recovery","account-storage","account-revisions","account-calendar-lineage","account-transaction-store"];
const assets=new Map(modules.map(n=>["/"+n+".js",n+".js"]));
const server=createServer(async(req,res)=>{
 if(req.url==="/"){res.writeHead(200,{"Content-Type":"text/html"}).end("<!doctype html><title>Transactional account test</title>");return;}
 const asset=assets.get(req.url);if(!asset){res.writeHead(404).end();return;}
 try{res.writeHead(200,{"Content-Type":"text/javascript"}).end(await readFile(join(__dirname,"../..",asset)));}
 catch{res.writeHead(500).end();}
});
async function probe(context,origin){
 const tabs=await Promise.all([context.newPage(),context.newPage()]);
 const name="torn-transaction-fixture:"+randomUUID(),id="999999913";
 await Promise.all(tabs.map(async tab=>{
  await tab.goto(origin);
  for(const module of modules)await tab.addScriptTag({url:origin+module+".js"});
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
    read:()=>db.read(id,guard),
    edit:({before,after})=>db.editPreference(id,before,{section:"notes:gym",before:before.bundle.records.find(r=>r.section==="notes:gym")?.value??null,after},true,guard),
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
 await Promise.all(tabs.map(t=>t.evaluate(()=>fixture.close())));
}
async function main(){
 const trials=Number(process.argv[2]??20);assert.ok(Number.isInteger(trials)&&trials>=1&&trials<=100);
 let browser,failures=0;
 try{
  await new Promise((resolve,reject)=>server.listen(0,"127.0.0.1",resolve).once("error",reject));
  const origin="http://127.0.0.1:"+server.address().port+"/";
  browser=await chromium.launch({channel:"chrome",ignoreDefaultArgs:["--no-sandbox"]});
  for(let i=1;i<=trials;i++){
   const context=await browser.newContext();
   try{await probe(context,origin);console.log("PASS trial "+i);}
   catch(e){failures++;console.error("FAIL trial "+i,e.message);}
   finally{await context.close();}
  }
  console.log("Chrome "+browser.version()+": "+(trials-failures)+"/"+trials+" transactional trials passed");
  if(failures)process.exitCode=1;
 }finally{try{await browser?.close();}finally{await new Promise(resolve=>server.close(resolve));}}
}
main().catch(e=>{console.error(e);process.exitCode=1});
