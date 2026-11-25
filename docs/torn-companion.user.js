// ==UserScript==
// @name         Torn City Guide - Passive Visible Status Bridge
// @namespace    https://vagabond1215.github.io/TORN/
// @version      2.1.0
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
      if(packet?.version===1&&Array.isArray(packet.rows))window.dispatchEvent(new CustomEvent("torn-guide-rw-snapshot",{detail:JSON.stringify(packet)}));
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
  function collectMarket(){
    if(document.visibilityState!=="visible"||!document.hasFocus())return;
    const route=marketRoute();if(!route)return;
    const rows=[];
    for(const button of document.querySelectorAll('button[aria-label^="Buy item "]')){
      if(!rendered(button))continue;
      const m=button.getAttribute("aria-label").match(/^Buy item (.+), \$([\d,]+), 1 in total\.$/);
      if(!m)continue;
      const name=m[1],price=Number(m[2].replace(/,/g,""));
      if(!Number.isSafeInteger(price)||price<=0)continue;
      // Find a bounded listing ancestor, never collect surrounding market or chat.
      let card=button.parentElement,best=null;
      for(let depth=0;card&&depth<9;depth++,card=card.parentElement){
        if(card.querySelectorAll('button[aria-label^="Buy item "]').length!==1)break;
        const info=Array.from(card.querySelectorAll('button[aria-label^="View info for item "]')).some(b=>b.getAttribute("aria-label")==="View info for item "+name+".");
        if(info)best=card;
      }
      if(!best||!rendered(best))continue;
      const text=best.innerText||"";
      const row=parseRankedCard(text,name,price,route);if(!row)continue;
      // Collapsed weapon cards expose two standalone numeric stats. Do not guess
      // when the row contains extra ambiguous numbers.
      if(!row.complete&&route.category!=="Armor"&&route.category!=="Defensive"){
        const numbers=text.split(/\n/).map(x=>x.trim()).filter(x=>/^\d{1,3}\.\d{2}$/.test(x)).map(Number);
        if(numbers.length===2){row.stats.damage=numbers[0];row.stats.accuracy=numbers[1];}
      }
      const uid=best.getAttribute("data-uid")||best.getAttribute("data-item-uid");
      if(uid&&/^[1-9]\d*$/.test(uid))row.uid=uid;
      if(!row.complete&&!Object.keys(row.stats).length)continue;
      // Without a real UID, fingerprint conservatively; identical records count once.
      row.fingerprint=JSON.stringify([name,row.rarity,price,row.stats,row.bonuses]);
      row.at=Date.now();rows.push(row);
    }
    if(!rows.length)return;
    const old=GM_getValue(marketKey,null),merged=new Map();
    for(const row of Array.isArray(old?.rows)?old.rows:[])if(Date.now()-row.at<marketTTL)merged.set(row.uid?"uid:"+row.uid:row.fingerprint,row);
    let changed=false;
    for(const row of rows){
      const key=row.uid?"uid:"+row.uid:row.fingerprint,prev=merged.get(key);
      if(prev?.complete&&!row.complete)continue;
      if(!prev||Date.now()-prev.at>=60000||prev.complete!==row.complete){merged.set(key,row);changed=true;}
    }
    if(changed)GM_setValue(marketKey,{version:1,rows:Array.from(merged.values()).sort((a,b)=>b.at-a.at).slice(0,2500)});
  }
  // Observe already loaded pages. Never open tabs, refresh Torn, click controls,
  // issue requests, collect credentials, chat, or unrelated page contents.
  let pending=null, lastRead=0;
  function publish(){
    pending=null;
    if(document.visibilityState!=="visible")return;
    lastRead=Date.now();
    try{collectMarket();}catch{}
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
