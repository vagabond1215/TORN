"use strict";
/* Page-scoped Torn API coordinator. The Torn coordinator sends explicit GETs to Torn API v2.
 * Credential lives in memory, or opt-in browser localStorage only. No external API
 * receives the Torn key. The optional passive Torn-page bridge reads only allowlisted status bars.
 */
const tornGuideApi=(()=>{
  let secret=null,remember=false,epoch=0,timer=null,inFlight=null,queued=null,batchMode="unknown";
  const quarter=15*60*1000;
  // All Torn requests share these counters, including direct equipment/crime calls.
  let activeRequests=0,lastApiEnd=0,idleLastStart=0,idleAbort=null,idleVerifiedEpoch=-1,idleBlockedUntil=0;
  const idleEligible=(at,active,lastEnd,lastStart,busy,blocked=0)=>!busy&&active===0&&at>=blocked&&at-lastEnd>=15000&&at-lastStart>=60000;
  const authKey="torn-city-guide:api:v2:remember";
  const cachePrefix="torn-city-guide:api:v2:cache:";
  const inventoryTypes=["Primary","Secondary","Melee","Temporary","Defensive","Clothing","Medical","Drug","Energy Drink","Alcohol","Candy","Supply Pack","Booster","Enhancer","Tool","Material","Jewelry","Flower","Plushie","Car","Book","Special","Other","Artifact","Collectible"];
  const mins=60*1000,hrs=60*mins,days=24*hrs;
  const TTL={
    basic:days, profile:15*mins, bars:2*mins, cooldowns:2*mins, icons:15*mins, money:15*mins, networth:60*mins,
    missions:5*mins, jobpoints:15*mins, skills:15*mins, battlestats:15*mins, gym:30*mins, perks:60*mins,
    education:6*hrs, virus:15*mins, organizedcrime:10*mins, factionWars:5*mins, factionRankedWars:15*mins, merits:6*hrs, job:6*hrs, workstats:6*hrs, property:12*hrs,
    stocks:60*mins, personalstats:24*hrs, rehabStats:15*mins, factionChain:5*mins, calendarCatalog:6*hrs, calendar:6*hrs, warAttacks:5*mins, travel:15*mins, racingrecords:6*hrs, races:30*mins,
    honors:24*hrs,medals:24*hrs,honorCatalog:30*days,medalCatalog:30*days,gymCatalog:90*days, meritCatalog:30*days, stockCatalog:15*mins, educationCatalog:7*days, itemCatalog:15*mins, pointsCatalog:15*mins
  };
  const ROUTES={
    home:["profile","icons","perks","gymCatalog","pointsCatalog","honors","medals","organizedcrime","skills","itemCatalog","bars","cooldowns","refills","money","networth","battlestats","workstats","gym","job","property","education","merits","meritCatalog","stocks","stockCatalog","missions","factionWars","travel","races"],
    trainingProgress:["bars","cooldowns","battlestats","refills"],
    energy:["bars","cooldowns","refills","battlestats","gym","perks","icons","money","factionWars","profile","travel","itemCatalog","pointsCatalog","gymCatalog","education"],
    calendar:["bars","cooldowns","refills","battlestats","gym","perks","icons","money","factionWars","profile","travel","education","organizedcrime","virus","rehabStats","factionChain","races","calendarCatalog","calendar","itemCatalog","pointsCatalog","gymCatalog"],
    warProgress:["factionWars","factionChain","warAttacks","bars","cooldowns","icons"],
    warPreparation:["bars","cooldowns","icons","factionWars"],
    rehabProgress:["profile","icons","rehabStats","travel"],
    stats:["profile","bars","cooldowns","refills","battlestats","gym","perks","gymCatalog","itemCatalog","pointsCatalog","icons","money","factionWars","education","travel","rehabStats"],
    jobs:["job","workstats","perks","jobpoints"],
    timers:["education","virus","cooldowns","organizedcrime","factionRankedWars"],
    railTimers:["education","virus","itemCatalog","cooldowns","organizedcrime","factionWars","factionRankedWars","travel","money"],
    activity:["virus","travel","racingrecords","races"],
    quickStatus:["icons","travel","races","cooldowns"],
    crime:["bars","skills","itemCatalog"],
    merits:["honors","medals","honorCatalog","medalCatalog","merits","meritCatalog","battlestats","bars","gym","perks","gymCatalog","cooldowns","itemCatalog"],
    niceRefresh:["battlestats","bars","gym","perks","honors","honorCatalog","gymCatalog","cooldowns","itemCatalog"],
    checklist:["bars","merits","meritCatalog","job","education","educationCatalog","money","icons","profile","organizedcrime","virus"],
    money:["money"],
    stocks:["stocks","stockCatalog","itemCatalog"],
    education:["education","educationCatalog","merits","meritCatalog","stocks","stockCatalog","perks"],
    inventory:["itemCatalog"],
    log:[], racing:[], faction:[], attacking:[], war:[], tools:[]
  };
  const state={identity:null,data:{},inventory:{},errors:{},inventoryErrors:{},
    fetchedAt:{},failedAt:{},cachedSources:{},updated:null,loading:false,cached:false,
    storageWarning:null,bridge:null,requests:0,lastRequest:0};
  const cacheKey=id=>cachePrefix+id;
  const now=()=>Date.now();
  const routeName=()=>{
    const hash=(location.hash||"").slice(1);
    return hash==="quickstart"?"checklist":hash==="dashboard"?"home":ROUTES[hash]?hash:"home";
  };
  function announce(){
    if(typeof window!=="undefined"&&typeof Event!=="undefined")window.dispatchEvent(new Event("torn-guide-sync"));
  }
  function clearSaved(id){
    try{localStorage.removeItem(authKey);if(id!=null)localStorage.removeItem(cacheKey(id));}catch{}
  }
  function save(){
    if(!remember||!secret||!state.identity)return;
    try{
      localStorage.setItem(authKey,JSON.stringify({version:2,key:secret,identity:state.identity}));
      localStorage.setItem(cacheKey(state.identity.id),JSON.stringify({
        version:2,playerId:state.identity.id,data:state.data,inventory:state.inventory,
        errors:state.errors,inventoryErrors:state.inventoryErrors,
        fetchedAt:state.fetchedAt,failedAt:state.failedAt,updated:state.updated
      }));
      state.storageWarning=null;
    }catch{
      state.storageWarning="Browser storage unavailable or full. Session data will not persist.";
      remember=false;clearSaved(state.identity.id);
    }
  }
  function setRemember(on){
    if(!secret||!state.identity)return false;
    if(!on){remember=false;clearGear(state.identity.id);clearSaved(state.identity.id);state.cached=false;announce();return false;}
    remember=true;save();persistGear();announce();return remember;
  }
  function restore(){
    let record;
    try{record=JSON.parse(localStorage.getItem(authKey)||"null");}catch{return null;}
    if(!record)return null;
    const ident=record.identity;
    if(!/^[a-zA-Z0-9]{16}$/.test(String(record.key||""))||!ident||
      !Number.isInteger(Number(ident.id))||!ident.name){
      clearSaved(ident&&ident.id);return null;
    }
    secret=record.key;remember=true;epoch++;batchMode="unknown";
    state.identity={id:Number(ident.id),name:String(ident.name),level:ident.level};
    state.data={};state.inventory={};state.errors={};state.inventoryErrors={};
    state.fetchedAt={};state.failedAt={};state.cachedSources={};state.updated=null;state.bridge=null;state.cached=false;
    try{
      const snap=JSON.parse(localStorage.getItem(cacheKey(state.identity.id))||"null");
      if(snap&&Number(snap.playerId)===state.identity.id){
        for(const key of ["data","inventory","errors","inventoryErrors","fetchedAt","failedAt"]){
          state[key]=snap[key]&&typeof snap[key]==="object"?snap[key]:{};
        }
        state.updated=Number(snap.updated)||null;
        state.cachedSources=Object.fromEntries(Object.keys(state.fetchedAt).map(key=>[key,true]));
        state.cached=true;
      }
    }catch{}
    // Old builds cached an invalid no-category personalstats error. The new
    // category-qualified endpoint is not selected by Home, so this obsolete
    // error must not poison the account status forever.
    if(/incorrect category/i.test(String(state.errors.personalstats||""))){
      delete state.errors.personalstats;
      delete state.failedAt.personalstats;
    }
    schedule();announce();
    return {identity:state.identity,cached:state.cached,updated:state.updated};
  }
  function stopTimer(){if(timer!==null){clearTimeout(timer);timer=null;}}
  function schedule(){
    stopTimer();if(!secret)return;
    const next=(Math.floor(now()/quarter)+1)*quarter;
    timer=setTimeout(async()=>{
      timer=null;
      try{await refresh({route:routeName()});}
      catch(error){state.storageWarning=String(error.message||error);announce();}
      schedule();
    },Math.max(200,next-now()+125));
  }
  function refreshOnResume(){
    if(!secret||typeof document!=="undefined"&&document.visibilityState==="hidden")return;
    refresh({route:routeName()}).catch(()=>{});
    schedule();
  }
  if(typeof document!=="undefined")document.addEventListener("visibilitychange",()=>{
    if(document.visibilityState==="visible")refreshOnResume();
  });
  if(typeof window!=="undefined")window.addEventListener("focus",refreshOnResume);
  async function request(path,key,{idle=false}={}){
    if(!idle)idleAbort?.abort();
    const controller=new AbortController();
    if(idle)idleAbort=controller;
    activeRequests++;
    let timedOut=false;
    const timeout=setTimeout(()=>{timedOut=true;controller.abort();},15000);
    try{
      const response=await fetch("https://api.torn.com/v2/"+path,{
        method:"GET",headers:{Authorization:"ApiKey "+key,Accept:"application/json"},
        credentials:"omit",cache:"no-store",referrerPolicy:"no-referrer",signal:controller.signal
      });
      let payload;
      try{payload=await response.json();}catch(error){
        if(response.ok)throw error;
        const failure=Error("Torn API HTTP "+response.status);failure.httpStatus=response.status;throw failure;
      }
      if(payload&&payload.error){
        const error=Error("Torn API: "+String(payload.error.error||payload.error.message||payload.error.code||"request rejected"));
        error.tornCode=Number(payload.error.code);error.httpStatus=response.status;throw error;
      }
      if(!response.ok){const error=Error("Torn API HTTP "+response.status);error.httpStatus=response.status;throw error;}
      state.requests++;state.lastRequest=now();
      return payload;
    }catch(error){
      if([5,8,9,14].includes(error.tornCode)||error.httpStatus===429)
        idleBlockedUntil=Math.max(idleBlockedUntil,now()+(error.tornCode===14?24*hrs:10*mins));
      if(error.name==="AbortError"){const failure=Error("Torn API request timed out");failure.interrupted=idle&&!timedOut&&controller.signal.aborted;throw failure;}
      if(error instanceof TypeError)throw Error("Cannot reach Torn API. Check network/CORS.");
      throw error;
    }finally{clearTimeout(timeout);activeRequests--;lastApiEnd=now();if(idleAbort===controller)idleAbort=null;}
  }
  // At most one idle attempt per minute across cooperating Guide tabs. No
  // foreground request waits for this worker. Never follow a response URL.
  // Nonsecret, connection-bound capability; restored identity is not verified.
  function idleLogSession(){
    const id=state.identity?.id,key=secret,accountEpoch=epoch;
    if(!key||!Number.isSafeInteger(id)||id<=0)return null;
    const isCurrent=()=>epoch===accountEpoch&&secret===key&&state.identity?.id===id;
    return Object.freeze({playerId:String(id),isCurrent,isVerified:()=>isCurrent()&&idleVerifiedEpoch===accountEpoch});
  }
  async function idleLogPage(cursor=null,authorization=null){
    const id=state.identity?.id,key=secret,accountEpoch=epoch;
    if(!key||!Number.isSafeInteger(id)||id<=0)return {status:"disconnected"};
    if(authorization!==null&&(typeof authorization.isCurrent!=="function"||typeof authorization.verifyOnly!=="boolean"||authorization.verifyOnly&&cursor!==null))return {status:"stopped",reason:"Invalid idle log authorization"};
    const allowed=()=>{try{return authorization===null||authorization.isCurrent()===true;}catch{return false;}};
    if(!allowed())return {status:"changed"};
    if(cursor!==null&&(typeof cursor!=="string"||!/^\d{1,30}$/.test(cursor)))return {status:"stopped",reason:"Invalid pagination cursor"};
    if(typeof document==="undefined"||document.visibilityState!=="visible")return {status:"busy"};
    const eligible=()=>idleEligible(now(),activeRequests,lastApiEnd,idleLastStart,!!(inFlight||queued||state.loading||idleAbort),idleBlockedUntil);
    const current=()=>epoch===accountEpoch&&secret===key&&state.identity?.id===id&&allowed();
    if(authorization?.verifyOnly&&idleVerifiedEpoch===accountEpoch)return {status:"verified"};
    if(!eligible())return {status:"busy"};
    if(typeof navigator==="undefined"||!navigator.locks?.request)return {status:"stopped",reason:"Safe multi-tab coordination unavailable in this browser"};
    try{return await navigator.locks.request("torn-guide-idle-log:"+id,{ifAvailable:true},async lock=>{
      if(!current())return {status:"changed"};
      if(!lock||!eligible()||document.visibilityState!=="visible")return {status:"busy"};
      if(authorization?.verifyOnly&&idleVerifiedEpoch===accountEpoch)return {status:"verified"};
      const storageKey="torn-city-guide:idle-log-at:"+id;
      try{
        const last=Number(localStorage.getItem(storageKey))||0;
        if(now()-last<60000)return {status:"busy"};
        localStorage.setItem(storageKey,String(now()));
      }catch{return {status:"stopped",reason:"Safe request coordination storage unavailable"};}
      idleLastStart=now();
      try{
        if(idleVerifiedEpoch!==accountEpoch){
          const result=await request("user/basic",key,{idle:true});
          if(!current())return {status:"changed"};
          if(result?.profile?.id!==id)return {status:"stopped",reason:"Account identity verification failed"};
          idleVerifiedEpoch=accountEpoch;return {status:"verified"};
        }
        if(authorization?.verifyOnly)return {status:"verified"};
        if(!current())return {status:"changed"};
        const payload=await request("user/log?limit=100"+(cursor===null?"":"&nanostamp="+cursor),key,{idle:true});
        return current()?{status:"ok",payload}:{status:"changed"};
      }catch(error){
        if(!current())return {status:"changed"};
        if([1,2,7,10,13,16,18].includes(error.tornCode)||[401,403].includes(error.httpStatus))
          return {status:"stopped",reason:"API key cannot read logs. Verify its permissions before resuming."};
        if(error.tornCode===14)return {status:"stopped",reason:"Torn daily read limit reached; resume after reset."};
        if(error.interrupted)return {status:"busy"};
        idleBlockedUntil=Math.max(idleBlockedUntil,now()+10*mins);
        return {status:"backoff",reason:"API unavailable or rate limited; retry after 10 minutes."};
      }
    });}catch{return {status:"stopped",reason:"Safe multi-tab coordination unavailable"};}
  }
  async function connect(raw,stay=false){
    const key=String(raw||"").trim();
    if(!/^[a-zA-Z0-9]{16}$/.test(key))throw Error("Enter a valid 16-character Torn API key.");
    const basic=await request("user/basic",key);
    const profile=basic.profile;
    if(!profile||!Number.isInteger(profile.id)||!profile.name)throw Error("Torn returned an unexpected identity.");
    if(remember)clearSaved(state.identity&&state.identity.id);
    epoch++;secret=key;remember=Boolean(stay);batchMode="unknown";idleVerifiedEpoch=epoch;idleBlockedUntil=0;
    state.identity={id:profile.id,name:profile.name,level:profile.level};
    state.data={basic};state.inventory={};state.errors={};state.inventoryErrors={};
    state.fetchedAt={basic:now()};state.failedAt={};state.cachedSources={};state.updated=now();
    state.cached=false;state.bridge=null;state.storageWarning=null;
    save();schedule();announce();
    return state.identity;
  }
  // Backup identity must be verified against the own-account endpoint, not
  // a restored local identity or a user-provided numeric ID. Never expose key.
  async function verifyBackupOwner(){
    const key=secret,connectionEpoch=epoch,id=state.identity?.id;
    if(!key||!Number.isSafeInteger(id)||id<=0)throw Error("Connect your Torn account first");
    const isCurrent=()=>epoch===connectionEpoch&&secret===key&&state.identity?.id===id;
    const result=await request("user/basic",key);
    if(!isCurrent()||result?.profile?.id!==id)throw Error("Account changed or identity could not be verified");
    idleVerifiedEpoch=connectionEpoch;
    return {playerId:String(id),isCurrent};
  }
  // Keep the newest observation; older stored packets never overwrite newer API data.
  function bridgeIsFresh(){
    return state.bridge&&state.identity&&Number(state.bridge.playerId)===state.identity.id&&
      state.bridge.fields.length===4&&now()-Number(state.bridge.timestamp)<TTL.bars;
  }
  function acceptLocalSnapshot(snapshot){
    if(!snapshot||snapshot.version!==2||!state.identity||Number(snapshot.playerId)!==state.identity.id)return false;
    const stamp=Number(snapshot.timestamp);
    if(!Number.isFinite(stamp)||stamp<=0||stamp>now()+5000||stamp<=Number(state.bridge?.timestamp||0)||stamp<=Number(state.fetchedAt.bars||0))return false;
    const bars=snapshot.bars;
    if(!bars||typeof bars!=="object")return false;
    const clean={};
    for(const name of ["energy","nerve","happy","life"]){
      const item=bars[name];
      if(!item)continue;
      const current=Number(item.current),maximum=Number(item.maximum);
      if(Number.isInteger(current)&&Number.isInteger(maximum)&&current>=0&&maximum>0&&current<=maximum+100000)
        clean[name]={current,maximum};
    }
    if(Object.keys(clean).length!==4)return false;
    state.data.bars={bars:clean};
    state.bridge={playerId:state.identity.id,timestamp:stamp,fields:Object.keys(clean)};
    announce();
    if(typeof updateHomeLiveBars==="function")updateHomeLiveBars();
    if(routeName()==="stats"&&typeof tornStatPlanner!=="undefined")tornStatPlanner.syncLiveBars();
    return true;
  }
  function stale(key,force=false){
    if(key==="bars"&&!force&&bridgeIsFresh())return false;
    if(force)return true;
    const last=Number(state.fetchedAt[key])||0;
    if(last&&now()-last< (TTL[key]||15*mins))return false;
    const failed=Number(state.failedAt[key])||0;
    if(failed&&now()-failed<10*mins)return false;
    return true;
  }
  function endpoint(key){
    if(key==="refills")return "user?selections=refills&legacy=refills";
    if(key==="personalstats")return "user/personalstats?cat=popular";
    if(key==="rehabStats")return "user/personalstats?cat=drugs";
    if(key==="factionChain")return "faction/chain";
    if(key==="calendarCatalog")return "torn/calendar";
    if(key==="warAttacks")return "user/attacks?limit=100&sort=DESC&filters=outgoing";
    if(key==="factionWars")return "faction/wars";
    if(key==="factionRankedWars")return "faction/rankedwars";
    if(key==="gymCatalog")return "torn/gyms";
    if(key==="stockCatalog")return "torn/stocks";
    if(key==="educationCatalog")return "torn/education";
    if(key==="itemCatalog")return "torn/items";
    if(key==="pointsCatalog")return "market/pointsmarket";
    if(key==="honorCatalog")return "torn/honors";
    if(key==="medalCatalog")return "torn/medals";
    if(key==="meritCatalog")return "torn/merits";
    return "user/"+key;
  }
  // On-demand equipment reads use the connected key only against Torn.
  const gearCache=new Map(),gearPending=new Map();
  const gearAttempts=new Map();
  const gearKey=id=>"torn-city-guide:equipment:v2:"+id;
  let gearOwner=null,gearStored={};
  function gearUid(v){return (typeof v==="string"&&/^[1-9]\d*$/.test(v)||Number.isSafeInteger(v)&&v>0)?String(v):null;}
  function gearAccount(){
    const id=state.identity?.id??null;
    if(gearOwner!==id){gearOwner=id;gearStored={};if(id&&remember)try{const v=JSON.parse(localStorage.getItem(gearKey(id))||"{}");if(v&&typeof v==="object"&&!Array.isArray(v))gearStored=v;}catch{}}
    return id;
  }
  function persistGear(){
    const id=gearAccount();if(!id||!remember)return;
    try{localStorage.setItem(gearKey(id),JSON.stringify(gearStored));}catch{}
  }
  function clearGear(id){
    if(id)try{localStorage.removeItem(gearKey(id));}catch{}
    gearOwner=null;gearStored={};gearCache.clear();gearAttempts.clear();
  }
  const staticPath=path=>/^torn\/[1-9]\d*\/itemdetails$/.test(path);
  const dailyPath=path=>path==="user/equipment"||path==="user/itemmods";
  const crimePath=path=>/^user\/(?:[1-9]|1[0-3])\/crimes$/.test(path);
  function gearRecord(path){
    gearAccount();
    return gearCache.get(epoch+":"+path)??(staticPath(path)||dailyPath(path)||crimePath(path)?gearStored[path]:null);
  }
  function gearRead(path,allowStale=false){
    const record=gearRecord(path);
    if(!record||!Number.isFinite(record.at)||record.at>now())return null;
    const ttl=staticPath(path)?Infinity:crimePath(path)?hrs:dailyPath(path)?24*hrs:15*mins;
    return allowStale||now()-record.at<ttl?record.data:null;
  }
  async function gearRequest(path,force=false){
    if(!secret)throw Error("Connect Torn API first.");
    const accountEpoch=epoch,cacheKey=epoch+":"+path,existing=gearRead(path);
    if(!force&&existing)return existing;
    if(gearPending.has(cacheKey))return gearPending.get(cacheKey);
    const task=request(path,secret).then(data=>{
      if(accountEpoch!==epoch)throw Error("Account changed; reload equipment.");
      gearAccount();
      const record={at:now(),data};
      if(gearCache.size>=300)gearCache.delete(gearCache.keys().next().value);
      gearCache.set(cacheKey,record);
      if(staticPath(path)||dailyPath(path)||crimePath(path)){
        gearStored[path]=record;
        const keys=Object.keys(gearStored).filter(staticPath).sort((a,b)=>gearStored[a].at-gearStored[b].at);
        while(keys.length>500)delete gearStored[keys.shift()];
        persistGear();
      }
      return data;
    }).finally(()=>gearPending.delete(cacheKey));
    gearPending.set(cacheKey,task);return task;
  }
  const rwCache=new Map(),rwPending=new Map();
  const passiveRwKey="torn-city-guide:passive-rw:v1";
  let passiveRw=[],passiveRwDiagnostic=null,passiveRwBridge=null;
  const passiveBuckets=new Map(),passiveRevisions=new Map();
  let passiveIndex=null,archiveExpected=null,archiveStorageError=null;
  const retainRw=x=>x&&Number.isFinite(x.at)&&x.at<=now()+5000&&now()-x.at< (x.complete?90:30)*days;
  const rwDb=typeof indexedDB==="undefined"?Promise.resolve(null):new Promise(resolve=>{
    try{const req=indexedDB.open("torn-guide-rw-archive",1);
      req.onupgradeneeded=()=>req.result.createObjectStore("buckets");
      req.onsuccess=()=>resolve(req.result);req.onerror=()=>{archiveStorageError="Local archive unavailable";resolve(null);};
      req.onblocked=()=>{archiveStorageError="Local archive upgrade blocked";resolve(null);};
    }catch{archiveStorageError="Local archive unavailable";resolve(null);}
  });
  function archiveWrite(id,revision,rows){
    rwDb.then(db=>{if(!db)return;try{const tx=db.transaction("buckets","readwrite");tx.objectStore("buckets").put({revision,rows},id);tx.onerror=()=>{archiveStorageError="Local archive write failed";};}catch{archiveStorageError="Local archive write failed";}});
  }
  rwDb.then(db=>{if(!db)return;try{const req=db.transaction("buckets","readonly").objectStore("buckets").openCursor();
    req.onsuccess=()=>{const cursor=req.result;if(cursor){const id=cursor.key,part=cursor.value;if(!passiveBuckets.has(id)&&(!archiveExpected||Object.hasOwn(archiveExpected,id))&&Array.isArray(part?.rows)){passiveBuckets.set(id,part.rows.filter(retainRw));passiveRevisions.set(id,part.revision);passiveIndex=null;}cursor.continue();}else if(typeof refreshRwDiagnostics==="function")refreshRwDiagnostics();};
  }catch{archiveStorageError="Local archive read failed";}});
  function archivedRows(){return (passiveBuckets.size?Array.from(passiveBuckets.values()).flat():passiveRw).filter(retainRw);}
  function passiveModelIndex(){if(!passiveIndex){passiveIndex=new Map();for(const x of archivedRows()){const k=x.name.toLowerCase()+"|"+x.rarity;if(!passiveIndex.has(k))passiveIndex.set(k,[]);passiveIndex.get(k).push(x);}}return passiveIndex;}

  try{const saved=JSON.parse(localStorage.getItem(passiveRwKey)||"[]");if(Array.isArray(saved))passiveRw=saved;}catch{}
  function acceptRwSnapshot(packet){
    if(!packet||![1,2].includes(packet.version))return false;
    if(packet.version===2&&!["meta","bucket"].includes(packet.kind))return false;
    const d=packet.diagnostic;
    if(typeof packet.companionVersion==="string"&&/^\d+\.\d+\.\d+$/.test(packet.companionVersion))passiveRwBridge={version:packet.companionVersion,at:now()};
    if(d&&Number.isFinite(d.at)&&d.at<=now()+5000&&["Primary","Secondary","Melee","Armor","Defensive"].includes(d.category)){
      const counts={};for(const k of ["buttons","rendered","matched","ranked","accepted","complete","duplicates","added","processed","batches","maxBatchMs","queued","dropped","transitionSkipped","panels","enriched","persistedAdded"])counts[k]=Number.isSafeInteger(d[k])&&d[k]>=0&&d[k]<=100000?d[k]:null;
      passiveRwDiagnostic={...counts,at:d.at,lastCapture:Number.isFinite(d.lastCapture)&&d.lastCapture<=now()+5000?d.lastCapture:null,category:d.category,rarity:["yellow","orange","red"].includes(d.rarity)?d.rarity:null,mode:d.mode==="incremental"?"incremental":null,panelSamples:Array.isArray(d.panelSamples)?d.panelSamples.slice(-12).filter(s=>s&&typeof s.name==="string"&&s.name.length<=120&&Number.isSafeInteger(s.price)&&s.price>0).map(s=>({name:s.name,price:s.price,at:Number.isFinite(s.at)?s.at:null,quality:Number.isFinite(s.quality)?s.quality:null,bonusCount:Number.isSafeInteger(s.bonusCount)?s.bonusCount:0,labels:Array.isArray(s.labels)?s.labels.slice(0,30).filter(l=>l&&/^(Damage|Accuracy|Armor|Quality|Bonus(?:es)?|Rate of Fire|Ammo|Coverage|Stealth|Caliber)$/i.test(l.label)&&typeof l.value==="string").map(l=>({label:l.label,value:l.value.slice(0,100)})):[]})):[]};
    }
    if(packet.version===2&&packet.kind==="meta"){
      if(packet.buckets&&typeof packet.buckets==="object"){
        archiveExpected=Object.fromEntries(Object.entries(packet.buckets).filter(([k,v])=>/^\d+$/.test(k)&&Number(k)<128&&typeof v==="string"));
        for(const id of passiveBuckets.keys())if(!Object.hasOwn(archiveExpected,id)){passiveBuckets.delete(id);passiveRevisions.delete(id);passiveIndex=null;}
      }
      return false;
    }
    if(!Array.isArray(packet.rows))return false;
    if(packet.version===2&&(!Number.isInteger(packet.bucket)||packet.bucket<0||packet.bucket>=128||typeof packet.revision!=="string"))return false;
    if(packet.version===2&&passiveRevisions.get(packet.bucket)===packet.revision)return false;
    const clean=[];
    for(const x of packet.rows.slice(0,packet.version===2?800:2500)){
      if(!x||typeof x.name!=="string"||!x.name.trim()||x.name.length>120||
        !["Primary","Secondary","Melee","Armor","Defensive"].includes(x.category)||
        !["yellow","orange","red"].includes(x.rarity)||!Number.isSafeInteger(x.price)||x.price<=0||
        !Number.isFinite(x.at)||x.at>now()+5000||now()-x.at>(x.complete===true?90:30)*days)continue;
      const stats={};for(const k of ["quality","damage","accuracy","armor"]){const n=x.stats?.[k];if(typeof n==="number"&&Number.isFinite(n)&&n>=0&&n<=10000)stats[k]=n;}
      const bonuses=Array.isArray(x.bonuses)?x.bonuses.slice(0,3).filter(b=>b&&typeof b.title==="string"&&/^[A-Za-z][A-Za-z '-]{0,40}$/.test(b.title)&&Number.isFinite(b.value)&&b.value>=0&&b.value<=10000).map(b=>({title:b.title,value:b.value})):[];
      const complete=x.complete===true&&Number.isFinite(stats.quality)&&bonuses.length>0&&bonuses.length===x.bonuses?.length&&(Number.isFinite(stats.armor)||Number.isFinite(stats.damage)&&Number.isFinite(stats.accuracy));
      const uid=gearUid(x.uid);
      const pair=(v,max)=>Array.isArray(v)&&v.length===2&&v.every(n=>Number.isSafeInteger(n)&&n>0&&n<=max)?v.slice():null;
      clean.push({name:x.name,category:x.category,rarity:x.rarity,price:x.price,stats,bonuses,complete,uid,at:x.at,rate:pair(x.rate,500),ammo:pair(x.ammo,1000)});
    }
    if(packet.version===2){
      passiveBuckets.set(packet.bucket,clean);passiveRevisions.set(packet.bucket,packet.revision);passiveIndex=null;
      archiveWrite(packet.bucket,packet.revision,clean);return true;
    }
    if(passiveBuckets.size)return false;
    const next=JSON.stringify(clean);
    if(next===JSON.stringify(passiveRw))return false;
    passiveRw=clean;passiveIndex=null;
    try{localStorage.setItem(passiveRwKey,next);}catch{}
    return true;
  }
  function rarityConflicts(rows){
    const groups=new Map(),conflicts=new Set();
    for(const x of rows){const k=JSON.stringify([x.name,x.price,x.stats?.damage??null,x.stats?.accuracy??null,x.stats?.armor??null]);const g=groups.get(k)??new Set();g.add(x.rarity);groups.set(k,g);}
    for(const [k,g] of groups)if(g.size>1)conflicts.add(k);
    return conflicts;
  }
  const conflictKey=x=>JSON.stringify([x.name,x.price,x.stats?.damage??null,x.stats?.accuracy??null,x.stats?.armor??null]);
  function passiveRwReport(){const rows=archivedRows(),conflicts=rarityConflicts(rows);return {version:2,bridge:passiveRwBridge,diagnostic:passiveRwDiagnostic,archive:{loaded:passiveBuckets.size,expected:archiveExpected?Object.keys(archiveExpected).length:null,error:archiveStorageError,conflictingGroups:conflicts.size},rows:rows.map(x=>conflicts.has(conflictKey(x))?{...x,rarityConflict:true}:x)};}
  function readPassiveRwMarket(id,rarity){
    const raw=state.data.itemCatalog;
    const items=raw?.items??raw?.data?.items??raw?.payload?.items;
    const catalog=Array.isArray(items)?items:Object.entries(items||{}).map(([id,x])=>({...x,id:x.id??id}));
    const name=catalog.find(x=>Number(x.id)===id)?.name;
    if(!name)return null;
    const index=passiveModelIndex(),all=["yellow","orange","red"].flatMap(r=>index.get(String(name).toLowerCase()+"|"+r)??[]),conflicts=rarityConflicts(all);
    const observations=(index.get(String(name).toLowerCase()+"|"+rarity)??[]).filter(x=>retainRw(x)&&now()-x.at<=24*hrs&&!conflicts.has(conflictKey(x)));
    if(!observations.length)return null;
    const rows=[],seen=new Set();
    for(const x of observations.filter(x=>x.complete).sort((a,b)=>b.at-a.at)){
      const key=x.uid??JSON.stringify([x.stats,x.bonuses,x.price]);
      if(seen.has(key))continue;seen.add(key);
      rows.push({uid:x.uid??"passive:"+key,price:x.price,stats:x.stats,bonuses:x.bonuses,at:x.at});
    }
    return {at:Math.max(...observations.map(x=>x.at)),rows,observations:observations.length,source:"passive",truncated:true};
  }
  function rwKey(id,rarity){return "torn-city-guide:rw-market:v1:"+id+":"+rarity;}
  function readRwMarket(id,rarity){
    const key=rwKey(id,rarity);
    if(!rwCache.has(key)){try{const x=JSON.parse(localStorage.getItem(key)||"null");if(x&&Array.isArray(x.rows)&&Number.isFinite(x.at))rwCache.set(key,x);}catch{}}
    return rwCache.get(key)??null;
  }
  async function loadRwMarket(id,rarity,force=false){
    if(!secret||!Number.isSafeInteger(id)||id<=0||!["yellow","orange","red"].includes(rarity))throw Error("Invalid ranked equipment lookup.");
    const key=rwKey(id,rarity),old=readRwMarket(id,rarity);
    if(!force&&old&&now()-old.at<24*hrs)return old;
    if(rwPending.has(key))return rwPending.get(key);
    const accountEpoch=epoch,apiKey=secret;
    const task=(async()=>{
      const rows=[],seen=new Set();let truncated=false,sourceAt=null;
      for(let offset=0;offset<500;offset+=100){
        if(epoch!==accountEpoch)throw Error("Account changed.");
        const data=await request("market/"+id+"/itemmarket?bonus="+encodeURIComponent(rarity[0].toUpperCase()+rarity.slice(1))+"&limit=100&offset="+offset,apiKey);
        const m=data.itemmarket;
        if(!Array.isArray(m?.listings)||Number(m.item?.id)!==id)throw Error("Unexpected item market response.");
        sourceAt=Number(m.cache_timestamp)||sourceAt;
        for(const x of m.listings){
          const d=x.item_details,uid=gearUid(d?.uid);
          if(!uid||seen.has(uid)||d.rarity!==rarity||!Number.isSafeInteger(x.price)||x.price<=0||!Array.isArray(d.bonuses))continue;
          seen.add(uid);rows.push({uid,price:x.price,stats:d.stats,bonuses:d.bonuses.map(b=>({id:b.id,title:b.title,value:b.value}))});
        }
        const more=m.listings.length===100&&(!Number.isFinite(data._metadata?.total)||offset+100<data._metadata.total);
        if(!more)break;
        if(offset===400)truncated=true;
      }
      if(epoch!==accountEpoch)throw Error("Account changed.");
      const result={at:now(),sourceAt,rows,truncated};rwCache.set(key,result);
      try{localStorage.setItem(key,JSON.stringify(result));}catch{}
      return result;
    })().finally(()=>rwPending.delete(key));
    rwPending.set(key,task);return task;
  }
  function readCrimeProgress(id){return Number.isInteger(id)&&id>=1&&id<=13?gearRead("user/"+id+"/crimes",true):null;}
  let crimeVersionEpoch=-1,detectedCrimeVersion=null;
  function crimeVersion(){
    if(crimeVersionEpoch!==epoch){crimeVersionEpoch=epoch;detectedCrimeVersion=null;}
    const raw=state.data.skills?.skills??state.data.skills,profile=state.data.profile?.profile??state.data.profile;
    const explicit=profile?.crimes_version??profile?.crime_version??raw?.crimes_version;
    if(["1","1.0","2","2.0"].includes(String(explicit)))return Number(explicit);
    const skills=raw?.crimes??raw?.crime??raw;
    const names=Array.isArray(skills)?skills.map(x=>x?.name??x?.crime??x?.type):Object.keys(skills||{});
    if(names.some(x=>/^(search.?for.?cash|bootlegging|graffiti|pickpocketing|card.?skimming)$/i.test(String(x))))return 2;
    if(detectedCrimeVersion!==null)return detectedCrimeVersion;
    for(let id=1;id<=13;id++)if(gearRead("user/"+id+"/crimes",true)?.crimes)return 2;
    return null;
  }
  const crimeRetry=new Map();
  let crimeRefreshTask=null;
  function refreshCrimeProgress(){
    if(!secret||document.visibilityState!=="visible"||!["home","crime"].includes(routeName()))return Promise.resolve(false);
    if(crimeRefreshTask)return crimeRefreshTask;
    const owner=epoch;
    if(crimeVersion()===1)return Promise.resolve(false);
    crimeRefreshTask=(async()=>{
      let changed=false;
      for(let id=1;id<=13;id++){
        if(owner!==epoch||document.visibilityState!=="visible"||!["home","crime"].includes(routeName()))break;
        const path="user/"+id+"/crimes",key=owner+":"+id;
        if(gearRead(path)||now()-(crimeRetry.get(key)||0)<15*mins)continue;
        try{const data=await gearRequest(path);if(data?.crimes){crimeVersionEpoch=owner;detectedCrimeVersion=2;}changed=true;crimeRetry.delete(key);}catch(error){crimeRetry.set(key,now());if(/(?:migrate|switch|upgrade).{0,50}crimes.{0,10}(?:2|v2)|crimes.{0,10}(?:2|v2).{0,50}(?:migrate|switch|upgrade)/i.test(String(error.message))){crimeVersionEpoch=owner;detectedCrimeVersion=1;changed=true;break;}}
      }
      if(changed&&owner===epoch&&["home","crime"].includes(routeName())&&typeof renderRoute==="function")renderRoute();
      return changed;
    })().finally(()=>{crimeRefreshTask=null;});
    return crimeRefreshTask;
  }
  async function loadCrimeProgress(id){if(!Number.isInteger(id)||id<1||id>13)throw Error("Invalid crime ID.");return gearRequest("user/"+id+"/crimes",true);}
  function readGear(uid){
    uid=gearUid(uid);if(!uid)return {};
    const equipment=gearRead("user/equipment",true),mods=gearRead("user/itemmods",true),detail=gearRead("torn/"+uid+"/itemdetails")?.itemdetails;
    const equipped=Array.isArray(equipment?.equipment)?equipment.equipment.find(x=>gearUid(x.uid)===uid):null;
    const unique=(Array.isArray(detail)?detail:[detail]).find(x=>gearUid(x?.uid)===uid);
    const equipmentAt=gearRecord("user/equipment")?.at??0,modsAt=gearRecord("user/itemmods")?.at??0;
    const fromMods=Array.isArray(mods?.itemmods)?mods.itemmods.filter(x=>x.equipped&&gearUid(x.equipped_item_uid)===uid):null;
    const fromEquipment=Array.isArray(equipped?.mods)?equipped.mods:null;
    const preferMods=fromMods!==null&&(fromEquipment===null||modsAt>=equipmentAt);
    const attached=preferMods?fromMods:fromEquipment;
    return {item:unique??equipped??null,mods:attached,ammo:equipped?.ammo??null,ammoAt:equipmentAt,modsAt:attached===null?0:preferMods?modsAt:equipmentAt};
  }
  async function loadGear(uid,equipped,weapon,force=false){
    uid=gearUid(uid);if(!uid)throw Error("Unique item identifier unavailable.");
    const errors=[];
    if(equipped){
      try{await gearRequest("user/equipment",force);}catch(e){errors.push(e.message);}
    }
    // Store immutable UID data separately; never persist equipment snapshots as immutable stats.
    if(!gearRead("torn/"+uid+"/itemdetails")){
      try{await gearRequest("torn/"+uid+"/itemdetails");}catch(e){errors.push(e.message);}
    }
    if(weapon&&(force||!gearRead("user/itemmods"))){
      try{await gearRequest("user/itemmods",force);}catch(e){errors.push(e.message);}
    }
    return {data:readGear(uid),errors};
  }
  let initialGearScan=null;
  async function checkInitialGear(){
    if(!secret||routeName()!=="inventory")return;
    if(initialGearScan)return initialGearScan;
    const scanEpoch=epoch;
    const candidates=new Set();
    for(const [cat,items] of Object.entries(state.inventory)){
      if(!["Primary","Secondary","Melee","Defensive"].includes(cat)||!Array.isArray(items))continue;
      for(const item of items){
        const uid=gearUid(item.uid??item.unique_id);
        if(!uid)continue;
        // All weapons and armor use individual UID attributes, regardless of rarity.
        if(gearRead("torn/"+uid+"/itemdetails")||gearAttempts.has(scanEpoch+":initial:"+uid))continue;
        candidates.add(uid);
      }
    }
    if(!candidates.size)return;
    const task=(async()=>{
      let changed=false,attempted=0;
      for(const uid of candidates){
        if(epoch!==scanEpoch||routeName()!=="inventory"||!secret||attempted>=25)break;
        const path="torn/"+uid+"/itemdetails";
        if(gearRead(path))continue;
        gearAttempts.set(scanEpoch+":initial:"+uid,now());
        attempted++;
        try{await gearRequest(path);changed=true;}
        catch{break;} // Stop on errors rather than hammering the API.
        if(epoch!==scanEpoch)break;
      }
      if(changed&&epoch===scanEpoch&&routeName()==="inventory")announce();
    })();
    initialGearScan=task;
    try{await task;}finally{if(initialGearScan===task)initialGearScan=null;}
  }
  async function checkGearDaily(){
    if(!secret||routeName()!=="inventory")return;
    const known=Object.entries(state.inventory).some(([cat,items])=>["Primary","Secondary","Melee"].includes(cat)&&Array.isArray(items)&&items.some(x=>gearUid(x.uid??x.unique_id)));
    await checkInitialGear();
    if(!secret||routeName()!=="inventory"||!known||gearRead("user/itemmods"))return;
    const key=epoch+":daily-mods";
    if(now()-(gearAttempts.get(key)??0)<15*mins)return;
    gearAttempts.set(key,now());
    try{await gearRequest("user/itemmods");announce();}catch{}
  }
  async function fetchInventory(cat,key){
    const list=[];let total=null;
    for(let offset=0;offset<2500;offset+=250){
      const data=await request("user/inventory?cat="+encodeURIComponent(cat)+"&limit=250&offset="+offset,key);
      const batch=data.inventory&&Array.isArray(data.inventory.items)?data.inventory.items:[];
      list.push(...batch);
      total=Number(data._metadata&&data._metadata.total);
      if(batch.length<250||Number.isFinite(total)&&total>=0&&list.length>=total)break;
    }
    return {list,truncated:Number.isFinite(total)&&total>list.length};
  }
  async function batch(route,force=false,category=null,includeStatus=false,includeMerits=false){
    if(!secret)throw Error("Connect Torn API first.");
    const currentEpoch=epoch,currentKey=secret;
    // Current-page navigation, scheduled refresh and resume share the
    // existing coordinator. Do not add these selections to background
    // trainingProgress, inventory-category or other auxiliary requests.
    const visibleMerits=route===routeName()&&!category&&typeof tornRightRail!=="undefined"&&tornRightRail.meritsVisible();
    const meritKeys=includeMerits||visibleMerits?["honors","medals","honorCatalog","medalCatalog","battlestats","bars","gym","perks","gymCatalog"]:[];
    const names=[...new Set([...(ROUTES[route]||ROUTES.home),...(includeStatus?ROUTES.quickStatus:[]),...meritKeys])].filter(name=>stale(name,force));
    const cats=route==="inventory"
      ?(category?[category]:Object.keys(state.inventory).filter(c=>inventoryTypes.includes(c)))
      :(route==="energy"||route==="calendar")?["Candy","Drug","Booster"]:route==="warPreparation"?["Drug"]:(route==="niceRefresh"||route==="merits")?["Candy"]:route==="stats"?["Candy","Drug","Booster"]:route==="home"?["Candy","Drug","Alcohol","Tool","Enhancer","Booster","Energy Drink","Medical","Material","Supply Pack","Clothing","Defensive","Temporary","Other","Special","Flower"]:route==="crime"?["Tool","Enhancer","Material"]:[];
    const selectedCats=cats.filter(cat=>inventoryTypes.includes(cat)&&stale("inventory:"+cat,force));
    if(!names.length&&!selectedCats.length)return {failures:0,requested:0,skipped:true};
    state.loading=true;announce();
    let succeeded=0,failures=0;
    const userNames=names.filter(name=>!name.endsWith("Catalog") && !["factionWars","factionRankedWars","personalstats","rehabStats","factionChain","warAttacks"].includes(name));
    const otherNames=names.filter(name=>name.endsWith("Catalog") || ["factionWars","factionRankedWars","personalstats","rehabStats","factionChain","warAttacks"].includes(name));
    const jobs=[];
    if(userNames.length>=2 && batchMode!=="unsupported"){
      jobs.push({
        name:"multiUser",names:userNames,
        run:()=>request("user?selections="+encodeURIComponent(userNames.join(","))+(userNames.includes("refills")?"&legacy=refills":""),currentKey)
      });
    }else for(const name of userNames)jobs.push({name,run:()=>request(endpoint(name),currentKey)});
    for(const name of otherNames)jobs.push({name,run:()=>request(endpoint(name),currentKey)});
    for(const cat of selectedCats)jobs.push({name:"inventory:"+cat,run:()=>fetchInventory(cat,currentKey)});
    // At most three simultaneous requests; a visit does not spend the entire
    // per-user quota in a burst. Failed selections back off for ten minutes.
    let cursor=0;
    async function worker(){
      while(cursor<jobs.length){
        const index=cursor++,job=jobs[index];
        let value=null,error=null;
        try{value=await job.run();}catch(ex){error=String(ex.message||ex);}
        if(currentEpoch!==epoch||currentKey!==secret)return;
        if(job.name==="multiUser"){
          const present=!error && value && typeof value==="object"
            ?job.names.filter(name=>Object.prototype.hasOwnProperty.call(value,name)):[];
          if(present.length>=2){
            batchMode="supported";
            for(const name of job.names){
              if(present.includes(name)){
                state.fetchedAt[name]=now();delete state.failedAt[name];delete state.cachedSources[name];
                state.data[name]={[name]:value[name]};
                delete state.errors[name];succeeded++;
              }else jobs.push({name,run:()=>request(endpoint(name),currentKey)});
            }
          }else{
            batchMode="unsupported";
            // A changed response or per-selection failure must never blank
            // every dashboard card: retry each requested field independently.
            for(const name of job.names)jobs.push({name,run:()=>request(endpoint(name),currentKey)});
          }
          continue;
        }
        if(error){
          state.failedAt[job.name]=now();failures++;
          if(job.name.startsWith("inventory:"))state.inventoryErrors[job.name.slice(10)]=error;
          else state.errors[job.name]=error;
        }else{
          state.fetchedAt[job.name]=now();delete state.failedAt[job.name];delete state.cachedSources[job.name];succeeded++;
          if(job.name.startsWith("inventory:")){
            const cat=job.name.slice(10);
            state.inventory[cat]=value.list;
            if(value.truncated)state.inventoryErrors[cat]="Inventory list capped at 2,500 items.";
            else delete state.inventoryErrors[cat];
          }else{
            state.data[job.name]=value;delete state.errors[job.name];
          }
        }
      }
    }
    await Promise.all(Array.from({length:Math.min(3,jobs.length)},()=>worker()));
    if(currentEpoch!==epoch||currentKey!==secret)return {failures,requested:jobs.length,discarded:true};
    if(succeeded){state.updated=now();state.cached=false;}
    if(!succeeded)state.storageWarning="No requested Torn API selections updated; last data is retained.";
    state.loading=false;save();announce();
    if(typeof renderRoute==="function" && location.hash!=="#profile" && route!=="timers" && route!=="railTimers")renderRoute();
    return {failures,requested:jobs.length,skipped:false};
  }
  function refresh(options={}){
    if(!secret)return Promise.reject(Error("Connect Torn API first."));
    const opts=typeof options==="object"&&options?options:{};
    const route=opts.route||routeName();
    // Deduplicate request sets. When one is in flight, schedule one follow-up
    // using the new route, rather than aborting the current page load.
    if(inFlight){
      if(opts.force||opts.category||opts.includeStatus||opts.includeMerits||route!==inFlight.route)queued={route,force:Boolean(opts.force),category:opts.category||null,includeStatus:Boolean(opts.includeStatus),includeMerits:Boolean(opts.includeMerits)};
      return inFlight.promise;
    }
    const promise=batch(route,Boolean(opts.force),opts.category||null,Boolean(opts.includeStatus),Boolean(opts.includeMerits)).then(result=>{if(["home","crime"].includes(route))refreshCrimeProgress().catch(()=>{});return result;}).finally(()=>{
      inFlight=null;
      if(queued){
        const next=queued;queued=null;
        refresh(next).catch(()=>{});
      }
    });
    inFlight={route,promise};
    return promise;
  }
  function loadPage(route,force=false){return refresh({route,force});}
  function loadInventory(cat,force=false){return refresh({route:"inventory",force,category:cat});}
  function disconnect(){
    const id=state.identity&&state.identity.id;
    epoch++;idleAbort?.abort();secret=null;remember=false;stopTimer();queued=null;
    clearSaved(id);clearGear(id);
    state.identity=null;state.data={};state.inventory={};state.errors={};
    state.inventoryErrors={};state.fetchedAt={};state.failedAt={};state.cachedSources={};
    state.updated=null;state.bridge=null;state.loading=false;state.cached=false;
    announce();
  }
  return {state,connect,refresh,loadPage,loadInventory,acceptLocalSnapshot,gearUid,readGear,loadGear,checkGearDaily,readRwMarket,loadRwMarket,readPassiveRwMarket,acceptRwSnapshot,passiveRwReport,readCrimeProgress,loadCrimeProgress,refreshCrimeProgress,crimeVersion,
    disconnect,restore,setRemember,isRemembering:()=>remember,
    isConnected:()=>Boolean(secret),verifyBackupOwner,refreshOnResume,idleLogSession,idleLogPage,idleEligible,cancelIdleLog:()=>idleAbort?.abort(),inventoryTypes,routeName,TTL,ROUTES};
})();

const guideSteps = [
  { id:"tutorial", stage:"First hour", title:"Finish the tutorial and learn the bars", detail:"Energy is for training/attacking; nerve is for Crimes 2.0. Avoid sitting at full bars.", source:"https://wiki.torn.com/wiki/New_Player_Missions" },
  { id:"first-merit", stage:"First hour", title:"Earn an easy early honor and merit", detail:"Check the Awards page for inexpensive honors such as Historian, Gone Fishing, Landlord and Pocket Money. Confirm each requirement in-game before spending.", source:"https://wiki.torn.com/wiki/Award" },
  { id:"education-start", stage:"First hour", title:"Start an education course immediately", detail:"Begin a useful course and keep one running. Consider Introduction to Biochemistry and work toward Intravenous Therapy, then Sports Science.", source:"https://wiki.torn.com/wiki/Education" },
  { id:"education-merit", stage:"First hour", title:"Invest merits into Education Length, ultimately 10/10", detail:"Each upgrade saves 2% on FUTURE courses; 10/10 grants 20% total. Fully upgrading costs 55 merits, so this is a long-term target.", source:"https://wiki.torn.com/wiki/Education", auto:"educationMerit" },
  { id:"first-job", stage:"First hour", title:"Get a job or start applying to companies", detail:"Use a starter city job while applying to player companies. Compare work-stat training and company specials; a useful company may beat starter-job cash.", source:"https://wiki.torn.com/wiki/Job", auto:"job" },
  { id:"faction", stage:"First hour", title:"Join an active, beginner-friendly faction", detail:"Ask about training bonuses, armory, protection, organized crimes, missions, and war expectations.", source:"https://wiki.torn.com/wiki/Faction" },
  { id:"first-property", stage:"First week", title:"Move beyond the starter Shack", detail:"An Apartment costs $25k (125 base Happy), but renting a Mansion (500 base Happy) can be better value if affordable. Compare current listings, upkeep and rental terms.", source:"https://wiki.torn.com/wiki/Property" },
  { id:"daily-training", stage:"First week", title:"Use gym energy consistently", detail:"Higher Happy improves gains. Track Strength, Defense, Speed and Dexterity. Avoid wasting energy by keeping it capped.", source:"https://wiki.torn.com/wiki/Gym" },
  { id:"candy", stage:"First week", title:"Learn candy, happy and booster cooldowns", detail:"Candy can increase Happy before gym training. Check booster cooldown and Torn-time Happy resets; never blindly copy expensive jump routines.", source:"https://wiki.torn.com/wiki/Happy" },
  { id:"starter-crimes", stage:"First week", title:"Build Crime Experience with easier crimes", detail:"Start with Search for Cash or Bootlegging and advance when reliable. Shoplifting, Pickpocketing, Burglary and Hustling offer different money/XP tradeoffs. Consistent success matters more than rushing difficult crimes.", source:"https://wiki.torn.com/wiki/Crimes" },
  { id:"starter-cash", stage:"First week", title:"Establish non-crime income", detail:"Check city finds, resell eligible city-shop goods after market-fee math, and compare item-market demand. Cash from crimes alone is not usually the fastest route to travel funding.", source:"https://www.torn.com/forums.php?p=threads&t=16607164" },
  { id:"honors", stage:"First week", title:"Collect inexpensive honors strategically", detail:"Look up requirements for Pocket Money (first bank deposit), Historian, Landlord and early activity honors. Avoid spending more on an honor than the reward is worth.", source:"https://wiki.torn.com/wiki/Award" },
  { id:"missions", stage:"First week", title:"Check Duke missions and daily routines", detail:"Missions, education, faction participation, crime and training should become a regular rhythm.", source:"https://wiki.torn.com/wiki/Mission" },
  { id:"bank", stage:"First week", title:"Begin bank investments and obtain Pocket Money", detail:"Bank deposits safely earn interest but lock funds for the selected term. New players unlock longer terms progressively.", source:"https://wiki.torn.com/wiki/Bank" },
  { id:"level15", stage:"Level 15", title:"Reach level 15 and unlock travel", detail:"Train enough to attack appropriate leveling targets. Avoid random stronger targets. Level 15 unlocks international travel and major trade income.", source:"https://www.torn.com/forums.php?p=threads&t=16582732", auto:"level15" },
  { id:"travel", stage:"Level 15", title:"Learn profitable flower/plushie travel loops", detail:"Compare local buying prices, Torn sell prices, time away and mugging risk. Travel light and avoid carrying unnecessary money.", source:"https://wiki.torn.com/wiki/Travel" },
  { id:"stock-ticker", stage:"Level 15", title:"Buy the Stock Ticker at the Points Building", detail:"The Stock Ticker costs 50 points, unlocking the stock market. Check point prices and avoid sacrificing essential early progress.", source:"https://wiki.torn.com/wiki/Stock_Market" },
  { id:"suitcase", stage:"Level 15", title:"Acquire a Large Suitcase when it pays for itself", detail:"A Large Suitcase currently adds +3 travel-item capacity (since the June 2026 change); suitcases do not stack. At the Hawaii shop it costs $10m.", source:"https://wiki.torn.com/wiki/Large_Suitcase", auto:"suitcase" },
  { id:"pi-rent", stage:"Level 15", title:"Plan a Private Island rental", detail:"Renting a Private Island is a realistic path to higher Happy and a faster-travel pilot before buying a PI; verify pilot/upkeep terms.", source:"https://wiki.torn.com/wiki/Property" },
  { id:"bank-merit", stage:"Long-term", title:"Raise Bank Interest to 10/10 as deposits grow", detail:"Each merit upgrade increases bank APR by 5%; prioritize it when investment principal makes the gain meaningful. A complete line costs 55 merits.", source:"https://wiki.torn.com/wiki/Bank", auto:"bankMerit" },
  { id:"wsu", stage:"Long-term", title:"Acquire the WSU education stock benefit", detail:"Hold 1,000,000 West Side University shares for a passive 10% reduction to FUTURE education course lengths; monitor current price.", source:"https://wiki.torn.com/wiki/Education", auto:"wsu" },
  { id:"principal", stage:"Long-term", title:"Obtain the permanent Principal education-job perk", detail:"Reaching Principal in the Education starter career grants a permanent 10% education-time reduction, even after leaving.", source:"https://wiki.torn.com/wiki/Education" },
  { id:"crime-progression", stage:"Long-term", title:"Invest in Crime Progression when useful", detail:"Crimes 2.0 progression merits improve crime experience and skill gains. Avoid repeatedly failing harder crimes.", source:"https://wiki.torn.com/wiki/Crimes" },
  { id:"bank-2b", stage:"Long-term", title:"Build a sustainable bank investment fund", detail:"The ordinary bank investment cap is $2 billion; invest within your cash-flow needs and grow toward it over time.", source:"https://wiki.torn.com/wiki/Bank" },
  { id:"pi-buy", stage:"Long-term", title:"Eventually purchase a Private Island", detail:"A PI costs $500 million base before extensive upgrades. Treat purchase as a major wealth milestone, not a beginner requirement.", source:"https://wiki.torn.com/wiki/Property" },
  { id:"routine", stage:"Ongoing", title:"Keep an efficient daily schedule", detail:"Check bars, cooldowns, active education, faction activity, crimes, training, missions and available inventory before spending.", source:"https://wiki.torn.com/wiki/Main_Page" }
];
function safe(value) {
  return String(value == null ? "" : value).replace(/[&<>"']/g, character => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[character]));
}
function sourceError(name) { return tornGuideApi.state.errors[name] ? '<p class="api-error">' + safe(name + ": " + tornGuideApi.state.errors[name]) + '</p>' : ""; }
function payload(name, field) {
  const item = tornGuideApi.state.data[name];
  return item ? (field && item[field] !== undefined ? item[field] : item) : null;
}
function formatNumber(value) {
  const number = Number(value);
  return value === null || value === undefined || !Number.isFinite(number) ? "Not available" : number.toLocaleString();
}
function meritLevel(name) {
  const user = payload("merits", "merits");
  const catalog = payload("meritCatalog", "merits");
  if (!user || !Array.isArray(user.upgrades) || !Array.isArray(catalog)) return null;
  const definition = catalog.find(merit => String(merit.name).toLowerCase() === name.toLowerCase());
  if (!definition) return null;
  const upgrade = user.upgrades.find(entry => Number(entry.id) === Number(definition.id));
  return upgrade ? Number(upgrade.level) : 0;
}
function ownedStockPositions() {
  const holdings = payload("stocks", "stocks");
  const catalog = payload("stockCatalog", "stocks");
  if (!Array.isArray(holdings) || !Array.isArray(catalog)) return null;
  return holdings.map(item => ({
    ...item,
    details: catalog.find(stock => Number(stock.id) === Number(item.id)) || null
  }));
}
function heldWsuShares() {
  const positions = ownedStockPositions();
  if (!positions) return null;
  const position = positions.find(item => item.details &&
    (String(item.details.acronym).toUpperCase() === "WSU" ||
    String(item.details.name).toLowerCase() === "west side university"));
  return position ? Number(position.shares || 0) : 0;
}
function autoDone(step) {
  const st = tornGuideApi.state;
  if (!st.identity) return false;
  if (step.auto === "level15") return Number(st.identity.level) >= 15;
  if (step.auto === "educationMerit") return meritLevel("Education Length") === 10;
  if (step.auto === "bankMerit") return meritLevel("Bank Interest") === 10;
  if (step.auto === "wsu") return heldWsuShares() !== null && heldWsuShares() >= 1000000;
  if (step.auto === "suitcase") return (st.inventory.Enhancer || []).some(item => item.name === "Large Suitcase" && Number(item.amount) > 0);
  if (step.auto === "job") {
    const info = payload("job", "job");
    return Boolean(info && typeof info === "object" && (info.name || info.position || info.company_name));
  }
  return false;
}
function stepKey(id) { return activeProfile ? activeKey("quickstart:" + id) : "quickstart:guest:" + id; }
function renderQuickstart() {
  const sections = [...new Set(guideSteps.map(step => step.stage))];
  const count = guideSteps.filter(step => autoDone(step) || read(stepKey(step.id)) === "done").length;
  let output = '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Checklist & quickstart</h1><p>Your daily routine and milestone roadmap are now one checklist. Supported milestones are checked against your Torn API data; your previous progress remains saved.</p></header>';
  output += '<section class="panel"><div class="panel-heading"><h2>Daily routine</h2></div><div class="panel-content"><p id="task-progress" role="status"></p><div class="checklist">' + Object.entries(tasks).map(([id,label]) => '<label><input type="checkbox" name="' + safe(id) + '" ' + (activeProfile ? "" : "disabled") + '><span>' + safe(label) + '</span></label>').join("") + '</div><p class="fine-print">The daily tasks reuse your old Checklist progress. Uncheck these when starting a new day.</p></div></section>';
  output += '<div class="panel"><div class="panel-content"><p class="progress-line" role="status">' + count + " of " + guideSteps.length + ' milestones complete</p><p class="fine-print">Guidance last reviewed November 2026. Rental prices and game mechanics may change. Always verify current in-game prices.</p></div></div>';
  for (const stage of sections) {
    output += '<section class="panel"><div class="panel-heading"><h2>' + safe(stage) + '</h2></div><div class="panel-content step-list">';
    for (const step of guideSteps.filter(item => item.stage === stage)) {
      const verified = autoDone(step);
      const checked = verified || read(stepKey(step.id)) === "done";
      output += '<div class="step-row"><label><input class="milestone-check" type="checkbox" data-step="' + safe(step.id) + '" ' + (checked ? "checked " : "") + (verified ? "disabled " : "") + '><span><strong>' + safe(step.title) + '</strong><small>' + safe(step.detail) + '</small></span></label><div class="step-foot">' + (verified ? '<span class="verified">Verified by API</span>' : "") + '<a href="' + safe(step.source) + '" target="_blank" rel="noopener noreferrer">Reference ↗</a></div></div>';
    }
    output += "</div></section>";
  }
  return output;
}
function wireQuickstart() {
  for (const checkbox of document.querySelectorAll(".milestone-check")) {
    checkbox.addEventListener("change", () => {
      write(stepKey(checkbox.dataset.step), checkbox.checked ? "done" : null);
      const count = guideSteps.filter(step => autoDone(step) || read(stepKey(step.id)) === "done").length;
      document.querySelector(".progress-line").textContent = count + " of " + guideSteps.length + " milestones complete";
    });
  }
}
function metric(label, value, description) {
  return '<div class="metric"><span class="metric-label">' + safe(label) + '</span><strong class="metric-value">' + safe(value) + '</strong>' + (description ? '<small>' + safe(description) + '</small>' : "") + "</div>";
}
function val(obj, key) { return obj && typeof obj === "object" ? obj[key] : undefined; }
function barsMarkup() {
  const bars = payload("bars", "bars");
  if (!bars) return sourceError("bars") || '<p>Bars not loaded yet.</p>';
  return '<div class="metric-grid">' + ["energy", "nerve", "happy", "life"].map(name => {
    const b = bars[name];
    return metric(name[0].toUpperCase() + name.slice(1), (b && b.current !== undefined ? formatNumber(b.current) : "?") + " / " + (b && b.maximum !== undefined ? formatNumber(b.maximum) : "?"));
  }).join("") + "</div>";
}
function battleMarkup() {
  const stats = payload("battlestats", "battlestats");
  if (!stats) return sourceError("battlestats") || '<p>Battle stats not loaded yet.</p>';
  return '<div class="metric-grid">' + ["strength", "defense", "speed", "dexterity", "total"].map(name => metric(name[0].toUpperCase() + name.slice(1), formatNumber(stats[name] && typeof stats[name] === "object" ? stats[name].value : stats[name]))).join("") + "</div>";
}
function inventoryMarkup() {
  let result = '<p class="fine-print">Torn caches inventory by category for 15 minutes. Quantities reflect the last successful API response. Sections show your inventory, not the faction armory.</p><div class="inventory-grid">';
  for (const category of ["Candy", "Drug", "Alcohol", "Tool", "Enhancer", "Booster", "Energy Drink", "Medical"]) {
    const list = tornGuideApi.state.inventory[category];
    const error = tornGuideApi.state.inventoryErrors[category];
    result += '<section class="inventory-panel"><h3>' + safe(category) + (list ? " (" + list.length + ")" : "") + '</h3>';
    if (error) result += '<p class="api-error">' + safe(error) + "</p>";
    else if (!list) result += '<p>Not loaded yet.</p>';
    else if (list.length === 0) result += '<p>Nothing currently held.</p>';
    else result += '<ul class="item-list">' + list.map(item => '<li><span>' + safe(item.name) + (item.equipped ? ' <small>(equipped)</small>' : "") + '</span><strong>×' + safe(formatNumber(item.amount)) + '</strong></li>').join("") + '</ul>';
    result += "</section>";
  }
  result += "</div>";
  return result;
}
const tornReportCatalog=Object.freeze({
  "energy": [
    "Energy",
    "https://torn.report/energy",
    "Energy",
    "M13 2 4 14h7l-1 8 10-12h-7z"
  ],
  "nerve": [
    "Nerve",
    "https://torn.report/nerve",
    "Nerve",
    "M12 3 3 8v8l9 5 9-5V8z M3 8l9 5 9-5"
  ],
  "education": [
    "Education",
    "https://torn.report/education",
    "Education",
    "M2 9l10-5 10 5-10 5z M6 11v6l6 3 6-3v-6"
  ],
  "drugs": [
    "Drugs",
    "https://torn.report/drugs",
    "Drugs",
    "M8 4a5 5 0 0 1 7 7l-6 6a5 5 0 0 1-7-7z M5 7l7 7"
  ],
  "racing": [
    "Racing",
    "https://torn.report/racing",
    "Racing",
    "M3 16v-5l3-5h12l3 5v5z M3 16v3m18-3v3M3 11h18"
  ],
  "uniques": [
    "Crime Uniques",
    "https://torn.report/uniques",
    "Crime Uniques",
    "M12 2l3 7 7 3-7 3-3 7-3-7-7-3 7-3z"
  ],
  "trains": [
    "Trains Received",
    "https://torn.report/trains",
    "Trains Received",
    "M3 9h3v6H3z M18 9h3v6h-3z M6 12h12"
  ],
  "oc": [
    "Organized Crimes",
    "https://torn.report/oc",
    "Organized Crimes",
    "M12 3a3 3 0 1 0 0 6 3 3 0 0 0 0-6 M4 21v-3a8 8 0 0 1 16 0v3 M2 11l3 2m17-2-3 2"
  ],
  "travel": [
    "Travel",
    "https://torn.report/travel",
    "Travel",
    "M2 12l9-2 5-8 2 1-2 8 6 4v2l-7-2-4 6-2-1 2-6-9 1z"
  ],
  "crimes": [
    "Old Crimes",
    "https://torn.report/crimes",
    "Old Crimes",
    "M4 4h16v16H4z M8 8h8m-8 4h8m-8 4h5"
  ],
  "bomb": [
    "Dirty Bomb",
    "https://torn.report/bomb",
    "Dirty Bomb",
    "M12 6a8 8 0 1 0 8 8 8 8 0 0 0-8-8 M15 7l3-4 3 1"
  ],
  "hunting": [
    "Hunting",
    "https://torn.report/hunting",
    "Hunting",
    "M12 2v5m0 10v5M2 12h5m10 0h5 M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14"
  ],
  "mug": [
    "Mug",
    "https://torn.report/mug",
    "Mug",
    "M4 8h16v12H4z M8 8V4h8v4 M9 14h6"
  ],
  "poker": [
    "Poker",
    "https://torn.report/poker",
    "Poker",
    "M5 2h14v20H5z M12 7l4 5-4 5-4-5z"
  ],
  "presspass": [
    "Press Pass",
    "https://torn.report/presspass",
    "Press Pass",
    "M4 3h16v18H4z M8 7h8m-8 4h8m-8 4h5"
  ],
  "slots": [
    "Slots",
    "https://torn.report/slots",
    "Slots",
    "M3 4h18v16H3z M8 4v16m8-16v16 M5 12h2m3 0h4m3 0h2"
  ],
  "wheel": [
    "Spin the Wheel",
    "https://torn.report/wheel",
    "Spin the Wheel",
    "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M12 3v18M3 12h18"
  ],
  "bazaar": [
    "Bazaar",
    "https://torn.report/bazaar",
    "Bazaar",
    "M3 9l3-6h12l3 6v3H3z M5 12v9h14v-9"
  ],
  "city": [
    "City Finds",
    "https://torn.report/city",
    "City Finds",
    "M3 21V9h6v12m0-18h6v18m0-11h6v11"
  ],
  "dump": [
    "Dump Search",
    "https://torn.report/dump",
    "Dump Search",
    "M3 6h18M6 6l1 15h10l1-15 M9 6V3h6v3"
  ],
  "imarket": [
    "Item Market",
    "https://torn.report/imarket",
    "Item Market",
    "M3 3h2l3 12h11l2-8H6 M9 20h1m7 0h1"
  ],
  "shops": [
    "Shop Sales",
    "https://torn.report/shops/sales",
    "Shop Sales",
    "M3 9l3-6h12l3 6v3H3z M5 12v9h14v-9 M9 16h6"
  ],
  "itemstats": [
    "Item Stats",
    "https://torn.report/itemstats",
    "Item Stats",
    "M4 20V4m0 16h16M8 16v-5m5 5V7m5 9v-8"
  ],
  "loot": [
    "Loot",
    "https://torn.report/loot",
    "Loot",
    "M3 8h18v13H3z M3 12h18M9 8V4h6v4"
  ],
  "pack": [
    "Supply Packs",
    "https://torn.report/pack",
    "Supply Packs",
    "M3 7l9-4 9 4v14H3z M3 7l9 5 9-5 M12 12v9"
  ],
  "christmas": [
    "Christmas Town",
    "https://torn.report/christmas",
    "Christmas Town",
    "M12 2l-6 8h3l-5 7h16l-5-7h3z M12 17v5"
  ],
  "dollarsales": [
    "Dollar Sales",
    "https://torn.report/dollarsales",
    "Dollar Sales",
    "M12 2v20 M17 6H9a3 3 0 0 0 0 6h6a3 3 0 0 1 0 6H7"
  ],
  "easter": [
    "Easter Eggs",
    "https://torn.report/easter",
    "Easter Eggs",
    "M12 2c-4 0-8 8-8 13a8 8 0 0 0 16 0c0-5-4-13-8-13z"
  ],
  "npc": [
    "Seasonal NPCs",
    "https://torn.report/npc",
    "Seasonal NPCs",
    "M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M4 21v-2a8 8 0 0 1 16 0v2"
  ],
  "halloween": [
    "Trick or Treat",
    "https://torn.report/halloween",
    "Trick or Treat",
    "M12 4c-6-3-10 2-10 8s4 10 10 8c6 2 10-2 10-8S18 1 12 4 M12 4V1 M7 10l2 2m6-2 2 2 M7 16h10"
  ],
  "loottimer": [
    "Loot Timer",
    "https://torn.report/loot/timer",
    "Loot Timer",
    "M12 5a8 8 0 1 0 0 16 8 8 0 0 0 0-16 M9 2h6m-3 3v8l4 2"
  ],
  "data": [
    "Manage Data",
    "https://torn.report/data",
    "Manage Data",
    "M3 6c0-5 18-5 18 0s-18 5-18 0v12c0 5 18 5 18 0V6 M3 12c0 5 18 5 18 0"
  ],
  "export": [
    "Export Logs",
    "https://torn.report/export",
    "Export Logs",
    "M12 3v12m-5-5 5 5 5-5 M3 15v6h18v-6"
  ]
});
function homePair(label,value,extraClass=""){
  return '<div class="home-pair"><dt>'+safe(label)+'</dt><dd class="'+extraClass+'">'+safe(value??"Not available")+'</dd></div>';
}
function homeStatList(items){
  return '<dl class="home-stat-list">'+items.map(([name,value])=>
    homePair(name,value)).join("")+'</dl>';
}
function homeValue(v){
  return v===undefined||v===null?"Not available":formatNumber(v);
}
/* Torn API v2 supplies current, maximum, increment, interval, tick_time
 * (seconds until next tick), and full_time. Preserve its actual tick phase
 * between cached pulls; never initiate an API request for animation. */
// Shared active-book detection; use only the current account's active perks.
// Book ownership/read state is only asserted from explicit cached evidence.
function tornBookTileStatus(name,active=false){
  if(active)return "active";
  const state=tornGuideApi.state,normalize=v=>String(v??"").toLowerCase().replace(/^book\s*:\s*/,"").replace(/[^a-z0-9]/g,"");
  const key=normalize(name),matches=item=>normalize(item?.name??item?.item?.name??item)===key;
  const rows=Object.values(state.inventory||{}).filter(Array.isArray).flat();
  const item=rows.find(matches);
  if(item&&(item.read===true||item.is_read===true||item.status==="read"))return "read";
  if(item&&Number(item.amount??item.quantity)>0)return "owned";
  return "";
}
function tornHappinessBook(){
  const state=tornGuideApi.state,raw=state.data.perks,perks=raw?.perks??raw;
  const books=perks&&Object.entries(perks).filter(([key])=>/^book(?:_?perks)?$/i.test(key));
  const known=Array.isArray(books)&&books.some(([,items])=>Array.isArray(items));
  const entries=(books||[]).flatMap(([,items])=>Array.isArray(items)?items:[]).map(item=>typeof item==="string"?item:[item?.name,item?.effect,item?.description].filter(Boolean).join(" "));
  const source=entries.find(t=>/ignorance\s+is\s+bliss|happiness\s+can\s+regenerate\s+above\s+maximum/i.test(t));
  return {active:!!source,known,source:source??null};
}
function tornBarProjection(name,bar,at,now=Date.now()){
  const rawCurrent=Number(bar?.current),max=Number(bar?.maximum);
  if(!bar||!Number.isFinite(rawCurrent)||!Number.isFinite(max)||max<=0)return null;
  const defaults={
    energy:{step:5,period:max>=150?600:900},
    nerve:{step:1,period:300},
    happy:{step:5,period:900},
    life:{step:Math.max(1,Math.floor(max*.05)),period:300}
  };
  const spec=defaults[name];if(!spec)return null;
  const reportedStep=Number(bar.increment),reportedInterval=Number(bar.interval);
  const step=reportedStep>0&&Number.isFinite(reportedStep)?reportedStep:spec.step;
  // v2 intervals are seconds. Do not interpret them as milliseconds.
  const interval=reportedInterval>0&&Number.isFinite(reportedInterval)?reportedInterval:spec.period;
  const stamp=Number(at)||now,elapsed=Math.max(0,(now-stamp)/1000);
  const tick=Number(bar.tick_time??bar.ticktime);
  const full=Number(bar.full_time??bar.fulltime);
  let first=null,phaseSource="estimated";
  if(bar.tick_time!=null||bar.ticktime!=null){
    if(Number.isFinite(tick)&&tick>=0&&tick<=interval){
      first=tick;phaseSource="API";
    }
  }
  if(first===null&&(bar.full_time!=null||bar.fulltime!=null)&&rawCurrent<max){
    const remainingTicks=Math.ceil((max-rawCurrent)/step);
    const derived=full-(remainingTicks-1)*interval;
    if(Number.isFinite(derived)&&derived>=0&&derived<=interval){
      first=derived;phaseSource="API";
    }
  }
  // Without an API tick phase, use a UTC-aligned approximation; this case is
  // identified in the tooltip and replaced by the next real API bar snapshot.
  if(first===null)first=(interval-((stamp/1000)%interval))%interval||interval;
  const ticks=elapsed<first?0:1+Math.floor((elapsed-first)/interval);
  const bliss=name==="happy"&&tornHappinessBook().active;
  const ceiling=bliss?99999:max;
  // Preserve observed over-cap values until a newer snapshot arrives unless
  // the active book confirms over-cap regeneration.
  const current=bliss?Math.min(ceiling,rawCurrent+ticks*step):rawCurrent>=max?rawCurrent:Math.min(max,rawCurrent+ticks*step);
  const nextTick=Math.max(0,first+ticks*interval-elapsed);
  const until=current>=max?0:nextTick;
  return {current,maximum:max,percentage:Math.max(0,Math.min(100,current/max*100)),
    until,phaseSource,estimated:phaseSource!=="API",
    snapshotAt:stamp,step,interval,nextTick};
}
function homeCountdown(seconds){
  if(seconds<=0)return "FULL";
  const total=Math.ceil(seconds);
  return (Math.floor(total/3600)?String(Math.floor(total/3600)).padStart(2,"0")+":" :"")+
    String(Math.floor(total%3600/60)).padStart(2,"0")+":"+
    String(total%60).padStart(2,"0");
}
function homeBar(name,bar){
  const state=tornGuideApi.state;
  const bridge=state.bridge&&state.bridge.fields?.includes(name)&&state.bridge.timestamp>Number(state.fetchedAt.bars||0);
  const at=bridge?state.bridge.timestamp:state.fetchedAt.bars;
  const projected=tornBarProjection(name,bar,at);
  const valid=projected!==null;
  const amount=valid?formatNumber(projected.current)+"/"+formatNumber(projected.maximum):"Not loaded";
  const countdown=valid?(projected.current>projected.maximum?"OVER":projected.current>=projected.maximum?"FULL":homeCountdown(projected.until)):"";
  const tooltip=valid?(projected.current>projected.maximum?"Over-cap bar: reset timing depends on active perks; next API snapshot needed":projected.estimated?"Estimated tick phase; awaiting precise Torn API bar timing":"Live projection from Torn API tick timing")+
    " • last snapshot "+tornGuidePreferences.formatDate(projected.snapshotAt):"Bar not loaded";
  return '<div class="home-bar home-bar-'+safe(name)+'" data-home-bar="'+safe(name)+'" title="'+safe(tooltip)+'">'+
    '<div class="home-bar-head"><strong>'+safe(name[0].toUpperCase()+name.slice(1))+
    ': <span data-home-current>'+safe(amount)+'</span></strong><small data-home-countdown>'+safe(countdown)+'</small></div>'+
    '<div class="home-bar-track" role="progressbar" aria-label="'+safe(name)+'" aria-valuemin="0" '+
      (valid?'aria-valuenow="'+projected.current+'" aria-valuemax="'+projected.maximum+'"':'aria-valuetext="Not loaded"')+'>'+
      '<span data-home-fill style="width:'+(valid?projected.percentage.toFixed(2):0)+'%"></span></div></div>';
}
function updateHomeLiveBars(){
  const state=tornGuideApi.state,bars=payload("bars","bars");
  const sidebar=document.getElementById("sidebar-character-details");
  const route=(location.hash||"#home").slice(1);
  const home=["","home","dashboard"].includes(route)?document.getElementById("topic-view"):null;
  const roots=[sidebar,home&&!home.hidden?home:null].filter(Boolean);
  if(bars)for(const root of roots){
    for(const row of root.querySelectorAll("[data-home-bar]")){
      const name=row.dataset.homeBar,bar=bars[name];if(!bar)continue;
      const bridge=state.bridge&&state.bridge.fields?.includes(name)&&state.bridge.timestamp>Number(state.fetchedAt.bars||0);
      const at=bridge?state.bridge.timestamp:state.fetchedAt.bars;
      const current=tornBarProjection(name,bar,at);
      if(!current)continue;
      const number=row.querySelector("[data-home-current]"),time=row.querySelector("[data-home-countdown]"),
        fill=row.querySelector("[data-home-fill]"),progress=row.querySelector("[role=progressbar]");
      if(number)number.textContent=formatNumber(current.current)+"/"+formatNumber(current.maximum);
      if(time)time.textContent=current.current>current.maximum?"OVER":
        current.current>=current.maximum?"FULL":homeCountdown(current.until);
      if(fill)fill.style.width=current.percentage.toFixed(2)+"%";
      if(progress)progress.setAttribute("aria-valuenow",String(current.current));
    }
  }
  if(!home||home.hidden)return;
  for(const time of home.querySelectorAll("[data-activity-deadline]")){
    const target=Number(time.dataset.activityDeadline);
    if(!Number.isFinite(target))continue;
    const remaining=Math.max(0,Math.ceil((target-Date.now())/1000));
    const days=Math.floor(remaining/86400),hours=Math.floor(remaining%86400/3600),
      minutes=Math.floor(remaining%3600/60),secs=remaining%60;
    time.textContent=remaining?((days?days+"d ":"")+String(hours).padStart(2,"0")+":"+
      String(minutes).padStart(2,"0")+":"+String(secs).padStart(2,"0")):"Ready";
  }
}

// Torn API v2 /user/networth is a distinct globally cached selection. Display
// its server-provided total instead of estimating wealth from visible balances.
const tornNetworthGroups=Object.freeze([
  ["Money", [
    ["wallet","Wallet"],["city_bank","City bank"],["cayman_bank","Cayman bank"],
    ["vault","Vault"],["piggy_bank","Piggy bank"],["bookie","Bookie"],
    ["pending","Pending"],["loans","Loans",true],["unpaid_fees","Unpaid fees",true]
  ]],
  ["Assets", [
    ["stock_market","Stocks"],["property","Properties"],["company","Company"]
  ]],
  ["Items", [
    ["inventory","Inventory"],["display_case","Display case"],["bazaar","Bazaar"],
    ["item_market","Item market"],["auction_house","Auction house"],
    ["enlisted_cars","Enlisted cars"],["trades","Trades"]
  ]]
]);
function networthAmount(v,negative=false){
  const value=Number(v);
  if(v===undefined||v===null||!Number.isFinite(value))return null;
  const adjusted=negative?-Math.abs(value):value;
  return adjusted<0?"-$"+formatNumber(Math.abs(adjusted)):"$"+formatNumber(adjusted);
}
function networthPanel(){
  const wealth=payload("networth","networth"),error=sourceError("networth");
  let out='<section class="panel home-networth"><div class="panel-heading"><h2>Net worth</h2></div>'+
    '<div class="panel-content">';
  if(!wealth||!Number.isFinite(Number(wealth.total))){
    return out+'<p class="networth-not-loaded">Net worth '+(error?"unavailable":"not loaded yet")+
      '</p>'+error+'</div></section>';
  }
  out+='<div class="networth-total" aria-label="Total net worth"><small>Total net worth</small>'+
    '<strong>'+safe(networthAmount(wealth.total))+'</strong></div>';
  for(const [name,entries] of tornNetworthGroups){
    const raw=wealth[name.toLowerCase()];
    const rows=[];
    let sum=0;
    for(const [key,label,negative] of entries){
      const input=raw?.[key];
      if(input===undefined||input===null||!Number.isFinite(Number(input))||Number(input)===0)continue;
      const contribution=negative?-Math.abs(Number(input)):Number(input);
      sum+=contribution;
      rows.push('<div class="networth-line"><dt>'+safe(label)+'</dt><dd>'+
        safe(networthAmount(input,negative))+'</dd></div>');
    }
    out+='<details class="networth-group" data-collapse-key="networth:'+safe(name)+'" open><summary><span>'+safe(name)+'</span>'+
      '<strong>'+safe(networthAmount(sum))+'</strong></summary>'+
      '<dl class="networth-lines">'+(rows.join("")||
        '<div class="networth-empty">No recorded value</div>')+'</dl></details>';
  }
  if(wealth.points!==undefined&&wealth.points!==null&&Number.isFinite(Number(wealth.points))){
    out+='<div class="networth-points"><span>Points value</span><strong>'+
      safe(networthAmount(wealth.points))+'</strong></div>';
  }
  const snapshot=Number(wealth.timestamp)*1000||tornGuideApi.state.fetchedAt.networth;
  const date=snapshot?tornGuidePreferences.formatDate(snapshot)
    .replace(/(\b\d{4}),\s+(?=\d{1,2}:)/,"$1 "):"Date unavailable";
  out+='<p class="networth-footnote">'+safe(date)+'</p>'+error+'</div></section>';
  return out;
}
function renderDashboard() {
  let result='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Home dashboard</h1></header>';
  if(!tornGuideApi.isConnected()){
    return result+'<section class="panel"><div class="panel-content"><p>Connect your Torn API key below to show your in-game-style dashboard. Account data remains private to this browser.</p></div></section>';
  }
  const st=tornGuideApi.state;
  result+=tornCrimeGuide.recommendations();
  const issues=[...Object.entries(st.errors).map(([key,value])=>[key,value]),
    ...Object.entries(st.inventoryErrors).map(([key,value])=>["Inventory: "+key,value])];
  if(issues.length){
    result+='<details class="home-expand-panel home-errors" data-collapse-key="home-api-issues" open><summary>API issues ('+issues.length+')</summary>'+
      '<div class="home-expand-body"><ul class="api-failure-list">'+issues.map(([name,detail])=>
        '<li><strong>'+safe(name)+'</strong><small>'+safe(detail)+'</small></li>').join("")+
      '</ul></div></details>';
  }
  return result;
}



const stockView={sort:"default",query:"",filter:"all",expanded:new Set()};
// Benefit requirements and reward names from the Torn stock market and Clairvoyant.
// API definitions override fallback data. No personal holdings or prices are stored here.
const stockFallback={
 TCI:[1500000,0,"10% bank interest bonus"],SYM:[500000,7,"Drug Pack"],TGP:[2500000,0,"Company advertising boost"],WSU:[1000000,0,"10% course time reduction"],WLT:[9000000,0,"Private jet access"],TCP:[1000000,0,"Company sales boost"],FHG:[2000000,7,"Feathery Hotel Coupon"],MCS:[350000,7,"100 energy"],SYS:[3000000,0,"Advanced firewall"],PRN:[1000000,7,"Erotic DVD"],THS:[150000,7,"Box of Medical Supplies"],ASS:[1000000,7,"Six-Pack of Alcohol"],MSG:[300000,0,"Free classified advertising"],TMI:[6000000,31,"$25,000,000",25000000],IIL:[1000000,0,"50% coding time reduction"],LOS:[7500000,0,"25% mission reward bonus"],PTS:[10000000,7,"100 points"],YAZ:[1000000,0,"Free banner advertising"],TSB:[3000000,31,"$50,000,000",50000000],CNC:[7500000,31,"$80,000,000",80000000],EVL:[100000,7,"1000 happiness"],LSC:[500000,7,"Lottery Voucher"],MUN:[5000000,7,"Six-Pack of Energy Drink"],IST:[100000,0,"Free education courses"],TCC:[7500000,7,"Clothing Cache"],BAG:[3000000,7,"Ammunition Pack"],LAG:[750000,7,"Lawyer's Business Card"],CBD:[350000,7,"50 nerve"],GRN:[500000,31,"$4,000,000",4000000],ELT:[5000000,0,"10% home upgrade discount"],TCT:[100000,31,"$1,000,000",1000000],TCM:[1000000,0,"10% racing skill gain boost"],EWM:[1000000,7,"Box of Grenades"],HRG:[10000000,31,"Random Property"],IOU:[3000000,31,"$12,000,000",12000000]
};
function stockRows(){
 const catalog=payload("stockCatalog","stocks"),holdings=payload("stocks","stocks"),items=payload("itemCatalog","items");
 const list=Array.isArray(catalog)?catalog:Object.values(catalog||{}),owned=Array.isArray(holdings)?holdings:Object.values(holdings||{}),itemList=Array.isArray(items)?items:Object.values(items||{});
 const num=v=>v!=null&&v!==""&&Number.isFinite(Number(v))?Number(v):null;
 return list.map(c=>{
  const h=owned.find(x=>Number(x.id)===Number(c.id)),ticker=String(c.acronym||"").toUpperCase(),f=stockFallback[ticker]||[],b=c.bonus??c.benefit??{};
  const price=[c.market?.price,c.current_price,c.price].map(num).find(v=>v!=null&&v>0)??null,shares=holdings==null?null:num(h?.shares??0),value=price!=null&&shares!=null?price*shares:null;
  const req=num(b.requirement??b.shares??f[0]),freq=num(b.frequency??f[1]),description=typeof b.description==="string"?b.description:typeof b.name==="string"?b.name:f[2]||"Benefit unavailable";
  const passive=b.passive===true||String(b.type||"").toLowerCase()==="passive"||freq===0;
  const tier=req>0&&shares!=null?Math.max(0,Math.floor(Math.log2(shares/req+1))):0;
  const active=shares!=null&&req>0&&shares>=req,benefit=h?.bonus??h?.dividend??h?.benefit;
  const availability=benefit?.available??benefit?.ready;
  const readyCount=num(availability);
  const ready=availability===true||readyCount>0;
  const waiting=availability===false||readyCount===0;
  const progress=num(benefit?.progress),cycle=num(benefit?.frequency??freq);
  const days=active&&!passive?(ready?0:progress!=null&&cycle>0?Math.max(0,cycle-progress):null):null;
  const nextShares=req>0&&shares!=null&&!(passive&&active)?Math.max(0,req*(2**(tier+1)-1)-shares):null;
  const nextCost=nextShares!=null&&price!=null?nextShares*price:null,blockCost=req>0&&price!=null?req*price:null;
  const itemName=String(f[2]||description).toLowerCase(),item=itemList.find(x=>String(x.name||"").toLowerCase()===itemName);
  const itemPrice=num(item?.market_value??item?.value?.market_price??item?.value?.market_value??item?.market_price);
  const cashMatch=description.match(/^\$([\d,]+)$/);
  const payout=num((cashMatch?cashMatch[1].replace(/,/g,""):null)??f[3]??itemPrice);
  const daily=payout!=null&&freq>0?payout/freq:null,roi=daily!=null&&blockCost>0?daily*365/blockCost*100:null;
  const nextRoi=daily!=null&&blockCost>0?daily*365/(blockCost*2**tier)*100:null;
  const transactions=Array.isArray(h?.transactions)?h.transactions:Object.values(h?.transactions||{});
  const costs=transactions.map(t=>{const n=num(t.shares),p=num(t.bought_price??t.price??t.purchase_price);return n!=null&&p!=null?n*p:null;});
  const cost=shares===0?0:costs.length&&costs.every(x=>x!==null)&&transactions.reduce((sum,t)=>sum+(num(t.shares)||0),0)===shares?costs.reduce((sum,x)=>sum+x,0):null;
  // Only explicit collected dividend counts qualify for historical return.
  // Holding age, progress and current benefit tier do not establish claims.
  const countRaw=benefit?.collected_count??benefit?.times_collected??benefit?.payouts_collected??h?.dividends_collected;
  const claimedRaw=num(countRaw),claimed=!passive&&claimedRaw!=null&&claimedRaw>=0&&Number.isInteger(claimedRaw)?claimedRaw:null;
  const dividendTotal=claimed!=null&&payout!=null?claimed*payout:null;
  const profit=cost!=null&&value!=null?value-cost:null;
  const lifetimeRoi=dividendTotal!=null&&cost>0?dividendTotal/cost*100:null;
  const combinedReturn=dividendTotal!=null&&profit!=null?dividendTotal+profit:null;
  const combinedRoi=combinedReturn!=null&&cost>0?combinedReturn/cost*100:null;
  return {name:c.name||ticker,ticker,price,shares,value,req,freq,description,passive,tier,active,ready,waiting,days,nextShares,nextCost,blockCost,payout,daily,roi,nextRoi,cost,profit,claimed,dividendTotal,lifetimeRoi,combinedReturn,combinedRoi};

 });
}
function renderStocksPanel(){
 const rows=stockRows(),money=v=>v==null?"—":"$"+formatNumber(Math.round(v)),number=v=>v==null?"—":formatNumber(v),percent=v=>v==null?"—":v.toFixed(1)+"%";
 const total=rows.filter(r=>r.shares>0),sum=key=>total.length&&total.every(r=>r[key]!=null)?total.reduce((n,r)=>n+r[key],0):null;
 const options=[["default","Active dividends, then value"],["name","Stock name"],["value","Holdings value"],["shares","Shares owned"],["price","Share price"],["roi","Annual ROI (first block)"],["nextRoi","Annual ROI (next block)"],["nextCost","Cost to next block"],["days","Days to payout"],["daily","Daily dividend value"],["lifetimeRoi","Collected dividend ROI"],["combinedRoi","Combined total ROI"]];
 const q=stockView.query.toLowerCase(),filtered=rows.filter(r=>(r.name+" "+r.ticker).toLowerCase().includes(q)&&(stockView.filter==="all"||stockView.filter==="owned"&&r.shares>0||stockView.filter==="active"&&r.active||stockView.filter==="cash"&&!r.passive||stockView.filter==="passive"&&r.passive));
 const cmp=(a,b,k,asc=false)=>a[k]==null?(b[k]==null?0:1):b[k]==null?-1:asc?a[k]-b[k]:b[k]-a[k];
 filtered.sort((a,b)=>stockView.sort==="default"?Number(b.active&&!b.passive)-Number(a.active&&!a.passive)||Number(b.active)-Number(a.active)||cmp(a,b,"value")||a.name.localeCompare(b.name):stockView.sort==="name"?a.name.localeCompare(b.name):cmp(a,b,stockView.sort,["nextCost","days"].includes(stockView.sort))||a.name.localeCompare(b.name));
 let out='<section class="panel stock-market-panel"><div class="panel-heading"><h2>Stock Market</h2><span>Value: '+money(sum("value"))+' · Profit: '+money(sum("profit"))+'</span></div><div class="panel-content">';
 out+='<div class="stock-controls"><label>Search <input data-stock-query value="'+safe(stockView.query)+'" placeholder="Stock name or ticker"></label><label>Show <select data-stock-filter>'+[["all","All stocks"],["owned","Owned"],["active","Active benefits"],["cash","Payout benefits"],["passive","Passive benefits"]].map(([v,l])=>'<option value="'+v+'" '+(stockView.filter===v?"selected":"")+'>'+l+'</option>').join("")+'</select></label><label>Sort <select data-stock-sort>'+options.map(([v,l])=>'<option value="'+v+'" '+(stockView.sort===v?"selected":"")+'>'+l+'</option>').join("")+'</select></label><small>'+filtered.length+' of '+rows.length+' stocks</small></div>';
 out+='<div class="stock-table-scroll"><table class="stock-market-table"><thead><tr><th>Stock</th><th>Price</th><th>Owned / value</th><th>Dividend / benefit</th></tr></thead><tbody>';
 for(const r of filtered){
 const status=r.shares==null?"Holdings not loaded":!r.active?"Inactive":r.passive?"Benefit active":r.ready?"Collection ready":r.days!=null?"Ready in "+r.days+" days":"Payout timing unavailable";
 const expanded=typeof tornDisclosureState!=="undefined"?tornDisclosureState.get("stock-row:"+r.ticker,stockView.expanded.has(r.ticker)):stockView.expanded.has(r.ticker),profitClass=r.profit==null||r.profit===0?"stock-neutral":r.profit>0?"stock-positive":"stock-negative";
 const rowId="stock-detail-"+r.ticker;
 const ownedText=r.shares==null?"—":number(r.shares)+" shares"+(r.shares>0?" @ "+money(r.cost):"");
 const field=(label,val,cls="")=>'<div class="stock-detail-pair"><span>'+safe(label)+'</span><strong class="'+cls+'">'+safe(val)+'</strong></div>';
 out+='<tr class="stock-summary '+(r.active?"stock-active":"")+'" data-stock-row="'+safe(r.ticker)+'"><td><button type="button" class="stock-expand" data-stock-expand="'+safe(r.ticker)+'" aria-expanded="'+expanded+'" aria-controls="'+safe(rowId)+'"><span class="stock-chevron" aria-hidden="true">'+(expanded?"▾":"▸")+'</span><span><span class="stock-ticker">'+safe(r.ticker)+'</span><strong>'+safe(r.name)+'</strong></span></button></td><td>'+(r.price!=null?"$"+r.price.toFixed(2):"—")+'</td><td><strong>'+ownedText+'</strong><small class="stock-current-value '+profitClass+'" title="'+safe(r.profit==null?"Profit unavailable":"Unrealized profit: "+money(r.profit))+'">'+money(r.value)+'</small></td><td><strong>'+safe(r.description)+'</strong><small class="'+(r.active?"stock-benefit-active":"")+'">'+safe(status)+(r.active&&!r.passive?' · '+r.tier+' block'+(r.tier===1?'':'s'):'')+'</small>'+(r.freq>0?'<small>Every '+r.freq+' days · '+money(r.payout)+' / block</small>':'')+'</td></tr>';
 out+='<tr id="'+safe(rowId)+'" class="stock-detail-row" '+(expanded?"":"hidden")+'><td colspan="4"><div class="stock-detail-grid"><section><h3>Next benefit block</h3>'+
 (r.passive&&r.active?'<p class="fine-print">Passive benefit unlocked; no additional block.</p>':field("Additional shares",number(r.nextShares))+field("Additional cost",money(r.nextCost))+field("First block cost",money(r.blockCost)))+
 '</section><section><h3>Annual dividend ROI</h3>'+field("First block",percent(r.roi))+field("Next block",percent(r.nextRoi))+field("Daily value / block",money(r.daily))+'</section><section><h3>Lifetime return</h3>'+
 field("Unrealized profit",money(r.profit),profitClass)+(r.passive?'<p class="fine-print">Passive benefit; no recurring dividend.</p>':field("Collected payouts",number(r.claimed))+field("Dividend value (current MV)",money(r.dividendTotal))+field("Dividend ROI",percent(r.lifetimeRoi))+field("Total return incl. price",money(r.combinedReturn))+field("Total ROI",percent(r.combinedRoi))+(r.claimed==null?'<p class="fine-print">Collected payout history unavailable in holdings data.</p>':""))+'</section></div></td></tr>';
 }
 return out+'</tbody></table></div><p class="fine-print">Annual dividend ROI uses current share prices and 365 days, excluding stock price changes. Item rewards use cached Torn market values; passive or unpriced rewards are not assigned a cash ROI. Next block cost is the additional shares required, excluding fees.</p>'+sourceError("stocks")+sourceError("stockCatalog")+sourceError("itemCatalog")+'</div></section>';
}
function wireStocksPanel(view){
 if(view.dataset.stockBound==="1")return;view.dataset.stockBound="1";
 view.addEventListener("click",event=>{
 const row=event.target.closest("[data-stock-row]");
 if(!row||!view.contains(row))return;
 const ticker=row.dataset.stockRow,button=row.querySelector("[data-stock-expand]"),detail=row.nextElementSibling;
 if(!button||!detail?.classList.contains("stock-detail-row"))return;
 const expanded=button.getAttribute("aria-expanded")!=="true";
 if(typeof tornDisclosureState!=="undefined")tornDisclosureState.set("stock-row:"+ticker,expanded);
 if(expanded)stockView.expanded.add(ticker);else stockView.expanded.delete(ticker);
 button.setAttribute("aria-expanded",String(expanded));
 button.querySelector(".stock-chevron").textContent=expanded?"▾":"▸";
 detail.hidden=!expanded;
 });
 view.addEventListener("change",event=>{
 const el=event.target;
 if(el.matches("[data-stock-sort]"))stockView.sort=el.value;
 else if(el.matches("[data-stock-filter]"))stockView.filter=el.value;
 else if(el.matches("[data-stock-query]"))stockView.query=el.value;
 else return;
 const panel=view.querySelector(".stock-market-panel");if(panel)panel.outerHTML=renderStocksPanel();
 });
}
const inventoryExpanded=new Set();
const inventoryTabs=new Map();
const inventoryEquippedIcon='<span class="inventory-equipped-icon" title="Equipped" role="img" aria-label="Equipped"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="6" r="3"/><path d="M5 21v-3a7 7 0 0 1 14 0v3"/></svg></span>';
function inventorySelectTab(row,tab){
  if(!row||!["details","market"].includes(tab))return;
  const detail=row.querySelector("[data-inventory-detail]");
  inventoryTabs.set(detail.dataset.inventoryDetail,tab);
  for(const button of row.querySelectorAll("[data-inventory-tab]"))button.setAttribute("aria-pressed",String(button.dataset.inventoryTab===tab));
  for(const panel of row.querySelectorAll("[data-inventory-tab-panel]"))panel.hidden=panel.dataset.inventoryTabPanel!==tab;
}
if(typeof document!=="undefined")document.addEventListener("click",event=>{
  const button=event.target.closest?.("[data-inventory-tab]");
  if(button)inventorySelectTab(button.closest(".inventory-detail-row"),button.dataset.inventoryTab);
});
let inventoryFilter="All";
const inventoryIcons={"All":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 7h7l2 2h9v12H3zM3 7V4h7l2 3h8\"/></svg>","Temporary":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m5 8 11 11 4-4L9 4zM4 4l2-2m11 2 3 3\"/></svg>","Defensive":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z\"/></svg>","Clothing":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m8 3-6 4 3 5 3-2v11h8V10l3 2 3-5-6-4c-1 4-7 4-8 0z\"/></svg>","Medical":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M9 3h6v6h6v6h-6v6H9v-6H3V9h6z\"/></svg>","Drug":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M12 21V4m0 10-7-7 2 8-4 1 9 3 9-3-4-1 2-8-7 7\"/></svg>","Energy Drink":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><rect x=\"7\" y=\"3\" width=\"10\" height=\"18\" rx=\"2\"/><path d=\"m13 6-3 6h4l-3 6\"/></svg>","Alcohol":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M5 3h14l-2 9H7zM12 12v8m-5 0h10\"/></svg>","Candy":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m7 8 4-4 9 9-4 4zM7 8 2 6v7l5-1m9 5 1 5h6l-3-9\"/></svg>","Supply Pack":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m3 7 9-4 9 4v12l-9 3-9-3zM3 7l9 4 9-4M12 11v11\"/></svg>","Booster":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m12 3 7 8h-4v10H9V11H5z\"/></svg>","Enhancer":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m4 20 13-13 3 3L7 23zM5 3v5m-2-2h5m12-3v4m-2-2h4\"/></svg>","Tool":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m4 4 5 5m6 6 5 5M4 20 16 8m0 0-1-5 3 3 3-3v5l-5 3M3 3l4 1 2 4-2 2-4-2z\"/></svg>","Material":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m3 16 5-5 4 5-4 5zM12 16l4-5 5 5-5 5zM7 8l5-5 5 5-5 5z\"/></svg>","Other":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><circle cx=\"5\" cy=\"12\" r=\"1\"/><circle cx=\"12\" cy=\"12\" r=\"1\"/><circle cx=\"19\" cy=\"12\" r=\"1\"/></svg>","Special":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m12 2 3 7 7 1-5 5 1 7-6-4-6 4 1-7-5-5 7-1z\"/></svg>","Flower":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M12 22v-9m0 5 5-3M12 18l-5-3\"/><circle cx=\"12\" cy=\"8\" r=\"3\"/><path d=\"M12 5c-5-8-11 3-3 4-6 5 4 10 5 2 8 1 7-9 1-7z\"/></svg>","Primary":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M2 8h13l2-2h5v4h-6l-3 3h-3l-2 6H4l2-6H2z\"/></svg>","Secondary":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 6h18v5h-9l-2 8H5l2-8H3z\"/></svg>","Melee":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m4 20 5-5m-6 2 4 4m0-9 5 5M9 14 20 3l1 6-9 9\"/></svg>","Jewelry":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m3 8 4-5h10l4 5-9 13zM3 8h18M7 3l5 18 5-18\"/></svg>","Plushie":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><circle cx=\"12\" cy=\"8\" r=\"5\"/><circle cx=\"6\" cy=\"4\" r=\"2\"/><circle cx=\"18\" cy=\"4\" r=\"2\"/><path d=\"M8 12c-8 4-3 11 4 9 7 2 12-5 4-9M10 8h.01M14 8h.01\"/></svg>","Car":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"m4 10 3-6h10l3 6 2 3v6h-4v-3H6v3H2v-6zM4 10h16M5 13h2m10 0h2\"/></svg>","Book":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 4h7c2 0 2 2 2 2s0-2 2-2h7v15h-7l-2 2-2-2H3zM12 6v15\"/></svg>","Artifact":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M8 3h8M9 3v5l-5 6v5l4 2h8l4-2v-5l-5-6V3M5 15h14\"/></svg>","Collectible":"<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M7 3h10v6c0 4-2 6-5 6s-5-2-5-6zM7 5H3v3c0 3 2 4 5 4M17 5h4v3c0 3-2 4-5 4M12 15v5m-5 1h10\"/></svg>"};
const inventoryCategoryLabels={"Temporary":"Temp","Defensive":"Armor","Drug":"Drugs","Energy Drink":"E-Cans","Supply Pack":"Supply Packs","Booster":"Boosters","Enhancer":"Enhancers","Tool":"Tools","Material":"Materials","Flower":"Flowers","Plushie":"Plushies","Car":"Cars","Book":"Books","Other":"Misc","Artifact":"Artifacts","Collectible":"Collectibles"};
const inventoryRefreshIcon="<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M20 7v5h-5M20 12a8 8 0 1 0-2 6\"/></svg>";
const inventorySearchIcon="<svg viewBox=\"0 0 24 24\" width=\"17\" height=\"17\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"><path d=\"M3 15 5 6h4l2 9m2 0 2-9h4l2 9M9 9h6\"/><circle cx=\"7\" cy=\"16\" r=\"4\"/><circle cx=\"17\" cy=\"16\" r=\"4\"/><path d=\"M11 16h2\"/></svg>";
function inventoryAge(stamp){
  if(!stamp)return "—";
  const mins=Math.max(0,Math.floor((Date.now()-stamp)/60000));
  return mins<60?mins+"m":mins<6000?Math.floor(mins/60)+"h":Math.min(99,Math.floor(mins/1440))+"d";
}
function updateInventoryAges(){
  document.querySelectorAll("[data-inventory-age]").forEach(el=>el.textContent=inventoryAge(Number(el.dataset.inventoryAge)));
}
function inventoryFilterBar(){
  const preferred=["All",...tornGuideApi.inventoryTypes];
  const cats=preferred.filter(cat=>cat==="All"||tornGuideApi.inventoryTypes.includes(cat));
  for(const cat of tornGuideApi.inventoryTypes)if(!cats.includes(cat))cats.push(cat);
  return '<nav class="inventory-filterbar" aria-label="Inventory categories">'+cats.map(cat=>'<button type="button" data-inventory-filter="'+safe(cat)+'" title="'+safe(inventoryCategoryLabels[cat]??cat)+'" aria-label="'+safe(inventoryCategoryLabels[cat]??cat)+'" aria-pressed="'+(cat===inventoryFilter)+'">'+(inventoryIcons[cat]??inventoryIcons.Other)+'</button>').join("")+'</nav>';
}
if(typeof document!=="undefined")document.addEventListener("click",event=>{
  const button=event.target.closest?.("[data-inventory-filter]");
  if(!button)return;
  inventoryFilter=button.dataset.inventoryFilter;
  document.querySelectorAll("[data-inventory-filter]").forEach(el=>el.setAttribute("aria-pressed",String(el.dataset.inventoryFilter===inventoryFilter)));
  document.querySelectorAll("[data-inventory-category]").forEach(el=>el.hidden=inventoryFilter!=="All"&&el.dataset.inventoryCategory!==inventoryFilter);
});
let inventoryExpandedOwner=null;
const weav3rBuyers=(()=>{
  const base="https://weav3r.dev";
  const freshness=5*60*1000;
  const storageKey=id=>"torn-city-guide:weav3r-buyers:v1:"+id;
  const results=new Map(), pending=new Map();
  let retryAt=0;

  function normalize(rows){
    return rows.filter(row=>Number.isSafeInteger(row?.player_id)&&row.player_id>0&&
      typeof row.player_name==="string"&&row.player_name.trim()&&
      Number.isSafeInteger(row.price)&&row.price>0)
      .sort((a,b)=>b.price-a.price)
      .filter((row,index,sorted)=>sorted.findIndex(other=>other.player_id===row.player_id)===index)
      .map(({player_id,player_name,price,last_action,last_trade,pricelist_updated,sponsored})=>
        ({player_id,player_name,price,last_action,last_trade,pricelist_updated,sponsored}));
  }

  function read(id){
    if(!results.has(id)){
      let result=null;
      try{
        const cached=JSON.parse(localStorage.getItem(storageKey(id)));
        if(Number.isFinite(cached?.checkedAt)&&cached.checkedAt>0&&cached.checkedAt<=Date.now()&&Array.isArray(cached.traders)){
          result={...cached,traders:normalize(cached.traders)};
        }
      }catch{}
      results.set(id,result);
    }
    return results.get(id);
  }

  async function load(id){
    if(Date.now()<retryAt)throw new Error("Weav3r rate limit. Try again in "+Math.ceil((retryAt-Date.now())/1000)+" seconds.");
    let response;
    try{
      response=await fetch(base+"/api/marketplace/"+id+"/traders?limit=10&sort=price",{
        credentials:"omit",referrerPolicy:"no-referrer",signal:AbortSignal.timeout(10000)
      });
    }catch{
      throw new Error("Can't reach Weav3r. The request may have timed out or been blocked by your browser or network.");
    }
    if(response.status===429){
      const header=response.headers.get("Retry-After"), seconds=Number(header);
      const until=header&&(Number.isFinite(seconds)?Date.now()+seconds*1000:Date.parse(header));
      retryAt=until>Date.now()?until:Date.now()+60000;
      throw new Error("Weav3r rate limit. Try again in "+Math.ceil((retryAt-Date.now())/1000)+" seconds.");
    }
    if(response.status===401||response.status===403)throw new Error("Weav3r denied the public request. Open Weav3r to check buyers.");
    if(!response.ok)throw new Error("Weav3r lookup failed (HTTP "+response.status+").");
    const data=await response.json().catch(()=>null);
    if(data?.item_id!==id||!Array.isArray(data.traders))throw new Error("Weav3r returned an unexpected buyer response.");
    const traders=normalize(data.traders);
    if(data.traders.length&&!traders.length)throw new Error("Weav3r returned an unexpected buyer response.");
    const result={checkedAt:Date.now(),generatedAt:data.generated_at,traders};
    results.set(id,result);
    try{localStorage.setItem(storageKey(id),JSON.stringify(result));}catch{}
    return result;
  }

  function query(id){
    if(!Number.isSafeInteger(id)||id<=0)throw new Error("Item ID unavailable.");
    if(!pending.has(id))pending.set(id,load(id).finally(()=>pending.delete(id)));
    return pending.get(id);
  }

  function stale(result){
    const source=Number.isSafeInteger(result.generatedAt)&&result.generatedAt>0?result.generatedAt*1000:result.checkedAt;
    return Date.now()-Math.min(result.checkedAt,source)>=freshness;
  }

  return {base,query,read,stale,pending:id=>pending.has(id)};
})();

function inventoryMarketplaceUrl(id){
  return weav3rBuyers.base+"/dashboard?tab=marketplace&intent=sell&item="+id;
}

function inventoryBuyerIcon(id){
  const result=id&&weav3rBuyers.read(id);
  if(!result?.traders.length||weav3rBuyers.stale(result))return "";
  return '<a class="inventory-buyer-icon" href="'+safe(inventoryMarketplaceUrl(id))+
    '" target="_blank" rel="noopener noreferrer" aria-label="Open Weav3r buyer listings" title="Pricelist buyers found on last check">$</a>';
}

function inventoryBuyerResults(id,qty){
  const result=weav3rBuyers.read(id);
  if(!result)return "";
  const stamp=safe(tornGuidePreferences.formatDate(result.checkedAt));
  const timing='<p class="fine-print">'+(weav3rBuyers.stale(result)?"Stale result · ":"")+"Last checked "+stamp+"</p>";
  const [best,...more]=result.traders;
  if(!best)return timing+'<p>No active pricelist buyers returned. Check Weav3r for anonymous buy orders.</p>';
  const buyer=row=>{
    const list=weav3rBuyers.base+"/pricelist/"+row.player_id;
    const trade="https://www.torn.com/trade.php#step=start&userID="+row.player_id;
    const activity=[["Last active",row.last_action],["Last trade",row.last_trade],["Pricelist updated",row.pricelist_updated]]
      .filter(([,time])=>Number.isSafeInteger(time)&&time>0)
      .map(([label,time])=>label+" "+safe(tornGuidePreferences.formatDate(time*1000))).join(" · ");
    return '<p><strong>'+safe(row.player_name)+'</strong> · $'+formatNumber(row.price)+' each'+
      (row.sponsored===1?' · Sponsored':'')+'<br><a href="'+list+'" target="_blank" rel="noopener noreferrer">Pricelist</a>'+
      ' · <a href="'+trade+'" target="_blank" rel="noopener noreferrer">Open Torn trade page</a>'+
      (activity?'<br><small>'+activity+'</small>':'')+'</p>';
  };
  const proceeds=qty>0&&Number.isSafeInteger(best.price*qty)?
    '<p>Potential stack proceeds <strong>$'+formatNumber(best.price*qty)+'</strong> if the buyer takes all '+formatNumber(qty)+'.</p>':"";
  return timing+'<p><strong>Highest advertised pricelist price</strong></p>'+buyer(best)+proceeds+
    '<p class="fine-print">Requested quantity is unknown. Confirm capacity and any bulk terms on the trader’s pricelist.</p>'+
    (more.length?'<details data-collapse-key="inventory-more-buyers"><summary>More pricelist buyers ('+more.length+')</summary>'+more.map(buyer).join("")+'</details>':"");
}

const inventoryStatIcons={
  damage:'<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.15" stroke-linejoin="round"><path d="m8 1 1.5 4 3.7-2.1-1.1 4.1 3.2 1-3.2 1.2 1.1 4-3.7-2L8 15l-1.5-3.8-3.7 2 1.1-4L.7 8l3.2-1-1.1-4.1 3.7 2.1Z"/><path d="m6.4 8 1.6-1.6L9.6 8 8 9.6Z"/></svg>',
  accuracy:'<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.15"><circle cx="8" cy="8" r="5"/><circle cx="8" cy="8" r="2"/><path d="M8 0v5m0 6v5M0 8h5m6 0h5"/></svg>',
  armor:'<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.15" stroke-linejoin="round"><path d="M8 1 14 3v4c0 3.7-2.2 6-6 8-3.8-2-6-4.3-6-8V3Z"/><path d="M8 4v7"/></svg>',
  coverage:'<svg viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.15"><circle cx="8" cy="2.8" r="1.8"/><path d="m4 6 4-1 4 1 1 4-3 .5V15H6v-4.5L3 10Z"/></svg>'
};
function inventoryGearTitle(uid,category,name,equipped,info={}){
  const read=tornGuideApi.readGear(uid),gear=read.item;
  const rarity=String(gear?.rarity??"").toLowerCase();
  const ranked=["yellow","orange","red"].includes(rarity);
  const stats=gear?.stats??{};
  const num=v=>typeof v==="number"&&Number.isFinite(v)?v.toFixed(2):null;
  const quality=num(stats.quality),damage=num(stats.damage),accuracy=num(stats.accuracy),armor=num(stats.armor);
  const coverage=info.details?.coverage;
  const values=Array.isArray(coverage)?coverage.map(x=>x?.value):[];
  const coverageText=values.length===1&&typeof values[0]==="number"&&Number.isFinite(values[0])?values[0]+"%":values.length>1&&values.every(v=>typeof v==="number"&&Number.isFinite(v))?values.map(v=>v+"%").join(", "):"—";
  const coverageLabel=Array.isArray(coverage)?coverage.map(x=>x.name+" "+x.value+"%").join(" · "):"Coverage unavailable";
  const field=(label,value,icon)=>value==null?"":'<span class="inventory-title-stat" title="'+safe(label)+'"'+(icon?' aria-label="'+safe(label+": "+value)+'"':"")+'>'+(inventoryStatIcons[icon]??"")+safe(value)+'</span>';
  const bonuses=Array.isArray(gear?.bonuses)?gear.bonuses:[];
  const bonusText=bonuses.map(b=>field(b.description||"Ranked bonus",(typeof b.value==="number"?b.value+"% ":"")+(b.title??b.name??""))).join("");
  const modText=(Array.isArray(read.mods)?read.mods:[]).map(m=>{
    const name=typeof m==="string"?m:m?.name??m?.title;
    return name?'<span class="inventory-title-mod" title="'+safe((typeof m==="object"&&m?.description)||"Attached mod")+'">'+safe(name)+'</span>':"";
  }).filter(Boolean).join('<span class="inventory-title-mod-separator" aria-hidden="true">·</span>');
  return '<span class="inventory-title-content'+(ranked?" rarity-"+rarity:"")+'"><span class="inventory-title-main"><span class="inventory-title-name">'+safe(name)+(equipped?inventoryEquippedIcon:"")+'</span>'+
    field("Quality",quality===null?"—%":quality+"%")+'</span><span class="inventory-title-combat">'+(category==="Defensive"?field("Armor rating",armor??"—","armor")+field("Coverage · "+coverageLabel,coverageText,"coverage"):field("Damage",damage??"—","damage")+field("Accuracy",accuracy??"—","accuracy"))+'</span>'+
    (bonusText||modText?'<span class="inventory-title-secondary">'+bonusText+(modText?'<span class="inventory-title-mods" aria-label="Attached mods">'+modText+'</span>':"")+'</span>':"")+'</span>';
}
function weaponEndurance(min,max,mag,magazines){
  if(![min,max,mag,magazines].every(Number.isSafeInteger)||min<1||max<min||max>500||mag<1||mag>1000||magazines<1||magazines>20)return null;
  const e=[0];for(let r=1;r<=mag;r++){let sum=0;for(let n=min;n<=max;n++)sum+=e[Math.max(0,r-n)];e[r]=1+sum/(max-min+1);}
  return {expected:e[mag],min:Math.ceil(mag/max),max:Math.ceil(mag/min),total:e[mag]*magazines,reloads:magazines-1,efficiency:e[mag]*magazines/(e[mag]*magazines+magazines-1),rounds:mag*magazines};
}
function rwComparableEstimate(gear,rows,uid){
  const key=b=>String(b.title??b.id??"").trim().toLowerCase();
  const bonuses=Array.isArray(gear?.bonuses)?gear.bonuses:[],signature=bs=>bs.map(key).sort().join("|");
  if(!bonuses.length||!bonuses.every(b=>key(b)&&Number.isFinite(b.value)))return null;
  const candidates=rows.filter(r=>r.uid!==uid&&Array.isArray(r.bonuses)&&signature(r.bonuses)===signature(bonuses)&&r.bonuses.every(b=>Number.isFinite(b.value))&&Number.isFinite(r.price)&&r.price>0).map(r=>{
    const distance=bonuses.reduce((s,b)=>s+Math.abs(b.value-r.bonuses.find(x=>key(x)===key(b)).value)/Math.max(1,Math.abs(b.value)),0)/bonuses.length;
    const q=Number.isFinite(gear.stats?.quality)&&Number.isFinite(r.stats?.quality)?Math.abs(gear.stats.quality-r.stats.quality)/100:0;
    const combat=["damage","accuracy","armor"].filter(k=>Number.isFinite(gear.stats?.[k])&&Number.isFinite(r.stats?.[k])).reduce((s,k)=>s+Math.abs(gear.stats[k]-r.stats[k])/100,0);
    return {...r,distance,score:distance*4+q*.5+combat};
  }).sort((a,b)=>a.score-b.score);
  const close=candidates.filter(x=>x.distance<=.2),selected=(close.length>=3?close:candidates).slice(0,12);
  if(selected.length<3)return {count:selected.length,rows:selected,estimate:null};
  const prices=selected.map(x=>x.price).sort((a,b)=>a-b),quantile=q=>prices[Math.floor((prices.length-1)*q)];
  const weighted=selected.map(x=>({...x,w:1/(.1+x.score)})).sort((a,b)=>a.price-b.price);let running=0,half=weighted.reduce((s,x)=>s+x.w,0)/2,median=weighted[0].price;
  for(const x of weighted){running+=x.w;median=x.price;if(running>=half)break;}
  return {count:selected.length,rows:selected,estimate:median,low:quantile(.25),high:quantile(.75),confidence:close.length>=5?"Higher match":close.length>=3?"Moderate match":"Low match"};
}
function inventoryRwDiagnosticsBody(){
  const {rows,bridge,diagnostic:d,archive}=tornGuideApi.passiveRwReport();
  const full=rows.filter(x=>x.complete).length,models=new Map();
  for(const x of rows){const key=x.name,entry=models.get(key)??{name:key,total:0,full:0,yellow:0,orange:0,red:0};entry.total++;if(x.complete)entry.full++;entry[x.rarity]++;models.set(key,entry);}
  const count=(label,value)=>'<div><small>'+safe(label)+'</small><strong>'+safe(value??"—")+'</strong></div>';
  const stamp=v=>v?new Date(v).toLocaleString():"Not recorded";
  const byRarity=["yellow","orange","red"].map(r=>count(r[0].toUpperCase()+r.slice(1),rows.filter(x=>x.rarity===r).length)).join("");
  const scan=d?'<p class="fine-print">Last scan: '+safe(d.category)+' · '+safe(d.rarity??"unfiltered")+' · '+safe(stamp(d.at))+'</p><div class="rw-diagnostic-counts">'+count("Buy buttons",d.buttons)+count("Rendered",d.rendered)+count("Matched cards",d.matched)+count("Ranked",d.ranked)+count("Accepted",d.accepted)+count("Full details",d.complete)+count("Duplicates",d.duplicates)+count("New records",d.added)+(d.mode==="incremental"?count("Processed cards",d.processed)+count("Pending cards",d.queued)+count("Batches",d.batches)+count("Longest batch",d.maxBatchMs==null?null:d.maxBatchMs+" ms")+count("Queue overflow",d.dropped)+count("Transition skips",d.transitionSkipped)+count("Expanded panels",d.panels)+count("Enriched in batch",d.enriched)+count("Archive growth",d.persistedAdded):"")+'</div>':'<p class="fine-print">No scan diagnostics received. Install companion 2.5.0 and focus an equipment market page.</p>';
  return '<div class="rw-diagnostic-actions"><span role="status">'+safe(bridge?"Companion "+bridge.version+" connected · "+stamp(bridge.at):"No live companion handshake yet")+'</span><button type="button" class="button secondary" data-rw-sync>Sync local data</button><button type="button" class="button secondary" data-rw-export>Export JSON</button></div>'+
    '<div class="rw-diagnostic-counts">'+count("Stored observations",rows.length)+count("Complete",full)+count("Partial",rows.length-full)+count("Models",models.size)+count("Fresh ≤24h",rows.filter(x=>Date.now()-x.at<=86400000).length)+count("Older observations",rows.filter(x=>Date.now()-x.at>86400000).length)+count("Conflicting rarity groups",archive.conflictingGroups)+byRarity+'</div>'+
    '<p class="fine-print">Last successful capture: '+safe(stamp(d?.lastCapture??(rows.length?Math.max(...rows.map(r=>r.at)):null)))+'</p>'+scan+
    (models.size?'<div class="rw-diagnostic-table"><table><thead><tr><th>Equipment</th><th>All</th><th>Full</th><th>Yellow</th><th>Orange</th><th>Red</th></tr></thead><tbody>'+Array.from(models.values()).sort((a,b)=>b.total-a.total||a.name.localeCompare(b.name)).map(x=>'<tr><td>'+safe(x.name)+'</td>'+["total","full","yellow","orange","red"].map(k=>'<td>'+x[k]+'</td>').join("")+'</tr>').join("")+'</tbody></table></div>':"")+
    '<p class="fine-print">Archive shards: '+safe(archive.loaded)+' / '+safe(archive.expected??"—")+(archive.error?' · '+safe(archive.error):"")+'. Local asking-price observations: 24h valuation freshness, 30-day partial and 90-day complete retention, up to 102,400 records across 128 shards (800 each). Older observations are not confirmed sales. No Torn API requests.</p>';
}
function inventoryRwDiagnostics(){
  return '<details class="rw-diagnostic-panel" data-collapse-key="inventory-rw-diagnostics"><summary>Passive RW market diagnostics</summary><div data-rw-diagnostics>'+inventoryRwDiagnosticsBody()+'</div></details>';
}
function refreshRwDiagnostics(){
  for(const el of document.querySelectorAll("[data-rw-diagnostics]"))el.innerHTML=inventoryRwDiagnosticsBody();
}
if(typeof document!=="undefined")document.addEventListener("click",event=>{
  if(event.target.closest?.("[data-rw-sync]"))window.dispatchEvent(new Event("torn-guide-request-snapshot"));
  if(!event.target.closest?.("[data-rw-export]"))return;
  const report=tornGuideApi.passiveRwReport(),url=URL.createObjectURL(new Blob([JSON.stringify(report,null,2)],{type:"application/json"}));
  const link=document.createElement("a");link.href=url;link.download="torn-rw-observations-"+new Date().toISOString().slice(0,10)+".json";document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
function inventoryRwMarket(uid,id){
  const gear=tornGuideApi.readGear(uid).item,rarity=gear?.rarity;
  if(!id||!["yellow","orange","red"].includes(rarity))return "";
  const passive=tornGuideApi.readPassiveRwMarket(id,rarity),api=tornGuideApi.readRwMarket(id,rarity);
  const passiveModel=passive?rwComparableEstimate(gear,passive.rows,uid):null;
  const data=passiveModel?.estimate!=null&&Date.now()-passive.at<24*60*60*1000?passive:api??passive;
  const model=data===passive?passiveModel:data?rwComparableEstimate(gear,data.rows,uid):null;
  const money=n=>"$"+formatNumber(n);
  const catalog=payload("itemCatalog","items");
  const name=gear.name??(Array.isArray(catalog)?catalog.find(item=>Number(item.id)===id)?.name:catalog?.[id]?.name)??"Item #"+id;
  const stat=value=>typeof value==="number"&&Number.isFinite(value)?formatNumber(value):"—";
  const listing=r=>{
    const quality=stat(r.stats?.quality);
    const armor=Number.isFinite(r.stats?.armor);
    const combat=armor?stat(r.stats.armor):stat(r.stats?.damage)+"/"+stat(r.stats?.accuracy);
    const effects=r.bonuses.map(b=>'<span>'+safe(b.title??b.id)+' '+safe(stat(b.value))+'%</span>').join(" · ");
    return '<p class="inventory-rw-comparable"><strong class="inventory-title-content rarity-'+rarity+'">'+safe(name)+'</strong> '+
      '<span title="Quality">'+safe(quality==="—"?quality:quality+"%")+'</span> <span title="'+(armor?"Armor rating":"Damage / Accuracy")+'">'+safe(combat)+'</span> '+
      effects+' <strong>'+safe(money(r.price))+'</strong></p>';
  };
  return '<section class="inventory-rw-market"><h4>RW comparable asking prices</h4><button type="button" class="button secondary" data-rw-query>'+ (data?"Query API comparables":"Check RW value")+'</button>'+
    (data?'<p class="fine-print">Checked '+safe(tornGuidePreferences.formatDate(data.at))+(data.source==="passive"?" · passive observations, not a complete market scan":data.truncated?" · first 500 listings only":"")+'</p>':"")+
    (passive?'<p class="fine-print">Passive market: '+passive.observations+' observations · '+passive.rows.length+' full-detail records</p>':"")+
    (model?.estimate!=null?'<p><strong>'+safe(money(model.estimate))+'</strong> · '+safe(model.confidence)+' · '+model.count+' matches</p><p>Middle asking-price range: '+safe(money(model.low))+' – '+safe(money(model.high))+'</p>':data?'<p>Insufficient exact bonus matches ('+(model?.count??0)+'). No estimated RW value.</p>':"")+
    (model?.rows.length?'<details data-collapse-key="inventory-comparable-listings"><summary>Comparable listings</summary>'+model.rows.map(listing).join("")+'</details>':"")+
    '<small>Active asking prices, not completed sales. Generic MV remains separate.</small><p class="inventory-rw-status" role="status"></p></section>';
}
if(typeof document!=="undefined")document.addEventListener("click",async event=>{
  const button=event.target.closest?.("[data-rw-query]");if(!button)return;
  const row=button.closest(".inventory-detail-row"),uid=row.dataset.gearUid,id=Number(row.dataset.buyerItem),gear=tornGuideApi.readGear(uid).item;
  if(!gear)return;button.disabled=true;
  try{await tornGuideApi.loadRwMarket(id,gear.rarity,true);
    for(const target of document.querySelectorAll("[data-gear-uid]")){
      const section=target.querySelector(".inventory-rw-slot");if(section&&Number(target.dataset.buyerItem)===id)section.innerHTML=inventoryRwMarket(target.dataset.gearUid,id);
    }
  }catch(e){if(row.isConnected)row.querySelector(".inventory-rw-status").textContent=e.message;}
  finally{if(button.isConnected)button.disabled=false;}
});
function inventoryGearMarkup(uid,category,info,equipped){
  const weapon=["Primary","Secondary","Melee"].includes(category),armor=category==="Defensive";
  if(!weapon&&!armor)return "";
  const meta=info.details??{},ammo=meta.ammo,rate=ammo?.rate_of_fire;
  const pair=(label,value,wide=false,tip="")=>'<div class="inventory-gear-pair'+(wide?' inventory-gear-wide':'')+'"'+(tip?' title="'+safe(tip)+'"':'')+'><dt>'+safe(label)+'</dt><dd>'+safe(value??"—")+'</dd></div>';
  const num=(value,suffix="")=>typeof value==="number"&&Number.isFinite(value)?value.toLocaleString(undefined,{maximumFractionDigits:2})+suffix:null;
  const read=tornGuideApi.readGear(uid),unique=read.item;
  const bonuses=Array.isArray(unique?.bonuses)?unique.bonuses:[];
  const modNames=(Array.isArray(read.mods)?read.mods:[]).map(m=>String(typeof m==="string"?m:m?.name??m?.title??"").trim().toLowerCase());
  const specialist=bonuses.some(b=>String(b.title??b.name).toLowerCase()==="specialist");
  const extra=modNames.some(n=>/^extra (?:mags|magazines|clips) x2$/.test(n))?2:modNames.some(n=>/^extra (?:mag|magazine|clip)$/.test(n))?1:0;
  const perks=payload("perks","perks");
  const jobPerks=perks?.job??perks?.job_perks;
  const bandolier=Array.isArray(jobPerks)&&jobPerks.some(p=>{
    const t=typeof p==="string"?p:[p?.name,p?.effect,p?.description].filter(Boolean).join(" ");
    return /\bbandolier\b|\b(?:one|1|\+1|an) extra (?:clip|magazine)\b|\+1\s+(?:clip|magazine)\b/i.test(t);
  });
  const mags=specialist?1:3+extra+(bandolier?1:0);
  const reloadDelta=mags-3;
  const magBase=ammo?.magazine_rounds;
  const extended=modNames.includes("high capacity mags")?.3:modNames.includes("extended mags")?.2:0;
  const dual=/\bdual\b/i.test(String(info.name??unique?.name??""));
  const mag=Number.isSafeInteger(magBase)?Math.floor(magBase*(1+extended*(dual?.5:1))):null;
  const endurance=weaponEndurance(rate?.minimum,rate?.maximum,mag,mags);
  const type=String(read.ammo?.type??"").toLowerCase().replace(/[_-]/g," ");
  const specialAmmo=/tracer/.test(type)?"Tracer":/hollow\s*point/.test(type)?"Hollow Point":/piercing/.test(type)?"Piercing":/incendiary/.test(type)?"Incendiary":"";
  const caliber=ammo?.name??read.ammo?.name;
  const ammoLabel=caliber?[caliber,specialAmmo].filter(Boolean).join(" · "):specialAmmo||null;
  const formatDelta=n=>n>0?" +"+n:n<0?" −"+Math.abs(n):"";
  const className=unique?.sub_type??info.sub_type??meta.category;
  let rows=pair("Class",className,!weapon);
  if(weapon)rows+=pair("Stealth",num(meta.stealth_level));
  if(weapon&&ammo){
    rows+=pair("Ammo",ammoLabel,true)+
      pair("Magazine rounds",num(mag),false,extended?"Includes known magazine-size mod.":"")+
      pair("Rate of fire",rate?.minimum!=null&&rate?.maximum!=null?rate.minimum+"–"+rate.maximum:null);
    if(endurance)rows+=pair("Attacks / mag",endurance.min+"–"+endurance.max,false,"Range at full magazine using base rate of fire.")+
      pair("Avg Attacks",endurance.total.toFixed(2),false,"Expected firing attacks across all magazines; excludes reload turns and unmodeled ammo conservation.")+
      pair("Reloads","2"+formatDelta(reloadDelta),false,"Base reloads plus known magazine adjustments: "+(specialist?"Specialist":([extra?extra+" extra mod magazine(s)":"",bandolier?"Bandolier":" integral base magazines"].filter(Boolean).join("; "))))+
      pair("Efficiency",(endurance.efficiency*100).toFixed(1)+"%",false,"Expected firing turns divided by firing plus reload turns; excludes unmodeled ammo conservation.");
  }
  return '<section class="inventory-gear"><h4>Equipment attributes</h4><dl class="inventory-gear-grid">'+rows+'</dl>'+
    (!unique?'<p class="fine-print">Individual attributes not loaded.</p>':"")+
    (!uid?'<p class="fine-print">Unique item ID unavailable.</p>':"")+'<p role="status" class="inventory-gear-status"></p></section>';
}
if(typeof document!=="undefined")document.addEventListener("click",async event=>{
  const button=event.target.closest?.("[data-load-gear]");if(!button)return;
  const row=button.closest(".inventory-detail-row"),uid=row.dataset.gearUid,category=row.dataset.gearCategory,owner=tornGuideApi.state.identity?.id;
  if(!uid)return;
  button.disabled=true;button.setAttribute("aria-busy","true");
  try{
    inventorySelectTab(row,"details");
    const result=await tornGuideApi.loadGear(uid,row.dataset.gearEquipped==="true",["Primary","Secondary","Melee"].includes(category),true);
    if(tornGuideApi.state.identity?.id!==owner)return;
    for(const target of document.querySelectorAll("[data-gear-uid]")){
      const panel=target.querySelector(".inventory-gear");if(!panel)continue;
      const raw=payload("itemCatalog","items"),catalog=Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
      const info=catalog.find(x=>String(x.id)===target.dataset.buyerItem)??{};
      panel.outerHTML=inventoryGearMarkup(target.dataset.gearUid,target.dataset.gearCategory,info,target.dataset.gearEquipped==="true");
      const rw=target.querySelector(".inventory-rw-slot");if(rw)rw.innerHTML=inventoryRwMarket(target.dataset.gearUid,Number(target.dataset.buyerItem));
      const title=target.querySelector(".inventory-row-title");
      if(title)title.innerHTML=inventoryGearTitle(target.dataset.gearUid,target.dataset.gearCategory,title.dataset.titleName,title.dataset.titleEquipped==="true",info);
      if(target.dataset.gearUid===uid)target.querySelector(".inventory-gear-status").textContent=result.errors.join(" · ");
    }
  }catch(error){if(row.isConnected)row.querySelector(".inventory-gear-status").textContent=error.message;}
  finally{if(button.isConnected){button.disabled=false;button.removeAttribute("aria-busy");}}
});

function inventoryDetailRow(item,category,index){
  const owner=tornGuideApi.state.identity?.id??null;
  if(owner!==inventoryExpandedOwner){inventoryExpanded.clear();inventoryTabs.clear();inventoryExpandedOwner=owner;}
  const raw=payload("itemCatalog","items");
  const catalog=Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
  const name=String(item.name??item.item?.name??"Unknown item");
  const numericId=v=>/^\d+$/.test(String(v??""))&&Number.isSafeInteger(Number(v))&&Number(v)>0?Number(v):null;
  const supplied=numericId(item.item_id??item.item?.id??item.id);
  const exact=catalog.filter(x=>String(x.name??"").trim().toLowerCase()===name.trim().toLowerCase());
  const record=exact.find(x=>numericId(x.id)===supplied)??(exact.length===1?exact[0]:null);
  const id=numericId(record?.id)??(!catalog.length?numericId(item.item_id??item.item?.id):null);
  const rowKey=category+":"+String(id??name)+":"+String(item.uid??item.unique_id??index);
  const info=record??item.item??item;
  const description=typeof info.description==="string"&&info.description.trim()?info.description:"Description unavailable in cached item data.";
  const effectText=value=>{
    if(typeof value==="string")return value.trim();
    if(Array.isArray(value))return value.map(effectText).filter(Boolean).join(" · ");
    if(value&&typeof value==="object")return Object.entries(value).map(([k,v])=>{const t=typeof v==="number"||typeof v==="boolean"?String(v):effectText(v);return t?k.replace(/_/g," ")+": "+t:"";}).filter(Boolean).join(" · ");
    return "";
  };
  const effects=effectText(info.effect??info.effects??item.effect??item.effects);
  const price=info.market_value??info.value?.market_price??info.value?.market_value??info.market_price;
  const qty=Number(item.amount??item.quantity);
  const validPrice=price!=null&&Number.isFinite(Number(price))&&Number(price)>0;
  const url=id?inventoryMarketplaceUrl(id):"";
  const uid=tornGuideApi.gearUid(item.uid??item.unique_id);
  const gear=["Primary","Secondary","Melee","Defensive"].includes(category);
  const tab=inventoryTabs.get(rowKey)??"details";
  const tabbar='<div class="inventory-item-tabs" role="group" aria-label="Item information">'+["details","market"].map(t=>'<button type="button" data-inventory-tab="'+t+'" aria-pressed="'+(tab===t)+'">'+(t==="details"?"Details":"Market")+'</button>').join("")+(gear&&uid?'<button type="button" class="inventory-gear-refresh inventory-refresh-icon" data-load-gear aria-label="Refresh equipment details" title="Refresh equipment / mods / ammo">'+inventoryRefreshIcon+'</button>':"")+'</div>';
  return '<li class="inventory-detail-row" '+(gear?'data-gear-uid="'+safe(uid??"")+'" data-gear-category="'+safe(category)+'" data-gear-equipped="'+Boolean(item.equipped)+'" ':"")+'data-buyer-item="'+(id??"")+'" data-buyer-qty="'+(Number.isSafeInteger(qty)&&qty>0?qty:0)+'"><details data-inventory-detail="'+safe(rowKey)+'" '+(inventoryExpanded.has(rowKey)?"open":"")+'><summary><span class="inventory-row-title" data-title-name="'+safe(name)+'" data-title-equipped="'+Boolean(item.equipped)+'">'+(gear?inventoryGearTitle(uid,category,name,item.equipped,info):safe(name)+(item.equipped?inventoryEquippedIcon:""))+'</span><span class="inventory-buyer-badge">'+inventoryBuyerIcon(id)+'</span>'+(id?'<button type="button" class="inventory-inline-search" data-query-buyers aria-label="Query Weav3r buyers for '+safe(name)+'" title="Query Weav3r buyers" '+(weav3rBuyers.pending(id)?'disabled aria-busy="true"':'')+'>'+inventorySearchIcon+'</button>':'')+'<strong>×'+safe(formatNumber(item.amount??item.quantity))+'</strong></summary><div class="inventory-detail-body">'+tabbar+'<div data-inventory-tab-panel="details" '+(tab!=="details"?"hidden":"")+'><p>'+safe(description)+'</p>'+inventoryGearMarkup(uid,category,info,item.equipped)+(effects?'<section class="inventory-item-effects"><h4>Effects</h4><p>'+safe(effects)+'</p></section>':"")+'</div><div data-inventory-tab-panel="market" '+(tab!=="market"?"hidden":"")+'><div class="inventory-market-summary">'+(url?'<a class="inventory-weav3r-icon" href="'+safe(url)+'" target="_blank" rel="noopener noreferrer" aria-label="Open Weav3r marketplace" title="Open Weav3r marketplace"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m2 6 5 12 5-8 5 8 5-12M7 6l5 7 5-7"/></svg></a>':'')+'<span title="Market value per item">MV: '+(validPrice?'$'+safe(formatNumber(Number(price))):'Unavailable')+'</span><span class="inventory-market-qty">× '+(Number.isFinite(qty)&&qty>=0?safe(formatNumber(qty)):'—')+'</span><strong class="inventory-market-gross" title="Estimated gross stack value">'+(validPrice&&Number.isFinite(qty)&&qty>=0?'$'+safe(formatNumber(Number(price)*qty)):'—')+'</strong></div>'+(info.circulation!=null&&Number.isFinite(Number(info.circulation))?'<p class="fine-print">Circulation: '+safe(formatNumber(Number(info.circulation)))+'</p>':'')+(item.equipped?'<p class="fine-print">Equipped item: verify what you can spare before trading.</p>':'')+
    (gear&&id?'<div class="inventory-rw-slot">'+inventoryRwMarket(uid,id)+'</div>':"")+
    (id?'<p class="inventory-buyer-status" role="status"></p><div class="inventory-buyer-results">'+inventoryBuyerResults(id,qty)+'</div>':"")+
    '</div></div></details></li>';
}
if(typeof document!=="undefined")document.addEventListener("toggle",event=>{
  const el=event.target,key=el.dataset?.inventoryDetail;
  if(!key||!el.isConnected)return;
  if(!el.open){inventoryExpanded.delete(key);return;}
  inventoryExpanded.add(key);
  const row=el.closest("[data-buyer-item]");
  const id=Number(row.dataset.buyerItem);
  const result=id&&weav3rBuyers.read(id);
  if(result&&weav3rBuyers.stale(result)){
    row.querySelector(".inventory-buyer-badge").textContent="";
    row.querySelector(".inventory-buyer-results").innerHTML=inventoryBuyerResults(id,Number(row.dataset.buyerQty));
  }
},true);

if(typeof document!=="undefined")document.addEventListener("click",async event=>{
  const button=event.target.closest?.("[data-query-buyers]");
  if(!button)return;
  event.preventDefault();
  const row=button.closest("[data-buyer-item]");
  row.querySelector("[data-inventory-detail]").open=true;
  inventorySelectTab(row,"market");
  const id=Number(row.dataset.buyerItem);
  if(!id||weav3rBuyers.pending(id))return;
  const rows=()=>document.querySelectorAll('[data-buyer-item="'+id+'"]');
  const setStatus=(message,busy)=>{
    for(const item of rows()){
      const control=item.querySelector("[data-query-buyers]");
      control.disabled=busy;
      control.setAttribute("aria-busy",String(busy));
      control.title=busy?"Checking buyers…":"Query Weav3r buyers";
      item.querySelector(".inventory-buyer-status").textContent=message;
    }
  };
  setStatus("Checking active pricelists…",true);
  let message="Pricelist check complete.";
  try{await weav3rBuyers.query(id);}
  catch(error){message=error.message;}
  for(const item of rows()){
    item.querySelector(".inventory-buyer-badge").innerHTML=inventoryBuyerIcon(id);
    item.querySelector(".inventory-buyer-results").innerHTML=inventoryBuyerResults(id,Number(item.dataset.buyerQty));
  }
  setStatus(message,false);
});

function renderInventoryPage(){
  let out=inventoryFilterBar()+'<h1 id="topic-title" tabindex="-1" class="sr-only">Inventory</h1>'+inventoryRwDiagnostics();
  if(!tornGuideApi.isConnected())return out+'<section class="panel"><div class="panel-content">Connect your account to load inventory.</div></section>';
  const st=tornGuideApi.state;
  out+='<div class="inventory-grid">';
  for(const cat of tornGuideApi.inventoryTypes){
    const items=st.inventory[cat],stamp=Number(st.fetchedAt["inventory:"+cat])||0;
    const error=st.inventoryErrors[cat];
    out+='<section class="inventory-panel" data-inventory-category="'+safe(cat)+'" '+(inventoryFilter!=="All"&&inventoryFilter!==cat?'hidden':'')+'><div class="inventory-tile-head"><h3>'+safe(cat)+(items?' ('+items.length+')':'')+'</h3><span class="inventory-age" data-inventory-age="'+stamp+'" title="'+(stamp?'Updated '+safe(tornGuidePreferences.formatDate(stamp)):'Not loaded')+'">'+inventoryAge(stamp)+'</span><button type="button" class="inventory-refresh-icon" data-inventory-load="'+safe(cat)+'" aria-label="'+(items?'Refresh ':'Load ')+safe(cat)+'" title="'+(items?'Refresh category':'Load category')+'">'+inventoryRefreshIcon+'</button></div>';
    if(error)out+='<p class="api-error">'+safe(error)+'</p>';
    if(!items)out+='<p>Not requested yet.</p>';
    else if(!items.length)out+='<p>Nothing held.</p>';
    else out+='<ul class="item-list inventory-detail-list">'+items.map((item,index)=>inventoryDetailRow(item,cat,index)).join("")+'</ul>';
    out+='</section>';
  }
  return out+'</div>';
}

const educationView={open:new Set(),selected:null,filter:"all",groupBy:"category",effect:"all",owner:null};
function loadEducationPreference(){const id=String(tornGuideApi.state.identity?.id??"guest");if(educationView.owner===id)return;educationView.owner=id;educationView.groupBy="category";educationView.effect="all";educationView.selected=typeof tornDisclosureState!=="undefined"?tornDisclosureState.get(tornDisclosureState.ownKey("edu-course"),"")||null:null;educationView.open.clear();try{const p=JSON.parse(localStorage.getItem("torn-city-guide:edu-path:"+id));if(p?.groupBy==="effect")educationView.groupBy="effect";if(educationPaths.some(([name])=>name===p?.effect))educationView.effect=p.effect;}catch{}}
function saveEducationPreference(){try{localStorage.setItem("torn-city-guide:edu-path:"+educationView.owner,JSON.stringify({groupBy:educationView.groupBy,effect:educationView.effect}));}catch{}}
// Effect paths are editorial groupings, not official degree requirements.
// A course may contribute to more than one path.
const educationPaths=[
 ["Gym Perks","SPT1430 SPT2440 SPT2450 SPT2460 SPT2470 SPT3510",/gym gains|gym training/i],
 ["Passive Battle Stats","CBT1780 CBT2790 HAF1103 HAF2104 HAF2105 HAF2106 HAF2107 HAF2108 HAF2109 MTH1220 MTH2240 MTH2250 MTH2260 MTH2320 PSY1630 PSY2640 PSY2650 PSY2660 PSY2670 DEF1700 DEF2710 DEF2730 DEF2740 DEF2750 DEF2760 SPT1430 SPT2490 SPT2500",/passive (?:battle|strength|speed|defen[cs]e|dexterity)|passive.*(?:strength|speed|defen[cs]e|dexterity)/i],
 ["Company Perks","BUS1100 BUS2200 BUS2300 BUS2400 BUS2500 BUS2600 BUS2700 BUS2800 BUS2900 BUS2100 BUS2110 BUS2120 BUS3130 MTH1220 MTH2280 LAW1880 LAW2100",/company productivity|employee effectiveness|employee working|advertising effectiveness|product value|company size/i],
 ["City Find Perks","HIS1140 HIS2150 HIS2180 HIS2190 HIS2200 PSY1630 PSY2680",/awareness|(?:coin|sculpture|quran|senet|amulet).*find/i],
 ["Crime Perks","CMT1520 CMT2230 CMT2130 CMT2131 CMT2540 CMT2610 CMT2570 CMT2128 CMT2129 GEN1112 GEN2113 PSY1630 PSY2132 PSY3690",/crime|cracking|bootlegging|scamming|rig heat|overclock/i],
 ["Attacking Perks","BIO1340 BIO2350 BIO2380 BIO2400 BIO2410 CBT1780 CBT2820 CBT2830 CBT2840 CBT2850 CBT2860 CBT2125 CBT3870 GEN1112 GEN2116 GEN2119 HAF1103 HAF3111 HIS1140 HIS2160 HIS2170 MTH1220 MTH2310 MTH3330 DEF1700 DEF2720 DEF3770",/weapon damage|weapon accuracy|weapon experience|critical hit|stealth|ammo conservation|melee damage|blade damage|kick attacks|fist-only|throat-hit|opponent escape/i],
 ["Jail Perks","LAW1880 LAW2890 LAW2900 LAW2920 LAW2930 LAW2970 LAW2980 LAW2990 LAW3102",/jail|bail|busting/i],
 ["Virus Perks","CMT1520 CMT2530 CMT2560 CMT2580 CMT2600",/virus coding/i],
 ["Medical Perks","BIO1340 BIO2360 BIO2370 BIO2127 BIO3420 SPT1430 SPT2480",/medical item|blood withdrawal|transfusion|needle effectiveness|temporary-slot needles/i],
 ["Other Perks","",null]
];
function educationCode(c){
 return /study of pistols/i.test(c.name??c.title??"")?"CBT2840":String(c.code??c.course_code??"").replace(/\s/g,"").toUpperCase();
}
function educationEffectText(c){
 const b=c.effects??c.benefits??c.learning_outcomes??c.outcomes??c.effect??c.results?.perks??c.results?.ability;
 const values=typeof b==="string"?[b]:Array.isArray(b)?b:Object.values(b||{});
 const effects=values.map(v=>typeof v==="string"?v:v?.description??v?.name??v?.effect??"").filter(Boolean);
 return (effects.length?effects:(tornEducationReference[educationCode(c)]?.effects||[])).join(" · ");
}
function educationGroups(m){
 if(educationView.groupBy==="category")return m.groups;
 const grouped=educationPaths.slice(0,-1).map(([name,codes,pattern])=>{
   const set=new Set(codes.split(" "));
   return {name,courses:m.courses.filter(c=>set.has(educationCode(c))||pattern.test(educationEffectText(c)))};
 });
 const assigned=new Set(grouped.flatMap(g=>g.courses.map(educationCode)));
 grouped.push({name:"Other Perks",courses:m.courses.filter(c=>!assigned.has(educationCode(c)))});
 return grouped.filter(g=>educationView.effect==="all"||g.name===educationView.effect);
}
function educationModel(){
 const root=tornGuideApi.state.data.education, data=payload("education","education"), catalog=payload("educationCatalog","education");
 const groups=(Array.isArray(catalog)?catalog:Object.values(catalog||{})).filter(g=>g&&g.courses);
 const list=g=>(Array.isArray(g.courses)?g.courses:Object.entries(g.courses||{}).map(([key,c])=>({...c,id:c.id??c.course_id??key}))).map(c=>({...c,id:c.id??c.course_id??c.code}));
 const courses=groups.flatMap(list), current=data?.current??data?.course??root?.education_current;
 const id=typeof current==="object"?current?.id??current?.course_id:current;
 const completed=data?.complete??data?.completed??data?.completed_courses??data?.education_completed??root?.education_completed??root?.completed??root?.completed_courses;
 const known=completed!=null&&typeof completed==="object";
 const ids=new Set(known?Object.values(completed).map(x=>String(typeof x==="object"?x.id??x.course_id:x)):[]);
 const active=courses.find(c=>String(c.id)===String(id));
 const deadline=tornTctClock.entries().find(e=>e.id==="education")?.at;
 const perks=meritLevel("Education Length"), positions=heldWsuShares();
 return {groups,list,courses,current,id,known,ids,active,deadline,perks,positions};
}
function educationReduction(m){
 const p=payload("perks","perks");
 const job=p?.job??p?.job_perks;
 const entries=Array.isArray(job)?job:[];
 const principal=Array.isArray(job)?entries.some(x=>/education|course/i.test(typeof x==="string"?x:x?.description??x?.effect??x?.name??"")&&/10\s*%/.test(typeof x==="string"?x:x?.description??x?.effect??x?.name??"")):null;
 const parts=[["Merits",m.perks==null?null:Math.min(20,Math.max(0,Number(m.perks)*2))],["WSU stock",m.positions==null?null:m.positions>=1000000?10:0],["Principal career perk",principal===null?null:principal?10:0]];
 const known=parts.filter(([,v])=>v!==null&&Number.isFinite(v));
 const total=known.reduce((a,[,v])=>a+v,0);
 return {total,complete:known.length===parts.length,label:known.length?total+"%"+(known.length<parts.length?" (partial)":""):"Unavailable",tooltip:parts.map(([name,v])=>name+": "+(v===null?"Not loaded":v+"%")).join("\n")};
}
function educationDuration(seconds){
 if(seconds==null||!Number.isFinite(Number(seconds)))return "Unavailable";
 const m=Math.round(Number(seconds)/60);return Math.floor(m/1440)+"d "+Math.floor(m%1440/60)+"h "+m%60+"m";
}
function educationCourseDetail(c,m){
 const code=String(c.code??c.course_code??"").replace(/\s/g,"").toUpperCase();
 // The wiki repeats the rifle code for pistols; match the course title explicitly.
 const wikiKey=/study of pistols/i.test(c.name??c.title??"")?"CBT2840":code;
 const fallback=tornEducationReference[wikiKey]||{};
 const numeric=v=>v!=null&&v!==""&&Number.isFinite(Number(v));
 const apiWork=c.working_stats??c.work_stats??c.workingstats??c.stats??c.gains??c.results;
 const apiDuration=c.duration??c.length??c.time;
 const apiBenefit=c.effects??c.benefits??c.learning_outcomes??c.outcomes??c.effect??c.results?.perks??c.results?.ability;
 const apiCost=c.cost??c.price??c.money_cost;
 const workIsUsable=apiWork&&typeof apiWork==="object"&&Object.entries(apiWork).some(([k,v])=>/^(manual_labor|manual|intelligence|endurance|man|int|end)$/i.test(k)&&numeric(typeof v==="object"?v?.value??v?.amount:v));
 const durationValue=typeof apiDuration==="object"?apiDuration?.seconds??apiDuration?.base:apiDuration;
 const effectIsUsable=typeof apiBenefit==="string"?Boolean(apiBenefit.trim()):Array.isArray(apiBenefit)?apiBenefit.length>0:apiBenefit&&typeof apiBenefit==="object"&&Object.keys(apiBenefit).length>0;
 const fromWiki=Boolean(fallback.source&&(!workIsUsable||!numeric(durationValue)||!effectIsUsable||!numeric(apiCost)));

 const values=v=>Array.isArray(v)?v:Object.values(v||{});
 const text=v=>typeof v==="string"?v:v?.description??v?.name??v?.effect??"";
 const benefit=effectIsUsable?apiBenefit:fallback.effects;
 const effects=typeof benefit==="string"?[benefit]:values(benefit).map(text).filter(Boolean);
 const work=workIsUsable?apiWork:fallback.working_stats;
 const workLabels={manual_labor:"Manual labor",manual:"Manual labor",man:"Manual labor",intelligence:"Intelligence",int:"Intelligence",endurance:"Endurance",end:"Endurance"};
 const gains=work&&typeof work==="object"?Object.entries(work).map(([k,v])=>[workLabels[k]||k,typeof v==="object"?v?.value??v?.amount:v]).filter(([,v])=>Number.isFinite(Number(v))&&Number(v)>0):[];
 const rawDuration=numeric(durationValue)?durationValue:fallback.duration;
 const duration=typeof rawDuration==="object"?rawDuration?.seconds??rawDuration?.base:rawDuration;
 const cost=numeric(apiCost)?apiCost:fallback.cost;
 const req=c.prerequisites??c.requirements;
 const prerequisites=values(req).map(v=>{const id=typeof v==="object"?v.id??v.course_id:v;return m.courses.find(x=>String(x.id)===String(id))?.name??text(v)??String(id);}).filter(Boolean);
 const reduction=educationReduction(m);
 const effective=numeric(duration)&&reduction.complete?Number(duration)*(1-reduction.total/100):null;
 const pair=(label,value)=>'<span class="edu-inline-pair">'+safe(label)+' <strong>'+safe(value)+'</strong></span>';
 const gainMap=new Map(gains);
 const statValue=label=>gainMap.has(label)?"+"+formatNumber(gainMap.get(label)):workIsUsable||fallback.working_stats?"+0":"—";
 return '<div class="edu-course-detail">'+(c.description?'<p>'+safe(c.description)+'</p>':'')+
 '<div class="edu-inline-row">'+pair("Base length",educationDuration(duration))+pair("Effective length",educationDuration(effective))+pair("Cost",cost!=null?"$"+formatNumber(cost):"Unavailable")+'</div>'+
 '<div class="edu-inline-row">'+["Manual labor","Intelligence","Endurance"].map(label=>pair(label,statValue(label))).join("")+'</div>'+
 (prerequisites.length?'<p class="edu-prerequisites">Prerequisites: '+safe(prerequisites.join(", "))+'</p>':'')+'</div>';
}
function renderEducationPage(){
 loadEducationPreference();
 const m=educationModel(),reduction=educationReduction(m),name=m.current?.name??m.active?.name??(m.id!=null?"Course #"+m.id:"None active / not loaded");
 const courseTooltip=m.active?(educationEffectText(m.active)||"No additional course perks listed."):"Course perks unavailable.";
 let out='<section class="panel edu-panel"><div class="panel-heading edu-compact-heading"><div class="edu-heading-status"><h2>Education:</h2><strong class="edu-active-course" tabindex="0" title="'+safe(courseTooltip)+'">'+safe(name)+'</strong><span class="edu-reduction" tabindex="0" title="'+safe(reduction.tooltip)+'">'+safe(reduction.label==="Unavailable"?"—":"-"+reduction.label)+'</span>'+(m.deadline?'<span class="edu-time-left" tabindex="0" title="'+safe(reduction.tooltip)+'" data-edu-deadline="'+m.deadline+'">'+tornTctClock.formatDuration((m.deadline-Date.now())/1000)+'</span>':'')+'</div><span class="edu-completion-count">'+(m.known?m.ids.size:"—")+' / '+m.courses.length+'</span></div><div class="panel-content">'+
 '<div class="edu-filters"><a class="edu-wiki-link" href="https://wiki.torn.com/wiki/Education" target="_blank" rel="noopener noreferrer">Wiki</a><label>Group by <select data-edu-groupby><option value="category" '+(educationView.groupBy==="category"?"selected":"")+'>Education category</option><option value="effect" '+(educationView.groupBy==="effect"?"selected":"")+'>Effect / perk</option></select></label>'+
 (educationView.groupBy==="effect"?'<label>Education path <select data-edu-path><option value="all">All effects</option>'+educationPaths.map(([name])=>'<option value="'+safe(name)+'" '+(educationView.effect===name?"selected":"")+'>'+safe(name)+'</option>').join("")+'</select></label>':"")+
 '<label>Show <select data-edu-filter>'+[["all","All courses"],["remaining","Remaining"],["completed","Completed"]].map(([v,l])=>'<option value="'+v+'" '+(educationView.filter===v?"selected":"")+'>'+l+'</option>').join("")+'</select></label></div>';
 for(const g of educationGroups(m)){
 const courses=m.list(g),group=String(g.name??g.title??"Courses"),count=courses.filter(c=>m.ids.has(String(c.id))).length;
 const shown=courses.filter(c=>!m.known||educationView.filter==="all"||(educationView.filter==="completed")===m.ids.has(String(c.id)));
 if(!shown.length)continue;
 const opened=educationView.open.has(group)||!educationView.open.has("closed:"+group)&&(educationView.groupBy==="effect"&&educationView.effect===group||courses.some(c=>String(c.id)===String(m.id)));
 out+='<details class="edu-category" data-edu-group="'+safe(group)+'" '+(opened?"open":"")+'><summary><strong>'+safe(group)+'</strong><span>'+(m.known?count:"—")+'/'+courses.length+'</span></summary><div class="edu-courses">';
 for(const c of shown){
 const id=String(c.id),done=m.ids.has(id),active=id===String(m.id),key=group+":"+String(c.code??c.id??c.name),selected=educationView.selected===key;
 out+='<div class="edu-course '+(done?"is-completed":active?"is-active":"")+'"><button type="button" data-edu-course="'+safe(key)+'" aria-expanded="'+selected+'"><span class="edu-course-name"><span>'+safe(c.code??c.course_code??"")+'</span><strong>'+safe(c.name??c.title??"Course "+id)+'</strong></span><span class="edu-course-effect"><span>'+safe(educationEffectText(c))+'</span><small>'+(done?"Completed":active?"In progress":"")+'</small></span></button>'+(selected?educationCourseDetail(c,m):"")+'</div>';
 }
 out+='</div></details>';
 }
 return out+sourceError("education")+sourceError("educationCatalog")+'</div></section>';
}
function wireEducationPage(view){
 if(view.dataset.eduBound==="1")return;view.dataset.eduBound="1";
 const rebuild=()=>{if(location.hash==="#education")view.innerHTML=renderEducationPage();};
 view.addEventListener("toggle",e=>{const el=e.target;if(!el.matches?.("[data-edu-group]")||!el.isConnected)return;const g=el.dataset.eduGroup;if(el.open){educationView.open.add(g);educationView.open.delete("closed:"+g);}else{educationView.open.delete(g);educationView.open.add("closed:"+g);}},true);
 view.addEventListener("click",e=>{const el=e.target.closest("[data-edu-course]");if(!el||location.hash!=="#education")return;const group=el.closest("[data-edu-group]");if(group){educationView.open.add(group.dataset.eduGroup);educationView.open.delete("closed:"+group.dataset.eduGroup);}educationView.selected=educationView.selected===el.dataset.eduCourse?null:el.dataset.eduCourse;if(typeof tornDisclosureState!=="undefined")tornDisclosureState.set(tornDisclosureState.ownKey("edu-course"),educationView.selected??"");rebuild();});
 view.addEventListener("change",e=>{if(location.hash!=="#education")return;const el=e.target;if(el.matches("[data-edu-filter]"))educationView.filter=el.value;else if(el.matches("[data-edu-groupby]")){educationView.groupBy=el.value;educationView.selected=null;}else if(el.matches("[data-edu-path]")){educationView.effect=el.value;educationView.open.add(el.value);educationView.open.delete("closed:"+el.value);educationView.selected=null;}else return;if(typeof tornDisclosureState!=="undefined"){tornDisclosureState.set(tornDisclosureState.ownKey("edu-course"),educationView.selected??"");if(el.matches("[data-edu-path]")){const group=[...view.querySelectorAll("[data-edu-group]")].find(x=>x.dataset.eduGroup===el.value);if(group)tornDisclosureState.remember(group,true);}}saveEducationPreference();rebuild();});
}
