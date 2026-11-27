"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {r,l}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js"].map(read).join("\n")+"\nreturn {r:tornAccountRevisions,l:tornCalendarLineage};")();
const id=123,section="calendar-events",now=Date.UTC(2026,10,27);
let n=0;const newRevision=()=>String(++n).padStart(32,"0");
const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);};
const options={digest,newRevision},event=(key,title=key)=>({id:key,kind:"personal",title,start:now,end:now+60000,blocking:false,source:"manual"});
async function make(prior,rows){const records=rows===null?[]:[{section,value:JSON.stringify(rows)}],omitted=[];return {records,omitted,manifest:await r.observe(prior,{records,omitted},id,options)};}
async function run(){
 const first=await make(r.empty(id),[event("a"),event("b")]);
 const initial=await l.initialize(first,id,options);assert.equal(initial.entries.length,2);assert.ok(initial.entries.every(x=>x.digest!==null));
 assert.deepEqual(await l.verify(initial,first,id,options),initial);
 const second=await make(first.manifest,[event("a","edited"),event("c")]);
 await assert.rejects(()=>l.advance(initial,first,second,id,[],options),/explicit deletion/);
 await assert.rejects(()=>l.advance(initial,first,second,id,["b","c"],options),/explicit deletion/);
 const next=await l.advance(initial,first,second,id,["b"],options);
 const tomb=next.entries.find(x=>x.id==="b");
 assert.equal(tomb.digest,null);assert.equal(tomb.deletedFrom,initial.entries.find(x=>x.id==="b").digest);
 assert.equal(tomb.deletedAtRevision,second.manifest.entries[0].revision);
 assert.ok(!JSON.stringify(next).includes("edited"));
 assert.deepEqual(await l.verify(next,second,id,options),next);
 assert.equal(initial.entries.find(x=>x.id==="b").digest!==null,true);
 const third=await make(second.manifest,[event("c","changed")]);
 const more=await l.advance(next,second,third,id,["a"],options);
 assert.deepEqual(more.entries.find(x=>x.id==="b"),tomb);
 const reinsert=await make(third.manifest,[event("c","changed"),event("b")]);
 await assert.rejects(()=>l.advance(more,third,reinsert,id,[],options),/cannot be reused/);
 const branch=await make(first.manifest,[event("a"),event("other")]);
 await assert.rejects(()=>l.advance(next,second,branch,id,["c"],options),/proven descendant/);
 await assert.rejects(()=>l.verify(next,first,id,options),/binding/);
 await assert.rejects(()=>l.verify({...next,playerId:"456"},second,id,options),/binding/);
 await assert.rejects(()=>l.verify({...next,entries:next.entries.filter(x=>x.id!=="a")},second,id,options),/digest mismatch/);
 await assert.rejects(()=>l.verify({...next,entries:[...next.entries,tomb]},second,id,options),/entry/);
 await assert.rejects(()=>l.verify(next,{...second,omitted:[section]},id,options),/Incomplete/);
 const empty=await make(third.manifest,null);
 const allRemoved=await l.advance(more,third,empty,id,["c"],options);
 assert.ok(allRemoved.entries.every(x=>x.digest===null));
 assert.equal((await l.initialize(empty,id,options)).entries.length,0); // no invented historic tombstones
 const untracked={records:[],omitted:[],manifest:r.empty(id)};
 await assert.rejects(()=>l.initialize(untracked,id,options),/Tracked/);
 const cap={...next,entries:[...next.entries,...Array.from({length:l.MAX_ENTRIES-next.entries.length},(_,i)=>({...tomb,id:"deleted-"+i}))]};
 await l.verify(cap,second,id,options);
 const overflow=await make(second.manifest,[event("a","edited"),event("c"),event("new")]);
 await assert.rejects(()=>l.advance(cap,second,overflow,id,[],options),/limit/);
 console.log("Calendar lineage binding, exact observed deletions, retained tombstones, no ID reuse, legacy bootstrap, branch/owner/digest validation and capacity passed.");
}
module.exports=run;
if(require.main===module)run().catch(error=>{console.error(error);process.exitCode=1;});
