"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,m,l,j}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-merge.js","account-calendar-lineage.js","account-calendar-journal.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,m:tornCalendarMerge,l:tornCalendarLineage,j:tornCalendarJournal};")();
const id=123,section="calendar-events",now=Date.UTC(2026,10,27),yes=()=>true,cal="torn-city-guide:activity-events:"+id,note="torn-city-guide:v1:profile:"+id+":notes:gym",manifest=r.key(id),lineage=j.lineageKey(id),journal=a.journalKey(id);
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);},options={digest,newRevision:()=>String(++n).padStart(32,"0")};
const event=(key,extra={})=>({id:key,kind:"personal",title:key,start:now,end:now+60000,blocking:false,source:"manual",...extra});
function storage(entries={}){const x=new Map(Object.entries(entries));return {get length(){return x.size;},key:i=>[...x.keys()][i]??null,getItem:k=>x.get(k)??null,setItem:(k,v)=>x.set(k,String(v)),removeItem:k=>x.delete(k)};}
let lockCalls=0;const locks={request:async(name,opt,fn)=>{assert.equal(name,"torn-city-guide:account-recovery:"+id);assert.equal(opt.mode,"exclusive");lockCalls++;return fn();}};
async function make(prior,events){const records=[{section,value:JSON.stringify(events)},{section:"notes:gym",value:"keep"}],omitted=[];return {records,omitted,manifest:await r.observe(prior,{records,omitted},id,options)};}
async function run(){
 const left=await make(r.empty(id),[event("a"),event("war",{kind:"war"})]),right=await make(left.manifest,[event("a",{title:"changed"}),event("war",{kind:"war",title:"remote war"}),event("new")]);
 const p=await m.preview(left,right,id,options),row=p.rows.find(x=>x.id==="a"),decisions=[{id:row.id,reviewKey:row.reviewKey,choice:"take-incoming"}];
 const initial=await l.initialize(left,id,options);
 const store=()=>storage({[cal]:left.records[0].value,[note]:"keep",[manifest]:JSON.stringify(left.manifest),[lineage]:JSON.stringify(initial)});
 const apply=(s,opts=options)=>j.apply(s,id,left,right,decisions,yes,locks,opts);
 const ok=store();assert.equal((await apply(ok)).status,"applied");
 const result=JSON.parse(ok.getItem(cal));assert.equal(result[0].title,"changed");assert.equal(result[1].title,"war");assert.equal(result.length,2);assert.equal(ok.getItem(note),"keep");
 assert.equal(a.journalPending(ok,id),false);const after={...a.snapshot(ok,id),manifest:r.read(ok,id)};await l.verify(JSON.parse(ok.getItem(lineage)),after,id,options);
 assert.equal(after.manifest.entries.find(x=>x.section===section).ancestors[0],left.manifest.entries.find(x=>x.section===section).revision);
 assert.notEqual(after.manifest.entries.find(x=>x.section===section).revision,right.manifest.entries.find(x=>x.section===section).revision);
 const no=store();no.removeItem(lineage);await assert.rejects(()=>apply(no),/bootstrap/);assert.equal((await apply(no,{...options,allowBootstrap:true})).status,"applied");
 await assert.rejects(()=>j.apply(store(),id,left,right,decisions,yes,null,options),/Web Locks/);
 const held=store();held.setItem("torn-city-guide:training-session:"+id,"held");await assert.rejects(()=>apply(held),/training state/);
 const stale=store();stale.setItem(note,"changed");await assert.rejects(()=>apply(stale),/changed/);
 const noop=store();assert.equal((await j.apply(noop,id,left,right,[{...decisions[0],choice:"keep-local"}],yes,locks,options)).status,"unchanged");assert.equal(noop.getItem(manifest),JSON.stringify(left.manifest));assert.equal(noop.getItem(journal),null);
 const reused=store();await assert.rejects(()=>apply(reused,{...options,newRevision:()=>right.manifest.entries.find(x=>x.section===section).revision}),/collision/);assert.equal(reused.getItem(journal),null);
 const denied=store();await assert.rejects(()=>j.apply(denied,id,left,right,decisions,()=>false,locks,options),/training state/);assert.equal(denied.getItem(journal),null);
 // Existing local tombstones remain authoritative for rejecting reuse.
 const tombStore=store(),oldLineage=JSON.parse(tombStore.getItem(lineage));
 oldLineage.entries.push({id:"new",digest:null,deletedFrom:"a".repeat(64),deletedAtRevision:left.manifest.entries.find(x=>x.section===section).revision});
 tombStore.setItem(lineage,JSON.stringify(oldLineage));
 const newRow=p.rows.find(x=>x.id==="new");
 await assert.rejects(()=>j.apply(tombStore,id,left,right,[{id:newRow.id,choice:"take-incoming",reviewKey:newRow.reviewKey}],yes,locks,options),/cannot be reused/);
 assert.equal(tombStore.getItem(journal),null);
 const quota=store(),w=quota.setItem;quota.setItem=(k,v)=>{if(k===journal)throw Error("quota");w(k,v);};await assert.rejects(()=>apply(quota),/quota/);assert.equal(quota.getItem(cal),left.records[0].value);
 for(const dest of [cal,lineage,manifest]){
   const s=store(),write=s.setItem;s.setItem=(k,v)=>{if(k===dest)throw Error("quota");write(k,v);};
   await assert.rejects(()=>apply(s),/journal retained/);
   assert.equal(a.journalPending(s,id),true);assert.throws(()=>a.readJournal(s,id),/Invalid restore journal/);
   assert.throws(()=>a.trackedWrite(s,id,note,"bad"),/pending/);
   const info=j.read(s,id);assert.equal(info.conflict,false);assert.equal(info.complete,false);
   await assert.rejects(()=>j.recover(s,id,info.raw,"finish",yes,locks,options),/incomplete/);
   s.setItem=write;assert.equal((await j.recover(s,id,info.raw,"rollback",yes,locks,options)).status,"rolled-back");
   assert.equal(s.getItem(cal),left.records[0].value);assert.equal(s.getItem(lineage),JSON.stringify(initial));assert.equal(s.getItem(manifest),JSON.stringify(left.manifest));assert.equal(s.getItem(journal),null);
 }
 const finished=store(),remove=finished.removeItem;finished.removeItem=k=>{if(k===journal)throw Error("interrupted finalization");remove(k);};
 await assert.rejects(()=>apply(finished),/journal retained/);const pending=j.read(finished,id);assert.equal(pending.complete,true);
 finished.removeItem=remove;assert.equal((await j.recover(finished,id,pending.raw,"finish",yes,locks,options)).status,"finalized");
 const conflict=store(),cw=conflict.setItem;conflict.setItem=(k,v)=>{if(k===manifest)throw Error("quota");cw(k,v);};
 await assert.rejects(()=>apply(conflict),/journal retained/);conflict.setItem=cw;cw(cal,JSON.stringify([event("foreign")]));
 const broken=j.read(conflict,id);assert.equal(broken.conflict,true);await assert.rejects(()=>j.recover(conflict,id,broken.raw,"rollback",yes,locks,options),/Conflicting/);assert.equal(conflict.getItem(journal),broken.raw);
 const unrelated=store(),uw=unrelated.setItem;unrelated.setItem=(k,v)=>{if(k===manifest)throw Error("quota");uw(k,v);};
 await assert.rejects(()=>apply(unrelated),/journal retained/);unrelated.setItem=uw;uw(note,"independent");
 await assert.rejects(()=>j.recover(unrelated,id,j.read(unrelated,id).raw,"rollback",yes,locks,options),/digest/);assert.ok(unrelated.getItem(journal));
 assert.ok(lockCalls>10);
 console.log("Scoped calendar journal, local revision, lineage, quota/interruption rollback, finalization, stale/held/lock guards and conflict retention passed.");
}
module.exports=run;
if(require.main===module)run().catch(error=>{console.error(error);process.exitCode=1;});
