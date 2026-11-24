// ==UserScript==
// @name         Torn City Guide - Passive Visible Status Bridge
// @namespace    https://vagabond1215.github.io/TORN/
// @version      2.0.0
// @description  Automatically synchronize visible Torn status bars to your local Torn City Guide. Read-only, no API key or network calls.
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
  document.addEventListener("visibilitychange",schedule);
  setInterval(schedule,15000);
  schedule();
})();
