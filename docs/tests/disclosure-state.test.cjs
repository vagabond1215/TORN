"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const code=fs.readFileSync(path.join(__dirname,"..","disclosure-state.js"),"utf8");
const d=new Function(code+"\nreturn tornDisclosureState;")();
const storage=()=>{const m=new Map();return {getItem:k=>m.get(k)??null,setItem:(k,v)=>m.set(k,v)};};
const s=storage(),first=d.createStore(s),second=d.createStore(s);
assert.equal(first.get("a",true),true);first.set("a",false);assert.equal(second.get("a",true),false);
second.set("b",true);assert.equal(first.get("b",false),true);assert.equal(first.get("a",true),false);
first.set("choice","one");assert.equal(second.get("choice",""),"one");assert.equal(second.get("choice",false),false);
s.setItem(d.storageKey,"{");assert.equal(first.get("a",true),true);
s.setItem(d.storageKey,JSON.stringify([["valid",false],["__proto__",true],["invalid",{}],["other",true]]));
assert.equal(first.get("valid",true),false);assert.equal(first.get("invalid",false),false);
const denied=d.createStore({getItem:()=>{throw Error("denied")},setItem:()=>{throw Error("denied")}});
denied.set("closed",false);assert.equal(denied.get("closed",true),false);
const partial=d.createStore({getItem:()=>null,setItem:()=>{throw Error("quota")}});
partial.set("open",true);assert.equal(partial.get("open",false),true);
function el(attrs={},parent=null,root="topic",id=""){
 const x={id,parentElement:parent,getAttribute:k=>attrs[k]??null,hasAttribute:k=>Object.hasOwn(attrs,k)};
 x.closest=s=>s==="details"?x:s==="#topic-view"&&root==="topic"?true:s==="#guide-right-rail"&&root==="rail"?true:null;return x;
}
const a=el({"data-collapse-key":"networth:Cash"}),b=el({"data-collapse-key":"networth:Cash"},null,"rail");
assert.notEqual(d.keyFor(a),d.keyFor(b));
const row1=el({"data-inventory-detail":"Drug:1:0"}),row2=el({"data-inventory-detail":"Drug:2:0"});
assert.notEqual(d.keyFor(el({"data-collapse-key":"buyers"},row1)),d.keyFor(el({"data-collapse-key":"buyers"},row2)));
assert.equal(d.keyFor(el({"data-rec-group":"timeline"})),null);
assert.equal(d.keyFor(el({"data-ts-timeline":"natural"})),null);
assert.equal(d.keyFor(el({},null,"static","sidebar-character")),null);
assert.equal(d.keyFor(el({})),null);
// Synthetic observer: initial open/closed, rerender, user changes, removed
// elements and a second initialization as on full reload.
const nativeStorage=storage();let handler,notify;
const root={documentElement:{},querySelectorAll:()=>[],addEventListener:(type,fn)=>{handler=fn;}};
class Observer{constructor(fn){notify=fn;}observe(){}}
const boot=()=>new Function("document","MutationObserver","globalThis",code+"\nreturn tornDisclosureState;")(root,Observer,{localStorage:nativeStorage});
function detail(open,key){return Object.assign(el({"data-collapse-key":key}),{open,isConnected:true,nodeType:1,matches:s=>s==="details",querySelectorAll:()=>[]});}
const insert=x=>notify([{type:"childList",addedNodes:[x]}]),toggle=(x,v)=>{x.open=v;notify([{type:"attributes",target:x}]);handler({target:x});};
let live=boot(),initial=detail(true,"a");insert(initial);toggle(initial,false);
initial.isConnected=false;const rebuilt=detail(true,"a");insert(rebuilt);assert.equal(rebuilt.open,false);
toggle(rebuilt,true);const closed=detail(false,"a");insert(closed);assert.equal(closed.open,true);
initial.open=true;handler({target:initial});assert.equal(closed.open,true);
live=boot();const reload=detail(false,"a");insert(reload);assert.equal(reload.open,true);
live.remember(reload,false);const later=detail(true,"a");insert(later);assert.equal(later.open,false);
console.log("Disclosure store: persistence, reload, nested keys, legacy ownership, observer rebuild and storage failure passed.");
