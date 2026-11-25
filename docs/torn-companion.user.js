// ==UserScript==
// @name         Torn City Guide - Passive Visible Status Bridge
// @namespace    https://vagabond1215.github.io/TORN/
// @version      2.3.0
// @description  Synchronize visible status bars and ranked market observations to your local Torn City Guide. Read-only, no API key or network calls.
// @match        https://www.torn.com/*
// @match        https://torn.com/*
// @match        https://vagabond1215.github.io/TORN/*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_addValueChangeListener
// @run-at       document-idle
// ==/UserScript==
(function(){
  "use strict";
  const key="torn-city-guide:passive-bars:v2";
  const marketKey="torn-city-guide:passive-rw:v1";
  const guideOrigin="https://vagabond1215.github.io";
  const refreshAge=60*1000;
  const isTorn=location.hostname==="www.torn.com"||location.hostname==="torn.com";
  const isGuide=location.origin===guideOrigin&&location.pathname.startsWith("/TORN/");
  if(window.top!==window)return;
  if(isGuide){
    const share=()=>{
      const packet=GM_getValue(key,null);
      if(!packet||packet.version!==2||!Number.isInteger(packet.playerId)||
        !Number.isFinite(packet.timestamp)||packet.timestamp>Date.now()+5000)return;
      // Only 4 allowlisted bar objects and player ID cross the origin boundary.
      window.dispatchEvent(new CustomEvent("torn-guide-local-snapshot",{
        detail:JSON.stringify(packet)
      }));
    };
    const shareMarket=()=>{
      const packet=GM_getValue(marketKey,null);
      const snapshot=packet?.version===1&&Array.isArray(packet.rows)?packet:{version:1,rows:[]};
      window.dispatchEvent(new CustomEvent("torn-guide-rw-snapshot",{detail:JSON.stringify({...snapshot,companionVersion:"2.3.0",bridgeAt:Date.now()})}));
    };
    window.addEventListener("torn-guide-request-snapshot",shareMarket);
    GM_addValueChangeListener(marketKey,shareMarket);
    setTimeout(shareMarket,1200);
    window.addEventListener("focus",shareMarket);
    window.addEventListener("torn-guide-request-snapshot",share);
    GM_addValueChangeListener(key,()=>share());
    if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",share,{once:true});
    else share();
    setTimeout(share,1200);
    window.addEventListener("focus",share);
    document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")share();});
    return;
  }
  if(!isTorn)return;
  function extractOwnId(){
    for(const element of Array.from(document.querySelectorAll('input[type="hidden"]')).slice(0,80)){
      const value=element.value||"";
      if(value.length>1500||!value.includes('"playername"')||!value.includes('"id"'))continue;
      try{
        const valueObject=JSON.parse(value);
        if(Number.isInteger(Number(valueObject.id))&&Number(valueObject.id)>0)return Number(valueObject.id);
      }catch{}
    }
    return null;
  }
  function extract(){
    // Read only the visible status sidebar of a loaded page. Never store raw DOM text.
    const id=extractOwnId();
    if(!id)throw Error("Unable to verify your Torn player ID on this page.");
    let text="";
    const known=["#sidebar","#sidebar-wrapper",'[class*="sidebar"]'];
    for(const selector of known){
      const el=document.querySelector(selector);
      if(el && /Energy/i.test(el.innerText||"") && /Nerve/i.test(el.innerText||"")){
        text=String(el.innerText||"").slice(0,10000);break;
      }
    }
    if(!text){
      const body=String(document.body?.innerText||"");
      const match=/\bInformation\s*\n/i.exec(body);
      if(!match)throw Error("Torn status sidebar was not found.");
      const after=body.slice(match.index+match[0].length,match.index+match[0].length+4000);
      const areas=after.search(/\bAreas\b/i);
      text=areas>=0?after.slice(0,areas):after;
    }
    const bars={};
    for(const name of ["energy","nerve","happy","life"]){
      const pattern=new RegExp("\\b"+name+"\\s*:?\\s*([\\d,]{1,12})\\s*\\/\\s*([\\d,]{1,12})","i");
      const match=text.match(pattern);
      if(match){
        const current=Number(match[1].replace(/,/g,"")),maximum=Number(match[2].replace(/,/g,""));
        if(maximum>0&&current>=0&&current<=maximum+100000)bars[name]={current,maximum};
      }
    }
    if(!Object.keys(bars).length)throw Error("No readable Energy/Nerve/Happy/Life values found.");
    return {version:2,playerId:id,timestamp:Date.now(),bars};
  }
  const marketTTL=72*60*60*1000;
  function marketRoute(){
    if(location.pathname!=="/page.php"||new URLSearchParams(location.search).get("sid")!=="ItemMarket")return null;
    const q=new URLSearchParams(location.hash.replace(/^#\/market\//,""));
    const category=q.get("categoryName");
    return ["Primary","Secondary","Melee","Armor","Defensive"].includes(category)?{category,rarity:({"1":"yellow","2":"orange","3":"red"})[q.get("rarity")]??null}:null;
  }
  function rendered(el){
    return el&&el.getClientRects().length>0&&getComputedStyle(el).visibility==="visible";
  }
  function parseRankedCard(text,name,price,route){
    const get=label=>{const m=text.match(new RegExp("(?:^|\\n)\\s*"+label+"\\s*:\\s*([\\d.]+)","i"));return m?Number(m[1]):null;};
    const quality=get("Quality"),damage=get("Damage"),accuracy=get("Accuracy"),armor=get("Armor");
    const explicit=text.match(/(?:^|\n)\s*(Y\s*ellow|O\s*range|R\s*ed)\s*(?:\n|$)/i);
    const rarity=explicit?explicit[1].replace(/\s/g,"").toLowerCase():route.rarity;
    if(!rarity)return null;
    const bonusSection=text.match(/(?:^|\n)\s*Bonus(?:es)?\s*:\s*([\s\S]*?)(?=\n\s*(?:Quality|Damage|Accuracy|Armor|Rate of Fire|Coverage|Stealth|Ammo|Caliber)\s*:|$)/i);
    const bonuses=bonusSection?Array.from(bonusSection[1].matchAll(/(\d+(?:\.\d+)?)\s*%\s*([A-Za-z][A-Za-z '-]{0,40})(?=\s*(?:\n|,|$))/g),m=>({value:Number(m[1]),title:m[2].trim()})):[];
    const complete=quality!==null&&bonuses.length>0&& (armor!==null||damage!==null&&accuracy!==null);
    const rate=text.match(/Rate of Fire\s*:\s*(\d+)\s*[-–]\s*(\d+)/i),ammo=text.match(/Ammo\s*:\s*(\d+)\s*[x×]\s*(\d+)/i);
    const stats={};for(const [k,v] of Object.entries({quality,damage,accuracy,armor}))if(v!==null)stats[k]=v;
    return {name,category:route.category,rarity,price,stats,bonuses,complete,rate:rate?[Number(rate[1]),Number(rate[2])]:null,ammo:ammo?[Number(ammo[1]),Number(ammo[2])]:null};
  }
  // Incremental market collector: no periodic full-page market scan.
  const buySelector='button[aria-label^="Buy item "]';
  const infoSelector='button[aria-label^="View info for item "]';
  const active=()=>document.visibilityState==="visible"&&document.hasFocus();
  const maxStored=2500,maxQueue=12000;
  let routeKey="",route=null,queue=new Set(),cards=new WeakMap(),owners=new WeakMap(),seen=new WeakMap(),boundaries=new WeakSet();
  let workTimer=null,flushTimer=null,dirty=false,lastFlush=0,lastCapture=null,stored=null,metrics=null;
  function freshMetrics(){return {buttons:0,rendered:0,matched:0,ranked:0,accepted:0,complete:0,duplicates:0,added:0,processed:0,batches:0,maxBatchMs:0,queued:0,dropped:0};}
  function rowKey(row){return row.uid?"uid:"+row.uid:row.fingerprint;}
  function readStore(){
    if(stored)return stored;
    const p=GM_getValue(marketKey,null);
    stored=new Map();lastCapture=p?.diagnostic?.lastCapture??null;
    for(const r of Array.isArray(p?.rows)?p.rows:[])if(r&&Number.isFinite(r.at)&&Date.now()-r.at<marketTTL&&rowKey(r))stored.set(rowKey(r),r);
    return stored;
  }
  function flush(){
    if(flushTimer!==null){clearTimeout(flushTimer);flushTimer=null;}
    if(!dirty||!metrics||!route)return;
    // Merge the latest persisted records once per write, not once per card.
    const prior=GM_getValue(marketKey,null),stamp=Date.now(),map=new Map();
    for(const r of Array.isArray(prior?.rows)?prior.rows:[])if(r&&stamp-r.at<marketTTL&&rowKey(r))map.set(rowKey(r),r);
    for(const [k,r] of readStore()){const old=map.get(k);if(stamp-r.at<marketTTL&&(!old||r.complete&&!old.complete||r.complete===old.complete&&r.at>=old.at))map.set(k,r);}
    const rows=Array.from(map.values()).sort((a,b)=>Number(b.complete)-Number(a.complete)||b.at-a.at).slice(0,maxStored);
    stored=new Map(rows.map(r=>[rowKey(r),r]));
    const diagnostic={...metrics,at:stamp,lastCapture,category:route.category,rarity:route.rarity,queued:queue.size,mode:"incremental"};
    GM_setValue(marketKey,{version:1,diagnostic,rows});
    lastFlush=stamp;dirty=false;
  }
  function scheduleFlush(){
    dirty=true;
    if(flushTimer===null)flushTimer=setTimeout(flush,Math.max(1000,30000-(Date.now()-lastFlush)));
  }
  function enqueue(button,force=false){
    if(!button?.isConnected||!button.matches(buySelector))return;
    if(!force&&seen.has(button))return;
    if(queue.size>=maxQueue&&!queue.has(button)){metrics.dropped++;return;}
    queue.add(button);
  }
  function locateCard(button,name){
    const cached=cards.get(button);
    if(cached?.isConnected&&cached.contains(button))return cached;
    let best=null;
    for(let el=button.parentElement,depth=0;el&&depth<9;el=el.parentElement,depth++){
      if(boundaries.has(el))break;
      const buttons=el.querySelectorAll(buySelector);
      if(buttons.length!==1){boundaries.add(el);break;}
      if(Array.from(el.querySelectorAll(infoSelector)).some(b=>b.getAttribute("aria-label")==="View info for item "+name+"."))best=el;
    }
    if(best){cards.set(button,best);owners.set(best,button);}
    return best;
  }
  function process(button){
    metrics.processed++;
    if(!button.isConnected||!rendered(button))return;
    metrics.rendered++;
    const label=button.getAttribute("aria-label")||"",m=label.match(/^Buy item (.+), \$([\d,]+), 1 in total\.$/);
    if(!m)return;
    const name=m[1],price=Number(m[2].replace(/,/g,""));
    if(!Number.isSafeInteger(price)||price<=0)return;
    const card=locateCard(button,name);if(!card||!rendered(card))return;
    metrics.matched++;
    const text=card.innerText||"",previous=seen.get(button);
    if(previous?.text===text&&previous?.label===label)return;
    seen.set(button,{text,label});
    const row=parseRankedCard(text,name,price,route);if(!row)return;
    metrics.ranked++;
    if(!row.complete){
      const nums=text.split(/\n/).map(x=>x.trim()).filter(x=>/^\d{1,3}\.\d{2}$/.test(x)).map(Number);
      if(["Armor","Defensive"].includes(route.category)){if(nums.length===1)row.stats.armor=nums[0];}
      else if(nums.length===2){row.stats.damage=nums[0];row.stats.accuracy=nums[1];}
      // Only explicit, rendered card-local labels qualify. No hidden app state,
      // network interception, arbitrary data attributes, or generic page text.
      const hints=[];
      for(const el of card.querySelectorAll("[title],[aria-label]")){
        if(!rendered(el))continue;
        for(const attr of ["title","aria-label"]){
          const value=el.getAttribute(attr)||"";
          if(/^(?:Quality|Bonus(?:es)?)\s*:/i.test(value)&&value.length<=180)hints.push(value);
        }
      }
      if(hints.length){
        const extra=parseRankedCard(text+"\n"+Array.from(new Set(hints)).join("\n"),name,price,route);
        if(extra){Object.assign(row.stats,extra.stats);if(extra.bonuses.length)row.bonuses=extra.bonuses;}
      }
      // An explicitly expanded row is the only proven complete bonus signature.
      // Tooltip-only bonuses can be partial; retain them but do not mark complete.
    }
    const uid=card.getAttribute("data-uid")||card.getAttribute("data-item-uid");
    if(uid&&/^[1-9]\d*$/.test(uid))row.uid=uid;
    if(!Object.keys(row.stats).length) return;
    row.fingerprint=JSON.stringify([name,row.rarity,price,row.stats,row.bonuses]);
    row.at=Date.now();lastCapture=row.at;metrics.accepted++;if(row.complete)metrics.complete++;
    const map=readStore(),k=rowKey(row),prev=map.get(k);
    if(prev){metrics.duplicates++;if(prev.complete&&!row.complete)return;}
    else metrics.added++;
    map.set(k,row);
    // Bound transient memory even when loading a very long market page.
    if(map.size>maxStored+500){
      const keep=Array.from(map.values()).sort((a,b)=>Number(b.complete)-Number(a.complete)||b.at-a.at).slice(0,maxStored);
      stored=new Map(keep.map(r=>[rowKey(r),r]));
    }
  }
  function runBatch(){
    workTimer=null;
    if(!active()||!route||location.hash!==routeKey)return;
    const start=performance.now();let n=0;
    while(queue.size&&n<24&&performance.now()-start<8){
      const button=queue.values().next().value;queue.delete(button);
      try{process(button);}catch{}n++;
    }
    metrics.batches++;metrics.maxBatchMs=Math.max(metrics.maxBatchMs,Math.round(performance.now()-start));metrics.queued=queue.size;
    scheduleFlush();
    if(queue.size)kick();
  }
  function kick(){if(workTimer===null&&queue.size&&active())workTimer=setTimeout(runBatch,40);}
  function resetMarket(){
    if(!active())return;
    const next=marketRoute(),hash=location.hash;
    if(hash===routeKey&&route){kick();return;}
    if(dirty)flush();
    routeKey=hash;route=next;queue.clear();cards=new WeakMap();owners=new WeakMap();seen=new WeakMap();boundaries=new WeakSet();metrics=freshMetrics();
    if(!route)return;
    // Initial scan once per manually selected route. Subsequent work uses mutations.
    setTimeout(()=>{
      if(!active()||!route||location.hash!==hash||routeKey!==hash)return;
      for(const button of document.querySelectorAll(buySelector)){metrics.buttons++;enqueue(button);}
      scheduleFlush();kick();
    },600);
  }
  function ownerOf(node){
    for(let el=node?.nodeType===1?node:node?.parentElement,depth=0;el&&depth<12;el=el.parentElement,depth++){
      const b=owners.get(el);if(b)return b;
    }
    return null;
  }
  function marketMutations(records){
    if(!active())return;
    if(location.hash!==routeKey||!route){resetMarket();return;}
    if(!marketRoute())return;
    for(const r of records){
      if(r.type==="attributes"){
        if(r.target.matches?.(buySelector)){enqueue(r.target,true);continue;}
        const b=ownerOf(r.target);if(b)enqueue(b,true);
      }else{
        const b=ownerOf(r.target);if(b)enqueue(b,true);
        for(const node of r.addedNodes??[]){
          if(node.nodeType!==1)continue;
          if(node.matches(buySelector)){metrics.buttons++;enqueue(node);}
          for(const button of node.querySelectorAll(buySelector)){metrics.buttons++;enqueue(button);}
        }
      }
    }
    kick();
  }
  // Explicit user expansions may change card content without replacing the buy button.
  document.addEventListener("click",event=>{
    if(!active()||!marketRoute()||!event.target.closest?.(infoSelector))return;
    const button=ownerOf(event.target);
    if(button)setTimeout(()=>{if(active()){enqueue(button,true);kick();}},350);
  },true);
  const marketObserver=new MutationObserver(marketMutations);
  if(document.body)marketObserver.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:["aria-label","title","aria-expanded"]});
  window.addEventListener("focus",resetMarket);
  window.addEventListener("hashchange",resetMarket);
  window.addEventListener("blur",()=>{if(dirty)flush();});
  document.addEventListener("visibilitychange",()=>{if(active())resetMarket();else if(dirty)flush();});
  window.addEventListener("pagehide",()=>{if(dirty)flush();});
  resetMarket();
  // Observe already loaded pages. Never open tabs, refresh Torn, click controls,
  // issue requests, collect credentials, chat, or unrelated page contents.
  let pending=null, lastRead=0;
  function publish(){
    pending=null;
    if(document.visibilityState!=="visible")return;
    lastRead=Date.now();
    try{
      const packet=extract(),previous=GM_getValue(key,null);
      // Require a complete bar set so an intermediate DOM render cannot
      // replace the latest valid account snapshot with partial values.
      if(Object.keys(packet.bars).length!==4)return;
      const changed=!previous||previous.playerId!==packet.playerId||
        JSON.stringify(previous.bars)!==JSON.stringify(packet.bars);
      if(changed||Date.now()-Number(previous.timestamp)>=refreshAge)GM_setValue(key,packet);
    }catch{}
  }
  function schedule(){
    if(document.visibilityState!=="visible"||pending!==null)return;
    pending=setTimeout(publish,Math.max(250,2000-(Date.now()-lastRead)));
  }
  const observer=new MutationObserver(schedule);
  if(document.body)observer.observe(document.body,{childList:true,subtree:true,characterData:true});
  window.addEventListener("focus",schedule);
  window.addEventListener("pageshow",schedule);
  window.addEventListener("hashchange",schedule);
  document.addEventListener("visibilitychange",schedule);
  setInterval(schedule,15000);
  schedule();
})();
