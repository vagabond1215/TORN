"use strict";
/* Browser-local UI preferences. These settings are independent of Torn API
 * credentials, cached gameplay data, and per-character checklist progress. */
const tornGuidePreferences=(()=>{
  const key="torn-city-guide:interface:v1";
  const defaults=Object.freeze({
    theme:"dark",timeZone:"local",externalMode:"tab",contextualQuickAccess:false
  });
  const zones=Object.freeze([
    ["local","Browser local time"],
    ["UTC","Torn City Time (UTC)"],
    ["America/New_York","US Eastern"],
    ["America/Chicago","US Central"],
    ["America/Denver","US Mountain"],
    ["America/Los_Angeles","US Pacific"],
    ["Europe/London","London"],
    ["Europe/Berlin","Central Europe"],
    ["Asia/Kolkata","India"],
    ["Asia/Tokyo","Japan"],
    ["Australia/Sydney","Sydney"]
  ]);
  const accepted={
    theme:new Set(["dark","light","system"]),
    timeZone:new Set(zones.map(([id])=>id)),
    externalMode:new Set(["tab","window"]),
    contextualQuickAccess:new Set([true,false])
  };
  const load=()=>{
    try{
      const parsed=JSON.parse(localStorage.getItem(key)||"null");
      if(!parsed||typeof parsed!=="object")return {...defaults};
      const valid={...defaults};
      for(const name of Object.keys(defaults)){
        if(accepted[name].has(parsed[name]))valid[name]=parsed[name];
      }
      return valid;
    }catch{return {...defaults};}
  };
  let current=load(),initialized=false,schemeQuery=null;
  function resolvedTheme(){
    if(current.theme!=="system")return current.theme;
    return typeof window!=="undefined"&&typeof window.matchMedia==="function"&&
      window.matchMedia("(prefers-color-scheme: light)").matches?"light":"dark";
  }
  function apply(){
    if(typeof document!=="undefined"&&document.documentElement){
      document.documentElement.setAttribute("data-theme",resolvedTheme());
    }
  }
  function get(name){return current[name];}
  function set(name,value){
    if(!Object.hasOwn(defaults,name)||!accepted[name].has(value))return false;
    current[name]=value;
    try{localStorage.setItem(key,JSON.stringify(current));}catch{}
    apply();
    if(typeof window!=="undefined"&&typeof window.dispatchEvent==="function"&&typeof Event!=="undefined"){
      window.dispatchEvent(new Event("torn-guide-preferences"));
    }
    return true;
  }
  function formatDate(date){
    const value=date instanceof Date?date:new Date(date);
    if(!Number.isFinite(value.getTime()))return "Unknown";
    try{
      const zone=current.timeZone;
      const opts={dateStyle:"medium",timeStyle:"short"};
      if(zone!=="local")opts.timeZone=zone;
      return new Intl.DateTimeFormat(undefined,opts).format(value)+
        (zone==="UTC"?" TCT":zone==="local"?"":" ("+zones.find(x=>x[0]===zone)?.[1]+")");
    }catch{return value.toLocaleString();}
  }
  function externalLink(event){
    if(event.defaultPrevented||event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;
    const target=event.target;
    const link=target&&typeof target.closest==="function"?target.closest("a[href]"):null;
    if(!link||link.hasAttribute("download"))return;
    let url;
    try{url=new URL(link.href,location.href);}catch{return;}
    if(!["http:","https:"].includes(url.protocol)||url.origin===location.origin)return;
    if(current.externalMode==="tab"){
      link.target="_blank";
      link.rel="noopener noreferrer";
      return;
    }
    event.preventDefault();
    // A window request is a browser preference, not a guarantee: some
    // browsers route it to a tab or block it entirely.
    window.open(url.href,"_blank","popup=yes,width=1180,height=820,resizable=yes,scrollbars=yes,noopener,noreferrer");
  }
  function init(){
    if(initialized)return;
    initialized=true;
    apply();
    if(typeof window.matchMedia==="function"){
      schemeQuery=window.matchMedia("(prefers-color-scheme: light)");
      if(typeof schemeQuery.addEventListener==="function")schemeQuery.addEventListener("change",apply);
    }
    document.addEventListener("click",externalLink,true);
  }
  return {init,get,set,apply,formatDate,zones,defaults};
})();
