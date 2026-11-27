"use strict";
const assert=require("node:assert/strict"),r=require("../log-records.js");
const now=Date.UTC(2026,10,27),row=(id="a",data={})=>({id,timestamp:now/1000,details:{id:123,category:"Fixture",title:"Fixture event"},data,params:{secret:"discard-me"}});
const page=(rows,meta={links:{prev:null,next:null}})=>({log:rows,_metadata:meta});
const raw=page([row("a",{quantity:2,amount:-12.5,stat:1,api_key:"discard-me",item_name:"discard-me",nested:{value:10},money:"300",price:Infinity}),row("b")],{links:{prev:"https://example.invalid/?key=discard-me",next:null},nanostamp:"1760000000000000001"});
const p=r.decodePage(raw,123,now);
assert.equal(p.playerId,"123");assert.equal(p.cursor,"1760000000000000001");assert.equal(p.continuation,"more");
assert.equal(p.records.length,2);assert.equal(p.records[0].occurredAt,now);assert.equal(p.records[0].typeId,123);
assert.deepEqual(p.records[0].fields,{amount:-12.5,quantity:2,stat:1});
assert.ok(!JSON.stringify(p).includes("discard-me"));assert.ok(!JSON.stringify(p).includes("https://"));
assert.equal(r.classify(null,p.records[0]),"insert");
assert.equal(r.classify(p.records[0],r.decodePage(raw,"123",now+1).records[0]),"duplicate");
assert.equal(r.classify(p.records[0],{...p.records[0],fields:{quantity:3}}),"conflict");
assert.throws(()=>r.classify(p.records[0],{...p.records[0],playerId:"456"}),/identity/);
assert.equal(r.decodePage(page([]),123,now).continuation,"terminal");
assert.equal(r.decodePage(page([],{links:{prev:"x",next:null}}),123,now).continuation,"unknown");
assert.equal(r.decodePage(page([],{links:{prev:null,next:null},nanostamp:"123"}),123,now).continuation,"unknown");
assert.equal(r.decodePage(page([],{links:{prev:"x",next:null},nanostamp:1760000000000000001}),123,now).cursor,null);
for(const malformed of [
  page([row(),row()]),page(Array.from({length:101},(_,i)=>row(String(i)))),page([{...row(),timestamp:"1760000000"}]),
  page([{...row(),timestamp:now/1000+301}]),page([{...row(),details:{id:"123",title:"x",category:"x"}}]),
  page([{...row(),data:[]}]),page([{...row(),params:null}]),page([row("https://example.invalid")]),page([row("bad\nid")]),
  page([{...row(),timestamp:now/1000-1},row("b")]),{log:[row()],_metadata:{}},{error:{code:5},...page([])}
])assert.throws(()=>r.decodePage(malformed,123,now),/Invalid API log/);
for(const id of [0,"guest","01",null,NaN])assert.throws(()=>r.decodePage(page([]),id,now),/Invalid API log/);
const polluted=JSON.parse('{"__proto__":{"secret":"discard-me"},"constructor":1,"quantity":1}');
assert.deepEqual(r.decodePage(page([row("a",polluted)]),123,now).records[0].fields,{quantity:1});
console.log("Typed log records, exact IDs/cursor, bounded numeric fields, duplicate/conflict and malformed-page tests passed.");
