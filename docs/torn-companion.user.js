// ==UserScript==
// @name         Torn City Guide - Passive Visible Status Bridge
// @namespace    https://vagabond1215.github.io/TORN/
// @version      2.6.0
// @description  Synchronize visible status bars, ranked market observations and opted-in personal activity logs to your local Torn City Guide. Read-only, no API key or network calls.
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
  const archivePrefix="torn-city-guide:passive-rw:v2:",archiveMeta=archivePrefix+"meta",bucketCount=128,bucketLimit=800;
  const archiveAge=row=>(row.complete?90:30)*86400000;
  const archiveValid=(row,stamp=Date.now())=>row&&Number.isFinite(row.at)&&row.at<=stamp+5000&&stamp-row.at<archiveAge(row);
  // Keep the same key when an observation gains quality or bonus details.
  const archiveId=row=>row.uid?"uid:"+row.uid:JSON.stringify([row.name,row.rarity,row.price,row.stats?.damage??null,row.stats?.accuracy??null,row.stats?.armor??null]);
  const observationKey=row=>JSON.stringify([row.name,row.price,row.stats?.damage??null,row.stats?.accuracy??null,row.stats?.armor??null]);
  function bucketOf(id){let h=2166136261;for(let i=0;i<id.length;i++)h=Math.imul(h^id.charCodeAt(i),16777619);return (h>>>0)%bucketCount;}
  const guideOrigin="https://vagabond1215.github.io";
  const refreshAge=60*1000;
  const isTorn=location.hostname==="www.torn.com"||location.hostname==="torn.com";
  const isGuide=location.origin===guideOrigin&&location.pathname.startsWith("/TORN/");
  // BEGIN personal log helpers
  const logPrefix="torn-city-guide:personal-log:v1:",logSignal=logPrefix+"changed",logLimit=2000;
  const logOwner=id=>Number.isSafeInteger(Number(id))&&Number(id)>0?Number(id):null;
  function ownLogRoute(loc){
    if(!["www.torn.com","torn.com"].includes(loc.hostname)||loc.protocol!=="https:"||loc.pathname!=="/page.php")return false;
    try{
      const pairs=loc.search.replace(/^\?/,"").split("&").map(part=>part.split("=").map(decodeURIComponent));
      return pairs.filter(([k,v])=>k==="sid"&&v==="log").length===1&&pairs.every(([k])=>["sid","cat","log","search","from","to"].includes(k));
    }catch{return false;}
  }
  function logTime(value){
    const text=String(value??"").trim();
    let y,m,d,h,min,s;
    const t=text.match(/^(\d{2}):(\d{2}):(\d{2})\s*[-–]\s*(\d{2})\/(\d{2})\/(\d{2}|\d{4})(?:\s*TCT)?$/i);
    const iso=text.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:Z| UTC| TCT)?$/i);
    if(t){[,h,min,s,d,m,y]=t.map(Number);if(y<100)y+=2000;}else if(iso){[,y,m,d,h,min,s]=iso.map(Number);}else return null;
    const at=Date.UTC(y,m-1,d,h,min,s),date=new Date(at);
    return y>=2004&&date.getUTCFullYear()===y&&date.getUTCMonth()===m-1&&date.getUTCDate()===d&&date.getUTCHours()===h&&date.getUTCMinutes()===min&&date.getUTCSeconds()===s?at:null;
  }
  const cleanLogText=value=>String(value??"").replace(/\s+/g," ").trim().replace(/\b((?:api[ _-]?key|access[ _-]?token|password|session[ _-]?token)\s*[:=]\s*)\S+/gi,"$1[redacted]").slice(0,1200);
  function logRow(at,description,now=Date.now()){
    const text=cleanLogText(description);
    return Number.isSafeInteger(at)&&at>=Date.UTC(2004,0,1)&&at<=now+300000&&text?{at,text}:null;
  }
  function mergeLogRows(prior,observed,now=Date.now()){
    const grouped=new Map();
    for(const set of [prior,observed]){
      const counts=new Map();
      for(const raw of Array.isArray(set)?set:[]){
        const row=logRow(raw?.at,raw?.text,now);if(!row)continue;
        const k=JSON.stringify([row.at,row.text]),n=(counts.get(k)??0)+1;counts.set(k,n);
        if(n>(grouped.get(k)?.count??0))grouped.set(k,{...row,count:n});
      }
    }
    const result=[];
    for(const {at,text,count} of [...grouped.values()].sort((a,b)=>b.at-a.at||a.text.localeCompare(b.text))){
      for(let i=0;i<count&&result.length<logLimit;i++)result.push({at,text});
      if(result.length>=logLimit)break;
    }
    return result;
  }
  function readVisibleLogRows(doc,visible,now=Date.now()){
    const rows=[],seen=new Set();let skipped=0,matched=0;
    for(const el of doc.querySelectorAll('tr .log-text, tr span[class*="text___"]')){
      const tr=el.closest("tr");if(!tr||seen.has(tr)||!visible(tr)||!visible(el))continue;
      const cell=tr.querySelector('time,[class*="timeValue"],[class*="time-value"]')??tr.querySelector("td");
      if(!cell||!visible(cell))continue;
      const at=[cell.getAttribute("datetime"),cell.getAttribute("title"),cell.innerText,tr.querySelector("td")?.innerText].map(logTime).find(v=>v!==null);
      if(at==null){if(el.matches(".log-text")){seen.add(tr);matched++;skipped++;}continue;}
      seen.add(tr);matched++;
      const row=logRow(at,el.innerText,now);if(row)rows.push(row);else skipped++;
      if(matched>=logLimit)break;
    }
    return {rows,matched,skipped};
  }
  // END personal log helpers
  if(window.top!==window)return;
  if(isGuide){
    let requestedLogOwner=null;
    function shareLog(){
      if(location.hash!=="#log"||document.visibilityState!=="visible"||!requestedLogOwner)return;
      const stored=GM_getValue(logPrefix+"rows:"+requestedLogOwner,null);
      const packet=stored?.playerId===requestedLogOwner?stored:null;
      window.dispatchEvent(new CustomEvent("torn-guide-log-snapshot",{detail:JSON.stringify({
        version:1,playerId:requestedLogOwner,companionVersion:"2.6.0",capturedAt:packet?.capturedAt??null,
        matched:packet?.matched??0,skipped:packet?.skipped??0,rows:Array.isArray(packet?.rows)?packet.rows.slice(0,logLimit):[]
      })}));
    }
    window.addEventListener("torn-guide-request-log",e=>{
      if(location.hash!=="#log")return;
      requestedLogOwner=logOwner(e.detail?.playerId);shareLog();
    });
    GM_addValueChangeListener(logSignal,()=>shareLog());
    window.addEventListener("focus",shareLog);
    document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")shareLog();});
    window.addEventListener("hashchange",()=>{if(location.hash!=="#log")requestedLogOwner=null;});
    window.addEventListener("torn-guide-stop-log",()=>{requestedLogOwner=null;});
    const share=()=>{
      const packet=GM_getValue(key,null);
      if(!packet||packet.version!==2||!Number.isInteger(packet.playerId)||
        !Number.isFinite(packet.timestamp)||packet.timestamp>Date.now()+5000)return;
      // Only 4 allowlisted bar objects and player ID cross the origin boundary.
      window.dispatchEvent(new CustomEvent("torn-guide-local-snapshot",{
        detail:JSON.stringify(packet)
      }));
    };
    const sent=new Map();
    let transferTimer=null;
    function shareMarket(force=false){
      if(document.visibilityState!=="visible")return;
      const meta=GM_getValue(archiveMeta,null);
      if(!meta?.buckets){
        const packet=GM_getValue(marketKey,null);
        window.dispatchEvent(new CustomEvent("torn-guide-rw-snapshot",{detail:JSON.stringify({...((packet?.version===1&&Array.isArray(packet.rows))?packet:{version:1,rows:[]}),companionVersion:"2.6.0",bridgeAt:Date.now()})}));
        return;
      }
      window.dispatchEvent(new CustomEvent("torn-guide-rw-snapshot",{detail:JSON.stringify({version:2,kind:"meta",diagnostic:meta.diagnostic,companionVersion:"2.6.0",bridgeAt:Date.now(),buckets:meta.buckets})}));
      if(transferTimer!==null)clearTimeout(transferTimer);
      const pending=Object.entries(meta.buckets).filter(([id,rev])=>force||sent.get(id)!==rev);
      const next=()=>{
        transferTimer=null;
        if(document.visibilityState!=="visible")return;
        const entry=pending.shift();if(!entry)return;
        const [id,rev]=entry,part=GM_getValue(archivePrefix+id,null);
        if(part&&Array.isArray(part.rows)){
          window.dispatchEvent(new CustomEvent("torn-guide-rw-snapshot",{detail:JSON.stringify({version:2,kind:"bucket",bucket:Number(id),revision:part.revision,rows:part.rows})}));
          sent.set(id,part.revision);
        }
        if(pending.length)transferTimer=setTimeout(next,40);
      };
      next();
    }
    window.addEventListener("torn-guide-request-snapshot",()=>shareMarket(true));
    GM_addValueChangeListener(archiveMeta,()=>shareMarket());
    GM_addValueChangeListener(marketKey,()=>{if(!GM_getValue(archiveMeta,null))shareMarket();});
    setTimeout(()=>shareMarket(),1200);
    window.addEventListener("focus",()=>shareMarket());
    document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")shareMarket();});
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
    return {name,category:route.category,rarity,rarityVerified:!!explicit,price,stats,bonuses,complete,rate:rate?[Number(rate[1]),Number(rate[2])]:null,ammo:ammo?[Number(ammo[1]),Number(ammo[2])]:null};
  }
  // Incremental market collector: no periodic full-page market scan.
  const buySelector='button[aria-label^="Buy item "]';
  const infoSelector='button[aria-label^="View info for item "]';
  const active=()=>document.visibilityState==="visible"&&document.hasFocus();
  const maxQueue=12000;
  let routeKey="",route=null,queue=new Set(),cards=new WeakMap(),owners=new WeakMap(),seen=new WeakMap(),boundaries=new WeakSet();
  let priorButtons=new WeakSet(),transitionUntil=0,previousRarity=null,stableLabels=new WeakMap(),panelSamples=[],manualTarget=null;
  const closeSelector='button[aria-label^="Close item info for "]';
  function panelFor(name){
    const matches=Array.from(document.querySelectorAll(closeSelector)).filter(b=>rendered(b)&&b.getAttribute("aria-label")==="Close item info for "+name);
    if(matches.length!==1)return null;
    let best=null;
    for(let el=matches[0].parentElement,depth=0;el&&depth<9;el=el.parentElement,depth++){
      if(el.querySelectorAll(buySelector).length>1||el.querySelectorAll(closeSelector).length>1)break;
      const t=el.innerText||"";
      if(t.length>6000)break;
      if(/Quality\s*:/i.test(t)&&/Bonus(?:es)?\s*:/i.test(t)){best={el,text:t};break;}
    }
    return best;
  }
  function samplePanel(name,price,text,row){
    const labels=Array.from(text.matchAll(/(?:^|\n)[ \t]*(Damage|Accuracy|Armor|Quality|Bonus(?:es)?|Rate of Fire|Ammo|Coverage|Stealth|Caliber)[ \t]*:[\s]*([^\n]+)/gi),m=>({label:m[1],value:m[2].trim().slice(0,100)}));
    // Keep only recognized equipment labels, never arbitrary panel text or player data.
    const clean=labels.map(x=>({label:x.label,value:x.value.split("\n")[0].trim()}));
    panelSamples.push({name,price,at:Date.now(),quality:row?.stats?.quality??null,bonusCount:row?.bonuses?.length??0,labels:clean});if(panelSamples.length>12)panelSamples.shift();
  }
  let workTimer=null,flushTimer=null,dirty=false,lastFlush=0,lastCapture=null,stored=new Map(),metrics=null,initialScanPending=false;
  function freshMetrics(){return {buttons:0,rendered:0,matched:0,ranked:0,accepted:0,complete:0,duplicates:0,added:0,processed:0,batches:0,maxBatchMs:0,queued:0,dropped:0,transitionSkipped:0,panels:0,enriched:0,persistedAdded:0};}
  function rowKey(row){return archiveId(row);}
  function readStore(){return stored;}
  function mergeBucket(id,updates,stamp){
    const prior=GM_getValue(archivePrefix+id,null),map=new Map();
    for(const row of prior?.rows??[])if(archiveValid(row,stamp))map.set(rowKey(row),row);
    for(const row of updates){
      if(!archiveValid(row,stamp))continue;
      const k=rowKey(row),old=map.get(k);
      if(!old||row.complete&&!old.complete||row.complete===old.complete&&row.at>=old.at){if(!old)metrics.persistedAdded++;else if(row.complete&&!old.complete)metrics.enriched++;map.set(k,row);}else if(old.complete&&!row.complete){map.set(k,{...old,at:Math.max(old.at,row.at)});}
    }
    const rows=Array.from(map.values()).sort((a,b)=>Number(b.complete)-Number(a.complete)||b.at-a.at).slice(0,bucketLimit);

    const revision=stamp+"-"+Math.random().toString(36).slice(2,10);
    GM_setValue(archivePrefix+id,{revision,rows});
    return revision;
  }
  function flush(){
    if(flushTimer!==null){clearTimeout(flushTimer);flushTimer=null;}
    if(!dirty||!metrics||!route)return;
    const stamp=Date.now(),old=GM_getValue(archiveMeta,null),buckets={...(old?.buckets??{})},groups=new Map();
    const add=row=>{if(!archiveValid(row,stamp))return;const id=bucketOf(rowKey(row));if(!groups.has(id))groups.set(id,[]);groups.get(id).push(row);};
    if(!old?.identityV25){
      // Rebucket once using the enrichment-compatible identity; keep legacy backup.
      const previous=[];for(const id of Object.keys(old?.buckets??{})){const part=GM_getValue(archivePrefix+id,null);for(const row of part?.rows??[])previous.push(row);}
      if(!previous.length){const legacy=GM_getValue(marketKey,null);for(const row of legacy?.rows??[])previous.push(row);}
      for(const row of previous)add(row);
      for(let id=0;id<bucketCount;id++)if(!groups.has(id))groups.set(id,[]);
    }
    for(const row of stored.values())add(row);
    // Stale shards are pruned during normal writes; rotate one additional shard per flush.
    const sweep=Number.isInteger(old?.sweep)?old.sweep%bucketCount:0;
    if(buckets[sweep]&&!groups.has(sweep))groups.set(sweep,[]);
    for(const [id,rows] of groups){if(!old?.identityV25)GM_setValue(archivePrefix+id,{rows:[]});buckets[id]=mergeBucket(id,rows,stamp);}
    const diagnostic={...metrics,at:stamp,lastCapture,category:route.category,rarity:route.rarity,queued:queue.size,mode:"incremental",panelSamples:panelSamples.slice(),identityVersion:25};
    GM_setValue(archiveMeta,{version:2,migrated:true,identityV25:true,buckets,sweep:(sweep+1)%bucketCount,diagnostic});
    stored.clear();lastFlush=stamp;dirty=false;
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
    const cardText=card.innerText||"";let text=cardText;
    const explicitRarity=/(?:^|\n)\s*(Y\s*ellow|O\s*range|R\s*ed)\s*(?:\n|$)/i.exec(text);
    const prior=priorButtons.has(button);

    const target=manualTarget;
    if(target?.button===button&&target.hash===routeKey&&Date.now()-target.at<15000){
      const panel=panelFor(name);
      if(panel){text+="\n"+panel.text;metrics.panels++;}
    }
    const combinedRarity=/(?:^|\n)\s*(Y\s*ellow|O\s*range|R\s*ed)\s*(?:\n|$)/i.exec(text);
    if(!combinedRarity&&(Date.now()<transitionUntil||prior)){metrics.transitionSkipped++;return;}
    if(combinedRarity&&route.rarity&&combinedRarity[1].replace(/\s/g,"").toLowerCase()!==route.rarity){metrics.transitionSkipped++;return;}
    const previous=seen.get(button);
    // A forced recheck can reveal newly added tooltip attributes even if text is unchanged.
    seen.set(button,{label});
    const row=parseRankedCard(text,name,price,route);if(!row)return;
    if(manualTarget?.button===button&&/Quality\s*:/i.test(text))samplePanel(name,price,text,row);
    metrics.ranked++;
    if(!row.complete){
      const nums=cardText.split(/\n/).map(x=>x.trim()).filter(x=>/^\d{1,3}\.\d{2}$/.test(x)).map(Number);
      if(["Armor","Defensive"].includes(route.category)){if(nums.length===1&&row.stats.armor==null)row.stats.armor=nums[0];}
      else if(nums.length===2){if(row.stats.damage==null)row.stats.damage=nums[0];if(row.stats.accuracy==null)row.stats.accuracy=nums[1];}
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
    row.complete=row.stats.quality!=null&&row.bonuses.length>0&&(row.stats.armor!=null||row.stats.damage!=null&&row.stats.accuracy!=null)&&/Bonus(?:es)?\s*:/i.test(text)&&/Quality\s*:/i.test(text);
    const uid=card.getAttribute("data-uid")||card.getAttribute("data-item-uid");
    if(uid&&/^[1-9]\d*$/.test(uid))row.uid=uid;
    if(!Object.keys(row.stats).length) return;
    row.fingerprint=archiveId(row);
    row.at=Date.now();lastCapture=row.at;metrics.accepted++;if(row.complete)metrics.complete++;
    const map=readStore(),k=rowKey(row),prev=map.get(k);
    if(prev){metrics.duplicates++;if(prev.complete&&!row.complete)return;}
    else metrics.added++;
    map.set(k,row);dirty=true;
    if(row.complete||map.size>=1000)flush();
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
    if(hash===routeKey&&route&&!initialScanPending){kick();return;}
    if(dirty)flush();
    const changedRarity=route&&next&&(route.rarity!==next.rarity||route.category!==next.category);
    priorButtons=new WeakSet();
    if(changedRarity){for(const button of document.querySelectorAll(buySelector))if(seen.has(button))priorButtons.add(button);}
    transitionUntil=changedRarity?Date.now()+1800:0;
    routeKey=hash;route=next;queue.clear();cards=new WeakMap();owners=new WeakMap();seen=new WeakMap();boundaries=new WeakSet();metrics=freshMetrics();manualTarget=null;
    initialScanPending=Boolean(route);
    if(!route)return;
    // Initial scan once per manually selected route. Subsequent work uses mutations.
    setTimeout(()=>{
      if(!active()||!route||location.hash!==hash||routeKey!==hash||!initialScanPending)return;
      initialScanPending=false;
      for(const button of document.querySelectorAll(buySelector)){metrics.buttons++;enqueue(button);}
      scheduleFlush();kick();
    },changedRarity?2200:600);
  }
  function ownerOf(node){
    for(let el=node?.nodeType===1?node:node?.parentElement,depth=0;el&&depth<12;el=el.parentElement,depth++){
      const b=owners.get(el);if(b)return b;
    }
    return null;
  }
  function marketMutations(records){
    if(!active()||!marketRoute())return;
    if(location.hash!==routeKey||!route){resetMarket();return;}
    if(initialScanPending)return;
    if(!marketRoute())return;
    for(const r of records){
      if(r.type==="attributes"){
        if(r.target.matches?.(buySelector)){priorButtons.delete(r.target);enqueue(r.target,true);continue;}
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
    if(!active()||!marketRoute())return;
    const clicked=event.target.closest?.(infoSelector+","+buySelector);if(!clicked)return;
    let button=clicked.matches(buySelector)?clicked:ownerOf(clicked);
    if(!button){for(let el=clicked.parentElement,depth=0;el&&depth<9;el=el.parentElement,depth++){const candidates=el.querySelectorAll(buySelector);if(candidates.length===1){button=candidates[0];break;}if(candidates.length>1)break;}}
    if(!button)return;
    manualTarget={button,hash:routeKey,at:Date.now()};
    for(const delay of [350,900,1800])setTimeout(()=>{if(active()&&manualTarget?.button===button&&manualTarget.hash===routeKey){enqueue(button,true);kick();}},delay);
  },true);
  const marketObserver=new MutationObserver(marketMutations);
  if(document.body)marketObserver.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:["aria-label","title","aria-expanded"]});
  window.addEventListener("focus",resetMarket);
  window.addEventListener("hashchange",resetMarket);
  window.addEventListener("blur",()=>{if(dirty)flush();});
  document.addEventListener("visibilitychange",()=>{if(active())resetMarket();else if(dirty)flush();});
  window.addEventListener("pagehide",()=>{if(dirty)flush();});
  resetMarket();
  // Personal log capture: own focused log page only, no requests or clicks.
  let logTimer=null;
  const logPanelId="torn-guide-log-capture";
  function logActive(){return ownLogRoute(location)&&active();}
  function publishLog(manual=false){
    if(!logActive())return;
    const id=extractOwnId(),panel=document.getElementById(logPanelId),status=panel?.querySelector("[data-log-status]");
    if(!id){if(status)status.textContent="Cannot verify your player ID; nothing captured.";return;}
    if(!manual&&GM_getValue(logPrefix+"auto:"+id,false)!==true)return;
    const obs=readVisibleLogRows(document,rendered),storageKey=logPrefix+"rows:"+id,old=GM_getValue(storageKey,null);
    const prior=old?.playerId===id?old.rows:[],rows=mergeLogRows(prior,obs.rows);
    const changed=JSON.stringify(rows)!==JSON.stringify(prior??[])||old?.matched!==obs.matched||old?.skipped!==obs.skipped;
    if(manual||changed){
      try{
        GM_setValue(storageKey,{version:1,playerId:id,capturedAt:Date.now(),matched:obs.matched,skipped:obs.skipped,rows});
        GM_setValue(logSignal,{playerId:id,at:Date.now()});
      }catch{if(status)status.textContent="Could not save the log archive.";return;}
    }
    if(status){
      const message=obs.matched?obs.rows.length+" readable rows · "+rows.length+" archived"+(obs.skipped?" · "+obs.skipped+" unreadable skipped":""):"No recognizable log rows yet. Load entries on this page.";
      if(status.textContent!==message)status.textContent=message;
    }
  }
  function mountLogCapture(){
    let panel=document.getElementById(logPanelId);
    if(!ownLogRoute(location)){panel?.remove();return;}
    if(!logActive())return;
    const id=extractOwnId();if(!id){panel?.remove();return;}
    if(panel&&panel.dataset.player!==String(id)){panel.remove();panel=null;}
    if(!panel){
      const first=document.querySelector('tr .log-text,tr span[class*="text___"]'),table=first?.closest("table");
      if(!table?.parentElement)return;
      panel=document.createElement("section");panel.id=logPanelId;panel.dataset.player=String(id);
      panel.style.cssText="display:flex;align-items:center;flex-wrap:wrap;gap:8px;padding:8px;margin:8px 0;border:1px solid #777;border-radius:5px;font-size:12px";
      panel.innerHTML='<strong>Torn Guide · Log archive</strong><button type="button" data-log-capture>Capture loaded entries</button><label><input type="checkbox" data-log-auto> Auto-capture while focused</label><button type="button" data-log-clear>Clear archive</button><span data-log-status role="status">Only loaded, rendered entries are captured.</span>';
      const auto=panel.querySelector("[data-log-auto]");auto.checked=GM_getValue(logPrefix+"auto:"+id,false)===true;
      panel.querySelector("[data-log-capture]").addEventListener("click",()=>publishLog(true));
      auto.addEventListener("change",()=>{if(!logActive()||extractOwnId()!==id)return;GM_setValue(logPrefix+"auto:"+id,auto.checked);if(auto.checked)publishLog(true);});
      panel.querySelector("[data-log-clear]").addEventListener("click",()=>{
        if(!logActive()||extractOwnId()!==id||!window.confirm("Clear your local Torn Guide activity log archive and disable automatic capture?"))return;
        GM_setValue(logPrefix+"auto:"+id,false);auto.checked=false;
        GM_setValue(logPrefix+"rows:"+id,{version:1,playerId:id,capturedAt:Date.now(),matched:0,skipped:0,rows:[]});
        GM_setValue(logSignal,{playerId:id,at:Date.now()});panel.querySelector("[data-log-status]").textContent="Archive cleared.";
      });
      table.parentElement.insertBefore(panel,table);
    }
    publishLog(false);
  }
  function scheduleLog(){
    if(!ownLogRoute(location)){document.getElementById(logPanelId)?.remove();return;}
    if(!logActive()||logTimer!==null)return;
    logTimer=setTimeout(()=>{logTimer=null;mountLogCapture();},1000);
  }
  const logObserver=new MutationObserver(records=>{
    if(!logActive())return;
    if(records.some(rec=>!((rec.target.nodeType===1?rec.target:rec.target.parentElement)?.closest("#"+logPanelId))))scheduleLog();
  });
  if(ownLogRoute(location)&&document.body)logObserver.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:["class","style","hidden","title","datetime"]});
  window.addEventListener("focus",scheduleLog);
  window.addEventListener("hashchange",scheduleLog);
  window.addEventListener("pageshow",scheduleLog);
  document.addEventListener("visibilitychange",scheduleLog);
  scheduleLog();
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
    pending=setTimeout(publish,Math.max(250,15000-(Date.now()-lastRead)));
  }
  const observer=new MutationObserver(schedule);
  // The sidebar timer is independent of market scrolling and chat mutations.
  const sidebar=document.querySelector("#sidebar")||document.querySelector("#sidebar-wrapper");
  if(sidebar)observer.observe(sidebar,{childList:true,subtree:true,characterData:true});
  window.addEventListener("focus",schedule);
  window.addEventListener("pageshow",schedule);
  window.addEventListener("hashchange",schedule);
  document.addEventListener("visibilitychange",schedule);
  setInterval(schedule,15000);
  schedule();
})();
