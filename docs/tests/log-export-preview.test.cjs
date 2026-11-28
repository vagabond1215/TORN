"use strict";
const assert=require("node:assert/strict"),r=require("../log-records.js"),c=require("../log-coverage.js"),a=require("../log-archive.js"),x=require("../log-export-preview.js");
const at=Date.UTC(2026,10,28),id="1",copy=v=>JSON.parse(JSON.stringify(v)),yes=()=>true;
function rows(n){
 return Array.from({length:n},(_,i)=>({schemaVersion:1,decoderVersion:1,playerId:id,source:"api-log",sourceId:"row-"+String(n-i).padStart(5,"0"),occurredAt:at-Math.floor(i/3)*1000,typeId:1,category:"Fixture",title:"Synthetic event",fields:{quantity:i},observedAt:at}));
}
function fixture(n){
 let data=rows(n),s={playerId:id,source:"api-log",version:1,generation:3,count:n,bytes:data.reduce((sum,v)=>sum+2*JSON.stringify(v).length,0),checkpoint:c.create(id),blocked:null},reads=0,hook=null;
 const store={state:async()=>copy(s),readPage:async(player,guard,{limit,after})=>{
   assert.equal(player,id);assert.ok(guard());const start=after?data.findIndex(v=>v.sourceId===after.id&&v.occurredAt===after.at)+1:0;
   const part=data.slice(start,start+limit),last=part.at(-1);
   const page={records:copy(part),after:start+part.length<data.length?{at:last.occurredAt,id:last.sourceId}:null};reads++;
   return hook?hook(page,reads):page;
 }};
 return {store,get data(){return copy(data)},get state(){return copy(s)},setState:patch=>s={...s,...patch},setHook:fn=>hook=fn};
}
async function run(){
 const f=fixture(2101),preview=await x.prepare(f.store,id,f.state,true,yes);
 assert.equal(preview.count,2101);assert.equal(preview.evictionAllowed,false);
 assert.deepEqual(preview.chunks.flatMap(v=>v.records),f.data);
 assert.ok(preview.chunks.every(v=>v.count<=x.MAX_CHUNK_ROWS));
 const empty=fixture(0);assert.equal((await x.prepare(empty.store,id,empty.state,true,yes)).chunkCount,0);
 await assert.rejects(()=>x.prepare(f.store,id,f.state,false,yes),/Explicit/);
 await assert.rejects(()=>x.prepare(f.store,"2",f.state,true,yes),/Owner/);
 const changed=fixture(101);changed.setHook((page,n)=>{if(n===1)changed.setState({generation:4});return page;});
 await assert.rejects(()=>x.prepare(changed.store,id,changed.state,true,yes),/Archive changed/);
 const duplicate=fixture(101);duplicate.setHook((page,n)=>{if(n===2)page.records=[duplicate.data[0]];return page;});
 await assert.rejects(()=>x.prepare(duplicate.store,id,duplicate.state,true,yes),/duplicate|unordered/);
 const missing=fixture(100);missing.setHook(page=>({...page,records:page.records.slice(0,-1),after:null}));
 await assert.rejects(()=>x.prepare(missing.store,id,missing.state,true,yes),/count or bytes mismatch/);
 const invalid=fixture(100);invalid.setHook(page=>({...page,after:{at:at,id:"wrong"}}));
 await assert.rejects(()=>x.prepare(invalid.store,id,invalid.state,true,yes),/cursor/);
 const stale=fixture(100);let valid=true;stale.setHook(page=>{valid=false;return page;});
 await assert.rejects(()=>x.prepare(stale.store,id,stale.state,true,()=>valid),/authorization/);
 console.log("Log export preview: 2,101 exact rows, bounded chunks, no eviction, owner/approval, concurrent generation, duplicate, missing rows, cursor and authorization passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
