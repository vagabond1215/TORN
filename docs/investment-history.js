"use strict";
// Public price history only; no API key, no Torn quota, no personal data.
const tornInvestmentHistory=(()=>{
 const key="torn-city-guide:stock-history:v1",ttl=24*60*60*1000;
 let cache={};try{cache=JSON.parse(localStorage.getItem(key))||{};}catch{}
 let inflight=null;
 function get(ticker,price){
   const x=cache[ticker];if(!x||Date.now()-x.at>ttl||!Number.isFinite(price)||price<=0)return null;
   const ratio=(lo,hi)=>hi>lo?Math.max(0,Math.min(1,(price-lo)/(hi-lo))):.5;
   return {month:ratio(x.monthLow,x.monthHigh),year:ratio(x.yearLow,x.yearHigh)};
 }
 async function refresh(){
   if(inflight)return inflight;
   inflight=(async()=>{
     const prefs=tornRoadmap.preferences(),company=prefs.priority==="company"||tornRoadmap.selectedStyles().includes("Business");
     const rows=stockRows(),symbols=[...new Set(["TCI",...(company?["TCP","TGP"]:[]),"WSU",...rows.filter(r=>r.nextCost>0&&r.nextRoi!=null).sort((a,b)=>b.nextRoi-a.nextRoi).slice(0,3).map(r=>r.ticker)])];
     const now=Date.now(),day=86400000;
     for(const ticker of symbols){
       if(cache[ticker]&&now-cache[ticker].at<ttl)continue;
       try{
         const response=await fetch("https://tornsy.com/api/"+encodeURIComponent(ticker.toLowerCase())+"?interval=d1&from="+Math.floor((now-366*day)/1000)+"&limit=370",{credentials:"omit",referrerPolicy:"no-referrer",signal:AbortSignal.timeout(8000)});
         if(!response.ok)continue;
         const data=await response.json();
         const rows=(Array.isArray(data.data)?data.data:[]).filter(x=>Array.isArray(x)&&Number(x[0])*1000>=now-366*day&&Number(x[2])>0&&Number(x[3])>0);
         const month=rows.filter(x=>Number(x[0])*1000>=now-30*day);
         if(rows.length<330||month.length<25||Math.max(...rows.map(x=>Number(x[0])*1000))<now-3*day)continue;
         cache[ticker]={at:Date.now(),monthLow:Math.min(...month.map(x=>Number(x[3]))),monthHigh:Math.max(...month.map(x=>Number(x[2]))),yearLow:Math.min(...rows.map(x=>Number(x[3]))),yearHigh:Math.max(...rows.map(x=>Number(x[2])))};
       }catch{}
     }
     try{localStorage.setItem(key,JSON.stringify(cache));}catch{}
   })().finally(()=>{inflight=null;});
   return inflight;
 }
 return {get,refresh};
})();
