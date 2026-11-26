"use strict";
// Run from repository root: node docs/tests/personal-log.test.cjs
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const read=name=>fs.readFileSync(path.join(__dirname,"..",name),"utf8");
const script=read("torn-companion.user.js"),source=script.split("// BEGIN personal log helpers")[1].split("// END personal log helpers")[0];
const x=new Function(source+"\nreturn {ownLogRoute,logTime,mergeLogRows,readVisibleLogRows,logRow};")();
const now=Date.UTC(2026,10,26,12),loc={hostname:"www.torn.com",protocol:"https:",pathname:"/page.php",search:"?sid=log&cat=13"};
assert.equal(x.ownLogRoute(loc),true);
for(const search of ["?sid=log&otherUser=10","?sid=log&user_id=1","?sid=ItemMarket","?sid=log&sid=log","?sid=log&%6FtherUser=1"])assert.equal(x.ownLogRoute({...loc,search}),false);
assert.equal(x.logTime("12:00:00 - 26/11/26"),now);
assert.equal(x.logTime("12:00:00 - 26/11/2026 TCT"),now);
assert.equal(x.logTime("2026-11-26T12:00:00Z"),now);
assert.equal(x.logTime("12:00:00 - 31/11/26"),null);
assert.equal(x.logTime("24:00:00 - 26/11/26"),null);
assert.equal(x.logTime("Today"),null);
const row={at:now,text:"You used Xanax"};
assert.equal(x.mergeLogRows([row],[row,row],now).length,2);
assert.equal(x.mergeLogRows([row,row],[row,row],now).length,2);
assert.equal(x.logRow(now,"api key: secret",now).text,"api key: [redacted]");
assert.equal(x.logRow(now+600000,"future",now),null);
assert.equal(x.mergeLogRows([],Array.from({length:2100},(_,i)=>({at:now-i*1000,text:"entry "+i})),now).length,2000);
function element(text,date,{hidden=false,raw=false}={}){
 const cell={innerText:date,getAttribute:()=>null,hidden:false};
 const tr={hidden,querySelector:()=>cell};
 return {innerText:text,hidden,closest:()=>tr,matches:()=>!raw};
}
const one=element("You used Xanax","12:00:00 - 26/11/26"),two=element("You trained strength","11:59:00 - 26/11/26"),hidden=element("Do not capture","11:58:00 - 26/11/26",{hidden:true}),invalid=element("Date unknown","Yesterday"),unknown=element("Other text","Yesterday",{raw:true});
const capture=x.readVisibleLogRows({querySelectorAll:()=>[one,one,two,hidden,invalid,unknown]},el=>!el.hidden,now);
assert.equal(capture.rows.length,2);assert.equal(capture.matched,3);assert.equal(capture.skipped,1);
const win={addEventListener:()=>{}},doc={addEventListener:()=>{}};
const mod=new Function("tornGuideApi","window","document",read("log-guide.js")+"\nreturn tornLogGuide;")({isConnected:()=>true,state:{identity:{id:1}}},win,doc);
assert.equal(mod.validate({version:1,playerId:2,rows:[row]},1,now),null);
assert.equal(mod.validate({version:1,playerId:1,rows:[row,{at:now,text:""},{at:now+3600000,text:"future"}]},1,now).rows.length,1);
assert.equal(mod.filterRows([row],"xanax","2026-11-26").length,1);
assert.equal(mod.filterRows([row],"xanax","2026-11-25").length,0);
assert.ok(read("guide.js").includes('route === "log"'));
assert.ok(read("guide-features.js").includes("log:[]"));
assert.ok(read("index.html").includes("log-guide.js?v="));
console.log("Personal log route, timestamps, visible-row capture, deduplication, cap, account isolation and filters passed.");
