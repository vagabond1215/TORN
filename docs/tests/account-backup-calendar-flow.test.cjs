"use strict";
// Actual backup UI + actual calendar planner, synthetic authenticated
// envelopes and deterministic digest, mocked DOM/lock/transport.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const {a,r,m,u,recovery}=new Function(["training-recovery.js","account-storage.js","account-revisions.js","account-calendar-merge.js","account-calendar-preview-ui.js"].map(read).join("\n")+"\nreturn {a:tornAccountStorage,r:tornAccountRevisions,m:tornCalendarMerge,u:tornCalendarPreviewUI,recovery:tornTrainingRecovery};")();
const id="123",section="calendar-events",now=Date.UTC(2026,10,27),cal="torn-city-guide:activity-events:"+id,note="torn-city-guide:v1:profile:"+id+":notes:gym";
let n=0;const digests=new Map(),digest=async v=>{if(!digests.has(v))digests.set(v,String(digests.size+1).padStart(64,"0"));return digests.get(v);};
const options={digest,newRevision:()=>String(++n).padStart(32,"0")},event=(key,title=key,kind="personal")=>({id:key,kind,title,start:now,end:now+60000,blocking:false,source:"manual"});
async function make(prior,events,notes="local note"){const records=[{section,value:JSON.stringify(events)},{section:"notes:gym",value:notes}],omitted=[];return {records,omitted,manifest:await r.observe(prior,{records,omitted},id,options)};}
const walk=x=>[x,...x.children.filter(y=>typeof y==="object").flatMap(walk)];
function node(tag){
 const x={tag,children:[],textContent:"",value:"",type:"",checked:false,disabled:false,hidden:false,open:false,files:[],events:{},
 append(...v){this.children.push(...v);},replaceChildren(){this.children=[];},setAttribute(){},
 addEventListener(k,f){this.events[k]=f;},querySelectorAll(q){return walk(this).filter(n=>n!==this&&n.tag==="input"&&(q!=="input:checked"||n.checked));},
 querySelector(q){return this.querySelectorAll(q)[0]??null;},showModal(){this.open=true;},close(){this.open=false;this.events.close?.();}};
 return x;
}
async function run(){
 const base=await make(r.empty(id),[event("conflict"),event("independent"),event("war","War","war")]);
 const local=await make(base.manifest,[event("conflict","Local edit"),event("independent"),event("war","War","war")]);
 const incoming=await make(base.manifest,[event("conflict","Remote edit"),event("independent","Incoming edit"),event("war","Remote war","war")],"remote note");
 const store=new Map([[cal,local.records[0].value],[note,local.records[1].value],[r.key(id),JSON.stringify(local.manifest)]]);
 const storage={get length(){return store.size;},key:i=>[...store.keys()][i]??null,getItem:k=>store.get(k)??null,setItem:(k,v)=>store.set(k,String(v)),removeItem:k=>store.delete(k)};
 const nodes=new Map(),get=k=>{if(!nodes.has(k))nodes.set(k,node("div"));return nodes.get(k);};
 const win={events:{},addEventListener(k,f){this.events[k]=f;},confirm:()=>{throw Error("Unexpected write confirmation");}};
 const doc={getElementById:get,createElement:node,createTextNode:text=>text};
 const state={identity:{id:123}};let epoch=1,verifies=0,decrypts=0,writes=0;
 const api={state,isConnected:()=>true,verifyBackupOwner:async()=>{verifies++;const e=epoch;return {playerId:id,isCurrent:()=>epoch===e&&state.identity.id===123};}};
 const revisions={...r,capture:(s,i,g)=>r.capture(s,i,g,options),planMerge:(a,b,i)=>r.planMerge(a,b,i,options),applyMerge:()=>{writes++;throw Error("Unexpected preference write");}};
 const merge={preview:(a,b,i,o={})=>m.preview(a,b,i,{...options,...o}),resolve:(a,b,i,d,o={})=>m.resolve(a,b,i,d,{...options,...o})};
 const backup={maxFile:100000,decrypt:async(text,i,password)=>{decrypts++;assert.equal(i,id);assert.equal(password,"fixture passphrase");if(text==="incoming")return incoming;if(text==="base")return base;throw Error("Invalid common backup");}};
 const nav={locks:{request:async(n,o,f)=>f()}},loc={reload:()=>{throw Error("Unexpected reload");}};
 const before=JSON.stringify([...store]);
 const ui=new Function("document","window","localStorage","navigator","location","tornGuideApi","tornAccountStorage","tornAccountRevisions","tornTrainingRecovery","tornAccountBackup","tornCalendarMerge","tornCalendarPreviewUI",read("account-backup-ui.js")+"\nreturn tornBackupUI;")(doc,win,storage,nav,loc,api,a,revisions,recovery,backup,merge,u);
 ui.wire();
 const click=k=>get(k).events.click();
 const settle=async()=>{for(let i=0;i<240;i++)await Promise.resolve();};
 const file=(key,text)=>{get(key).files=[{size:10,text:async()=>text}];};
 click("backup-open");get("backup-passphrase").value="fixture passphrase";file("backup-file","incoming");
 click("backup-import");await settle();
 const panel=get("backup-calendar-review"),rows=get("backup-calendar-rows"),status=get("backup-calendar-status");
 assert.equal(panel.hidden,false);assert.ok(status.textContent.includes("conflict"));
 assert.equal(walk(rows).filter(x=>x.tag==="select").length,0);assert.equal(get("backup-passphrase").value,"");
 file("backup-calendar-base-file","bad");get("backup-calendar-base-secret").value="fixture passphrase";await click("backup-calendar-base");
 assert.ok(status.textContent.includes("could not be verified"));assert.equal(get("backup-calendar-base-secret").value,"");
 file("backup-calendar-base-file","base");get("backup-calendar-base-secret").value="fixture passphrase";await click("backup-calendar-base");
 assert.ok(status.textContent.includes("Verified common"));const selects=walk(rows).filter(x=>x.tag==="select");
 assert.equal(selects.length,2);assert.equal(get("backup-calendar-preview").disabled,true);
 selects[0].value="take-incoming";selects[0].events.change();assert.equal(get("backup-calendar-preview").disabled,false);
 await click("backup-calendar-preview");
 assert.ok(status.textContent.includes("1 selected incoming records"));assert.ok(status.textContent.includes("Nothing saved"));
 assert.equal(writes,0);assert.equal(JSON.stringify([...store]),before);assert.equal(verifies,1);assert.equal(decrypts,3);
 storage.setItem(note,"changed elsewhere");win.events["torn-account-write"]();
 assert.equal(panel.hidden,true);assert.equal(rows.children.length,0);assert.equal(get("backup-calendar-preview").disabled,true);
 assert.equal(get("backup-comparison").children.length,0);
 storage.setItem(note,local.records[1].value);
 get("backup-passphrase").value="fixture passphrase";file("backup-file","incoming");click("backup-import");await settle();
 assert.equal(panel.hidden,false);epoch++;win.events["torn-guide-sync"]();assert.equal(panel.hidden,true);
 get("backup-dialog").close();assert.equal(get("backup-calendar-base-secret").value,"");assert.equal(rows.children.length,0);
 assert.equal(writes,0);console.log("Backup dialog import, common-base rejection/verification, preview-only selection, no writes/API expansion, local edit and epoch invalidation passed.");
}
module.exports=run;
if(require.main===module)run().catch(error=>{console.error(error);process.exitCode=1;});
