"use strict";
const assert=require("node:assert/strict"),r=require("../log-records.js"),c=require("../log-coverage.js"),a=require("../log-archive.js");
const now=Date.UTC(2026,10,27),raw=(id,at=now)=>({id,timestamp:at/1000,details:{id:1,category:"Fixture",title:"Event"},data:{},params:{}});
const page=(rows,cursor,at=now)=>r.decodePage({log:rows,_metadata:{links:{prev:cursor===null?null:"opaque",next:null},...(cursor===null?{}:{nanostamp:cursor})}},"1",at);
const apply=(s,p)=>{const result=c.apply(s,c.task(s,p.observedAt),p);assert.equal(result.ok,true);assert.equal(a.validCheckpoint(result.checkpoint,"1"),true);return result.checkpoint;};
const empty=c.create("1");assert.equal(a.validCheckpoint(empty,"1"),true);
const initial=apply(empty,page([raw("a"),raw("b")],"123"));
const older=apply(initial,page([raw("c",now-1000)],"122",now+60000));
const pending=apply(older,page([raw("d",now+1000)],"200",now+300000));
const caught=apply(pending,page([raw("a")],"199",now+360000));
apply(caught,page([],null,now+420000));
apply(empty,page([],null)); // empty terminal
for(const bad of [{...empty,revision:1},{...initial,playerId:"2"},{...initial,head:null},{...initial,olderRecent:["123","123"]},{...initial,older:"999"},{...initial,lastPageAt:null},{...initial,extra:1},{...pending,pending:{...pending.pending,target:{id:"other",at:now}}},{...pending,pending:{...pending.pending,headAt:now-1000}},{...pending,pending:{...pending.pending,recent:["200","200"]}}])assert.equal(a.validCheckpoint(bad,"1"),false);
(async()=>{await assert.rejects(()=>a.open({indexedDB:null,IDBKeyRange:null}),/IndexedDB unavailable/);console.log("Archive checkpoint state validation and unsupported-storage gate passed.");})().catch(e=>{console.error(e);process.exitCode=1;});
