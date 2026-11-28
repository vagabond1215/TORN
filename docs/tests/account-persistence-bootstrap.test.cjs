"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,l,b}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-persistence-bootstrap.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,l:tornCalendarLineage,b:tornPersistenceBootstrap};")();
const id="123",prefix="torn-city-guide:",cal=prefix+"activity-events:"+id,ledger=prefix+"activity-spend-ledger:"+id,lineage=prefix+"calendar-lineage:v1:"+id,manifest=r.key(id),journal=a.journalKey(id),note=prefix+"v1:profile:"+id+":notes:gym";
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);},mock={digest,newRevision:()=>String(++n).padStart(32,"0")};
const yes=()=>true,locks={request:async(name,opt,fn)=>{assert.equal(name,prefix+"account-recovery:"+id);assert.equal(opt.mode,"exclusive");return fn();}};
function storage(entries={}){const m=new Map(Object.entries(entries));return {get length(){return m.size;},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
async function run({native=false}={}){
 const options=native?{}:mock;
 const preview=s=>b.preview(s,id,yes,options),apply=(s,p,approved=true,current=yes,lock=locks)=>b.apply(s,id,p.review,approved,current,lock,options);
 const verify=async s=>{const snap={...a.snapshot(s,id),manifest:r.read(s,id)};await r.verify(snap.manifest,snap.records,id,options);await l.verify(JSON.parse(s.getItem(lineage)),snap,id,options);};
 const empty=storage(),p=await preview(empty);assert.deepEqual(p.missing,["calendar-events","activity-spend","calendar-lineage"]);assert.equal(empty.length,0);
 await assert.rejects(()=>apply(empty,p,false),/approval/);await assert.rejects(()=>apply(empty,p,true,yes,null),/Web Locks/);await assert.rejects(()=>apply(empty,p,true,()=>false),/training state/);assert.equal(empty.length,0);
 assert.equal((await apply(empty,p)).status,"applied");assert.equal(empty.getItem(cal),"[]");assert.equal(empty.getItem(ledger),"[]");assert.equal(empty.getItem(journal),null);await verify(empty);
 assert.equal((await preview(empty)).status,"unchanged");assert.equal((await apply(empty,await preview(empty))).status,"unchanged");
 await assert.rejects(()=>apply(empty,p),/changed/);
 const legacy=storage({[note]:"keep"});await assert.rejects(()=>preview(legacy),/Capture or review/);
 const now=Date.now(),event={id:"a",kind:"personal",title:"Keep",start:now,end:now+60000,blocking:false,source:"manual"};
 const records=[{section:"calendar-events",value:JSON.stringify([event])},{section:"notes:gym",value:"keep"}],old=await r.observe(r.empty(id),{records,omitted:[]},id,options);
 const existing=storage({[cal]:records[0].value,[note]:"keep",[manifest]:JSON.stringify(old)});
 const ep=await preview(existing);assert.deepEqual(ep.missing,["activity-spend","calendar-lineage"]);
 await apply(existing,ep);assert.equal(existing.getItem(cal),records[0].value);assert.equal(existing.getItem(note),"keep");await verify(existing);
 for(const e of old.entries)assert.deepEqual(r.read(existing,id).entries.find(x=>x.section===e.section),e);
 const preserve=storage({[cal]:records[0].value,[note]:"keep",[manifest]:JSON.stringify(old),[lineage]:JSON.stringify(await l.initialize({records,omitted:[],manifest:old},id,options))});
 const prior=preserve.getItem(lineage);assert.deepEqual((await preview(preserve)).missing,["activity-spend"]);await apply(preserve,await preview(preserve));assert.equal(preserve.getItem(lineage),prior);await verify(preserve);
 const tomb=await r.observe(old,{records:records.filter(x=>x.section!=="calendar-events"),omitted:[]},id,options);
 const deleted=storage({[note]:"keep",[manifest]:JSON.stringify(tomb)});await assert.rejects(()=>preview(deleted),/Tracked missing/);
 const marker=storage({[prefix+"revision-observed-delete:v1:"+id+":activity-spend"]:"1"});await assert.rejects(()=>preview(marker),/deletion history/);
 const stale=storage(),sp=await preview(stale);stale.setItem(note,"new");await assert.rejects(()=>apply(stale,sp),/changed/);assert.equal(stale.getItem(cal),null);
 const held=storage({[prefix+"training-session:"+id]:"held"});await assert.rejects(()=>preview(held),/Incomplete|training state/);
 const quota=storage(),qp=await preview(quota),qw=quota.setItem;quota.setItem=(k,v)=>{if(k===journal)throw Error("quota");qw(k,v);};await assert.rejects(()=>apply(quota,qp),/quota/);assert.equal(quota.length,0);
 async function interrupt(dest){const s=storage(),p=await preview(s),w=s.setItem;s.setItem=(k,v)=>{if(k===dest)throw Error("quota");w(k,v);};await assert.rejects(()=>apply(s,p),/journal retained/);s.setItem=w;return s;}
 for(const dest of [cal,ledger,lineage,manifest]){
   const s=await interrupt(dest),info=b.read(s,id);assert.equal(info.version,8);assert.equal(info.complete,false);assert.equal(info.conflict,false);
   assert.throws(()=>a.readJournal(s,id),/Invalid restore journal/);assert.throws(()=>a.trackedWrite(s,id,note,"bad"),/pending/);
   await assert.rejects(()=>b.recover(s,id,info.raw,"finish",yes,locks,options),/incomplete/);
   assert.equal((await b.recover(s,id,info.raw,"rollback",yes,locks,options)).status,"rolled-back");assert.equal(s.length,0);
 }
 const finish=storage(),fp=await preview(finish),remove=finish.removeItem;finish.removeItem=k=>{if(k===journal)throw Error("finalization");remove(k);};await assert.rejects(()=>apply(finish,fp),/journal retained/);
 assert.equal(b.read(finish,id).complete,true);finish.removeItem=remove;assert.equal((await b.recover(finish,id,b.read(finish,id).raw,"finish",yes,locks,options)).status,"finalized");await verify(finish);
 const conflict=await interrupt(manifest);conflict.setItem(cal,records[0].value);assert.equal(b.read(conflict,id).conflict,true);await assert.rejects(()=>b.recover(conflict,id,b.read(conflict,id).raw,"rollback",yes,locks,options),/Conflicting/);assert.ok(conflict.getItem(journal));
 const other=await interrupt(manifest);other.setItem(note,"independent");await assert.rejects(()=>b.recover(other,id,b.read(other,id).raw,"rollback",yes,locks,options),/Capture or review/);assert.ok(other.getItem(journal));
 const fake=await interrupt(manifest),raw=JSON.parse(fake.getItem(journal));raw.after.ledger=JSON.stringify([{id:"manual-fake",kind:"war",at:now,cost:1,source:"Manual confirmation"}]);fake.setItem(journal,JSON.stringify(raw));await assert.rejects(()=>b.recover(fake,id,fake.getItem(journal),"rollback",yes,locks,options),/Conflicting|missing sections only/);assert.ok(fake.getItem(journal));
 console.log((native?"Native Web Crypto ":"Deterministic digest ")+"V8 bootstrap: new and existing accounts, preserved revisions/lineage, tombstones, stale/held/lock guards, journal and destination faults, finish/rollback and conflict retention passed.");
}
module.exports=run;
if(require.main===module)run().then(()=>run({native:true})).catch(error=>{console.error(error);process.exitCode=1;});
