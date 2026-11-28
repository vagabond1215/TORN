"use strict";
const assert=require("node:assert/strict"),r=require("../log-records.js"),c=require("../log-coverage.js"),x=require("../log-export-preview.js"),codec=require("../log-file-codec.js");
const run=(function testSuite(assert,r,c,x,codec){
  return async function run(){
    const id="1",at=Date.UTC(2026,10,28),secret="synthetic-only-password",yes=()=>true;
    const copy=v=>JSON.parse(JSON.stringify(v)),bytes=rows=>rows.reduce((n,v)=>n+2*JSON.stringify(v).length,0);
    const api=Array.from({length:2101},(_,i)=>({schemaVersion:1,decoderVersion:1,playerId:id,source:"api-log",sourceId:"row-"+String(2101-i).padStart(5,"0"),occurredAt:at-Math.floor(i/3)*1000,typeId:1,category:"Fixture",title:"Synthetic event",fields:{quantity:i},observedAt:at}));
    const companion=await r.decodeCompanion({version:1,playerId:1,capturedAt:at,rows:[{at,text:"Synthetic event"},{at,text:"Synthetic event"}]},id,at,async()=>"a".repeat(64));
    const review={api:{playerId:id,source:"api-log",version:1,generation:3,count:api.length,bytes:bytes(api),checkpoint:c.create(id),blocked:null,consent:true},companion:{playerId:id,source:r.COMPANION,version:1,revision:2,count:companion.length,bytes:bytes(companion)}};
    let state=copy(review);
    const page=rows=>async(p,g,{limit,after})=>{
      const start=after?rows.findIndex(v=>v.sourceId===after.id)+1:0,part=rows.slice(start,start+limit),last=part.at(-1);
      return {records:copy(part),after:start+part.length<rows.length?{at:last.occurredAt,id:last.sourceId}:null};
    };
    const store={reviewSources:async()=>copy(state),readPage:page(api),readCompanionPage:page(companion)};
    const file=await codec.encode(store,id,review,true,yes,secret,at);
    assert.ok(!file.includes("Synthetic event")&&!file.includes("playerId")&&!file.includes(secret));
    const decoded=await codec.decode(file,id,secret,true,yes),expected=await x.prepareUnified(store,id,review,true,yes);
    assert.equal(decoded.count,2103);assert.equal(decoded.evictionAllowed,false);assert.deepEqual(decoded.chunks,expected.chunks);assert.deepEqual(decoded.review,review);
    assert.deepEqual(state,review);
    const change=fn=>{const v=JSON.parse(file);fn(v);return JSON.stringify(v);};
    const refuse=(v=file,p=id,s=secret,g=yes)=>assert.rejects(()=>codec.decode(v,p,s,true,g));
    await refuse(file,"2");await refuse(file,id,"wrong-password-123");await refuse(change(v=>v.version=2));
    await refuse(change(v=>v.chunks.pop()));await refuse(change(v=>v.chunks.push(v.chunks[0])));
    await refuse(change(v=>[v.chunks[0],v.chunks[1]]=[v.chunks[1],v.chunks[0]]));
    await refuse(change(v=>v.chunks[0]=(v.chunks[0][0]==="A"?"B":"A")+v.chunks[0].slice(1)));
    await refuse(change(v=>v.manifest=(v.manifest[0]==="A"?"B":"A")+v.manifest.slice(1)));
    await refuse(change(v=>v.iterations=1));await refuse(change(v=>v.nonce="AAAA"));
    await refuse(file,id,secret,()=>false);
    await assert.rejects(()=>codec.decode(file,id,secret,false,yes));
    await assert.rejects(()=>codec.encode(store,id,review,false,yes,secret,at));
    state.api.generation++;
    await assert.rejects(()=>codec.encode(store,id,review,true,yes,secret,at));
    state=copy(review);
    // Count the preview's exact state reads independently; the next read
    // is the codec's final post-encryption comparison, not a preview read.
    let checks=0;const counted={...store,reviewSources:async()=>{checks++;return copy(review);}};
    await x.prepareUnified(counted,id,review,true,yes);
    const previewChecks=checks;
    checks=0;const staleStore={...store,reviewSources:async()=>{checks++;const v=copy(review);if(checks>previewChecks)v.companion.revision++;return v;}};
    await assert.rejects(()=>codec.encode(staleStore,id,review,true,yes,secret,at),/Archive changed/);
    assert.equal(checks,previewChecks+1);
    let decodeChecks=0;
    await assert.rejects(()=>codec.decode(file,id,secret,true,()=>++decodeChecks<5),/authorization/);
    // Independently exercise authorization loss during asynchronous work.
    let guards=0;await assert.rejects(()=>codec.encode(store,id,review,true,()=>++guards<10,secret,at));
    const other=await codec.encode(store,id,review,true,yes,secret,at);
    assert.ok(other!==file);
    await refuse(change(v=>v.chunks[0]=JSON.parse(other).chunks[0]));
    const empty={api:{...review.api,count:0,bytes:0},companion:{...review.companion,count:0,bytes:0}};
    state=empty;
    const emptyStore={reviewSources:async()=>copy(empty),readPage:page([]),readCompanionPage:page([])};
    const zero=await codec.decode(await codec.encode(emptyStore,id,empty,true,yes,secret,at),id,secret,true,yes);
    assert.equal(zero.count,0);assert.equal(zero.chunks.length,0);
    return "2103 source records, exact review, empty archive, wrong owner/passphrase, tamper, missing/extra/reordered/mixed chunks, parameter/authorization/stale review refusal, independent encryption; no eviction";
  };
})(assert,r,c,x,codec);
module.exports=run;
if(require.main===module)run().then(console.log).catch(e=>{console.error(e);process.exitCode=1});
