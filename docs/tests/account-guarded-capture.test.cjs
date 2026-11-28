"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,l,g}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-lineage.js","account-guarded-capture.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,l:tornCalendarLineage,g:tornGuardedCapture};")();
const id="123",prefix="torn-city-guide:",cal=prefix+"activity-events:"+id,ledger=prefix+"activity-spend-ledger:"+id,lk=prefix+"calendar-lineage:v1:"+id,note=prefix+"v1:profile:"+id+":notes:gym",mark=prefix+"revision-observed-delete:v1:"+id+":",mk=r.key(id),jk=a.journalKey(id);
function storage(entries={}){const m=new Map(Object.entries(entries));return {get length(){return m.size},key:i=>[...m.keys()][i]??null,getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)};}
function lock(){let held=false,tail=Promise.resolve(),calls=0;return {get calls(){return calls},request(name,opts,fn){assert.equal(name,prefix+"account-recovery:"+id);assert.equal(opts.mode,"exclusive");calls++;const p=tail.then(async()=>{assert.equal(held,false);held=true;try{return await fn()}finally{held=false}});tail=p.catch(()=>{});return p;}};}
let n=0;const hashes=new Map(),digest=async v=>{if(!hashes.has(v))hashes.set(v,String(hashes.size+1).padStart(64,"0"));return hashes.get(v);},opts={digest,newRevision:()=>String(++n).padStart(32,"0")};
const current=()=>true,legacy={...opts,mode:"legacy"},protectedMode={...opts,mode:"protected"},event=JSON.stringify([{id:"e1",kind:"personal",title:"Test",start:1000,end:2000,blocking:false,source:"manual"}]);
async function run(){
 const locks=lock(),s=storage({[cal]:"[]",[ledger]:"[]",[note]:"A"});
 await assert.rejects(()=>g.capture(s,id,current,locks,opts),/mode/);
 await assert.rejects(()=>g.capture(s,id,current,null,legacy),/Web Locks/);
 await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/lineage/);
 const first=await g.capture(s,id,current,locks,legacy);
 assert.equal(first.changed,true);
 const lineage=JSON.stringify(await l.initialize(first,id,opts));s.setItem(lk,lineage);
 await assert.rejects(()=>g.capture(s,id,current,locks,legacy),/lineage installed/);
 const before=s.getItem(mk);
 s.setItem(note,"B");
 const next=await g.capture(s,id,current,locks,protectedMode);
 assert.equal(next.changed,true);assert.equal(s.getItem(lk),lineage);
 for(const section of ["calendar-events","activity-spend"])assert.deepEqual(next.manifest.entries.find(e=>e.section===section),first.manifest.entries.find(e=>e.section===section));
 assert.equal((await g.capture(s,id,current,locks,protectedMode)).changed,false);
 const safeRaw=s.getItem(mk);
 s.setItem(cal,event);await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/digest/);assert.equal(s.getItem(mk),safeRaw);s.setItem(cal,"[]");
 s.setItem(ledger,JSON.stringify([{id:"manual-x",kind:"war",at:1000,cost:5,source:"Manual confirmation"}]));await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/digest/);s.setItem(ledger,"[]");
 s.setItem(mark+"calendar-events","1");await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/deletion marker/);s.removeItem(mark+"calendar-events");
 s.removeItem(ledger);await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/Missing or deleted/);s.setItem(ledger,"[]");
 s.removeItem(lk);await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/lineage/);s.setItem(lk,lineage);
 s.setItem(lk,JSON.stringify({...JSON.parse(lineage),sectionDigest:"f".repeat(64)}));await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/lineage binding/);s.setItem(lk,lineage);
 s.setItem(jk,"{}");await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/journal pending/);s.removeItem(jk);
 s.setItem(prefix+"training-session:"+id,"{}");await assert.rejects(()=>g.capture(s,id,current,locks,protectedMode),/training session/);s.removeItem(prefix+"training-session:"+id);
 s.setItem(note,"C");let valid=true;
 await assert.rejects(()=>g.capture(s,id,()=>valid,locks,{...protectedMode,digest:async v=>{valid=false;return digest(v)}}),/epoch/);assert.equal(s.getItem(mk),safeRaw);
 // A writer from an older tab changes calendar bytes during digest.
 await assert.rejects(()=>g.capture(s,id,current,locks,{...protectedMode,digest:async v=>{s.setItem(cal,event);return digest(v)}}),/changed/);assert.equal(s.getItem(mk),safeRaw);s.setItem(cal,"[]");
 await assert.rejects(()=>g.capture(s,id,current,locks,{...protectedMode,digest:async v=>{s.setItem(lk,lineage+" ");return digest(v)}}),/changed/);s.setItem(lk,lineage);
 await assert.rejects(()=>g.capture(s,id,current,locks,{...protectedMode,digest:async v=>{s.setItem(mark+"notes:gym","1");return digest(v)}}),/changed/);s.removeItem(mark+"notes:gym");
 // Concurrent manifest replacement during observation must be preserved.
 const replacement=JSON.stringify({...r.read(s,id),entries:r.read(s,id).entries.map(e=>e.section==="notes:gym"?{...e,revision:"e".repeat(32)}:e)});
 await assert.rejects(()=>g.capture(s,id,current,locks,{...protectedMode,digest:async v=>{s.setItem(mk,replacement);return digest(v)}}),/changed/);assert.equal(s.getItem(mk),replacement);s.setItem(mk,safeRaw);
 // Ordinary observed deletion is allowed, marker remains durable.
 a.trackedWrite(s,id,note,null);
 const deleted=await g.capture(s,id,current,locks,protectedMode);assert.equal(deleted.manifest.entries.find(e=>e.section==="notes:gym").digest,null);assert.equal(s.getItem(mark+"notes:gym"),"1");
 // Cooperating captures serialize, including an unrelated writer.
 s.setItem(note,"D");const [one,two]=await Promise.all([g.capture(s,id,current,locks,protectedMode),g.capture(s,id,current,locks,protectedMode)]);
 assert.equal(one.changed,true);assert.equal(two.changed,false);
 // Missing lineage requires explicit legacy mode only before migration.
 const empty=storage();assert.equal((await g.capture(empty,id,current,locks,legacy)).changed,false);assert.equal(empty.getItem(mk),null);
 assert.equal(s.getItem(r.key("456")),null);
 console.log("Guarded capture: explicit modes/lock, protected digest and lineage, ordinary writes/deletions, journal/session holds, epoch, old-tab races and serialized captures passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
