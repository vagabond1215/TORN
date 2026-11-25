"use strict";
/* Optional read-only Tampermonkey bridge. No tab probing, network calls, or credentials. */
const tornGuideLocalBridge=(()=>{
  let lastStatus="No passive Torn status received yet";
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
  window.addEventListener("torn-guide-rw-snapshot",event=>{
    let packet;try{packet=typeof event.detail==="string"?JSON.parse(event.detail):event.detail;}catch{return;}
    const changed=tornGuideApi.acceptRwSnapshot(packet);
    refreshRwDiagnostics();
    if(!changed)return;
    for(const row of document.querySelectorAll("[data-gear-uid]")){
      const slot=row.querySelector(".inventory-rw-slot");
      if(slot)slot.innerHTML=inventoryRwMarket(row.dataset.gearUid,Number(row.dataset.buyerItem));
    }
  });
  function request(){
    window.dispatchEvent(new Event("torn-guide-request-snapshot"));
  }
  // The browser extension controls whether it responds; this is not a request
  // to Torn and does not scrape or otherwise access an unfocused tab.
  document.addEventListener("DOMContentLoaded",request,{once:true});
  window.addEventListener("focus",request);
  window.addEventListener("torn-guide-sync",request);
  return {request,getStatus:()=>lastStatus};
})();
