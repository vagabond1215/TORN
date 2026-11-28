"use strict";
/* Device-local disclosure preferences, independent of account backups.
 * Stable semantic keys only; never use changing heading text or positions.
 * Existing account-backed recommendation tiles, training timelines and
 * sidebar disclosure keep their established preference owners.
 */
const tornDisclosureState=(()=>{
  const storageKey="torn-city-guide:disclosures:v1",cap=2000,maxRaw=500000;
  const validKey=k=>typeof k==="string"&&k.length>0&&k.length<=600;
  const validValue=v=>typeof v==="boolean"||typeof v==="string"&&v.length<=160;
  function decode(raw){
    const result=new Map();
    if(typeof raw!=="string"||raw.length>maxRaw)return result;
    try{
      const x=JSON.parse(raw);
      if(!Array.isArray(x))return result;
      for(const e of x.slice(-cap))if(Array.isArray(e)&&e.length===2&&validKey(e[0])&&validValue(e[1]))result.set(e[0],e[1]);
    }catch{}
    return result;
  }
  function createStore(storage){
    let memory=new Map(),dirty=new Map();
    function read(){
      try{if(storage){memory=decode(storage.getItem(storageKey));for(const [k,v] of dirty)memory.set(k,v);}}catch{}
      return memory;
    }
    function get(k,fallback){const v=read().get(k);return typeof v===typeof fallback?v:fallback;}
    function set(k,v){
      if(!validKey(k)||!validValue(v))return;
      const data=read();
      if(data.get(k)===v&&!dirty.has(k))return;
      data.delete(k);data.set(k,v);dirty.delete(k);dirty.set(k,v);
      while(data.size>cap)data.delete(data.keys().next().value);
      while(dirty.size>cap)dirty.delete(dirty.keys().next().value);
      try{if(storage){const raw=JSON.stringify([...data]);if(raw.length<=maxRaw){storage.setItem(storageKey,raw);dirty.clear();}}}catch{}
    }
    return {get,set};
  }
  let storage;try{storage=globalThis.localStorage;}catch{}
  const prefs=createStore(storage);
  const account=()=>{try{return String(tornGuideApi.state.identity?.id??"guest");}catch{return "guest";}};
  const ownKey=name=>"account:"+account()+":"+name;
  const attrs=[["data-inventory-detail","inventory",true],["data-edu-group","edu-group",true],["data-tc-bonus-stat","stat-bonus",true],["data-rail-section","rail",false],["data-job-panel","job-panel",false],["data-ts-optimizer-settings","optimizer-settings",true],["data-ts-manual-settings","manual-settings",true],["data-rec-group","recommendation",true],["data-ts-timeline","training-timeline",true]];
  const delegated=el=>el.id==="sidebar-character"||el.hasAttribute("data-rec-group")||el.hasAttribute("data-ts-timeline");
  const part=el=>{
    const explicit=el.getAttribute("data-collapse-key");
    if(explicit)return explicit;
    for(const [attr,prefix,scoped] of attrs)if(el.hasAttribute(attr)){
      const value=prefix+":"+el.getAttribute(attr);
      return scoped?ownKey(value):value;
    }
    return null;
  };
  function keyFor(el){
    const leaf=part(el);if(!leaf||delegated(el))return null;
    const parents=[];
    let parent=el.parentElement?.closest("details");
    while(parent){const k=part(parent);if(k)parents.unshift(k);parent=parent.parentElement?.closest("details");}
    const root=el.closest("#guide-right-rail")?"rail":el.closest("#backup-dialog")?"backup":el.closest("#topic-view")?"topic":"static";
    return JSON.stringify([root,...parents,leaf]);
  }
  const initialized=new WeakMap();
  let observer=null;
  function restore(el){
    if(!el.isConnected||initialized.has(el))return;
    const key=keyFor(el);if(!key)return;
    const value=prefs.get(key,el.open);
    initialized.set(el,{key,open:value});
    if(el.open!==value)el.open=value;
  }
  function changed(el){
    if(!el.isConnected)return;
    const previous=initialized.get(el);
    // Initial toggles from freshly rendered HTML are not user decisions.
    if(!previous){restore(el);return;}
    if(previous.open===el.open)return;
    previous.open=el.open;prefs.set(previous.key,el.open);
  }
  function scan(node){
    if(node.nodeType!==1)return;
    if(node.matches("details"))restore(node);
    for(const el of node.querySelectorAll("details"))restore(el);
  }
  function init(root=document){
    if(observer)return;
    for(const el of root.querySelectorAll("details"))restore(el);
    root.addEventListener("toggle",event=>{if(event.target.matches?.("details"))changed(event.target);},true);
    observer=new MutationObserver(records=>{
      for(const record of records)if(record.type==="childList")for(const node of record.addedNodes)scan(node);
      for(const record of records)if(record.type==="attributes"&&record.target.matches("details"))changed(record.target);
    });
    observer.observe(root.documentElement??root,{subtree:true,childList:true,attributes:true,attributeFilter:["open"]});
  }
  function remember(el,value){
    if(!el||!el.isConnected||typeof value!=="boolean")return;
    const key=initialized.get(el)?.key??keyFor(el);
    if(key){prefs.set(key,value);const old=initialized.get(el);if(old)old.open=value;el.open=value;}
  }
  return Object.freeze({createStore,decode,keyFor,init,remember,get:prefs.get,set:prefs.set,ownKey,storageKey});
})();
if(typeof document!=="undefined"&&typeof MutationObserver!=="undefined")tornDisclosureState.init();
