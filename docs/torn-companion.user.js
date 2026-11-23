// ==UserScript==
// @name         Torn City Guide - Manual Visible Status Bridge
// @namespace    https://vagabond1215.github.io/TORN/
// @version      1.0.0
// @description  Manually share visible Torn Energy/Nerve/Happy/Life with your local Torn City Guide. No API key, no network calls, no background scraping.
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
  const key="torn-city-guide:manual-bars:v1";
  const guideOrigin="https://vagabond1215.github.io";
  const maxAge=90*1000;
  const isTorn=location.hostname==="www.torn.com"||location.hostname==="torn.com";
  const isGuide=location.origin===guideOrigin&&location.pathname.startsWith("/TORN/");
  if(window.top!==window)return;
  if(isGuide){
    const share=()=>{
      const packet=GM_getValue(key,null);
      if(!packet||packet.version!==1||!Number.isInteger(packet.playerId)||
        !Number.isFinite(packet.timestamp)||Date.now()-packet.timestamp>maxAge)return;
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
    // Read only this manually loaded, focused page. We never store raw DOM text.
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
      const body=String(document.body.innerText||"");
      const match=/\bInformation\s*\n/i.exec(body);
      if(!match)throw Error("Torn status sidebar was not found.");
      const after=body.slice(match.index+match[0].length,match.index+match[0].length+4000);
      const areas=after.search(/\bAreas\b/i);
      text=areas>=0?after.slice(0,areas):after;
    }
    const bars={};
    for(const name of ["energy","nerve","happy","life"]){
      const pattern=new RegExp("\\b"+name+"\\s*:?\\s*(\\d{1,7})\\s*\\/\\s*(\\d{1,7})","i");
      const match=text.match(pattern);
      if(match){
        const current=Number(match[1]),maximum=Number(match[2]);
        if(maximum>0&&current>=0&&current<=maximum+100000)bars[name]={current,maximum};
      }
    }
    if(!Object.keys(bars).length)throw Error("No readable Energy/Nerve/Happy/Life values found.");
    return {version:1,playerId:id,timestamp:Date.now(),bars};
  }
  function inject(){
    if(document.getElementById("torn-guide-share-bars"))return;
    const button=document.createElement("button");
    button.id="torn-guide-share-bars";
    button.textContent="Share bars with Torn Guide";
    button.type="button";
    button.title="Share visible Energy, Nerve, Happy and Life once. No passwords, messages or API calls.";
    Object.assign(button.style,{position:"fixed",bottom:"18px",right:"22px",zIndex:"2147483000",
      background:"#29372d",color:"#f2e8bb",border:"1px solid #c0ad65",padding:"9px 12px",
      borderRadius:"7px",font:"600 12px sans-serif",cursor:"pointer",boxShadow:"0 3px 10px #0009"});
    button.addEventListener("click",()=>{
      if(document.visibilityState!=="visible"||!document.hasFocus()){
        button.textContent="Focus Torn to share";return;
      }
      try{
        const packet=extract();
        GM_setValue(key,packet);
        button.textContent="Shared "+Object.keys(packet.bars).length+" bars · valid 90s";
      }catch(error){button.textContent=String(error.message||error).slice(0,75);}
    });
    document.body.appendChild(button);
  }
  if(document.body)inject();
  else document.addEventListener("DOMContentLoaded",inject,{once:true});
})();
