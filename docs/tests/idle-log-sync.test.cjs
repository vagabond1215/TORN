"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const now=Date.UTC(2026,10,26),win={addEventListener:()=>{}},doc={addEventListener:()=>{}};
const api=new Function("window","document",read("guide-features.js").split("\nconst guideSteps")[0]+"\nreturn tornGuideApi;")(win,doc);
assert.equal(api.idleEligible(now,0,now-15000,now-60000,false),true);
assert.equal(api.idleEligible(now,1,0,0,false),false);
assert.equal(api.idleEligible(now,0,now-14999,0,false),false);
assert.equal(api.idleEligible(now,0,0,now-59999,false),false);
assert.equal(api.idleEligible(now,0,0,0,true),false);
assert.equal(api.idleEligible(now,0,0,0,false,now+1),false);
const mod=new Function("tornGuideApi","window","document",read("log-guide.js")+"\nreturn tornLogGuide;")({},win,doc);
const row=(id,at=now)=>({id,timestamp:at/1000,details:{id:123,title:"Used item",category:"Drug"},data:{quantity:1,api_key:"not retained",secret:"not retained"},params:{key:"not retained"}});
const decode=(rows,cursor)=>mod.decodeApiPage({log:rows,_metadata:{nanostamp:cursor}},now);
let a=mod.newArchive();
let t=mod.nextApiTask(a,now);assert.equal(t.kind,"head");
a=mod.applyApiPage(a,t,decode([row("a"),row("b")],"1234567890123456789"),now);
assert.equal(a.rows.length,2);assert.equal(a.older,"1234567890123456789");
assert.ok(a.rows[0].text.includes("quantity: 1"));assert.ok(!JSON.stringify(a).includes("not retained"));
t=mod.nextApiTask(a,now+60000);assert.equal(t.kind,"older");
a=mod.applyApiPage(a,t,decode([row("b"),row("c",now-1000)],"1234567890123456788"),now+60000);
assert.equal(a.rows.length,3);
t=mod.nextApiTask(a,now+300000);assert.equal(t.kind,"head");
a=mod.applyApiPage(a,t,decode([row("d")],"2345"),now+300000);
assert.equal(a.catchup,"2345");
t=mod.nextApiTask(a,now+360000);assert.equal(t.kind,"catchup");
a=mod.applyApiPage(a,t,decode([row("a")],"2344"),now+360000);
assert.equal(a.catchup,null);
assert.equal(mod.mergeApiRows([],Array.from({length:2200},(_,i)=>({id:String(i),at:now-i,text:"x"}))).length,2000);
assert.equal(decode([row("a")],"https://other.test").cursor,null);
assert.throws(()=>decode([{...row("a"),timestamp:NaN}],null),/Invalid log record/);
assert.ok(read("guide.js").includes("tornLogGuide.tick()"));
assert.ok(read("guide-features.js").includes("idleAbort?.abort()"));
console.log("Idle eligibility, exact cursor, deduplication, cap, safe fields and catchup passed.");

// Deterministic mocked transport integration, not a live API test.
async function coordinatorRegression(){
  let clock=now,fetchMode="ok",calls=[],timeoutCallback=null,heldRequest=null;
  const store=new Map();
  const storage={getItem:k=>store.get(k)??null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)};
  class Controller{
    constructor(){this.signal={aborted:false,handler:null};}
    abort(){this.signal.aborted=true;this.signal.handler?.();}
  }
  const fetcher=async(url,options)=>{
    calls.push(url);
    if(url.includes("user/basic"))return {ok:true,json:async()=>({profile:{id:1,name:"Fixture"}})};
    if(fetchMode==="permission")return {ok:true,json:async()=>({error:{code:16,error:"Access denied"}})};
    if(fetchMode==="pending"){
      return await new Promise((resolve,reject)=>{
        heldRequest=options.signal;options.signal.handler=()=>{const err=Error("aborted");err.name="AbortError";reject(err);};
      });
    }
    return {ok:true,json:async()=>({log:[],_metadata:{}})};
  };
  const deps=["window","document","navigator","localStorage","Date","fetch","AbortController","setTimeout","clearTimeout"];
  const create=new Function(...deps,read("guide-features.js").split("\nconst guideSteps")[0]+"\nreturn tornGuideApi;");
  const coordinator=create({...win,dispatchEvent:()=>{}},{...doc,visibilityState:"visible"},{locks:{request:async(name,options,callback)=>callback({})}},storage,{now:()=>clock},fetcher,Controller,(fn,ms)=>{if(ms===15000)timeoutCallback=fn;return 1;},()=>{});
  await coordinator.connect("abcdefghijklmnop");
  assert.equal((await coordinator.idleLogPage()).status,"busy");
  clock+=60000;
  assert.equal((await coordinator.idleLogPage("1234567890123456789")).status,"ok");
  assert.ok(calls.at(-1).endsWith("user/log?limit=100&nanostamp=1234567890123456789"));
  assert.equal((await coordinator.idleLogPage()).status,"busy");
  clock+=60000;fetchMode="pending";
  const work=coordinator.idleLogPage();await Promise.resolve();
  assert.ok(heldRequest);
  await coordinator.verifyBackupOwner();
  assert.equal((await work).status,"busy");
  assert.equal(heldRequest.aborted,true);
  clock+=60000;heldRequest=null;
  const timeoutWork=coordinator.idleLogPage();await Promise.resolve();
  assert.ok(heldRequest&&timeoutCallback);timeoutCallback();
  assert.equal((await timeoutWork).status,"backoff");
  clock+=60000;assert.equal((await coordinator.idleLogPage()).status,"busy");
  clock+=600000;fetchMode="permission";
  assert.equal((await coordinator.idleLogPage()).status,"stopped");
  coordinator.disconnect();assert.equal((await coordinator.idleLogPage()).status,"disconnected");
  console.log("Mock coordinator foreground interruption, timeout backoff, permission and disconnect passed.");
}
if(typeof module!=="undefined")module.exports=coordinatorRegression;
if(typeof module!=="undefined"&&require.main===module)coordinatorRegression().catch(error=>{console.error(error);process.exitCode=1;});
