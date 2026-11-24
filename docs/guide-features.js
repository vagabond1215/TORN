"use strict";
/* Page-scoped Torn API coordinator. All network calls are explicit GETs to Torn API v2.
 * Credential lives in memory, or opt-in browser localStorage only. No external API
 * receives the Torn key. Live Torn-page bridge is an optional user-approved snapshot.
 */
const tornGuideApi=(()=>{
  let secret=null,remember=false,epoch=0,timer=null,inFlight=null,queued=null,batchMode="unknown";
  const quarter=15*60*1000;
  const authKey="torn-city-guide:api:v2:remember";
  const cachePrefix="torn-city-guide:api:v2:cache:";
  const inventoryTypes=["Candy","Drug","Alcohol","Tool","Enhancer","Booster","Energy Drink","Medical"];
  const mins=60*1000,hrs=60*mins,days=24*hrs;
  const TTL={
    basic:days, bars:2*mins, cooldowns:2*mins, money:15*mins,
    battlestats:15*mins, gym:30*mins, perks:60*mins,
    education:6*hrs, virus:15*mins, organizedcrime:10*mins, factionRankedWars:15*mins, merits:6*hrs, job:6*hrs, workstats:6*hrs, property:12*hrs,
    stocks:60*mins, personalstats:24*hrs, travel:15*mins, racingrecords:6*hrs,
    gymCatalog:90*days, meritCatalog:30*days, stockCatalog:7*days
  };
  const ROUTES={
    home:["bars","cooldowns","money","battlestats","workstats","gym","job","property","education","merits","meritCatalog"],
    stats:["bars","cooldowns","battlestats","gym","perks","gymCatalog"],
    jobs:["job","workstats"],
    timers:["education","virus","cooldowns","organizedcrime","factionRankedWars"],
    activity:["virus","travel","racingrecords"],
    crime:["bars"],
    checklist:["bars","merits","meritCatalog","job"],
    money:["money","stocks","stockCatalog"],
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
  function bridgeIsFresh(){
    return state.bridge&&state.identity&&Number(state.bridge.playerId)===state.identity.id&&
      now()-Number(state.bridge.timestamp)<90000;
  }
  // A userscript shares only allowlisted, manually captured public-side-bar values.
  function acceptLocalSnapshot(snapshot){
    if(!snapshot||!state.identity||Number(snapshot.playerId)!==state.identity.id)return false;
    if(!Number.isFinite(Number(snapshot.timestamp))||Math.abs(now()-snapshot.timestamp)>90000)return false;
    const bars=snapshot.bars;
    if(!bars||typeof bars!=="object")return false;
    const clean={};
    for(const name of ["energy","nerve","happy","life"]){
      const item=bars[name];
      if(!item)continue;
      const current=Number(item.current),maximum=Number(item.maximum);
      if(Number.isFinite(current)&&Number.isFinite(maximum)&&current>=0&&maximum>0&&current<=maximum+100000)
        clean[name]={current,maximum};
    }
    if(!Object.keys(clean).length)return false;
    const base=state.data.bars&&state.data.bars.bars||{};
    state.data.bars={bars:{...base,...clean}};
    state.bridge={playerId:state.identity.id,timestamp:Number(snapshot.timestamp),fields:Object.keys(clean)};
    announce();
    if(["home","stats","crime","checklist"].includes(routeName())&&typeof renderRoute==="function")renderRoute();
    return true;
  }
  // The bridge only replaces very fresh bar readings. It never authorizes
  // third-party access to inventory, finances, stats or any API key.
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
      :[];
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
    if(typeof renderRoute==="function" && location.hash!=="#profile" && route!=="timers")renderRoute();
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
  const bridge=state.bridge&&state.bridge.fields?.includes(name)&&Date.now()-state.bridge.timestamp<90000;
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
  if(typeof location!=="undefined"&&!["","home","dashboard"].includes((location.hash||"#home").slice(1)))return;
  const root=document.getElementById("topic-view");
  if(!root||root.hidden)return;
  const bars=payload("bars","bars"),state=tornGuideApi.state;
  if(!bars)return;
  for(const row of root.querySelectorAll("[data-home-bar]")){
    const name=row.dataset.homeBar,bar=bars[name];if(!bar)continue;
    const bridge=state.bridge&&state.bridge.fields?.includes(name)&&Date.now()-state.bridge.timestamp<90000;
    const at=bridge?state.bridge.timestamp:state.fetchedAt.bars;
    const current=tornBarProjection(name,bar,at),number=row.querySelector("[data-home-current]"),
      time=row.querySelector("[data-home-countdown]"),fill=row.querySelector("[data-home-fill]"),
      progress=row.querySelector("[role=progressbar]");
    if(!current)continue;
    if(number)number.textContent=formatNumber(current.current)+"/"+formatNumber(current.maximum);
    if(time)time.textContent=current.current>current.maximum?"OVER":current.current>=current.maximum?"FULL":homeCountdown(current.until);
    if(fill)fill.style.width=current.percentage.toFixed(2)+"%";
    if(progress)progress.setAttribute("aria-valuenow",String(current.current));
  }

  for(const time of root.querySelectorAll("[data-activity-deadline]")){
    const target=Number(time.dataset.activityDeadline);
    if(Number.isFinite(target)){
      const remaining=Math.max(0,Math.ceil((target-Date.now())/1000));
      const days=Math.floor(remaining/86400),hours=Math.floor(remaining%86400/3600),
        minutes=Math.floor(remaining%3600/60),secs=remaining%60;
      time.textContent=remaining?((days?days+"d ":"")+String(hours).padStart(2,"0")+":"+
        String(minutes).padStart(2,"0")+":"+String(secs).padStart(2,"0")):"Ready";
    }
  }
}

function renderDashboard() {
  let result='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Home dashboard</h1></header>';
  if(!tornGuideApi.isConnected()){
    return result+'<section class="panel"><div class="panel-content"><p>Connect your Torn API key below to show your in-game-style dashboard. Account data remains private to this browser.</p></div></section>';
  }
  const st=tornGuideApi.state,bars=payload("bars","bars"),cooldowns=payload("cooldowns","cooldowns");
  const battle=payload("battlestats","battlestats"),work=payload("workstats","workstats");
  const cash=payload("money","money"),merits=payload("merits","merits");
  const gym=payload("gym","gym"),job=payload("job","job"),property=payload("property","property");
  const education=payload("education","education");
  const statValue=(key)=>homeValue(battle?.[key]&&typeof battle[key]==="object"?battle[key].value:battle?.[key]);
  const workValue=(...keys)=>{for(const key of keys)if(work?.[key]!=null)return homeValue(work[key]);return "Not available";};
  const cdText=value=>{
    const num=Number(value);
    if(value==null||!Number.isFinite(num))return "Not loaded";
    if(num<=0)return "Ready";
    return (Math.floor(num/3600)?Math.floor(num/3600)+"h ":"")+
      Math.floor(num%3600/60)+"m";
  };
  const visibleMoney=cash?.wallet!=null?"$"+formatNumber(cash.wallet):"Not available";
  const currentJob=job?.name||job?.company_name||job?.position||"Not available";
  const homeProperty=property?.name||property?.property?.name||"Not available";

  result+='<div class="home-summary-grid">'+
    '<section class="panel home-information"><div class="panel-heading"><h2>Information</h2></div><div class="panel-content">'+
      '<dl class="home-information-list">'+
        homePair("Money",visibleMoney,"home-money")+
        homePair("Level",st.identity?.level??"Not available")+
        homePair("Points",cash?.points??"Not available")+
        homePair("Merits",merits?.available??"Not available")+
      '</dl><div class="home-bars">'+
        ["energy","nerve","happy","life"].map(key=>homeBar(key,bars?.[key])).join("")+
      '</div>'+
      ''+
    '</div></section>'+
    '<section class="panel home-battle"><div class="panel-heading"><h2>Battle stats <a href="#stats" title="Open training calculator">Calc</a></h2></div><div class="panel-content">'+
      homeStatList([
        ["Strength",statValue("strength")],
        ["Defense",statValue("defense")],
        ["Speed",statValue("speed")],
        ["Dexterity",statValue("dexterity")],
        ["Total",statValue("total")]
      ])+sourceError("battlestats")+
    '</div></section>'+
    '<section class="panel home-work"><div class="panel-heading"><h2>Working stats <a href="#jobs" title="Open Jobs and careers">Jobs</a></h2></div><div class="panel-content">'+
      homeStatList([
        ["Manual labor",workValue("manual_labor","manual","man")],
        ["Intelligence",workValue("intelligence","intel","int")],
        ["Endurance",workValue("endurance","end")]
      ])+'<p class="home-subline">Job: '+safe(currentJob)+'</p>'+sourceError("workstats")+
    '</div></section>'+
  '</div>';

  result+='<div class="home-secondary-grid">'+
    '<section class="panel"><div class="panel-heading"><h2>Account &amp; progress</h2></div>'+
    '<div class="panel-content">'+homeStatList([
      ["Property",homeProperty],
      ["Current gym",gym?.name||"Not available"],
      ["Bank",cash?.city_bank?.amount!=null?"$"+formatNumber(cash.city_bank.amount):"Not available"],
      ["Education merit",meritLevel("Education Length")===null?"Not loaded":meritLevel("Education Length")+"/10"],
      ["Bank merit",meritLevel("Bank Interest")===null?"Not loaded":meritLevel("Bank Interest")+"/10"],
      ["Education",education?.current?"Course #"+education.current.id:education?"None active":"Not loaded"]
    ])+'</div></section>'+
    '<section class="panel"><div class="panel-heading"><h2>Cooldowns &amp; next steps</h2></div>'+
    '<div class="panel-content">'+homeStatList([
      ["Drug",cdText(cooldowns?.drug)],
      ["Booster",cdText(cooldowns?.booster)],
      ["Medical",cdText(cooldowns?.medical)]
    ])+'<div class="home-action-links">'+
       '<a href="#stats">Train</a><a href="#crime">Crimes</a>'+
       '<a href="#checklist">Checklist</a><a href="#inventory">Inventory</a>'+
       '<a href="#money">Money</a>'+
      '</div></div></section>'+
  '</div>';


  // These are cached values only. User/virus, /travel and /racingrecords
  // are fetched exclusively when the player explicitly updates this panel.
  const bank=cash?.city_bank??null,virus=payload("virus","virus"),
    travel=payload("travel","travel"),races=payload("racingrecords","racingrecords");
  const unix=x=>{const v=Number(x);return Number.isFinite(v)&&v>1e9?(v>1e12?v:v*1000):null;};
  const when=x=>{const value=unix(x);return value?tornGuidePreferences.formatDate(value):"Not available";};
  const entry=(label,text,deadline)=>'<div class="home-pair"><dt>'+safe(label)+
    '</dt><dd>'+safe(text)+(deadline?
      ' <span class="activity-countdown" data-activity-deadline="'+deadline+'"></span>':"")+
    '</dd></div>';
  let bankSummary="No active deposit";
  if(!cash)bankSummary="Not loaded";
  else if(bank&&bank.amount!=null){
    bankSummary="$"+formatNumber(bank.amount);
    if(bank.profit!=null)bankSummary+=" · +$"+formatNumber(bank.profit)+" profit";
  }
  const vTime=virus?.until??virus?.ends_at??virus?.end,
    vAt=unix(vTime);
  const vName=virus?.item?.name||virus?.name||"Active virus";
  const travelAt=unix(travel?.arrival??travel?.until??travel?.timestamp),
    travelRemain=Number(travel?.time_left??travel?.remaining),
    tripEnd=travelAt||(Number.isFinite(travelRemain)&&travelRemain>0&&st.fetchedAt.travel?
      st.fetchedAt.travel+travelRemain*1000:null);
  const destination=typeof travel?.destination==="string"?travel.destination:
    travel?.destination?.name||travel?.to||"Flight";
  const flight=travel?tripEnd?destination:travel?.status||"No active flight":"Not loaded";
  const recordArray=Array.isArray(races)?races:
    Array.isArray(races?.records)?races.records:null;
  const recentRecords=recordArray?recordArray.length+" track records":"Not loaded";
  result+='<section class="panel home-activity"><div class="panel-heading"><h2>Bank, virus, travel &amp; racing</h2>'+
    '<button type="button" class="home-activity-refresh" data-home-activity-refresh title="Request only stale activity selections">Update activity</button>'+
    '</div><div class="panel-content"><dl class="home-stat-list">'+
      entry("Investment",bankSummary)+
      entry("Bank maturity",bank?.until!=null?when(bank.until):cash?"No active investment":"Not loaded")+
      entry("Virus",virus?vName:"Not loaded",vAt)+
      entry("Travel",flight,tripEnd)+
      entry("Racing records",recentRecords)+
    '</dl><p class="fine-print">Bank values are reused from Money. Virus, travel and personal racing records load only on request. Records are best laps, not the latest finishing position.</p>'+
    '<span class="sr-only" id="home-activity-status" role="status"></span></div></section>';

  result+='<details class="home-expand-panel"><summary>Activity &amp; detailed reports</summary>'+
    '<div class="home-expand-body"><p class="fine-print">Reports open in a preview window when supported by the provider, with a new-tab fallback.</p><div class="report-links">';
  for(const [id,[label,,tip]] of Object.entries(tornReportCatalog)){
    result+='<button type="button" class="report-launch" data-report="'+safe(id)+'" aria-haspopup="dialog" title="'+safe(tip)+'">'+
      '<strong>'+safe(label)+'</strong><small>'+safe(tip)+'</small></button>';
  }
  result+='</div></div></details>';
  result+='<details class="home-expand-panel"><summary>Data sources &amp; request budget</summary>'+
    '<div class="home-expand-body">'+renderSourcesPanel()+'</div></details>';
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



function renderStocksPanel(){
  let result="";
  const stockPositions = ownedStockPositions();
  result += '<section class="panel"><div class="panel-heading"><h2>Stock holdings and education benefit</h2></div><div class="panel-content"><div class="metric-grid">';
  const wsuShares = heldWsuShares();
  result += metric("WSU shares", wsuShares === null ? "Not available" : formatNumber(wsuShares), wsuShares !== null && wsuShares >= 1000000 ? "Education block unlocked" : "Goal: 1,000,000 shares");
  result += metric("Stock positions", stockPositions ? formatNumber(stockPositions.length) : "Not available");
  result += '</div>';
  if (stockPositions && stockPositions.length) {
    result += '<ul class="item-list stock-list">' + stockPositions.map(item =>
      '<li><span>' + safe(item.details && (item.details.name || item.details.acronym) || "Stock #" + item.id) +
      '</span><strong>' + safe(formatNumber(item.shares)) + ' shares</strong></li>').join("") + '</ul>';
  }
  result += sourceError("stocks") + sourceError("stockCatalog") + '</div></section>';

  return result;
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

function renderSourcesPanel(){
  const st=tornGuideApi.state;
  const live=st.bridge && Date.now()-st.bridge.timestamp<90000;
  const scriptUrl="https://vagabond1215.github.io/TORN/torn-companion.user.js";
  let out='<section class="panel"><div class="panel-heading"><h2>Data sources and API budget</h2></div><div class="panel-content"><div class="source-status-grid">';
  out+='<div><strong>Torn API v2</strong><small>Authoritative, page-specific and cached by selection</small><span>'+safe(st.requests)+' successful calls this visit</span></div>';
  out+='<div><strong>Visible Torn page</strong><small>Manual Tampermonkey share; no background scraping</small><span>'+
    (live?"Fresh "+safe(st.bridge.fields.join(", "))+" at "+safe(tornGuidePreferences.formatDate(st.bridge.timestamp)):"No fresh manual snapshot")+'</span></div>';
  out+='<div><strong>External reports</strong><small>TornStats and Torn Report are optional, separate services</small><span>Not connected automatically</span></div>';
  out+='</div><p class="fine-print">To share already visible Torn bars, <a href="'+safe(scriptUrl)+'" target="_blank" rel="noopener noreferrer">install the open-source companion userscript</a> in Tampermonkey. On a Torn page you are actively viewing, click <strong>Share bars with Torn Guide</strong>, then switch here within 90 seconds. No Torn API key or session cookie is exported.</p>';
  out+='<p class="fine-print"><a href="https://www.tornstats.com/api" target="_blank" rel="noopener noreferrer">TornStats API</a> is available for separately authorized integrations, but this guide will not send a Full Access key to outside services. Browser CORS compatibility and permission scopes must be confirmed before enabling direct provider requests. <a href="https://torn.report/" target="_blank" rel="noopener noreferrer">Torn Report</a> remains available through its own authenticated site.</p>';
  out+='</div></section>';
  return out;
}
