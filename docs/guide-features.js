"use strict";
/* Page-scoped Torn API coordinator. All network calls are explicit GETs to Torn API v2.
 * Credential lives in memory, or opt-in browser localStorage only. No external API
 * receives the Torn key. The optional passive Torn-page bridge reads only allowlisted status bars.
 */
const tornGuideApi=(()=>{
  let secret=null,remember=false,epoch=0,timer=null,inFlight=null,queued=null,batchMode="unknown";
  const quarter=15*60*1000;
  const authKey="torn-city-guide:api:v2:remember";
  const cachePrefix="torn-city-guide:api:v2:cache:";
  const inventoryTypes=["Candy","Drug","Alcohol","Tool","Enhancer","Booster","Energy Drink","Medical"];
  const mins=60*1000,hrs=60*mins,days=24*hrs;
  const TTL={
    basic:days, profile:15*mins, bars:2*mins, cooldowns:2*mins, money:15*mins, networth:60*mins,
    jobpoints:15*mins, skills:15*mins, battlestats:15*mins, gym:30*mins, perks:60*mins,
    education:6*hrs, virus:15*mins, organizedcrime:10*mins, factionRankedWars:15*mins, merits:6*hrs, job:6*hrs, workstats:6*hrs, property:12*hrs,
    stocks:60*mins, personalstats:24*hrs, travel:15*mins, racingrecords:6*hrs, races:30*mins,
    gymCatalog:90*days, meritCatalog:30*days, stockCatalog:15*mins, educationCatalog:7*days, itemCatalog:15*mins, pointsCatalog:15*mins
  };
  const ROUTES={
    home:["skills","itemCatalog","bars","cooldowns","money","networth","battlestats","workstats","gym","job","property","education","merits","meritCatalog"],
    stats:["profile","bars","cooldowns","battlestats","gym","perks","gymCatalog","itemCatalog","pointsCatalog"],
    jobs:["job","workstats","perks","jobpoints"],
    timers:["education","virus","cooldowns","organizedcrime","factionRankedWars"],
    railTimers:["education","virus","itemCatalog","cooldowns","organizedcrime","factionRankedWars","travel","money"],
    activity:["virus","travel","racingrecords","races"],
    crime:["bars","skills","itemCatalog"],
    checklist:["bars","merits","meritCatalog","job"],
    money:["money"],
    stocks:["stocks","stockCatalog","itemCatalog"],
    education:["education","educationCatalog","merits","meritCatalog","stocks","stockCatalog","perks"],
    inventory:[],
    racing:[], faction:[], attacking:[], war:[], tools:[]
  };
  const state={identity:null,data:{},inventory:{},errors:{},inventoryErrors:{},
    fetchedAt:{},failedAt:{},updated:null,loading:false,cached:false,
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
    if(!on){remember=false;clearSaved(state.identity.id);state.cached=false;announce();return false;}
    remember=true;save();announce();return remember;
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
    state.fetchedAt={};state.failedAt={};state.updated=null;state.bridge=null;state.cached=false;
    try{
      const snap=JSON.parse(localStorage.getItem(cacheKey(state.identity.id))||"null");
      if(snap&&Number(snap.playerId)===state.identity.id){
        for(const key of ["data","inventory","errors","inventoryErrors","fetchedAt","failedAt"]){
          state[key]=snap[key]&&typeof snap[key]==="object"?snap[key]:{};
        }
        state.updated=Number(snap.updated)||null;
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
  async function request(path,key){
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),15000);
    try{
      const response=await fetch("https://api.torn.com/v2/"+path,{
        method:"GET",headers:{Authorization:"ApiKey "+key,Accept:"application/json"},
        credentials:"omit",cache:"no-store",referrerPolicy:"no-referrer",signal:controller.signal
      });
      const payload=await response.json();
      if(payload&&payload.error)throw Error("Torn API: "+String(payload.error.error||payload.error.message||payload.error.code||"request rejected"));
      if(!response.ok)throw Error("Torn API HTTP "+response.status);
      state.requests++;state.lastRequest=now();
      return payload;
    }catch(error){
      if(error.name==="AbortError")throw Error("Torn API request timed out");
      if(error instanceof TypeError)throw Error("Cannot reach Torn API. Check network/CORS.");
      throw error;
    }finally{clearTimeout(timeout);}
  }
  async function connect(raw,stay=false){
    const key=String(raw||"").trim();
    if(!/^[a-zA-Z0-9]{16}$/.test(key))throw Error("Enter a valid 16-character Torn API key.");
    const basic=await request("user/basic",key);
    const profile=basic.profile;
    if(!profile||!Number.isInteger(profile.id)||!profile.name)throw Error("Torn returned an unexpected identity.");
    if(remember)clearSaved(state.identity&&state.identity.id);
    epoch++;secret=key;remember=Boolean(stay);batchMode="unknown";
    state.identity={id:profile.id,name:profile.name,level:profile.level};
    state.data={basic};state.inventory={};state.errors={};state.inventoryErrors={};
    state.fetchedAt={basic:now()};state.failedAt={};state.updated=now();
    state.cached=false;state.bridge=null;state.storageWarning=null;
    save();schedule();announce();
    return state.identity;
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
    if(key==="personalstats")return "user/personalstats?cat=popular";
    if(key==="factionRankedWars")return "faction/rankedwars";
    if(key==="gymCatalog")return "torn/gyms";
    if(key==="stockCatalog")return "torn/stocks";
    if(key==="educationCatalog")return "torn/education";
    if(key==="itemCatalog")return "torn/items";
    if(key==="pointsCatalog")return "market/pointsmarket";
    if(key==="meritCatalog")return "torn/merits";
    return "user/"+key;
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
  async function batch(route,force=false,category=null){
    if(!secret)throw Error("Connect Torn API first.");
    const currentEpoch=epoch,currentKey=secret;
    const names=(ROUTES[route]||ROUTES.home).filter(name=>stale(name,force));
    const cats=route==="inventory"
      ?(category?[category]:Object.keys(state.inventory).filter(c=>inventoryTypes.includes(c)))
      :route==="stats"?["Candy"]:["home","crime"].includes(route)?["Tool","Enhancer"]:[];
    const selectedCats=cats.filter(cat=>inventoryTypes.includes(cat)&&stale("inventory:"+cat,force));
    if(!names.length&&!selectedCats.length)return {failures:0,requested:0,skipped:true};
    state.loading=true;announce();
    let succeeded=0,failures=0;
    const userNames=names.filter(name=>!name.endsWith("Catalog") && !["factionRankedWars","personalstats"].includes(name));
    const otherNames=names.filter(name=>name.endsWith("Catalog") || ["factionRankedWars","personalstats"].includes(name));
    const jobs=[];
    if(userNames.length>=2 && batchMode!=="unsupported"){
      jobs.push({
        name:"multiUser",names:userNames,
        run:()=>request("user?selections="+encodeURIComponent(userNames.join(",")),currentKey)
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
                state.fetchedAt[name]=now();delete state.failedAt[name];
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
          state.fetchedAt[job.name]=now();delete state.failedAt[job.name];succeeded++;
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
      if(opts.force||opts.category||route!==inFlight.route)queued={route,force:Boolean(opts.force),category:opts.category||null};
      return inFlight.promise;
    }
    const promise=batch(route,Boolean(opts.force),opts.category||null).finally(()=>{
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
    epoch++;secret=null;remember=false;stopTimer();queued=null;
    clearSaved(id);
    state.identity=null;state.data={};state.inventory={};state.errors={};
    state.inventoryErrors={};state.fetchedAt={};state.failedAt={};
    state.updated=null;state.bridge=null;state.loading=false;state.cached=false;
    announce();
  }
  return {state,connect,refresh,loadPage,loadInventory,acceptLocalSnapshot,
    disconnect,restore,setRemember,isRemembering:()=>remember,
    isConnected:()=>Boolean(secret),refreshOnResume,inventoryTypes,routeName,TTL,ROUTES};
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
  energy:["Energy","https://torn.report/energy","Energy use & recovery"],
  nerve:["Nerve","https://torn.report/nerve","Crime nerve history"],
  education:["Education","https://torn.report/education","Courses and education benefits"],
  drugs:["Drugs","https://torn.report/drugs","Drug use history"],
  racing:["Racing","https://torn.report/racing","Races and performance"],
  uniques:["Crime uniques","https://torn.report/uniques","Unique crime outcomes"],
  trains:["Trains received","https://torn.report/trains","Workplace training history"],
  oc:["Organized crimes","https://torn.report/oc","Faction crime participation"],
  travel:["Travel","https://torn.report/travel","Travel activity and trips"]
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
  const current=rawCurrent>=max?rawCurrent:Math.min(max,rawCurrent+ticks*step);
  const until=current>=max?0:Math.max(0,first+ticks*interval-elapsed);
  return {current,maximum:max,percentage:Math.max(0,Math.min(100,current/max*100)),
    until,phaseSource,estimated:phaseSource!=="API",
    snapshotAt:stamp,step,interval};
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
    out+='<details class="networth-group" open><summary><span>'+safe(name)+'</span>'+
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
  result+='<details class="home-expand-panel"><summary>Activity &amp; detailed reports</summary>'+
    '<div class="home-expand-body"><p class="fine-print">Reports open in a preview window when supported by the provider, with a new-tab fallback.</p><div class="report-links">';
  for(const [id,[label,,tip]] of Object.entries(tornReportCatalog)){
    result+='<button type="button" class="report-launch" data-report="'+safe(id)+'" aria-haspopup="dialog" title="'+safe(tip)+'">'+
      '<strong>'+safe(label)+'</strong><small>'+safe(tip)+'</small></button>';
  }
  result+='</div></div></details>';
  const issues=[...Object.entries(st.errors).map(([key,value])=>[key,value]),
    ...Object.entries(st.inventoryErrors).map(([key,value])=>["Inventory: "+key,value])];
  if(issues.length){
    result+='<details class="home-expand-panel home-errors" open><summary>API issues ('+issues.length+')</summary>'+
      '<div class="home-expand-body"><ul class="api-failure-list">'+issues.map(([name,detail])=>
        '<li><strong>'+safe(name)+'</strong><small>'+safe(detail)+'</small></li>').join("")+
      '</ul></div></details>';
  }
  return result;
}



const stockView={sort:"default",query:"",filter:"all"};
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
  const h=owned.find(x=>Number(x.id)===Number(c.id)),ticker=String(c.acronym||"").toUpperCase(),f=stockFallback[ticker]||[],b=c.benefit||{};
  const price=num(c.current_price??c.price),shares=holdings==null?null:num(h?.shares??0),value=price!=null&&shares!=null?price*shares:null;
  const req=num(b.requirement??b.shares??f[0]),freq=num(b.frequency??f[1]),description=typeof b.description==="string"?b.description:typeof b.name==="string"?b.name:f[2]||"Benefit unavailable";
  const passive=String(b.type||"").toLowerCase()==="passive"||freq===0;
  const tier=req>0&&shares!=null?Math.max(0,Math.floor(Math.log2(shares/req+1))):0;
  const active=shares!=null&&req>0&&shares>=req,benefit=h?.dividend??h?.benefit;
  const ready=benefit?.ready===true||Number(benefit?.ready)>0;
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
  return {name:c.name||ticker,ticker,price,shares,value,req,freq,description,passive,tier,active,ready,days,nextShares,nextCost,blockCost,payout,daily,roi,nextRoi,cost,profit:cost!=null&&value!=null?value-cost:null};
 });
}
function renderStocksPanel(){
 const rows=stockRows(),money=v=>v==null?"—":"$"+formatNumber(Math.round(v)),number=v=>v==null?"—":formatNumber(v),percent=v=>v==null?"—":v.toFixed(1)+"%";
 const total=rows.filter(r=>r.shares>0),sum=key=>total.length&&total.every(r=>r[key]!=null)?total.reduce((n,r)=>n+r[key],0):null;
 const options=[["default","Active dividends, then value"],["name","Stock name"],["value","Holdings value"],["shares","Shares owned"],["price","Share price"],["roi","Annual ROI (first block)"],["nextRoi","Annual ROI (next block)"],["nextCost","Cost to next block"],["days","Days to payout"],["daily","Daily dividend value"]];
 const q=stockView.query.toLowerCase(),filtered=rows.filter(r=>(r.name+" "+r.ticker).toLowerCase().includes(q)&&(stockView.filter==="all"||stockView.filter==="owned"&&r.shares>0||stockView.filter==="active"&&r.active||stockView.filter==="cash"&&!r.passive||stockView.filter==="passive"&&r.passive));
 const cmp=(a,b,k,asc=false)=>a[k]==null?(b[k]==null?0:1):b[k]==null?-1:asc?a[k]-b[k]:b[k]-a[k];
 filtered.sort((a,b)=>stockView.sort==="default"?Number(b.active&&!b.passive)-Number(a.active&&!a.passive)||Number(b.active)-Number(a.active)||cmp(a,b,"value")||a.name.localeCompare(b.name):stockView.sort==="name"?a.name.localeCompare(b.name):cmp(a,b,stockView.sort,["nextCost","days"].includes(stockView.sort))||a.name.localeCompare(b.name));
 let out='<section class="panel stock-market-panel"><div class="panel-heading"><h2>Stock Market</h2><span>Value: '+money(sum("value"))+' · Profit: '+money(sum("profit"))+'</span></div><div class="panel-content">';
 out+='<div class="stock-controls"><label>Search <input data-stock-query value="'+safe(stockView.query)+'" placeholder="Stock name or ticker"></label><label>Show <select data-stock-filter>'+[["all","All stocks"],["owned","Owned"],["active","Active benefits"],["cash","Payout benefits"],["passive","Passive benefits"]].map(([v,l])=>'<option value="'+v+'" '+(stockView.filter===v?"selected":"")+'>'+l+'</option>').join("")+'</select></label><label>Sort <select data-stock-sort>'+options.map(([v,l])=>'<option value="'+v+'" '+(stockView.sort===v?"selected":"")+'>'+l+'</option>').join("")+'</select></label><small>'+filtered.length+' of '+rows.length+' stocks</small></div>';
 out+='<div class="stock-table-scroll"><table class="stock-market-table"><thead><tr><th>Stock</th><th>Price</th><th>Owned / value</th><th>Dividend / benefit</th><th>Next benefit block</th><th>Annual ROI</th></tr></thead><tbody>';
 for(const r of filtered){
 const status=r.shares==null?"Holdings not loaded":!r.active?"Inactive":r.passive?"Benefit active":r.ready?"Collection ready":r.days!=null?"Ready in "+r.days+" days":"Payout timing unavailable";
 out+='<tr class="'+(r.active?"stock-active":"")+'"><td><span class="stock-ticker">'+safe(r.ticker)+'</span><strong>'+safe(r.name)+'</strong></td><td>'+(r.price!=null?"$"+r.price.toFixed(2):"—")+'</td><td><strong>'+money(r.value)+'</strong><small>'+number(r.shares)+' shares</small>'+(r.cost!=null&&r.shares>0?'<small>Invested '+money(r.cost)+'</small>':'')+'</td><td><strong>'+safe(r.description)+'</strong><small class="'+(r.active?"stock-benefit-active":"")+'">'+safe(status)+(r.active&&!r.passive?' · '+r.tier+' block'+(r.tier===1?'':'s'):'')+'</small>'+(r.freq>0?'<small>Every '+r.freq+' days · '+money(r.payout)+' / block</small>':'')+'</td><td><strong>'+money(r.nextCost)+'</strong><small>'+number(r.nextShares)+' shares remaining</small><small>First block '+money(r.blockCost)+'</small></td><td><strong>'+percent(r.roi)+'</strong><small>Next: '+percent(r.nextRoi)+'</small><small>'+money(r.daily)+' / day</small></td></tr>';
 }
 return out+'</tbody></table></div><p class="fine-print">Annual dividend ROI uses current share prices and 365 days, excluding stock price changes. Item rewards use cached Torn market values; passive or unpriced rewards are not assigned a cash ROI. Next block cost is the additional shares required, excluding fees.</p>'+sourceError("stocks")+sourceError("stockCatalog")+sourceError("itemCatalog")+'</div></section>';
}
function wireStocksPanel(view){
 if(view.dataset.stockBound==="1")return;view.dataset.stockBound="1";
 view.addEventListener("change",event=>{
 const el=event.target;
 if(el.matches("[data-stock-sort]"))stockView.sort=el.value;
 else if(el.matches("[data-stock-filter]"))stockView.filter=el.value;
 else if(el.matches("[data-stock-query]"))stockView.query=el.value;
 else return;
 const panel=view.querySelector(".stock-market-panel");if(panel)panel.outerHTML=renderStocksPanel();
 });
}
function renderInventoryPage(){
  let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Inventory</h1><p>Load only the item categories you need. Once loaded, each category is cached independently for 15 minutes and preserved between visits when Stay logged in is enabled.</p></header>';
  if(!tornGuideApi.isConnected())return out+'<section class="panel"><div class="panel-content">Connect your account to load inventory.</div></section>';
  const st=tornGuideApi.state;
  out+='<div class="inventory-grid">';
  for(const cat of tornGuideApi.inventoryTypes){
    const items=st.inventory[cat],stamp=Number(st.fetchedAt["inventory:"+cat])||0;
    const error=st.inventoryErrors[cat];
    out+='<section class="inventory-panel"><h3>'+safe(cat)+(items?' ('+items.length+')':'')+'</h3>'+
      '<div class="inventory-actions"><button type="button" class="button secondary" data-inventory-load="'+safe(cat)+'">'+(items?'Refresh category':'Load category')+'</button>';
    if(stamp)out+='<small>Updated '+safe(tornGuidePreferences.formatDate(stamp))+'</small>';
    out+='</div>';
    if(error)out+='<p class="api-error">'+safe(error)+'</p>';
    if(!items)out+='<p>Not requested yet.</p>';
    else if(!items.length)out+='<p>Nothing held.</p>';
    else out+='<ul class="item-list">'+items.map(item=>
      '<li><span>'+safe(item.name)+(item.equipped?' <small>(equipped)</small>':'')+
      '</span><strong>×'+safe(formatNumber(item.amount))+'</strong></li>').join("")+'</ul>';
    out+='</section>';
  }
  return out+'</div>';
}

const educationView={open:new Set(),selected:null,filter:"all",groupBy:"category",effect:"all"};
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
 return {label:known.length?total+"%"+(known.length<parts.length?" (partial)":""):"Unavailable",tooltip:parts.map(([name,v])=>name+": "+(v===null?"Not loaded":v+"%")).join("\n")};
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
 return '<div class="edu-course-detail">'+(c.description?'<p>'+safe(c.description)+'</p>':'')+
 '<div class="edu-detail-grid"><div><h4>Working stats gained</h4>'+(gains.length?gains.map(([k,v])=>'<div>'+safe(k)+' <strong>+'+formatNumber(v)+'</strong></div>').join(""):'<p class="fine-print">Not supplied by catalog.</p>')+
 '</div><div><h4>Parameters</h4><div>Base length <strong>'+educationDuration(duration)+'</strong></div><div>Cost <strong>'+(cost!=null?"$"+formatNumber(cost):"Unavailable")+'</strong></div></div></div>'+
 (prerequisites.length?'<p class="edu-prerequisites">Prerequisites: '+safe(prerequisites.join(", "))+'</p>':'')+'</div>';
}
function renderEducationPage(){
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
 view.addEventListener("click",e=>{const el=e.target.closest("[data-edu-course]");if(!el||location.hash!=="#education")return;const group=el.closest("[data-edu-group]");if(group){educationView.open.add(group.dataset.eduGroup);educationView.open.delete("closed:"+group.dataset.eduGroup);}educationView.selected=educationView.selected===el.dataset.eduCourse?null:el.dataset.eduCourse;rebuild();});
 view.addEventListener("change",e=>{if(location.hash!=="#education")return;const el=e.target;if(el.matches("[data-edu-filter]"))educationView.filter=el.value;else if(el.matches("[data-edu-groupby]")){educationView.groupBy=el.value;educationView.selected=null;}else if(el.matches("[data-edu-path]")){educationView.effect=el.value;educationView.open.add(el.value);educationView.open.delete("closed:"+el.value);educationView.selected=null;}else return;rebuild();});
}
