"use strict";
/* Optional read-only Tampermonkey bridge. No tab probing, network calls, or credentials. */
const tornGuideLocalBridge=(()=>{
  let lastStatus="No passive Torn status received yet";
  const latestVersion="2.6.1";
  let detectedVersion=null,checking=true,versionTimer=null;
  const validVersion=v=>typeof v==="string"&&/^\d{1,4}\.\d{1,4}\.\d{1,4}$/.test(v);
  function compareVersions(a,b){
    const x=a.split(".").map(Number),y=b.split(".").map(Number);
    for(let i=0;i<3;i++)if(x[i]!==y[i])return Math.sign(x[i]-y[i]);
    return 0;
  }
  function versionState(version,checking=false,latest=latestVersion){
    if(!validVersion(version))return checking?{state:"checking",label:"Checking companion…",action:null,detail:"Looking for the companion on this page."}:{state:"missing",label:"Not detected",action:"Install",detail:"The script may be missing, disabled or blocked on this site."};
    const cmp=compareVersions(version,latest);
    return cmp<0?{state:"update",label:"v"+version+" detected",action:"Update",detail:"Available: v"+latest}:cmp===0?{state:"current",label:"Up to Date!",action:null,detail:"Installed v"+version}:{state:"current",label:"Up to Date!",action:null,detail:"Installed v"+version+" (newer than this guide's bundled v"+latest+")"};
  }
  function renderVersion(){
    const status=document.getElementById("companion-version-status"),detail=document.getElementById("companion-version-detail"),link=document.getElementById("companion-version-action");
    if(!status||!detail||!link)return;
    const model=versionState(detectedVersion,checking);
    status.textContent=model.label;status.dataset.state=model.state;detail.textContent=model.detail;
    link.hidden=!model.action;link.textContent=model.action?model.action+" companion script":"";
  }
  function acceptVersion(version){
    if(!validVersion(version))return;
    detectedVersion=version;checking=false;
    if(versionTimer!==null){clearTimeout(versionTimer);versionTimer=null;}
    renderVersion();
  }
  function checkVersion(){
    // Previously detected live version stays visible while probing again.
    checking=!detectedVersion;renderVersion();
    if(versionTimer!==null)clearTimeout(versionTimer);
    versionTimer=setTimeout(()=>{versionTimer=null;checking=false;renderVersion();},1500);
    window.dispatchEvent(new Event("torn-guide-request-companion-version"));
  }
  window.addEventListener("torn-guide-companion-version",event=>{
    let p;try{p=typeof event.detail==="string"?JSON.parse(event.detail):event.detail;}catch{return;}
    acceptVersion(p?.version);
  });

  function accept(event){
    let payload=null;
    try{payload=typeof event.detail==="string"?JSON.parse(event.detail):event.detail;}catch{return;}
    if(!payload||payload.version!==2)return;
    if(!tornGuideApi.acceptLocalSnapshot(payload))return;
    lastStatus="Visible Torn bars synchronized at "+new Date(payload.timestamp).toLocaleTimeString();
    const place=document.getElementById("local-bridge-status");
    if(place)place.textContent=lastStatus;
  }
  window.addEventListener("torn-guide-local-snapshot",accept);
  let rwRenderTimer=null,rwChanged=false;
  window.addEventListener("torn-guide-rw-snapshot",event=>{
    let packet;try{packet=typeof event.detail==="string"?JSON.parse(event.detail):event.detail;}catch{return;}
    // Older companions (2.5.x / 2.6.0) announce their version in a
    // live market packet even when no market observations have been captured.
    if([1,2].includes(packet?.version)&&Number.isFinite(packet.bridgeAt)&&Math.abs(Date.now()-packet.bridgeAt)<60000)acceptVersion(packet.companionVersion);
    const changed=tornGuideApi.acceptRwSnapshot(packet);
    rwChanged=rwChanged||changed;
    if(rwRenderTimer!==null)clearTimeout(rwRenderTimer);
    rwRenderTimer=setTimeout(()=>{
      rwRenderTimer=null;refreshRwDiagnostics();
      if(!rwChanged)return;rwChanged=false;
      for(const row of document.querySelectorAll("[data-gear-uid]")){
        const slot=row.querySelector(".inventory-rw-slot");
        if(slot)slot.innerHTML=inventoryRwMarket(row.dataset.gearUid,Number(row.dataset.buyerItem));
      }
    },350);
  });
  function request(){
    window.dispatchEvent(new Event("torn-guide-request-snapshot"));
  }
  // The browser extension controls whether it responds; this is not a request
  // to Torn and does not scrape or otherwise access an unfocused tab.
  document.addEventListener("DOMContentLoaded",()=>{request();checkVersion();},{once:true});
  window.addEventListener("focus",()=>{request();checkVersion();});
  window.addEventListener("torn-guide-sync",request);
  return {request,checkVersion,versionState,getStatus:()=>lastStatus};
})();
