"use strict";
const tornTrainSequence=(()=>{
  const externalHappyCost=200_000_000;
  const names={externalHappy:"Poison Mistletoe",xanax:"Xanax (+250 E)",ecstasy:"Ecstasy (double Happy)",candy:"Candy (+Happy)",dvd:"Erotic DVD (+2,500 Happy)",train:"Train",refill:"Points energy refill",wait:"Wait minutes"};
  const make=(type,qty=1,minutes=0)=>({type,qty,minutes});
  const actionOptions=Object.entries(names);
  const maxCandyAction=()=>({...make("candy"),max:true});
  const jumpStart=()=>Array.from({length:4},()=>make("xanax"));
  const defaults={
    natural:()=>[],
    maxenergy:()=>[make("xanax"),maxCandyAction(),make("train"),make("refill"),make("train"),make("xanax"),make("train")],
    mini:()=>[make("xanax"),maxCandyAction(),make("ecstasy"),make("train"),make("refill"),make("train"),make("xanax"),make("train")],
    low:()=>[maxCandyAction(),make("ecstasy"),make("train"),make("refill"),make("train"),{...make("wait"),untilDrug:true}],
    jump:()=>[...jumpStart(),make("dvd",5),make("ecstasy"),make("train"),make("refill"),make("train")],
    maxhappy:()=>[...jumpStart(),make("externalHappy"),make("ecstasy"),make("train"),make("refill"),make("train")],
    custom:()=>[make("train")]
  };
  const recurringTemplates=new Set(["maxenergy","mini","low"]);
  const templates=[["natural","NAT","Natural training"],["maxenergy","MAX E","Maximum Energy"],["mini","MINI","Mini jump"],["low","LOW#","Low-stat jump"],["jump","HJ","Happy jump"],["maxhappy","99k","99k Happy jump"],["custom","CUSTOM","Custom"]];
  const midnightJumps=new Set(["low","mini","maxenergy","jump","maxhappy"]);
  const midnightWindow=15*60;
  function happyResetWait(seconds,firstReset=900){
    const remaining=((firstReset-seconds)%900+900)%900;
    return remaining>0&&remaining<240?remaining+1:0;
  }
  function waitTitle(reason=""){
    if(reason==="Happiness reset")return "Wait for Happiness Reset";
    if(reason.startsWith("Drug cooldown"))return "Wait - Drug Cooldown";
    if(reason.startsWith("Booster cooldown"))return "Wait - Booster Cooldown";
    if(reason==="Full Energy")return "Wait for Energy";
    if(reason==="TCT midnight"||reason==="Daily points refill")return "Wait for TCT Midnight";
    return "Wait";
  }
  function energyRefillUsedToday(now=Date.now()){
    const state=tornGuideApi.state,stamp=Number(state.fetchedAt?.refills||0);
    if(!stamp||state.errors?.refills||Math.floor(stamp/86400000)!==Math.floor(Number(now)/86400000))return false;
    const refill=payload("refills","refills");
    return (refill?.energy_refill_used??refill?.energy?.used)===true;
  }
  const defaultEnergy=Object.fromEntries(templates.map(([id])=>[id,["natural","jump","maxhappy"].includes(id)?"zero":"full"]));
  const startingEnergy={...defaultEnergy};
  const startingTime=Object.fromEntries(templates.map(([id])=>[id,0]));
  const steps=Object.fromEntries(templates.map(([id])=>[id,defaults[id]()]));
  const selected=new Set(["natural","jump"]),openTimelines=new Set(),editedPlans=new Set();
  let settingsOpen=false,chartMode="cycles",chartCycles=1,continuousDays=7,cycleOverrides=[],overridesOpen=false,showOptimal=true,showOptimalBudget=false,showManual=false,showCycleBoundaries=false;
  const defaultExcludedPlans=["custom","maxhappy"];
  const excludedPlans={optimal:new Set(defaultExcludedPlans),budget:new Set(defaultExcludedPlans)};
  let optimizerSettingsOpen="";
  let planPreferenceOwner;
  function restoreAction(saved){
    if(!saved||typeof saved.type!=="string"||!Object.hasOwn(names,saved.type))return null;
    const action=make(saved.type,Math.floor(clamp(saved.qty,0,10000)),clamp(saved.minutes,0,10080));
    if(saved.type==="train"&&["full","drug"].includes(saved.when))action.when=saved.when;
    if(["candy","dvd"].includes(saved.type)&&saved.max===true)action.max=true;
    if(saved.type==="candy"&&(saved.candyHappy==="any"||positive(saved.candyHappy)))action.candyHappy=saved.candyHappy==="any"?"any":Number(saved.candyHappy);
    if(saved.type==="wait"&&saved.untilDrug===true)action.untilDrug=true;
    return action;
  }
  function loadPlanPreferences(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(planPreferenceOwner===owner)return;
    planPreferenceOwner=owner;
    let saved=null;try{saved=JSON.parse(localStorage.getItem("torn-city-guide:plan-view:"+owner));}catch{}
    chartMode=saved?.chartMode==="continuous"?"continuous":"cycles";
    chartCycles=Math.floor(clamp(saved?.chartCycles,1,28));
    continuousDays=Math.floor(clamp(saved?.continuousDays??7,1,28));
    const valid=new Set(templates.map(([id])=>id));
    cycleOverrides=Array.isArray(saved?.cycleOverrides)?saved.cycleOverrides.slice(0,28).map(id=>valid.has(id)?id:""):[];
    overridesOpen=false;
    optimizerSettingsOpen="";
    for(const key of Object.keys(excludedPlans)){
      const stored=saved?.excludedPlans?.[key];
      excludedPlans[key]=new Set(Array.isArray(stored)?stored.filter(id=>valid.has(id)):defaultExcludedPlans);
    }
    showManual=saved?.showManual??cycleOverrides.some(Boolean);
    showOptimal=saved?.showOptimal!==false;
    showOptimalBudget=saved?.showOptimalBudget===true;
    showCycleBoundaries=saved?.showCycleBoundaries===true;
    selected.clear();openTimelines.clear();editedPlans.clear();
    for(const id of (Array.isArray(saved?.selected)?saved.selected:["natural","jump"]))if(valid.has(id))selected.add(id);
    for(const id of (Array.isArray(saved?.expanded)?saved.expanded:[]))if(valid.has(id)||["optimal","optimal-budget"].includes(id))openTimelines.add(id);
    for(const [id] of templates){
      const plan=saved?.plans?.[id];
      startingEnergy[id]=["zero","full","current"].includes(plan?.energy)?plan.energy:defaultEnergy[id];
      startingTime[id]=Math.floor(clamp(plan?.time,0,3600*10000-1));
      steps[id]=defaults[id]();
      if(Array.isArray(plan?.actions)){
        editedPlans.add(id);
        steps[id]=plan.actions.map(restoreAction).filter(Boolean);
      }
    }
  }
  function savePlanPreferences(){
    if(planPreferenceOwner===undefined)return;
    const plans=Object.fromEntries(templates.map(([id])=>[id,{
      energy:startingEnergy[id],time:startingTime[id],actions:editedPlans.has(id)?steps[id]:undefined
    }]));
    try{localStorage.setItem("torn-city-guide:plan-view:"+planPreferenceOwner,JSON.stringify({selected:[...selected],expanded:[...openTimelines],plans,chartMode,chartCycles,continuousDays,cycleOverrides,showOptimal,showOptimalBudget,showManual,showCycleBoundaries,excludedPlans:{optimal:[...excludedPlans.optimal],budget:[...excludedPlans.budget]}}));}catch{}
  }
  function templateButtons(){loadPlanPreferences();return '<div class="ts-template-toggles" role="group" aria-label="Compare templates">'+templates.map(([id,short,label])=>'<button type="button" class="tc-stat-tab '+(selected.has(id)?"is-selected":"")+'" data-ts-template="'+id+'" aria-pressed="'+selected.has(id)+'" title="'+label+'">'+short+'</button>').join("")+'<button type="button" class="tc-stat-tab ts-settings-toggle '+(settingsOpen?"is-selected":"")+'" data-ts-settings aria-expanded="'+settingsOpen+'" aria-controls="ts-plan-settings" title="Time, cooldowns, effects, prices"><span aria-hidden="true">⚙</span> Settings</button></div>';}
  function activeTemplates(){return templates.filter(([id])=>selected.has(id));}
  // Booster quantities are immediate batches. They never hide several hours
  // of waiting between candy and training; users add separate Wait rows.
  const maxCandy=cfg=>Math.max(1,Math.floor(cfg.boosterCapH*3600/
    Math.max(1,Math.round(1800*cfg.candyCDMultiplier)))+1);
  const maxDvd=cfg=>Math.max(1,Math.floor(cfg.boosterCapH*3600/
    Math.max(1,Math.round(21600*cfg.dvdCDMultiplier)))+1);
  const p={hours:28,boosterCapH:24,startDrugMin:0,startBoosterMin:0,xanaxCDMin:420,ecstasyCDMin:215,resetAfterSec:600,tornClockMin:720,candyCDMultiplier:1,dvdCDMultiplier:1,dvdHappy:2500,candyHappy:"any",autoWait:true,
    xanaxPrice:null,ecstasyPrice:null,candyPrice:null,dvdPrice:null,pointPrice:null};
  const $=v=>String(v==null?"":v).replace(/[&<>"']/g,x=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]));
  const n=(v,f=0)=>v===null||v===undefined||v===""||!Number.isFinite(Number(v))?f:Number(v);
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,n(v,a)));
  const fmt=(v,d=0)=>Number(v).toLocaleString(undefined,{maximumFractionDigits:d});
  const clock=v=>{const s=Math.max(0,Math.round(v));return Math.floor(s/3600)+":"+String(Math.floor(s/60)%60).padStart(2,"0")+":"+String(s%60).padStart(2,"0");};
  let ctx=null,loadedPlayer=null,liveDrug=false,liveBooster=false,cooldownsKnown=false,apiBoosterCap=null,manualBoosterCap=24;
  const candyTiers={"25":["Bag of Bon Bons","Bag of Chocolate Kisses","Box of Bon Bons","Box of Extra Strong Mints","Box of Sweet Hearts","Lollipop","Box of Chocolate Bars"],"35":["Big Box of Chocolate Bars"],"50":["Bag of Candy Kisses","Chocolate Egg"],"75":["Bag of Bloody Eyeballs","Bag of Tootsie Rolls"],"100":["Bag of Chocolate Truffles","Bag of Reindeer Droppings"],"150":["Bag of Humbugs","Bag of Sherbet","Jawbreaker","Pixie Sticks"],"250":["Birthday Cupcake"]};
  const keyName=value=>String(value||"").toLowerCase().replace(/[^a-z0-9]/g,"");
  const positive=value=>value!=null&&Number.isFinite(Number(value))&&Number(value)>0?Number(value):null;
  function itemList(){
    const raw=payload("itemCatalog","items");
    return Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
  }
  function marketPrice(item){
    return positive(item?.market_value??item?.value?.market_price??item?.value?.market_value??item?.market_price);
  }
  function candyStock(){
    const items=itemList(),inventory=tornGuideApi.state.inventory.Candy;
    const rows=(Array.isArray(inventory)&&!tornGuideApi.state.inventoryErrors?.Candy?inventory:[]).map(x=>{
      const item=items.find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id)||keyName(i.name)===keyName(x.name??x.item?.name));
      const name=x.name??x.item?.name??item?.name, tier=Object.keys(candyTiers).find(k=>candyTiers[k].some(v=>keyName(v)===keyName(name)));
      const text=String(item?.effect??item?.description??"");
      const matched=text.match(/(?:increases?|increased)\s+(?:your\s+)?happiness\s+by\s+(\d+)/i);
      const happy=Number(tier??matched?.[1]??0);
      return {name,happy,qty:Math.max(0,Math.floor(n(x.amount??x.quantity))),price:marketPrice(item)};
    }).filter(x=>x.happy>0&&x.qty>0);
    return {loaded:Array.isArray(inventory)&&!tornGuideApi.state.inventoryErrors?.Candy,rows,tiers:[...new Set(rows.map(x=>x.happy))].sort((a,b)=>a-b)};
  }
  function priceFor(name){
    return marketPrice(itemList().find(i=>keyName(i.name)===keyName(name)));
  }
  function marketInputs(){
    const stock=candyStock();
    
    p.xanaxPrice=priceFor("Xanax");p.ecstasyPrice=priceFor("Ecstasy");p.dvdPrice=priceFor("Erotic DVD");
    const points=payload("pointsCatalog","pointsmarket");
    const list=Array.isArray(points)?points:Object.values(points||{});
    const prices=list.map(x=>positive(x?.cost??x?.price??x?.cost_per_point)).filter(x=>x!==null);
    p.pointPrice=prices.length?Math.min(...prices):null;
    return stock;
  }
  function candyPool(cfg){
    const stock=candyStock();
    return stock.rows.filter(x=>cfg.candyHappy==="any"||x.happy===cfg.candyHappy).sort((a,b)=>b.happy-a.happy||(a.price??Infinity)-(b.price??Infinity)).map(x=>({...x}));
  }
  // One fixed-clock snapshot for all live consumers. Unknown refill status
  // reserves today's refill; a stale bar or cooldown is not a verified zero.
  function liveInputs(state,now=Date.now(),project){
    const stamps=state.fetchedAt??{},errors=state.errors??{},data=state.data??{};
    const bars=data.bars?.bars??data.bars,cd=data.cooldowns?.cooldowns??data.cooldowns;
    const number=x=>x==null||x===""||!Number.isFinite(Number(x))||Number(x)<0?null:Number(x);
    const stamp=k=>Number(stamps[k])||0;
    const fresh=(at,maxAge)=>at>0&&at<=now&&now-at<=maxAge;
    const bar=k=>{
      const bridge=state.bridge?.fields?.includes(k)&&Number(state.bridge.timestamp)>stamp("bars");
      const at=bridge?Number(state.bridge.timestamp):stamp("bars"),raw=bars?.[k];
      if((!bridge&&errors.bars)||!fresh(at,300000)||number(raw?.current)===null||!(number(raw?.maximum)>0))return null;
      const value=project(k,raw,at,now);
      return value?{...value,source:bridge?"bridge":"API",observedAt:at}:null;
    };
    const energy=bar("energy"),happy=bar("happy");
    const cooldown=k=>{
      const raw=cd?.[k],seconds=number(typeof raw==="object"?raw?.remaining??raw?.time_left:raw);
      return errors.cooldowns||!fresh(stamp("cooldowns"),300000)||seconds===null?null:Math.max(0,seconds-(now-stamp("cooldowns"))/1000);
    };
    const drug=cooldown("drug"),booster=cooldown("booster");
    const refill=data.refills?.refills??data.refills;
    const rawUsed=refill?.energy_refill_used??refill?.energy?.used;
    const refillUsed=!errors.refills&&fresh(stamp("refills"),86400000)&&Math.floor(stamp("refills")/86400000)===Math.floor(now/86400000)&&typeof rawUsed==="boolean"?rawUsed:null;
    const issues=[];
    if(!energy||!happy)issues.push("Energy or Happiness is missing or stale");
    if(drug===null||booster===null)issues.push("Drug or booster cooldown is missing or stale");
    if(refillUsed===null)issues.push("Today's refill status is unknown; today's refill is excluded");
    const money=data.money?.money??data.money;
    const moneyFresh=!errors.money&&fresh(stamp("money"),900000);
    const points=moneyFresh?number(money?.points?.current??money?.points):null;
    const wallet=moneyFresh?number(money?.wallet?.current??money?.wallet):null;
    if(points===null)issues.push("Owned points unknown; no points credit assumed");
    return {now,energy,happy,drug,booster,refillUsed,points:points===null?null:Math.floor(points),wallet,issues};
  }
  function readCooldowns(){
    const data=tornGuideApi.state.data.cooldowns;
    const cd=data?.cooldowns??data;
    const valid=v=>v!=null&&v!==""&&Number.isFinite(Number(v))&&Number(v)>=0;
    return cd&&typeof cd==="object"?{drug:valid(cd.drug)?Number(cd.drug)/60:null,booster:valid(cd.booster)?Number(cd.booster)/60:null}:null;
  }
  function detectedBoosterCap(){
    const data=tornGuideApi.state.data.cooldowns,cd=data?.cooldowns??data;
    const explicit=[cd?.booster_max,cd?.max_booster,cd?.booster_maximum,cd?.max_booster_cooldown];
    for(const value of explicit){
      if(value==null||value==="")continue;
      const v=Number(value);
      if(v>=86400&&v<=172800)return v/3600;
    }
    const raw=tornGuideApi.state.data.perks,perks=raw?.perks??raw;
    const faction=Object.entries(perks||{}).filter(([k])=>/faction/i.test(k)).flatMap(([,v])=>Array.isArray(v)?v:[]);
    for(const entry of faction){
      const t=typeof entry==="string"?entry:[entry?.name,entry?.effect,entry?.description].filter(Boolean).join(" ");
      if(!/booster/i.test(t)||!/cooldown/i.test(t)||!/maximum|max\b|capacity|limit|cap\b/i.test(t))continue;
      const to=t.match(/(?:to|of|:)\s*(\d+(?:\.\d+)?)\s*(?:hours?|h\b)/i);
      const add=t.match(/(?:\+|by\s+)\s*(\d+(?:\.\d+)?)\s*(?:hours?|h\b)/i);
      const percent=t.match(/(?:\+|by\s+)\s*(\d+(?:\.\d+)?)\s*%/i);
      const value=to?Number(to[1]):add?24+Number(add[1]):percent?24*(1+Number(percent[1])/100):null;
      if(value!==null&&value>=24&&value<=48)return value;
    }
    return null;
  }
  function loadLive(force=false){
    const id=tornGuideApi.state.identity?.id??null;
    if(loadedPlayer!==id){loadedPlayer=id;liveDrug=false;liveBooster=false;manualBoosterCap=24;}
    const cd=readCooldowns();
    cooldownsKnown=cd!==null;
    if(cd?.drug==null)liveDrug=false;
    if(cd?.booster==null)liveBooster=false;
    apiBoosterCap=detectedBoosterCap();p.boosterCapH=apiBoosterCap??manualBoosterCap;
    const stamp=Number(tornGuideApi.state.fetchedAt?.cooldowns);
    const elapsed=Number.isFinite(stamp)&&stamp>0?Math.max(0,(Date.now()-stamp)/60000):0;
    p.startDrugMin=liveDrug?Math.max(0,cd.drug-elapsed):0;
    p.startBoosterMin=liveBooster?Math.max(0,cd.booster-elapsed):0;
    const now=new Date();
    p.tornClockMin=now.getUTCHours()*60+now.getUTCMinutes()+now.getUTCSeconds()/60;
    p.resetAfterSec=900-(now.getUTCMinutes()%15*60+now.getUTCSeconds());
  }
  function cooldownControls(){
    const cd=readCooldowns();
    const toggle=(kind,on,available)=>'<button type="button" class="button secondary" data-ts-cooldown-mode="'+kind+'" aria-pressed="'+on+'" '+(!available?"disabled":"")+'>'+(on?"Live ":"0 ")+(kind==="drug"?"Drug":"Booster")+' CD</button>';
    const cap=apiBoosterCap===null?'<button type="button" class="button secondary" data-ts-cap="toggle" aria-pressed="'+(p.boosterCapH===48)+'">Max '+p.boosterCapH+'H Booster</button>':'<span title="Maximum booster cooldown detected from API">Max '+fmt(apiBoosterCap,2)+'H Booster</span>';
    return '<div class="ts-cooldown-mode">'+toggle("drug",liveDrug,cd?.drug!=null)+toggle("booster",liveBooster,cd?.booster!=null)+cap+'</div>';
  }
  function activePerks(){
    const val=tornGuideApi.state.data.perks;
    const collections=val&&(val.perks||val);
    if(!collections||typeof collections!=="object")return [];
    return Object.values(collections).flatMap(value=>Array.isArray(value)?value:[]).map(v=>typeof v==="string"?v:v&&(v.name||v.effect||v.description)||"").filter(v=>/cooldown|voracity|metabolism|erotic dvd|candy/i.test(v));
  }
  function energyRules(){
    const live=ctx?.liveEnergy;
    if(live&&Number.isFinite(live.maximum)&&live.maximum>0){
      const interval=Number.isFinite(live.interval)&&live.interval>0?live.interval:live.maximum>=150?600:900;
      const step=Number.isFinite(live.step)&&live.step>0?live.step:5;
      const firstTick=Number.isFinite(live.nextTick)&&live.nextTick>=0&&live.nextTick<=interval?Math.max(1,Math.ceil(live.nextTick)):interval;
      return {cap:live.maximum,minutes:interval/60,step,firstTick,mode:"live",label:live.phaseSource==="API"?"Observed regeneration phase":"Estimated regeneration phase"};
    }
    const profile=payload("profile","profile");
    const known=profile&&Object.prototype.hasOwnProperty.call(profile,"donator_status");
    const status=String(profile?.donator_status||"").toLowerCase();
    const observed=Number(ctx?.state?.maxEnergy);
    const premium=known?status==="donator"||status==="subscriber":observed>=150;
    return {cap:premium?150:100,minutes:premium?10:15,mode:"auto",label:known?(premium?profile.donator_status:"Standard"):"Estimated from energy bar"};
  }
  function nervePreview(config){
    const source=tornGuideApi.state.data.bars;
    const value=source&&(source.bars||source),nerve=value&&value.nerve;
    if(!nerve||!Number.isFinite(Number(nerve.maximum))||!Number.isFinite(Number(nerve.current)))return "Nerve: +1 every 5 minutes regardless of Donator or Subscriber status (current bar unavailable).";
    const current=Math.max(0,Number(nerve.current)),cap=Math.max(1,Number(nerve.maximum));
    const final=Math.min(cap,current+Math.floor(config.hours*60/5));
    return "Nerve "+fmt(current)+" / "+fmt(cap)+"; passive-only estimate after "+fmt(config.hours)+"h: "+fmt(final)+
      " / "+fmt(cap)+" (+1 every 5 minutes, no crimes or refills simulated).";
  }
  function createEngine(overrides,planning=false){
    const cfg={...p,...overrides},base=ctx.state.statValues[ctx.state.compareStat];
    const bliss=tornHappinessBook().active; // Shared detection for default action generation and fixed-plan replay.
    const stock=candyStock(),pool=stock.rows.map(x=>({...x,initialQty:x.qty})).sort((a,b)=>b.happy-a.happy||(a.price??Infinity)-(b.price??Infinity));
    const dvdInventory=tornGuideApi.state.inventory.Booster;
    const dvdKnown=Array.isArray(dvdInventory)&&!tornGuideApi.state.inventoryErrors?.Booster;
    const dvdHeld=dvdKnown?dvdInventory.filter(x=>keyName(x.name??x.item?.name??itemList().find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id))?.name)===keyName("Erotic DVD")).reduce((sum,x)=>sum+Math.max(0,Math.floor(n(x.amount??x.quantity))),0):null;
    const rowInfo={},notices=[],actionStates={};let rowCandy=null,rowUsed=null;
    let candyGain=0;
    const gym=ctx.gym,stat=ctx.state.compareStat,limit=cfg.limitSeconds??Math.floor(cfg.hours*3600);
    const rule=energyRules(),eCap=rule.cap;
    const boosterLimit=cfg.boosterCapH*3600;
    const regenTime=rule.minutes*60,regenStep=rule.step??5,firstEnergyTick=rule.firstTick??regenTime;
    const gymCost=Math.max(1,Math.floor(gym.energy));
    const mult=ctx.effectsFor(stat).multiplier;
    const initialE=cfg.startEnergy==="zero"?0:cfg.startEnergy==="full"?eCap:Math.min(Math.max(0,ctx.state.currentEnergy),1000);
    const v={time:0,stat:base,energy:initialE,happy:ctx.state.happy,drug:Math.round(cfg.startDrugMin*60),booster:Math.round(cfg.startBoosterMin*60),
      costs:{xanax:0,ecstasy:0,dvd:0,candy:0,refill:0,externalHappy:0},used:0,log:[],errors:[],series:[{h:0,s:base}],days:new Set(),lostRegen:0,warnings:[]};
    const snap=()=>({time:v.time,energy:v.energy,happy:v.happy,drug:v.drug,booster:v.booster,stat:v.stat});
    if(cfg.refillUsedToday)v.days.add(Math.floor(cfg.tornClockMin*60/86400));
    const initial=snap();
    const canTrain=n(gym[stat])>0&&gymCost<=eCap;
    const nextEnergyTick=()=>v.time<firstEnergyTick?firstEnergyTick:firstEnergyTick+(Math.floor((v.time-firstEnergyTick)/regenTime)+1)*regenTime;
    function fullEnergyDelay(){
      const ticks=Math.max(0,Math.ceil((eCap-v.energy)/regenStep));
      return ticks?nextEnergyTick()+(ticks-1)*regenTime-v.time:0;
    }
    v.peakHappy=v.happy;
    const point=()=>{v.peakHappy=Math.max(v.peakHappy,v.happy);const last=v.series[v.series.length-1],h=v.time/3600;if(Math.abs(last.h-h)<1e-8)last.s=v.stat;else v.series.push({h,s:v.stat});};
    function train(maxEnergy=Infinity){
      if(v.energy<gymCost || n(gym[stat])<=0)return 0;
      const available=Math.min(v.energy,Math.max(0,Math.floor(maxEnergy/gymCost)*gymCost));
      if(available<gymCost)return 0;
      const out=ctx.trainBlock(v.stat,v.happy,available,gym,stat,mult);
      v.energy-=out.used;v.happy=out.happy;v.stat=out.stat;v.used+=out.used;
      return out.used;
    }
    function advance(duration){
      const until=Math.min(limit,v.time+Math.max(0,Math.ceil(duration)));
      while(v.time<until){
        const eTick=nextEnergyTick();
        const first=Math.max(1,Math.round(cfg.resetAfterSec));
        const hTick=first+Math.max(0,Math.floor((v.time-first)/900)+1)*900;
        const drugTick=v.drug>0?v.time+v.drug:Infinity;
        const next=Math.min(until,eTick,hTick,drugTick),passed=next-v.time;
        v.time=next;v.drug=Math.max(0,v.drug-passed);v.booster=Math.max(0,v.booster-passed);
        if(next===eTick){if(v.energy<eCap)v.energy=Math.min(eCap,v.energy+regenStep);else v.lostRegen+=regenStep;}
        if(next===hTick){const before=v.happy,start=snap();v.happy=bliss?Math.min(99999,before+5):before>ctx.state.maxHappy?ctx.state.maxHappy:Math.min(ctx.state.maxHappy,before+5);if(!bliss&&before>ctx.state.maxHappy)v.log.push({i:"•",type:"happyReset",parent:rowIndex,reason:"Quarter-hour reset",start,end:snap()});}
        if(next===hTick||next===until||next%3600===0)point();
      }
    }
    let rowIndex=-1,cutoff=false;
    function waitFor(seconds,label,requireAutoWait=true){
      if(seconds<=0)return true;
      if((label.startsWith("Drug cooldown")&&cfg.startDrugMin*60>v.time&&v.costs.xanax+v.costs.ecstasy===0)||(label==="Booster cooldown"&&cfg.startBoosterMin*60>v.time&&v.costs.candy+v.costs.dvd===0))notices.push({index:rowIndex,critical:true,text:"DELAY "+clock(seconds)+" · "+label});
      if(requireAutoWait&&!cfg.autoWait){v.errors.push(label+" blocked ("+clock(seconds)+" left).");return false;}
      const target=v.time+Math.ceil(seconds),start=snap();
      advance(seconds);
      v.log.push({i:"•",type:"autoWait",parent:rowIndex,reason:label,start,end:snap()});
      if(target>limit){cutoff=true;return false;}
      return true;
    }
    function useItem(type){
      if(type==="xanax"||type==="ecstasy"){
        if(type==="xanax"){
          v.energy=Math.min(1000,v.energy+250);v.happy=Math.min(99999,v.happy+75);
          v.drug=Math.round(cfg.xanaxCDMin*60);
        }else{v.happy=Math.min(99999,v.happy*2);v.drug=Math.round(cfg.ecstasyCDMin*60);}
        v.costs[type]++;
      }else{
        // A final booster is allowed at the cap, with zero simulated time between items.
        if(v.booster>boosterLimit&&!waitFor(v.booster-boosterLimit,"Booster cooldown"))return false;
        let candy=null;
        if(type==="candy"){
          candy=rowCandy.find(x=>x.qty>0);
          if(!candy){
            if(planning)return true; // Inventory availability must not hide later editable actions.
            v.errors.push(stock.loaded?"Insufficient candy in inventory for the selected Max Happy tier.":"Candy inventory not loaded.");return false;
          }
          candy.qty--;candyGain+=candy.happy;rowUsed[candy.name]=(rowUsed[candy.name]||0)+1;
        }
        const secs=type==="dvd"?21600*cfg.dvdCDMultiplier:1800*cfg.candyCDMultiplier;
        v.booster+=Math.round(secs);
        v.happy=Math.min(99999,v.happy+(type==="dvd"?cfg.dvdHappy:candy.happy));
        v.costs[type]++;
      }
      return true;
    }
    function execute(a,i,{beforeEcstasy=false,beforeXanax=false,automatic=false,midnightRefill=false,boostedRefill=false}={}){
      if(v.errors.length||cutoff)return false;
      rowIndex=i;
      const {type}=a;
      // Wait BEFORE happiness boosters when an Ecstasy action is next, so a
      // drug cooldown does not waste the boost at a quarter-hour reset.
      if(beforeEcstasy&&!waitFor(v.drug,"Drug cooldown before happiness boost"))return false;
      const isBooster=type==="candy"||type==="dvd",tier=a.candyHappy??cfg.candyHappy;
      rowCandy=pool.filter(x=>tier==="any"||x.happy===tier);rowUsed={};
      const itemCD=Math.max(1,Math.round(type==="dvd"?21600*cfg.dvdCDMultiplier:1800*cfg.candyCDMultiplier));
      if(type==="dvd"&&!a.max&&!cfg.allowPartialDvd&&a.qty>0){
        const batch=Math.floor(a.qty),maxBatch=Math.floor(boosterLimit/itemCD)+1;
        if(batch>maxBatch){v.errors.push("The requested DVD batch exceeds the booster cap.");return false;}
        const delay=Math.max(0,v.booster-boosterLimit+(batch-1)*itemCD);
        if(delay&&!waitFor(delay,"Booster cooldown for full DVD batch"))return false;
      }
      let allowance=v.booster>boosterLimit?0:Math.floor((boosterLimit-v.booster)/itemCD)+1;
      const held=type==="candy"?(stock.loaded?rowCandy.reduce((sum,x)=>sum+x.qty,0):null):dvdKnown?Math.max(0,dvdHeld-v.costs.dvd):null;
      if(isBooster&&allowance===0&&cfg.startBoosterMin*60>v.time&&v.costs.candy+v.costs.dvd===0&&(a.max?held>0:a.qty>0)){const delay=v.booster-boosterLimit;if(!waitFor(delay,"Booster cooldown"))return false;allowance=Math.floor((boosterLimit-v.booster)/itemCD)+1;}
      if(!bliss&&(type==="externalHappy"||isBooster&&allowance>0&&(a.max?held>0:a.qty>0))){
        const delay=happyResetWait(v.time,Math.max(1,Math.round(cfg.resetAfterSec)));
        if(delay&&!waitFor(delay,"Happiness reset"))return false;
        allowance=Math.floor((boosterLimit-v.booster)/itemCD)+1;
      }
      const maximum=held===null?null:Math.min(held,allowance);
      const baselineAllowance=Math.floor(boosterLimit/itemCD)+1;
      if(isBooster&&cfg.startBoosterMin*60>v.time&&v.costs.candy+v.costs.dvd===0&&allowance<baselineAllowance&&(a.max?held!=null&&held>allowance:a.qty>allowance)){
        const target=a.max?Math.min(held,baselineAllowance):a.qty;
        if(allowance>0)notices.push({index:i,critical:false,text:(type==="candy"?"Candy":"eDVD")+" CD "+clock(v.booster)+" · "+Math.min(allowance,target)+" / "+target+" possible"});
      }
      const qty=isBooster?(a.max?(maximum??0):Math.floor(clamp(a.qty,0,allowance))):1;
      if(isBooster)rowInfo[i]={maximum,allowance,held,qty,used:rowUsed,tier,happy:0,dvdBefore:v.costs.dvd};
      if(isBooster&&a.max&&maximum===null&&!planning){v.errors.push("MAX requires loaded inventory.");return false;}
      if((type==="xanax"||type==="ecstasy")&&!waitFor(v.drug,"Drug cooldown"))return false;
      // Live scheduling only: a dose may not overrun the hard clearance
      // deadline, even if its immediate training gain would be attractive.
      if(cfg.requireDrugClear&&["xanax","ecstasy"].includes(type)){
        const duration=type==="xanax"?Math.max(cfg.xanaxCDMin*60,cfg.warXanaxSeconds??28800):Math.max(cfg.ecstasyCDMin*60,14400);
        if(v.time+duration>limit){cutoff=true;return false;}
      }
      if(type==="train"){
        if(a.when==="full"&&!waitFor(fullEnergyDelay(),"Full Energy",false))return false;
        if(a.when==="drug"&&beforeXanax&&!waitFor(v.drug,"Drug cooldown before Xanax"))return false;
      }
      if(type==="refill"){
        const used=v.days.has(tornDay());
        if(used&&(boostedRefill||cfg.skipUsedRefill)){
          notices.push({index:i,text:boostedRefill?"Refill skipped: already used today. Train before Happiness resets.":"Refill skipped: already used today."});
          return true;
        }
        if(v.energy>=eCap){
          notices.push({index:i,text:"Refill skipped: Energy is already full or stacked."});
          return true;
        }
        if(used&&!waitFor((tornDay()+1)*86400-cfg.tornClockMin*60-v.time,"Daily points refill"))return false;
        if(v.energy>=eCap){
          notices.push({index:i,text:"Refill skipped: Energy regenerated to full while waiting."});
          return true;
        }
      }
      const start=snap();
      if(["xanax","ecstasy","dvd","candy"].includes(type)){
        for(let k=0;k<qty;k++){
          if(!useItem(type))break;
        }
      }else if(type==="externalHappy"){
        v.happy=Math.max(v.happy,50000);
        v.costs.externalHappy++;
        const warning="99k assumes coordinated Poison Mistletoe use at an estimated $200 million per boost.";
        if(!v.warnings.includes(warning))v.warnings.push(warning);
      }else if(type==="train")train(a.energyLimit??Infinity);
      else if(type==="wait"){
        const seconds=a.untilDrug?v.drug:Math.max(0,Math.ceil(n(a.minutes)*60));
        cutoff=v.time+seconds>limit;
        advance(seconds);
      }
      else if(type==="refill"){
        v.days.add(tornDay());v.energy=eCap;v.costs.refill++;
      }else{v.errors.push("Unrecognized action: "+type);}
      if(isBooster)rowInfo[i].happy=type==="dvd"?(v.costs.dvd-rowInfo[i].dvdBefore)*cfg.dvdHappy:Object.entries(rowUsed).reduce((sum,[name,q])=>sum+q*(pool.find(x=>x.name===name)?.happy??0),0);
      point();
      const executed=!v.errors.length&&!cutoff,end=snap();
      actionStates[i]={start,end,executed};
      if(executed)v.log.push({i:i+1,type,parent:i,editable:!automatic,midnightRefill,start,end,consumedValue:type==="candy"?(Object.entries(rowUsed).some(([name,q])=>q>0&&pool.find(x=>x.name===name)?.price==null)?null:Object.entries(rowUsed).reduce((sum,[name,q])=>sum+q*(pool.find(x=>x.name===name)?.price??0),0)):undefined,reason:type==="wait"&&a.untilDrug?"Drug cooldown":undefined,quantity:isBooster?(type==="candy"?Object.values(rowUsed).reduce((sum,q)=>sum+q,0):v.costs.dvd-rowInfo[i].dvdBefore):1});
      return executed;
    }
    function tornDay(){return Math.floor((cfg.tornClockMin*60+v.time)/86400);}
    const untilMidnight=()=>Math.ceil((tornDay()+1)*86400-cfg.tornClockMin*60-v.time);
    const midnightRefillDays=new Set();
    function addMidnightRefill(parent){
      const wait=untilMidnight();
      if(wait>midnightWindow||v.time+wait>limit||v.energy>=gymCost||!canTrain)return;
      rowIndex=parent;
      if(!waitFor(wait,"TCT midnight",false))return;
      const before=v.costs.refill;
      if(!execute(make("refill"),parent,{automatic:true,midnightRefill:true})||v.costs.refill===before)return;
      midnightRefillDays.add(tornDay());
      execute(make("train"),parent,{automatic:true});
    }
    function run(list,{midnightJump=cfg.midnightJump}={}){
      let jumpBoosted=false,refillDay=null;
      for(let i=0;i<list.length;i++){
        const type=list[i].type;
        if(type==="refill"&&midnightRefillDays.has(tornDay())){notices.push({index:i,text:"Refill skipped: today’s refill was used at midnight."});continue;}
        const next=["candy","dvd","externalHappy"].includes(type)&&list.slice(i+1).find(x=>["xanax","ecstasy","train","refill"].includes(x.type));
        const happyBefore=v.happy,dayBefore=tornDay(),usedBefore=v.days.has(dayBefore);
        const refillsBefore=v.costs.refill;
        if(!execute(list[i],i,{beforeEcstasy:next?.type==="ecstasy",beforeXanax:list[i+1]?.type==="xanax",boostedRefill:jumpBoosted&&list[i-1]?.type==="train"}))return false;
        if(["candy","dvd","externalHappy"].includes(type)&&v.happy>happyBefore)jumpBoosted=true;
        if(type==="refill")refillDay=v.costs.refill>refillsBefore&&jumpBoosted&&!usedBefore&&dayBefore===tornDay()?dayBefore:null;
        if(type==="train"&&list[i-1]?.type==="refill"&&refillDay===tornDay()&&midnightJump&&cfg.autoWait){
          addMidnightRefill(i+1);
          refillDay=null;
        }
      }
      return true;
    }
    function finish(list,{tail=true}={}){
      rowIndex=list.length;
      if(tail){
        advance(limit-v.time);
        const start=snap();
        if(train()>0)v.log.push({i:"•",type:"train",parent:rowIndex,reason:"End of comparison · remaining Energy",start,end:snap()});
      }
      point();
      if(cutoff&&!v.warnings.includes("The comparison window ended before all actions could run."))v.warnings.push("The comparison window ended before all actions could run.");
      const consumed=[
        {name:"Xanax",quantity:v.costs.xanax,price:cfg.xanaxPrice},
        {name:"Ecstasy",quantity:v.costs.ecstasy,price:cfg.ecstasyPrice},
        {name:"eDVD",quantity:v.costs.dvd,price:cfg.dvdPrice},
        {name:"Points",quantity:v.costs.refill*30,price:cfg.pointPrice},
        {name:"99k happiness boost",quantity:v.costs.externalHappy,price:externalHappyCost},
        ...pool.map(({name,initialQty,qty,price})=>({name,quantity:initialQty-qty,price}))
      ].filter(item=>item.quantity>0);
      return {...v,final:v.stat,gain:v.stat-base,complete:v.errors.length===0,candyGain,rowInfo,notices,actionStates,initial,consumed,
        money:consumed.some(item=>item.price==null)?null:consumed.reduce((sum,item)=>sum+item.quantity*item.price,0)};
    }
    // Branching at a terminal cycle must carry the exact cooldown, inventory,
    // refill-day and action-log state, not create a fresh player.
    function snapshot(){
      return {state:{...v,costs:{...v.costs},log:v.log.slice(),errors:v.errors.slice(),warnings:v.warnings.slice(),series:v.series.map(x=>({...x})),days:new Set(v.days)},
        quantities:pool.map(x=>x.qty),rowInfo:{...rowInfo},notices:notices.slice(),actionStates:{...actionStates},
        candyGain,rowIndex,cutoff,midnightDays:[...midnightRefillDays]};
    }
    function restore(saved){
      const s=saved.state;
      Object.assign(v,s,{costs:{...s.costs},log:s.log.slice(),errors:s.errors.slice(),warnings:s.warnings.slice(),series:s.series.map(x=>({...x})),days:new Set(s.days)});
      pool.forEach((x,i)=>x.qty=saved.quantities[i]);
      for(const key of Object.keys(rowInfo))delete rowInfo[key];Object.assign(rowInfo,saved.rowInfo);
      for(const key of Object.keys(actionStates))delete actionStates[key];Object.assign(actionStates,saved.actionStates);
      notices.splice(0,notices.length,...saved.notices);
      candyGain=saved.candyGain;rowIndex=saved.rowIndex;cutoff=saved.cutoff;rowCandy=null;rowUsed=null;
      midnightRefillDays.clear();for(const day of saved.midnightDays)midnightRefillDays.add(day);
    }
    return {state:v,limit,gymCost,canTrain,fullEnergyDelay,advance,waitFor,execute,run,finish,snapshot,restore,tornDay,untilMidnight,get cutoff(){return cutoff;}};
  }
  function trainingPurchases(pointsHeld=0,{excludeOwned=true,reserveXanax=0}={}){
    const items=itemList();
    const owned=(name,category)=>{
      const list=tornGuideApi.state.inventory[category];
      if(!excludeOwned)return 0;
      if(!Array.isArray(list)||tornGuideApi.state.inventoryErrors?.[category])return 0;
      return list.reduce((sum,item)=>{
        const id=item.id??item.item_id??item.item?.id;
        const itemName=item.name??item.item?.name??items.find(entry=>String(entry.id)===String(id))?.name;
        return keyName(itemName)===keyName(name)?sum+Math.max(0,Math.floor(n(item.amount??item.quantity))):sum;
      },0);
    };
    const supplies=[
      ["xanax","Xanax",Math.max(0,owned("Xanax","Drug")-reserveXanax),p.xanaxPrice,1],
      ["ecstasy","Ecstasy",owned("Ecstasy","Drug"),p.ecstasyPrice,1],
      ["dvd","Erotic DVD",owned("Erotic DVD","Booster"),p.dvdPrice,1],
      ["refill","Points",pointsHeld,p.pointPrice,30],
      ["externalHappy","99k happiness boost",0,externalHappyCost,1]
    ];
    return costs=>{
      const items=supplies.map(([type,name,held,price,units])=>({name,quantity:Math.max(0,(costs[type]??0)*units-held),price})).filter(item=>item.quantity>0);
      const cost=items.some(item=>item.price==null)?null:items.reduce((sum,item)=>sum+item.quantity*item.price,0);
      return {items,cost};
    };
  }
  function periodPurchases(periods,confirmed=[]){
    const old={...p};
    try{
      marketInputs();
      const balance=tornGuideApi.state.errors?.money?null:payload("money","money")?.points;
      const pointsHeld=Math.floor(positive(balance?.current??balance)??0);
      const purchases=trainingPurchases(pointsHeld);
      return periods.map(period=>{
        if(!period.costs)return period;
        const remaining={...period.costs};
        for(const action of confirmed){
          if(action.at<=period.days*86400&&Object.hasOwn(remaining,action.type)){
            remaining[action.type]=Math.max(0,remaining[action.type]-(action.quantity??1));
          }
        }
        return {...period,...purchases(remaining)};
      });
    }finally{Object.assign(p,old);}
  }
  // Home recommendations replay the same saved/default Plan templates with
  // one continuous weekly engine; no independent strategy definitions.
  function trainingExecution(log){
    return log.filter(x=>x.type!=="happyReset").map(x=>({type:x.type,at:x.start.time,end:x.end.time,quantity:x.quantity??1,energy:x.type==="train"?Math.max(0,x.start.energy-x.end.energy):null,before:{energy:x.start.energy,happy:x.start.happy,drug:x.start.drug,booster:x.start.booster,stat:x.start.stat},after:{energy:x.end.energy,happy:x.end.happy,drug:x.end.drug,booster:x.end.booster,stat:x.end.stat},reason:x.reason??null,midnightRefill:x.midnightRefill||undefined}));
  }
  function weeklyPrograms(context,budget,risk,options={}){
    const previous=ctx,old={...p};
    try{
      ctx=context;loadPlanPreferences();marketInputs();applyCooldownPerks();
      const live=options.liveInputs,now=new Date(live?.now??Date.now()),cd=readCooldowns(),stamp=Number(tornGuideApi.state.fetchedAt?.cooldowns),elapsed=stamp>0?Math.max(0,(now-stamp)/60000):0;
      if(live&&(!live.energy||!live.happy))return [];
      if(live)ctx={...context,liveEnergy:live.energy};
      if(!options.naturalOnly&&(budget==null||(live?(live.drug===null||live.booster===null):(cd?.drug==null||cd?.booster==null||!stamp||tornGuideApi.state.errors?.cooldowns))))return [];
      const clockMin=now.getUTCHours()*60+now.getUTCMinutes()+now.getUTCSeconds()/60;
      Object.assign(p,{startDrugMin:live?(live.drug??0)/60:Math.max(0,(cd?.drug??0)-elapsed),startBoosterMin:live?(live.booster??0)/60:Math.max(0,(cd?.booster??0)-elapsed),boosterCapH:detectedBoosterCap()??24,candyHappy:"any",tornClockMin:clockMin,resetAfterSec:900-(now.getUTCMinutes()%15*60+now.getUTCSeconds()),autoWait:true});
      const cash=Math.max(0,Number(budget)||0),excludeOwned=options.excludeOwned!==false;
      const deadline=Number.isFinite(options.deadline)?options.deadline:null;
      const end=deadline===null?604800:Math.min(604800,Math.floor((deadline-now.getTime())/1000)-60);
      if(end<=0)return [];
      const bounded=end<604800,requireDrugClear=bounded&&!!options.requireDrugClear;
      const pointsHeld=live?.points??0,reserveXanax=Math.max(0,Number(options.reserveXanax)||0);
      const purchases=trainingPurchases(pointsHeld,{reserveXanax});
      const cashCost=(result,engine)=>excludeOwned?purchases(result.costs).cost:engine?engine.finish([],{tail:false}).money:result.money;
      const actionsFor=id=>id==="natural"?cycleActions("natural"):editedPlans.has(id)?steps[id]:cycleActions(id);
      const ids=templates.map(([id])=>id).filter(id=>id==="natural"||!options.naturalOnly&&!excludedPlans.budget.has(id)&&(id!=="custom"||editedPlans.has(id))&&actionsFor(id).length&&!actionsFor(id).some(x=>options.blockDrugs&&["xanax","ecstasy"].includes(x.type)||x.type==="dvd"&&id!=="jump"||x.type==="externalHappy"&&id!=="maxhappy"));
      const projection={actionsFor,respectOffset:false,refillUsedToday:live?live.refillUsed!==false:energyRefillUsedToday(now),skipUsedRefill:true,requireDrugClear,warXanaxSeconds:options.warXanaxSeconds??28800,partialBudget:cash,partialOptions:{priceOf:cashCost,blockDrugs:!!options.blockDrugs}};
      const natural=mixedProjection(["natural"],end,{...projection,repeatLast:true});
      const candidates=ids.map(id=>id==="natural"?{id,data:natural}:{id});
      const proposal=ids.length===1?{data:natural}:optimizeChart(candidates,48,end,cash,[],{projection,priceOf:cashCost,minDepth:Math.max(4,Math.ceil(end/18000)),finishWindow:true});
      const data=proposal?.data;
      if(!data||data.errors.length||cashCost(data)==null||cashCost(data)>cash)return [];
      if(requireDrugClear&&data.log.some(e=>["xanax","ecstasy"].includes(e.type)&&e.start.time+(e.type==="xanax"?Math.max(p.xanaxCDMin*60,options.warXanaxSeconds??28800):Math.max(p.ecstasyCDMin*60,14400))>end))return [];
      const sequence=[...data.segments.map(s=>({id:s.id,start:s.start,at:s.at,gain:s.gain})),...(data.partialSegment?[{...data.partialSegment,partial:true}]:[])];
      const first=sequence[0],firstData=data.firstCycle;
      if(!first||!firstData)return [];
      const cycleExecution=trainingExecution(firstData.log),execution=trainingExecution(data.log);
      if(!cycleExecution.some(x=>x.type==="train"&&x.energy>0))return [];
      const id=first.id,label=templates.find(x=>x[0]===id)?.[2]??id;
      const selected={id,label,source:options.naturalOnly?"natural":"optimal-budget",sequence,gain:data.gain,money:data.money,cashCost:cashCost(data),excludeOwned,used:data.used,costs:data.costs,cycles:data.segments.length,drugRisk:firstData.costs.xanax+firstData.costs.ecstasy>0,startEnergy:"current",generatedAt:now.getTime(),horizonSeconds:end,deadline:bounded?deadline:null,execution,cycleExecution,cycleSpend:cashCost(firstData),timing:{xanaxCD:Math.round(p.xanaxCDMin*60),ecstasyCD:Math.round(p.ecstasyCDMin*60),boosterCap:p.boosterCapH*3600,candyCD:Math.round(1800*p.candyCDMultiplier),dvdCD:Math.round(21600*p.dvdCDMultiplier)}};
      const forecastDays=options.restockForecastDays;
      const horizons=[...new Set([1,7,28,...(Number.isInteger(forecastDays)&&forecastDays>=1&&forecastDays<=28?[forecastDays]:[])])];
      const periodFor=days=>{
        if(bounded&&days*86400>end)return {days,gain:null,value:null,energy:null,costs:null};
        if(days===7)return {days,gain:data.gain,value:data.money,energy:data.used,costs:data.costs};
        if(days<7){
          const events=data.log.filter(e=>e.end.time<=days*86400);
          const costs={xanax:0,ecstasy:0,dvd:0,candy:0,refill:0,externalHappy:0};let energy=0,value=0,known=true;
          for(const e of events){
            if(e.type==="train")energy+=Math.max(0,e.start.energy-e.end.energy);
            if(Object.hasOwn(costs,e.type)){
              const qty=e.quantity??1;costs[e.type]+=qty;
              const unit={xanax:p.xanaxPrice,ecstasy:p.ecstasyPrice,dvd:p.dvdPrice,refill:p.pointPrice==null?null:p.pointPrice*30,externalHappy:externalHappyCost}[e.type];
              const price=e.type==="candy"?e.consumedValue:unit==null?null:unit*qty;
              if(qty&&price==null)known=false;else value+=price??0;
            }
          }
          return {days,gain:(events.at(-1)?.end.stat??data.initial.stat)-data.initial.stat,value:known?value:null,energy,costs};
        }
        // Conditional repeat forecast, with continuous inventory and cooldown
        // state; do not publish estimates that exceed the rolling budget.
        const ids=sequence.map(s=>s.id);
        const result=mixedProjection(Array.from({length:Math.ceil(days/7)},()=>ids).flat(),days*86400,{...projection,repeatLast:true,partialBudget:null});
        const peak=weeklyPurchaseCost({excludeOwned,pointsHeld,reserveXanax})(result);
        if(result.errors.length||peak==null||peak>cash||result.elapsed<days*86400)return {days,gain:null,value:null,energy:null,costs:null};
        return {days,gain:result.gain,value:result.money,energy:result.used,costs:result.costs};
      };
      const periods=horizons.map(periodFor);
      selected.periods=periods.filter(period=>[1,7,28].includes(period.days));
      if(forecastDays!=null)selected.restockCosts=bounded&&forecastDays*86400>=end?data.costs:periods.find(x=>x.days===forecastDays)?.costs??null;
      return [selected];
    }finally{ctx=previous;Object.assign(p,old);}
  }
  // Re-simulate the unconfirmed suffix only, using the current account snapshot.
  // Preserve the strategy/order; proposals never mutate the saved session.
  function replayRemaining(context,session,options={}){
    const previous=ctx,old={...p};
    try{
      ctx=context;loadPlanPreferences();marketInputs();applyCooldownPerks();
      const now=new Date(),cd=readCooldowns(),stamp=Number(tornGuideApi.state.fetchedAt?.cooldowns),elapsed=stamp>0?Math.max(0,(now-stamp)/60000):0;
      if(cd?.drug==null||cd?.booster==null)return {error:"Cooldown data unavailable"};
      const remaining=session.actions.slice(session.index);
      if(!remaining.length)return {actions:[],gain:0,money:0,cashCost:0,used:0,generatedAt:now.getTime()};
      if(options.blockDrugs&&remaining.some(x=>["xanax","ecstasy"].includes(x.type)))return {error:"Drug restriction active"};
      const clockMin=now.getUTCHours()*60+now.getUTCMinutes()+now.getUTCSeconds()/60;
      const drugMin=Math.max(0,cd.drug-elapsed,((session.drugUntil||0)-now)/60000),boosterMin=Math.max(0,cd.booster-elapsed,((session.boosterUntil||0)-now)/60000);
      const cfg={hours:Math.min(336,Math.max(24,((remaining.at(-1)?.at??0)-(remaining[0]?.at??0))/3600+48)),startEnergy:"current",autoWait:true,startDrugMin:drugMin,startBoosterMin:boosterMin,boosterCapH:detectedBoosterCap()??manualBoosterCap,tornClockMin:clockMin,resetAfterSec:900-(now.getUTCMinutes()%15*60+now.getUTCSeconds()),refillUsedToday:session.refillDay===Math.floor(now/86400000)||energyRefillUsedToday(now)};
      const engine=createEngine(cfg),v=engine.state,executed=[];
      for(let i=0;i<remaining.length;i++){
        const row=remaining[i],next=remaining[i+1],type=row.type;
        if(!Object.hasOwn(names,type))return {error:"Unsupported remaining action: "+type};
        // Preserve intentional non-cooldown spacing, but let live CD state determine drug readiness.
        const prev=remaining[i-1];
        if(prev&&!["xanax","ecstasy","candy","dvd","refill"].includes(type)&&type!=="train")engine.advance(Math.max(0,row.at-prev.at));
        if(type==="train"){
          const wanted=Math.max(engine.gymCost,Number(row.energy)||engine.gymCost);
          if(wanted>context.state.maxEnergy&&v.energy<wanted)return {error:"Stacked Energy changed; refresh and replan"};
          if(next?.type==="xanax"&&Number(next.at)===Number(row.at))engine.advance(v.drug);
          if(v.energy<wanted)engine.advance(Math.max(0,Math.ceil((wanted-v.energy)/5))*energyRules().minutes*60);
        }
        if(type==="refill"&&v.energy>=context.state.maxEnergy)continue; // no benefit from refilling full energy
        const a=make(type,Math.max(1,Math.floor(Number(row.quantity)||1)));
        if(type==="candy")a.candyHappy="any";
        if(type==="train"&&Number(row.energy)>0)a.energyLimit=Number(row.energy);
        if(!engine.execute(a,i,{beforeEcstasy:next?.type==="ecstasy",beforeXanax:next?.type==="xanax"}))return {error:v.errors[0]??"Remaining plan exceeds simulation window"};
        executed.push(a);
      }
      const result=engine.finish(executed,{tail:false});
      if(!result.complete)return {error:result.errors[0]??"Remaining simulation incomplete"};
      const owned=(name,cat)=>{
        const list=tornGuideApi.state.inventory[cat];if(!Array.isArray(list)||tornGuideApi.state.inventoryErrors?.[cat])return 0;
        const items=itemList();
        return list.filter(x=>keyName(x.name??x.item?.name??items.find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id))?.name)===keyName(name)).reduce((sum,x)=>sum+Math.max(0,Math.floor(n(x.amount??x.quantity))),0);
      };
      const prices=[[Math.max(0,result.costs.xanax-owned("Xanax","Drug")),p.xanaxPrice],[Math.max(0,result.costs.ecstasy-owned("Ecstasy","Drug")),p.ecstasyPrice],[Math.max(0,result.costs.dvd-owned("Erotic DVD","Booster")),p.dvdPrice],[result.costs.refill*30,p.pointPrice]];
      const cashCost=options.excludeOwned===false?result.money:prices.some(([q,price])=>q>0&&price==null)?null:prices.reduce((s,[q,price])=>s+q*(price??0),0);
      const actions=result.log.filter(x=>!["autoWait","happyReset","wait"].includes(x.type)).map(x=>({type:x.type,at:x.start.time,quantity:x.quantity??1,energy:x.type==="train"?Math.max(0,x.start.energy-x.end.energy):null,happy:x.end.happy,gain:Math.max(0,x.end.stat-x.start.stat)})).filter(x=>x.type!=="train"||x.energy>0).filter(x=>!["candy","dvd"].includes(x.type)||x.quantity>0);
      return {actions,gain:result.gain,money:result.money,cashCost,used:result.used,costs:result.costs,generatedAt:now.getTime(),finalHappy:v.happy};
    }finally{ctx=previous;Object.assign(p,old);}
  }
  function simulate(list,overrides={}){
    const side=Object.keys(steps).find(id=>steps[id]===list);
    const engine=createEngine({startEnergy:startingEnergy[side],midnightJump:midnightJumps.has(side),...overrides});
    const prepared=side?cycleStart(side,list,engine,{adaptive:startingEnergy[side]==="current"||overrides.startEnergy==="current",prepare:startingEnergy[side]==="current"||overrides.startEnergy==="current",livePolicy:startingEnergy[side]==="current"||overrides.startEnergy==="current"}):list;
    if(prepared)engine.run(prepared);
    return engine.finish(list);
  }
  function defaultActions(id){
    const list=defaults[id](),recurring=recurringTemplates.has(id);
    if(id!=="natural"&&!recurring)return list;
    // Build the rows with the same state transitions the fixed-list replay uses.
    const engine=createEngine({startEnergy:startingEnergy[id],autoWait:true},true);
    const {state,limit,canTrain,gymCost}=engine;
    if(!engine.run(list))return list;
    function append(action){
      list.push(action);
      engine.execute(action,list.length-1);
    }
    while(state.time<=limit){
      const fullAt=canTrain?state.time+engine.fullEnergyDelay():Infinity;
      const drugAt=recurring?state.time+state.drug:Infinity;
      if(fullAt<=limit&&fullAt<=drugAt){
        append({...make("train"),when:"full"});
      }else if(drugAt<limit){
        // Inspect Energy at the cooldown boundary without adding a player action.
        engine.advance(state.drug);
        if(state.energy>=gymCost&&canTrain)append({...make("train"),when:"drug"});
        append(make("xanax"));
        append(make("train"));
      }else break;
    }
    return list;
  }
  function applyCooldownPerks(){
    p.xanaxCDMin=420;p.ecstasyCDMin=215;
    const raw=tornGuideApi.state.data.perks,collections=raw?.perks??raw;
    const entries=group=>Object.entries(collections||{}).filter(([key])=>group.test(key)).flatMap(([,items])=>Array.isArray(items)?items:[]).map(item=>typeof item==="string"?item:[item?.name,item?.effect,item?.description].filter(Boolean).join(" "));
    const job=entries(/job|company/i),book=entries(/book/i);
    const known=!!collections&&Object.keys(collections).length>0;
    const detect=(list,name,percent)=>list.find(t=>name.test(t)||new RegExp("\\b"+percent+"\\s*%","i").test(t)&&/consumable|candy/i.test(t)&&/cooldown/i.test(t)&&!/increase|longer|maximum|capacity/i.test(t));
    const grocery=detect(job,/fast metabolism/i,10),restaurant=detect(job,/professional metabolism/i,25),reading=detect(book,/self control is for losers/i,50);
    const tiles=[
      {label:"Grocery Store · 3★",detail:"Fast Metabolism · −10% candy CD",source:grocery,active:!!grocery&&!restaurant},
      {label:"Restaurant · 10★",detail:"Professional Metabolism · −25% candy CD",source:restaurant,active:!!restaurant},
      {label:"Book · Self Control Is For Losers",detail:"−50% candy CD",source:reading,active:!!reading}
    ];
    p.candyCDMultiplier=(restaurant?0.75:grocery?0.9:1)*(reading?0.5:1);
    p.dvdCDMultiplier=1;
    const indecent=job.find(text=>/\bindecent\b/i.test(text)||/100\s*%.*(?:erotic dvd|dvd happiness)/i.test(text));
    p.dvdHappy=indecent?5000:2500;
    tiles.push({label:"Adult Novelties · 10★",detail:"Indecent · +100% DVD Happiness",source:indecent,active:!!indecent});
    return {tiles,known,sources:{candy:tiles.filter(x=>x.active&&x.source!==indecent).map(x=>x.source),dvd:indecent?[indecent]:[]}};
  }
  let cooldownEffects={tiles:[],sources:{candy:[],dvd:[]},known:false};
  function cooldownTiles(){
    const bliss=tornHappinessBook();
    const tiles=[...cooldownEffects.tiles,{label:"Book · Ignorance Is Bliss",detail:"No Happy reset · 99,999 ceiling",source:bliss.source,active:bliss.active,known:bliss.known}];
    return '<div class="ts-perk-tiles" aria-label="Training perk status">'+tiles.map(x=>{const status=x.label.startsWith("Book · ")?tornBookTileStatus(x.label.slice(7),x.active):x.active?"active":"";return '<div class="ts-perk-tile '+(status?"is-"+status:"")+'" title="'+$(x.source||x.detail)+'"><strong>'+$(x.label)+'</strong><small>'+$(x.detail)+'</small><small>'+ (status?status[0].toUpperCase()+status.slice(1):(x.known??cooldownEffects.known)?"Not detected":"Unknown")+'</small></div>';}).join("")+'</div>';
  }
  function happinessStatus(){
    const book=tornHappinessBook();
    return '<div class="ts-membership">Happy: <strong>'+fmt(ctx.state.happy)+'</strong> / '+fmt(ctx.state.maxHappy)+' normal maximum'+(book.active?' · <strong>Ignorance Is Bliss active</strong> · 99,999 ceiling':book.known?'':' · Active book status unavailable')+'</div>';
  }
  function controls(){
    const priceText=v=>v==null?"Unavailable":"$"+fmt(v);
    const effect=(label,minutes,source)=>'<span title="'+$(source.join("\n")|| (cooldownEffects.known?"No applicable reduction reported":"Perks unavailable; base cooldown assumed"))+'">'+label+' <strong>'+fmt(minutes,2)+'m</strong></span>';
    return '<div id="ts-plan-settings" class="ts-settings" '+(settingsOpen?"":"hidden")+'><div class="ts-settings-summary"><span>Time, cooldowns, effects, prices</span>'+cooldownControls()+'</div>'+
      '<div class="ts-membership">Preparation window: <strong>'+fmt(p.hours,2)+'h</strong> · '+$(energyRules().label)+'</div>'+
      '<div class="ts-market-prices ts-auto-cooldowns">'+effect("Xanax",p.xanaxCDMin,[])+effect("Ecstasy",p.ecstasyCDMin,[])+effect("Candy",30*p.candyCDMultiplier,cooldownEffects.sources.candy)+effect("eDVD",360*p.dvdCDMultiplier,cooldownEffects.sources.dvd)+'</div>'+happinessStatus()+cooldownTiles()+
      '<div class="ts-market-prices"><span>Xanax '+priceText(p.xanaxPrice)+'</span><span>Ecstasy '+priceText(p.ecstasyPrice)+'</span><span>eDVD '+priceText(p.dvdPrice)+'</span><span>Point '+priceText(p.pointPrice)+'</span></div>'+
      '<label class="ts-switch"><input type="checkbox" data-ts-auto '+(p.autoWait?"checked":"")+'>Automatically wait when a cooldown blocks an action</label></div>';
  }
  function row(side,a,index,info,event){
    const booster=["candy","dvd"].includes(a.type),wait=a.type==="wait";
    const ceiling=a.type==="candy"?maxCandy(p):maxDvd(p);
    const tier=a.candyHappy??p.candyHappy,attr=' data-ts-side="'+side+'" data-ts-index="'+index+'"';
    const candyOptions=["any",...new Set([25,35,50,75,100,150,250,...candyStock().tiers])];
    const configurable=booster||(wait&&!a.untilDrug),editorId="ts-editor-"+side+"-"+index;
    const short=a.type==="candy"?"Candy ×"+(info?.qty??a.qty):a.type==="dvd"?"eDVD ×"+(info?.qty??a.qty):wait?(a.untilDrug?waitTitle("Drug cooldown")+(event?" "+clock(event.end.time-event.start.time):""):"Wait "+fmt(a.minutes,2)+"m"):"";
    const types=actionOptions.map(([id,label])=>'<option value="'+id+'" '+(a.type===id?"selected":"")+'>'+$(a.type===id&&short?short:label)+'</option>').join("");
    const detail=booster?'<div class="ts-booster-row"><label>'+(a.type==="candy"?"Candy:":"eDVD:")+'</label><input type="number" min="0" max="'+ceiling+'" step="1" value="'+(info?.qty??a.qty)+'"'+attr+' data-ts-edit="qty" aria-label="Quantity"><button type="button" class="button secondary" data-ts-op="max"'+attr+' aria-pressed="'+Boolean(a.max)+'" '+(info?.maximum==null?"disabled":"")+'>MAX</button>'+(a.type==="candy"?'<select'+attr+' data-ts-edit="candy-tier" aria-label="Candy happiness">'+candyOptions.map(h=>'<option value="'+h+'" '+(h===tier?"selected":"")+'>'+(h==="any"?"Any":h+" Happy")+'</option>').join("")+'</select>':'<small>'+fmt(p.dvdHappy)+' Happy each</small>')+'</div><div class="ts-booster-summary">'+(a.type==="candy"&&tier==="any"?Object.entries(info?.used??{}).map(([name,q])=>$(q+"× "+name)).join(" · "):"")+(info?.happy?' <strong>+'+fmt(info.happy)+' Happy</strong>':"")+(info?.held==null?' <small>Inventory or preceding step unavailable</small>':' <small>'+fmt(info.held)+' held · '+fmt(info.allowance)+' CD allowance'+(a.type==="dvd"&&info.qty>info.held?' · '+fmt(info.qty-info.held)+' to purchase':"")+'</small>')+'</div>':"";
    const editor= configurable?'<div class="ts-row-editor" id="'+editorId+'" popover="auto" data-ts-editor="'+editorId+'" role="dialog" aria-label="'+$(names[a.type])+' settings"><div class="ts-row-editor-title"><strong>'+$(names[a.type])+'</strong><button type="button" class="ts-editor-close" popovertarget="'+editorId+'" popovertargetaction="hide" aria-label="Close settings">×</button></div>'+
      (booster?detail:'<label class="ts-editor-wait">Minutes <input type="number" min="0" max="10080" step=".01" value="'+a.minutes+'"'+attr+' data-ts-edit="minutes" aria-label="Minutes"></label>')+'</div>':"";
    return '<div class="ts-step"><select'+attr+' data-ts-edit="type" aria-label="Training action">'+types+'</select>'+
      '<div class="ts-arrows">'+(configurable?'<button type="button" class="ts-row-gear" data-ts-gear="'+editorId+'" popovertarget="'+editorId+'" title="Action settings" aria-label="Edit '+$(names[a.type])+' settings"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"/><path d="M10.4 2h3.2l.6 2.6 1.8.8 2.3-1.4 2.3 2.3-1.4 2.3.8 1.8 2.6.6v3.2l-2.6.6-.8 1.8 1.4 2.3-2.3 2.3-2.3-1.4-1.8.8-.6 2.6h-3.2l-.6-2.6-1.8-.8-2.3 1.4-2.3-2.3 1.4-2.3-.8-1.8-2.6-.6V11l2.6-.6.8-1.8-1.4-2.3L5.7 4 8 5.4l1.8-.8z" transform="translate(0 -0.6)"/></svg></button>':a.type==="refill"&&energyRefillUsedToday()?'<span class="ts-gear-spacer ts-refill-caution" tabindex="0" aria-label="Refill caution" aria-describedby="'+editorId+'-refill-note"><span aria-hidden="true">⚠</span><span id="'+editorId+'-refill-note" role="tooltip">Today’s Points Energy refill has already been used.</span></span>':'<span class="ts-gear-spacer" aria-hidden="true"></span>')+
      '<button type="button" title="Move up" aria-label="Move up" data-ts-op="up"'+attr+'>↑</button><button type="button" title="Move down" aria-label="Move down" data-ts-op="down"'+attr+'>↓</button><button type="button" title="Remove" aria-label="Remove" data-ts-op="remove"'+attr+'>×</button></div>'+editor+'</div>';
  }
  function timelineCells(state,previous=state){
    if(!state)return '<td>—</td>'.repeat(6);
    const change=state.stat-(previous?.stat??state.stat);
    return '<td>'+fmt(state.energy)+'</td><td>'+fmt(state.happy)+'</td><td>'+clock(state.drug)+'</td><td>'+clock(state.booster)+'</td><td class="ts-row-gain '+(change>0?"is-positive":"")+'">'+(change>0?"+":"")+fmt(change,2)+'</td><td class="ts-row-stat">'+fmt(state.stat,2)+'</td>';
  }
  function dependencyRow(e,offset=0){
    const label=e.type==="autoWait"?waitTitle(e.reason)+" "+clock(e.end.time-e.start.time):e.type==="happyReset"?"Happiness reset":(names[e.type]??e.type)+(["candy","dvd"].includes(e.type)?" ×"+e.quantity:"")+(e.reason?" · "+e.reason:"");
    return '<tr class="ts-dependent"><td>'+clock(offset+e.end.time)+'</td><td><span class="ts-dependency-mark" aria-label="Automatic dependent step">↳</span> '+$(label)+'</td>'+timelineCells(e.end,e.type==="autoWait"?e.end:e.start)+'</tr>';
  }
  function mergedTimeline(side,data){
    const list=steps[side],byParent=new Map(),offset=startingTime[side]??0;
    // A reset matters in the timeline only if the next happiness-changing
    // action is a gym train, rather than another boost or reset.
    const affectsHappy=e=>e.type==="train"?e.end.energy<e.start.energy:
      ["xanax","ecstasy","candy","dvd","externalHappy","happyReset"].includes(e.type)&&e.end.happy!==e.start.happy;
    for(let j=0;j<data.log.length;j++){
      const e=data.log[j];
      if(e.type==="happyReset"){
        const next=data.log.slice(j+1).find(affectsHappy);
        if(next?.type!=="train")continue;
      }
      const parent=e.parent??-1;if(!byParent.has(parent))byParent.set(parent,[]);byParent.get(parent).push(e);
    }
    let rows='<tr class="ts-initial"><td><input class="ts-start-time" type="text" inputmode="numeric" data-ts-start-time="'+side+'" value="'+clock(offset)+'" aria-label="Starting time in hours, minutes and seconds" title="Timeline start (H:MM:SS)"></td><td><div class="ts-start-energy"><strong>Starting Energy</strong><select data-ts-start-energy="'+side+'" aria-label="Starting Energy"><option value="zero" '+(startingEnergy[side]==="zero"?"selected":"")+'>0 E</option><option value="full" '+(startingEnergy[side]==="full"?"selected":"")+'>'+energyRules().cap+' E</option><option value="current" '+(startingEnergy[side]==="current"?"selected":"")+'>Live '+fmt(ctx.state.currentEnergy,0)+' E</option></select></div></td>'+timelineCells(data.initial)+'</tr>';
    rows+=(byParent.get(-1)||[]).map(e=>dependencyRow(e,offset)).join("");
    list.forEach((action,i)=>{
      const events=byParent.get(i)||[],main=events.find(e=>e.editable);
      rows+=events.filter(e=>!e.editable).map(e=>dependencyRow(e,offset)).join("");
      rows+='<tr class="ts-editable-row"><td>'+(main?clock(offset+main.end.time):"—")+'</td><td>'+data.notices.filter(x=>x.index===i).map(x=>'<div class="ts-cd-notice '+(x.critical?"critical":"hazard")+'">'+(x.critical?"":"⚠ ")+$(x.text)+'</div>').join("")+row(side,action,i,data.rowInfo[i],main)+'</td>'+timelineCells(main?.end,main?.start)+'</tr>';
    });
    rows+=(byParent.get(list.length)||[]).map(e=>dependencyRow(e,offset)).join("");
    return '<div class="ts-log ts-merged"><div class="ts-log-scroller"><table><thead><tr><th>Time</th><th>Action</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th><th>Stat change</th><th>Current stat</th></tr></thead><tbody>'+rows+'</tbody></table></div>'+
      '<div class="ts-add"><select data-ts-choice="'+side+'" aria-label="Select action"><option value="" selected>Select action</option>'+actionOptions.map(([id,label])=>'<option value="'+id+'">'+$(label)+'</option>').join("")+'</select><button type="button" class="button secondary" data-ts-op="add" data-ts-side="'+side+'" disabled>Add action</button><button type="button" class="text-button" data-ts-op="preset" data-ts-side="'+side+'">Reset</button></div></div>';
  }
  function costMetric(id,cost,items,label){
    const dollars=value=>value==null?"Unavailable":"$"+fmt(value);
    const tooltipId="ts-cost-"+id;
    return '<span class="ts-title-metric ts-cost-metric" tabindex="0" aria-describedby="'+tooltipId+'"><small>Cost</small><strong>'+dollars(cost)+'</strong>'+
      '<span class="ts-cost-receipt" role="tooltip" id="'+tooltipId+'"><b>'+label+'</b>'+
      (items.length?items.map(({name,quantity,price})=>'<span><span>'+$(name)+' × '+fmt(quantity)+'</span><span>'+dollars(price==null?null:quantity*price)+'</span></span>').join(""):'<span>No items</span>')+
      '</span></span>';
  }
  function section(side,data,projection,hours,budget){
    const heading=templates.find(x=>x[0]===side)?.[2]??side;
    const metric=(label,value,extra="")=>'<span class="ts-title-metric '+extra+'"><small>'+label+'</small><strong>'+value+'</strong></span>';
    const purchases=chartPurchases()(projection.costs),weekly=weeklyPurchaseCost()(projection);
    return '<details class="ts-side ts-template-card" data-ts-timeline="'+side+'" '+(openTimelines.has(side)?"open":"")+'><summary class="ts-template-header"><span class="ts-template-name">'+$(heading)+'</span>'+
      metric("Window",fmt(hours,2)+"h · "+cycleCountLabel(projection))+metric("Energy used",fmt(projection.used)+" E")+metric("Stat change","+"+fmt(projection.gain,2),"ts-title-gain")+metric("Ending stat",fmt(projection.final,2))+costMetric(side,purchases.cost,purchases.items,"Items to purchase")+
      '<span class="ts-template-chevron" aria-hidden="true"></span></summary>'+
      '<p class="fine-print">Peak rolling 7-day spend '+(weekly==null?"Unavailable":"$"+fmt(weekly)+(budget!=null&&weekly>budget?" · Over weekly budget":""))+
      ' · Consumed value '+(projection.money==null?"Unavailable":"$"+fmt(projection.money))+' · One-cycle editor ('+fmt(data.elapsed/3600,2)+'h)</p>'+mergedTimeline(side,data)+partialLabel(projection)+partialTimeline(projection)+
      (projection.errors.length?'<p class="ts-error">'+projection.errors.map($).join(" · ")+'</p>':"")+
      (side==="maxhappy"?'<p class="fine-print">99,999 Happy target · Peak '+fmt(data.peakHappy??0)+' · '+((data.peakHappy??0)>=99999?"Target reached":"Additional happiness source required")+'</p>':"")+(data.warnings.length?'<p class="fine-print">'+data.warnings.map($).join("; ")+'</p>':"")+(data.errors.length?'<p class="ts-error">'+data.errors.map($).join("; ")+'</p>':"")+
      '</details>';
  }
  function optimizerCard(id,title,data,hours){
    const metric=(label,value)=>'<span class="ts-title-metric"><small>'+label+'</small><strong>'+value+'</strong></span>';
    const dollars=cost=>cost==null?"Unavailable":"$"+fmt(cost);
    const offset=data.offset??0;
    const row=(time,label,state,previous)=>'<tr><td>'+clock(time)+'</td><td>'+$(label)+'</td>'+timelineCells(state,previous)+'</tr>';
    let rows=row(offset,"Starting Energy",data.initial),cycleIndex=0;
    for(const [index,step] of data.log.entries()){
      while(data.segments[cycleIndex]?.logStart===index){
        const cycle=data.segments[cycleIndex++];
        const name=templates.find(([key])=>key===cycle.id)?.[2]??cycle.id;
        rows+='<tr class="ts-dependent"><td>'+clock(cycle.start)+'</td><td colspan="7"><strong>'+$(("Cycle "+cycleIndex+" · "+name+" · "+clock(cycle.at-cycle.start)))+'</strong></td></tr>';
      }
      if(step.type==="train"&&step.end.energy===step.start.energy)continue;
      const wait=["wait","autoWait"].includes(step.type);
      const label=wait?waitTitle(step.reason??"")+" "+clock(step.end.time-step.start.time):
        step.type==="happyReset"?"Happiness reset":
        step.type==="candy"||step.type==="dvd"?(step.type==="candy"?"Candy":"eDVD")+" ×"+step.quantity:names[step.type]??step.type;
      rows+=row(offset+step.end.time,label,step.end,step.start);
    }
    const purchases=chartPurchases()(data.costs),cash=purchases.cost,weekly=weeklyPurchaseCost()(data);
    return '<details class="ts-side ts-template-card" data-ts-timeline="'+id+'" '+(openTimelines.has(id)?"open":"")+'>'+
      '<summary class="ts-template-header"><span class="ts-template-name">'+title+'</span>'+
      metric("Window",fmt(hours,2)+"h · "+cycleCountLabel(data))+
      metric("Energy used",fmt(data.used)+" E")+metric("Stat change","+"+fmt(data.gain,2))+
      metric("Ending stat",fmt(data.final,2))+costMetric(id,cash,purchases.items,"Items to purchase")+
      '<span class="ts-template-chevron" aria-hidden="true"></span></summary>'+
      '<p class="fine-print">Purchase cost '+dollars(cash)+' · Peak rolling 7-day spend '+dollars(weekly)+' · Consumed value '+dollars(data.money)+'</p>'+
      '<div class="ts-log"><div class="ts-log-scroller"><table><thead><tr><th>Time</th><th>Action</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th><th>Stat change</th><th>Current stat</th></tr></thead><tbody>'+rows+'</tbody></table></div></div>'+
      partialLabel(data)+(data.warnings.length?'<p class="fine-print">'+data.warnings.map($).join(" · ")+'</p>':"")+'</details>';
  }
  function cycleCountLabel(data){
    const count=data.segments.length;
    return count+(count===1?" cycle":" cycles")+(data.partialSegment?(data.partialSegment.reason==="blocked"?" + blocked":" + partial"):"");
  }
  function partialLabel(data){
    const segment=data.partialSegment;
    if(!segment)return "";
    const name=templates.find(([id])=>id===segment.id)?.[2]??segment.id;
    return '<p class="fine-print ts-partial-detail">'+$(name)+' · '+(segment.reason==="window"?(segment.optimized?"Optimized partial cycle":"Partial cycle (window ended)"):"Incomplete cycle (blocked)")+
      ' · '+clock(segment.start)+'–'+clock(segment.at)+' · '+fmt(segment.used)+' E · +'+fmt(segment.gain,2)+' stat. Included in totals, not completed cycles.</p>';
  }
  function partialTimeline(data){
    const segment=data.partialSegment;if(!segment)return "";
    const rows=data.log.slice(segment.logStart).filter(e=>e.type!=="happyReset"&&!(e.type==="train"&&e.end.energy===e.start.energy)).map(e=>dependencyRow(e,data.offset??0)).join("");
    return rows?'<div class="ts-log"><div class="fine-print">Terminal partial cycle actions</div><div class="ts-log-scroller"><table><thead><tr><th>Time</th><th>Action</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th><th>Stat change</th><th>Current stat</th></tr></thead><tbody>'+rows+'</tbody></table></div></div>':"";
  }
  function chart(results,hours){
    const xval=hour=>80+hour/hours*800;
    let bottom=Infinity,top=-Infinity;
    for(const {data} of results){
      bottom=Math.min(bottom,data.initial.stat);
      top=Math.max(top,data.initial.stat);
      for(const point of data.series){
        bottom=Math.min(bottom,point.s);
        top=Math.max(top,point.s);
      }
    }
    top=Math.max(bottom+1,top);
    const yval=val=>210-(val-bottom)/(top-bottom)*190;
    const path=points=>points.map(({h,s},i)=>{
      const x=xval(h).toFixed(1),y=yval(s).toFixed(1);
      return i?"H"+x+"V"+y:"M"+x+","+y;
    }).join(" ");
    const seriesClass=(id,data)=>"ts-series ts-series-"+id+(data.errors.length?" is-blocked":"");
    const endpoint=(x,y)=>'<circle class="ts-series-end" cx="'+x+'" cy="'+y+'" r="3"/>';
    let out='<svg viewBox="0 0 910 260" class="ts-chart '+(showCycleBoundaries?"show-cycle-boundaries":"")+'" role="img" aria-label="Projected stat growth over '+hours+' hours">';
    for(let i=0;i<5;i++){
      const val=bottom+(top-bottom)*i/4,y=yval(val),hr=hours*i/4;
      out+='<line x1="80" y1="'+y+'" x2="'+xval(hours)+'" y2="'+y+'" class="ts-gridline"/><text x="74" y="'+(y+4)+'" font-size="11" text-anchor="end">'+fmt(val)+'</text><text x="'+xval(hr)+'" y="234" font-size="11" text-anchor="middle">'+fmt(hr,2)+'h</text>';
    }
    // Render behind the growth paths; adjacent starts/ends share one hairline.
    for(const {id,data} of results){
      const marks=new Map(),max=hours*3600;
      const mark=(at,kind,label)=>{
        if(!Number.isFinite(at)||at<0||at>max+1e-6)return;
        const existing=marks.get(at);
        if(existing){existing.labels.push(label);if(kind==="end")existing.kind="end";else if(kind==="partial-end")existing.kind=kind;}
        else marks.set(at,{kind,labels:[label]});
      };
      data.segments.forEach((seg,i)=>{mark(seg.start,"start","Cycle "+(i+1)+" start");mark(seg.at,"end","Cycle "+(i+1)+" end");});
      if(data.partialSegment){
        const seg=data.partialSegment;
        mark(seg.start,"partial-start","Incomplete cycle start");
        mark(seg.at,"partial-end",seg.reason==="window"?"Partial cycle cutoff":"Cycle blocked");
      }
      out+='<g class="'+seriesClass(id,data)+' ts-cycle-boundaries" aria-hidden="true">'+[...marks].map(([at,{kind,labels}])=>{
        const x=xval(Math.min(hours,at/3600)).toFixed(3);
        return '<line class="ts-cycle-marker ts-cycle-marker-'+kind+'" x1="'+x+'" x2="'+x+'" y1="20" y2="210"><title>'+$(labels.join(" · ")+" · "+clock(at))+'</title></line>';
      }).join("")+'</g>';
    }
    for(const {id,data} of results){
      // The simulator coalesces events at the same time. Restore the pre-action
      // value for the chart when an immediate train changes the first point.
      const points=[...data.series,{h:hours,s:data.final}];
      if(points[0].h!==0||points[0].s!==data.initial.stat)points.unshift({h:0,s:data.initial.stat});
      out+='<g class="'+seriesClass(id,data)+'"><path class="ts-series-stroke" d="'+path(points)+'"/>'+endpoint(xval(hours),yval(data.final))+'</g>';
    }
    return out+'</svg><div class="ts-legend ts-multi-legend">'+results.map(({id,label,data})=>'<span><svg class="'+seriesClass(id,data)+'" width="44" height="10" aria-hidden="true"><line class="ts-series-stroke" x1="2" y1="5" x2="42" y2="5"/>'+endpoint(35,5)+'</svg> '+$(label)+(data.errors.length?" (blocked)":data.partialSegment?" (partial)":"")+'</span>').join("")+'</div>';
  }
  function cycleActions(id){
    return id==="natural"?[{...make("train"),when:"full"}]:defaults[id]();
  }
  // Track only real progress in an unfinished cycle; a failed zero-time
  // attempt at the boundary is not an additional program.
  // Built-in templates consume the actual stack rather than manufacturing
  // a zero/full starting balance. Explicit custom action lists stay literal.
  function cycleStart(id,actions,engine,{adaptive=true,prepare=true,livePolicy=false}={}){
    const v=engine.state,stackPlan=id==="jump"||id==="maxhappy";
    if(adaptive&&!editedPlans.has(id)&&stackPlan){
      const leading=actions.findIndex(a=>a.type!=="xanax");
      if(leading>0){
        // When no further dose is needed, keep the entire stack. Otherwise
        // trim only the surplus above the last complete 250-E tier, after
        // any pending cooldown (which may regenerate Energy below cap).
        if(v.energy<1000&&!engine.waitFor(v.drug,"Drug cooldown"))return null;
        const tier=Math.min(1000,Math.floor(v.energy/250)*250);
        const surplus=v.energy-tier;
        if(surplus>=engine.gymCost&&!engine.execute({...make("train"),energyLimit:surplus},-1,{automatic:true}))return null;
        // If gym increments cannot reach the exact tier, leave the remainder
        // rather than spending Energy that belongs to the retained stack.
        const doses=Math.max(0,Math.min(leading,Math.ceil((1000-v.energy)/250)));
        return [...actions.slice(0,doses),...actions.slice(leading)];
      }
    }
    if(adaptive&&!editedPlans.has(id)&&["maxenergy","mini"].includes(id)&&actions[0]?.type==="xanax"){
      // A full stack is already better than the normal opening Xanax.
      // Preserve it for the planned happiness boost and training.
      if(v.energy>=1000)return actions.slice(1);
      if(v.energy>750){
        if(!engine.waitFor(v.drug,"Drug cooldown"))return null;
        if(!engine.execute({...make("train"),energyLimit:v.energy-750},-1,{automatic:true}))return null;
      }
    }
    if(prepare&&id!=="custom"&&(livePolicy?defaultEnergy[id]:startingEnergy[id])==="full"&&v.energy<energyRules().cap&&
      !engine.waitFor(engine.fullEnergyDelay(),"Full Energy",false))return null;
    return actions;
  }
  function cycleCheckpoint(v,offset,id){
    return {id,start:offset+v.time,logStart:v.log.length,stat:v.stat,used:v.used,costs:{...v.costs}};
  }
  function unfinishedCycle(checkpoint,engine,offset){
    const v=engine.state,at=offset+v.time;
    const costs=Object.fromEntries(Object.entries(v.costs).map(([key,value])=>[key,value-(checkpoint.costs[key]??0)]));
    const gain=v.stat-checkpoint.stat,used=v.used-checkpoint.used;
    if(at<=checkpoint.start&&!gain&&!used&&!Object.values(costs).some(Boolean))return null;
    if(!engine.cutoff&&!v.errors.length)return null;
    return {id:checkpoint.id,start:checkpoint.start,at,logStart:checkpoint.logStart,gain,used,costs,
      reason:engine.cutoff?"window":"blocked"};
  }
  // A terminal partial is a bounded, plan-specific training problem. Try
  // several event-driven policies, retain the best affordable result, and
  // leave the standard template untouched for any future full cycle.
  function optimizePartialCycle(checkpoint,engine,offset,prefix,budget,{priceOf,blockDrugs=false}={}){
    const v=engine.state,limit=engine.limit,id=checkpoint.id;
    if(!prefix||!engine.cutoff||!Number.isFinite(limit))return unfinishedCycle(checkpoint,engine,offset);
    const baseline=engine.snapshot();
    engine.restore(prefix);
    if(v.time>=limit||!engine.canTrain)return null;
    const allowOrdinary=id!=="natural";
    const allowDvd=id==="jump",allowExternal=id==="maxhappy";
    const purchases=chartPurchases(),weekly=weeklyPurchaseCost();
    const spendOf=()=>priceOf?priceOf(v,engine):weekly(v);
    const prefixSpend=budget==null?0:spendOf();
    const prefixItems=new Map(purchases(v.costs).items.map(x=>[x.name,x.quantity]));
    const noNewPurchases=()=>purchases(v.costs).items.every(x=>x.quantity<=(prefixItems.get(x.name)??0));
    const affordable=()=>{
      if(!allowDvd&&v.costs.dvd>checkpoint.costs.dvd)return false;
      if(!allowExternal&&v.costs.externalHappy>checkpoint.costs.externalHappy)return false;
      if(blockDrugs&&(v.costs.xanax>checkpoint.costs.xanax||v.costs.ecstasy>checkpoint.costs.ecstasy))return false;
      if(budget==null)return true;
      if(prefixSpend==null||prefixSpend>budget)return priceOf?false:noNewPurchases();
      const spend=spendOf();
      return spend!=null&&spend<=budget;
    };
    const score=()=>({gain:v.stat-checkpoint.stat,spend:(priceOf?spendOf():purchases(v.costs).cost)??Infinity,
      items:Object.entries(v.costs).reduce((sum,[key,value])=>sum+value-(checkpoint.costs[key]??0),0)});
    const better=(a,b)=>!b||a.gain>b.gain+1e-7||Math.abs(a.gain-b.gain)<=1e-7&&(a.spend<b.spend||a.spend===b.spend&&a.items<b.items);
    let best=null,bestScore=null;
    const retain=()=>{if(!affordable()||v.errors.length)return;const s=score();if(better(s,bestScore)){bestScore=s;best=engine.snapshot();}};
    // Keep the conventional truncated execution as a fallback only if it
    // respects the budget and the consumable locks.
    const row=10000;
    // The truncated template can have a useful stack at the boundary.
    // Train it before comparison rather than valuing unspent Energy.
    engine.restore({...baseline,cutoff:false});
    if(v.energy>=engine.gymCost)engine.execute(make("train"),row,{automatic:true});
    retain();
    const runBatch=(drug,boost,refill)=>{
      const before=v.stat,used=v.used;
      if(drug==="xanax"&&!engine.execute(make("xanax"),row,{automatic:true}))return false;
      if(boost==="candy"&&!engine.execute(maxCandyAction(),row,{automatic:true}))return false;
      if(typeof boost==="number"&&!engine.execute(make("dvd",boost),row,{automatic:true}))return false;
      if(boost==="external"&&!engine.execute(make("externalHappy"),row,{automatic:true}))return false;
      if(drug==="ecstasy"&&!engine.execute(make("ecstasy"),row,{automatic:true}))return false;
      if(v.energy>=engine.gymCost&&!engine.execute(make("train"),row,{automatic:true}))return false;
      if(refill&&!v.days.has(engine.tornDay())&&v.energy<energyRules().cap){
        if(!engine.execute(make("refill"),row,{automatic:true,boostedRefill:true})||
          !engine.execute(make("train"),row,{automatic:true}))return false;
      }
      return v.stat>before&&v.used>used&&!engine.cutoff&&affordable();
    };
    // Each policy makes different tradeoffs between immediate training,
    // conserving boost/drug cooldown for a larger Energy pool, and using
    // ordinary consumables versus the plan's premium boost.
    const policies=["immediate","reserve","ordinary","natural"];
    // A genuinely stacked jump can beat repeated small trains, especially
    // when an existing stack or a premium boost is available.
    if(allowOrdinary&&!blockDrugs&&limit-prefix.state.time>=p.xanaxCDMin*60)policies.push("stack2","stack3","stack4");
    for(const policy of policies){
      engine.restore(prefix);
      const stack=policy.startsWith("stack")?Number(policy.slice(5)):0;
      if(stack){
        let valid=true;
        for(let k=0;k<stack;k++){
          if(v.energy>=1000)break;
          if(v.time+v.drug>limit||!engine.waitFor(v.drug,"Drug cooldown")||
            !engine.execute(make("xanax"),row,{automatic:true})||!affordable()){valid=false;break;}
        }
        // Reserve the drug cooldown for a potential Ecstasy boost, but
        // never sacrifice the final train just to wait for it.
        if(valid&&v.drug>0&&v.time+v.drug<=limit)valid=engine.waitFor(v.drug,"Drug cooldown");
        if(!valid)continue;
      }
      let events=0;
      while(v.time<=limit&&events++<120){
        const base=engine.snapshot(),remaining=limit-v.time,cap=energyRules().cap;
        const refillReady=allowOrdinary&&!v.days.has(engine.tornDay());
        const drugReady=allowOrdinary&&!blockDrugs&&v.drug===0;
        const boostReady=allowOrdinary&&v.booster<=p.boosterCapH*3600;
        const enough=v.energy>=cap||remaining<engine.fullEnergyDelay()||remaining===0;
        const canSpend=policy!=="natural"&&allowOrdinary;
        const canBoost=canSpend&&(policy!=="reserve"||enough||refillReady);
        const drugs=[""];
        if(canSpend&&drugReady){
          const readyToBoost=canBoost&&(v.energy>=engine.gymCost||refillReady);
          if(policy!=="reserve"||!readyToBoost)drugs.push("xanax");
          if(readyToBoost)drugs.push("ecstasy");
        }
        const boosts=[""];
        if(canBoost&&boostReady&&candyStock().loaded)boosts.push("candy");
        if(canBoost&&boostReady&&allowDvd&&policy!=="ordinary")for(let qty=1;qty<=5;qty++)boosts.push(qty);
        if(canBoost&&allowExternal&&policy!=="ordinary")boosts.push("external");
        let chosen=null,chosenScore=null;
        // A batch is atomic for budget purposes: no untrained consumable
        // purchase or unaffordable partial refill can leak into the result.
        for(const drug of drugs)for(const boost of boosts){
          if(drug==="xanax"&&boost&&policy==="reserve")continue;
          for(const refill of canSpend&&refillReady?[false,true]:[false]){
            if(!drug&&!boost&&!refill&&!enough&&policy!=="immediate")continue;
            if(!drug&&!boost&&!refill&&base.state.energy<engine.gymCost)continue;
            engine.restore(base);
            if(!runBatch(drug,boost,refill))continue;
            const s=score();
            if(better(s,chosenScore)){chosenScore=s;chosen=engine.snapshot();}
          }
        }
        engine.restore(chosen??base);
        if(v.time>=limit)break;
        // Train again when an actionable boundary is reached. Do not wait
        // past the horizon, and dump any residual trainable Energy at it.
        const delays=[limit-v.time,engine.fullEnergyDelay()];
        if(canSpend){if(v.drug>0)delays.push(v.drug);if(v.days.has(engine.tornDay()))delays.push(engine.untilMidnight());if(v.booster>p.boosterCapH*3600)delays.push(v.booster-p.boosterCapH*3600);}
        const wait=Math.min(...delays.filter(x=>x>0));
        if(!Number.isFinite(wait)||!engine.waitFor(wait,"Partial cycle",false))break;
      }
      if(v.time<limit)engine.waitFor(limit-v.time,"Partial cycle",false);
      if(v.energy>=engine.gymCost)engine.execute(make("train"),row,{automatic:true});
      retain();
    }
    engine.restore(best??prefix);
    const costs=Object.fromEntries(Object.entries(v.costs).map(([key,value])=>[key,value-(checkpoint.costs[key]??0)]));
    return {id,start:checkpoint.start,at:offset+v.time,logStart:checkpoint.logStart,gain:v.stat-checkpoint.stat,
      used:v.used-checkpoint.used,costs,reason:"window",optimized:true};
  }
  function projectCycles(id,cycles,{end=Infinity,continuous=false,partialBudget=null,liveStart=false}={}){
    const list=id==="natural"&&!editedPlans.has(id)?cycleActions(id):steps[id];
    const offset=liveStart?0:startingTime[id],clockSeconds=Math.round(p.tornClockMin*60)+offset;
    const engine=createEngine({
      limitSeconds:Math.max(0,end-offset),startEnergy:liveStart?"current":startingEnergy[id],midnightJump:midnightJumps.has(id),

      startDrugMin:Math.max(0,p.startDrugMin-offset/60),startBoosterMin:Math.max(0,p.startBoosterMin-offset/60),
      tornClockMin:clockSeconds/60,resetAfterSec:900-clockSeconds%900
    });
    const v=engine.state;
    let completed=0,partialSegment=null;
    const segments=[];
    while(list.length&&completed<cycles&&v.time<=engine.limit){
      const before=v.time,statBefore=v.stat,logStart=v.log.length,checkpoint=cycleCheckpoint(v,offset,id),prefix=Number.isFinite(end)?engine.snapshot():null;
      const actions=cycleStart(id,list,engine,{adaptive:liveStart||startingEnergy[id]==="current"||completed>0,prepare:liveStart||completed>0||startingEnergy[id]==="current",livePolicy:liveStart||startingEnergy[id]==="current"});
      if(!actions||!engine.run(actions)){partialSegment=optimizePartialCycle(checkpoint,engine,offset,prefix,partialBudget);break;}
      completed++;
      segments.push({id,at:offset+v.time,start:offset+before,logStart,gain:v.stat-statBefore});
      if(continuous&&v.time===before){
        // Instant actions still move forward in real time between repetitions.
        const delay=engine.fullEnergyDelay()||energyRules().minutes*60;
        if(!engine.waitFor(delay,"Full Energy",false))break;
      }
      if(!continuous&&v.time===before&&completed<cycles&&v.energy<engine.gymCost&&list.some(step=>step.type==="train")){
        if(!engine.waitFor(engine.fullEnergyDelay(),"Full Energy",false))break;
      }
    }
    const data=engine.finish(list,{tail:false});
    return {...data,elapsed:v.time,offset,completed,segments,partialSegment,series:data.series.map(point=>({...point,h:point.h+offset/3600}))};
  }
  function mixedProjection(sequence,end,{fill=false,actionsFor=id=>steps[id],respectOffset=true,allowPartialDvd=false,refillUsedToday=false,skipUsedRefill=false,matchTemplateStart=false,repeatLast=false,partialBudget=null,partialOptions={},requireDrugClear=false,warXanaxSeconds=28800}={}){
    const first=sequence[0],offset=respectOffset?Math.min(end,startingTime[first]??0):0;
    const clockSeconds=Math.round(p.tornClockMin*60)+offset;
    const engine=createEngine({limitSeconds:end-offset,startEnergy:matchTemplateStart?startingEnergy[first]:"current",allowPartialDvd,skipUsedRefill,requireDrugClear,warXanaxSeconds,
      refillUsedToday:refillUsedToday&&clockSeconds<86400,
      startDrugMin:Math.max(0,p.startDrugMin-offset/60),startBoosterMin:Math.max(0,p.startBoosterMin-offset/60),
      tornClockMin:clockSeconds/60,resetAfterSec:900-clockSeconds%900});
    const segments=[];
    let firstCycle=null,partialSegment=null;
    for(let index=0;index<sequence.length||(repeatLast&&sequence.length);index++){
      const id=sequence[Math.min(index,sequence.length-1)];
      const actions=actionsFor(id),v=engine.state;
      if(!actions.length||v.time>engine.limit)break;
      const before=v.stat,start=offset+v.time,logStart=v.log.length,checkpoint=cycleCheckpoint(v,offset,id),prefix=Number.isFinite(end)?engine.snapshot():null;
      const prepare=!matchTemplateStart||index>0||startingEnergy[id]==="current";
      const prepared=cycleStart(id,actions,engine,{adaptive:prepare,prepare,livePolicy:!matchTemplateStart||startingEnergy[first]==="current"});
      if(!prepared||!engine.run(prepared,{midnightJump:midnightJumps.has(id)})){partialSegment=optimizePartialCycle(checkpoint,engine,offset,prefix,partialBudget,partialOptions);break;}
      segments.push({id,at:offset+v.time,start,logStart,gain:v.stat-before});
      if(matchTemplateStart&&start===offset+v.time){
        const delay=engine.fullEnergyDelay()||energyRules().minutes*60;
        if(!engine.waitFor(delay,"Full Energy",false))break;
      }
      if(!firstCycle){const snapshot=engine.finish(actions,{tail:false});firstCycle={...snapshot,costs:{...snapshot.costs},log:snapshot.log.slice()};}
    }
    const cycleState=engine.finish(sequence.flatMap(actionsFor),{tail:false});
    if(!firstCycle&&partialSegment)firstCycle={...cycleState,costs:{...cycleState.costs},log:cycleState.log.slice()};
    if(fill&&(segments.length===sequence.length||engine.state.time===engine.limit)){
      while(engine.canTrain){
        const delay=engine.fullEnergyDelay();
        if(engine.state.time+delay>engine.limit)break;
        if(!engine.waitFor(delay,"Full Energy",false)||!engine.execute(make("train"),0))break;
      }
    }
    const data=fill?engine.finish(sequence.flatMap(actionsFor),{tail:!engine.state.errors.length}):cycleState;
    return {...data,complete:data.complete&&segments.length>=sequence.length,
      elapsed:offset+data.time,offset,segments,partialSegment,firstCycle,series:data.series.map(point=>({...point,h:point.h+offset/3600}))};
  }
  function chartPurchases(){
    const credits=payload("money","money")?.points;
    return trainingPurchases(Math.floor(positive(credits?.current??credits)??0));
  }
  function weeklyPurchaseCost({excludeOwned=true,pointsHeld=null,reserveXanax=0}={}){
    const purchases=pointsHeld===null&&excludeOwned&&!reserveXanax?chartPurchases():trainingPurchases(excludeOwned?(pointsHeld??0):0,{excludeOwned,reserveXanax});
    return data=>{
      const costs={};
      const payments=[];
      let spent=0,previous=0,max=0,first=0,candyValue=0;
      for(const event of data.log){
        if(event.type==="candy"&&!excludeOwned){if(event.quantity&&event.consumedValue==null)return null;candyValue+=event.consumedValue??0;}
        else if(!["xanax","ecstasy","dvd","refill","externalHappy"].includes(event.type))continue;
        else costs[event.type]=(costs[event.type]??0)+(event.quantity??1);
        const base=purchases(costs).cost,cost=base==null?null:base+candyValue;
        if(cost===null)return null;
        const at=event.start.time;
        payments.push({at,cost:cost-previous});
        spent+=cost-previous;previous=cost;
        while(first<payments.length&&payments[first].at<=at-604800)spent-=payments[first++].cost;
        max=Math.max(max,spent);
      }
      return max;
    };
  }
  function optimizeCycles(ids,slots,end,continuous,{cap,priceOf,overrides=cycleOverrides,projection={}}={}){
    const actionsFor=projection.actionsFor??(id=>steps[id]);
    const budget=cap!==undefined?cap:typeof tornRoadmap==="undefined"?null:tornRoadmap.preferences().weeklyBudget;
    const weeklySpend=priceOf??weeklyPurchaseCost();
    const rank=(a,b)=>b.data.gain-a.data.gain||a.data.elapsed-b.data.elapsed||a.cost-b.cost;
    const choices=ids.filter(id=>actionsFor(id).length&&!actionsFor(id).some(step=>step.type==="externalHappy"));
    let frontier=[{sequence:[]}],best=null;
    const lastOverride=overrides.slice(0,slots).findLastIndex(Boolean);
    for(let index=0;index<slots&&frontier.length;index++){
      const required=overrides[index],next=[];
      for(const parent of frontier)for(const id of required?[required]:choices){
        const sequence=[...parent.sequence,id],data=mixedProjection(sequence,end,projection);
        const cost=weeklySpend(data);
        if(data.complete&&cost!==null&&(budget==null||cost<=budget))next.push({sequence,data,cost:cost??Infinity});
      }
      next.sort(rank);
      frontier=next.slice(0,5);
      if(continuous&&index>=lastOverride){
        for(const candidate of frontier){
          const sample={...candidate,data:mixedProjection(candidate.sequence,end,{...projection,fill:true})};
          if(!best||rank(sample,best)<0)best=sample;
        }
      }
    }
    if(!continuous)best=frontier[0]??null;
    return best;
  }
  function optimizeChart(results,slots,end,budget=null,overrides=[],{projection={},priceOf,minDepth=0,manualMode=false,finishWindow=false}={}){
    const weeklySpend=budget==null?null:priceOf??weeklyPurchaseCost();
    const lastOverride=overrides.findLastIndex(Boolean);
    const actionsFor=projection.actionsFor??(id=>id==="natural"&&!editedPlans.has(id)?cycleActions(id):steps[id]);
    const ids=[...new Set([...(manualMode&&!results.length?["natural"]:!manualMode&&lastOverride>=0?["natural"]:[]),...results.map(({id})=>id)])].filter(id=>actionsFor(id).length);
    const completed=new Map(results.map(({id,data})=>[id,data?.completed??0]));
    const natural=ids.includes("natural")&&!completed.has("natural")?projectCycles("natural",Infinity,{end,continuous:true,partialBudget:projection.partialBudget??budget}):null;
    if(natural)completed.set("natural",natural.completed);
    let best=null;
    const consider=(data,sequence)=>{
      if(!data||data.errors.length||finishWindow&&(!data.firstCycle||data.elapsed<end-1e-6))return;
      if(!best||data.gain>best.data.gain+1e-7||(manualMode&&Math.abs(data.gain-best.data.gain)<=1e-7&&(sequence?.length??0)>(best.sequence?.length??0)))best={data,sequence};
    };
    const affordable=data=>{
      if(!weeklySpend)return true;
      const cost=weeklySpend(data);
      return cost!==null&&cost<=budget;
    };
    if(lastOverride<0&&!manualMode){
      for(const {data} of results)if(data&&affordable(data))consider(data);
      if(natural&&affordable(natural))consider(natural);
    }
    const evaluated=new Map();
    // Search each pair independently so a newly selected plan cannot evict
    // promising prefixes from a search over plans that were already selected.
    for(const [i,first] of ids.entries())for(const second of ids.slice(i)){
      const pair=first===second?[first]:[first,second];
      const maxDepth=manualMode||lastOverride>=0?slots:Math.max(...pair.map(id=>completed.get(id)??0),1,minDepth)+5;
      let finalists=[];
      let frontier=[{sequence:[]}];
      for(let index=0;index<maxDepth&&frontier.length;index++){
        const next=[];
        const choices=overrides[index]?[overrides[index]]:pair;
        for(const parent of frontier)for(const id of choices){
          const sequence=[...parent.sequence,id];
          // Manual slots choose the prefix. The last resolved slot then
          // repeats through the shared window, just like a standalone plan.
          const repeatLast=(manualMode||lastOverride>=0)&&sequence.length===slots;
          const key=sequence.join(",");
          let data=evaluated.get(key);
          if(!data){data=mixedProjection(sequence,end,{partialBudget:budget,...projection,actionsFor,repeatLast});evaluated.set(key,data);}
          if(!affordable(data))continue;
          if(index>=lastOverride&&!data.errors.length&&(data.segments.length>Math.max(-1,lastOverride)&&data.segments.length>0||finishWindow&&data.partialSegment)){
            consider(data,sequence);
            if(finishWindow&&data.complete&&data.elapsed<end&&data.firstCycle){
              finalists.push({data,sequence});
              finalists.sort((a,b)=>b.data.gain-a.data.gain||a.data.elapsed-b.data.elapsed);
              finalists=finalists.slice(0,3);
            }
          }
          if(data.complete&&data.elapsed<end&&(!parent.data||data.elapsed>parent.data.elapsed||
            data.gain>parent.data.gain))next.push({sequence,data});
        }
        next.sort((a,b)=>b.data.gain-a.data.gain||a.data.elapsed-b.data.elapsed);
        frontier=next.slice(0,2);
      }
      if(finishWindow)for(const candidate of finalists){
        const seq=[...candidate.sequence,"natural"];
        const filled=mixedProjection(seq,end,{...projection,actionsFor,repeatLast:true});
        if(affordable(filled))consider(filled,seq);
      }
    }
    return best;
  }
  function cycleOverrideControls(slots,mixed){
    return '<details class="ts-cycle-overrides" data-ts-manual-settings '+(overridesOpen?"open":"")+'><summary aria-label="Manual cycle settings" title="Manual cycle settings"><span aria-hidden="true">⚙</span></summary>'+
      '<div class="ts-cycle-choices ts-manual-choices"><small class="ts-manual-note">Auto follows selected plans. Explicit choices are preserved. The last cycle repeats only within the chart window.</small>'+Array.from({length:slots},(_,i)=>{
        const picked=cycleOverrides[i]??"",segment=mixed?.data.segments[i]??(i===mixed?.data.segments.length?mixed.data.partialSegment:null);
        const automatic=templates.find(([id])=>id===segment?.id)?.[2];
        return '<label>Cycle '+(i+1)+' <select data-ts-cycle-override="'+i+'">'+
          '<option value="">'+$(automatic?"Auto · "+automatic:"Auto")+'</option>'+
          templates.map(([id,,name])=>'<option value="'+id+'" '+(id===picked?"selected":"")+'>'+$(name)+'</option>').join("")+'</select>'+
          (segment?'<small>'+(segment===mixed?.data.partialSegment?"Incomplete at ":"End ")+clock(segment.at)+' · Duration '+clock(segment.at-segment.start)+'<br>+'+fmt(segment.gain,2)+'</small>':"")+'</label>';
      }).join("")+(mixed?'<small class="ts-manual-note">Completed: '+mixed.data.segments.length+' · Repeated: '+Math.max(0,mixed.data.segments.length-slots)+(mixed.data.partialSegment?" · 1 incomplete":"")+'</small>':"")+'</div></details>';
  }
  function optimizerSettings(key,label){
    return '<details class="ts-cycle-overrides" data-ts-optimizer-settings="'+key+'" '+(optimizerSettingsOpen===key?"open":"")+'>'+
      '<summary aria-label="'+label+' settings" title="'+label+' settings"><span aria-hidden="true">⚙</span></summary>'+
      '<div class="ts-cycle-choices" role="group" aria-label="'+label+' included plans">'+
      templates.map(([id,,name])=>'<label><input type="checkbox" data-ts-optimizer-plan="'+id+'" '+(!excludedPlans[key].has(id)?"checked":"")+'>'+$(name)+'</label>').join("")+
      '</div></details>';
  }
  function cycleBoundaryButton(){
    const label=showCycleBoundaries?"Hide cycle boundaries":"Show cycle boundaries";
    return '<button type="button" class="tc-stat-tab ts-cycle-eye '+(showCycleBoundaries?"is-selected":"")+'" data-ts-cycle-boundaries aria-pressed="'+showCycleBoundaries+'" aria-label="'+label+'" title="'+label+'"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>'+(showCycleBoundaries?"":'<path d="m3 3 18 18"/>')+'</svg></button>';
  }
  function comparisonControls(hours,slots,mixed){
    return '<div class="ts-cycle-controls" aria-label="Stat growth chart range">'+
      '<label>Projection <select data-ts-chart-mode><option value="cycles" '+(chartMode==="cycles"?"selected":"")+'>Cycles</option><option value="continuous" '+(chartMode==="continuous"?"selected":"")+'>Continuous</option></select></label>'+
      (chartMode==="cycles"?'<label>Cycles <input type="number" min="1" max="28" step="1" data-ts-chart-cycles value="'+chartCycles+'"></label>':
      '<label>Days <input type="number" min="1" max="28" step="1" data-ts-chart-days value="'+continuousDays+'"></label>')+
      '<span class="fine-print" title="In Cycles mode, the slowest selected plan sets the window. With only Manual visible, its configured sequence sets the window.">'+fmt(hours,2)+'h shown</span>'+
      '<div class="ts-cycle-actions">'+cycleBoundaryButton()+'<button type="button" class="tc-stat-tab '+(showOptimal?"is-selected":"")+'" title="Maximize projected stat gain from live Energy without a cash budget" data-ts-optimal aria-pressed="'+showOptimal+'">Optimal</button>'+optimizerSettings("optimal","Optimal")+
      '<button type="button" class="tc-stat-tab '+(showOptimalBudget?"is-selected":"")+'" title="Maximize projected stat gain from live Energy within your weekly budget" data-ts-optimal-budget aria-pressed="'+showOptimalBudget+'">Optimal Budget</button>'+optimizerSettings("budget","Optimal Budget")+
      '<button type="button" class="tc-stat-tab '+(showManual?"is-selected":"")+'" data-ts-manual aria-pressed="'+showManual+'">Manual</button>'+
      cycleOverrideControls(slots,mixed)+'</div></div>';
  }
  function render(context,{keepClock=false}={}){
    if(context)ctx=context;
    if(!ctx)return "<p>Connect a stats calculator context first.</p>";
    loadPlanPreferences();if(!keepClock)loadLive();marketInputs();cooldownEffects=applyCooldownPerks();
    const active=activeTemplates();
    const optimize=showOptimal||showOptimalBudget;
    for(const [id] of templates)if(!editedPlans.has(id))steps[id]=cycleActions(id);
    const rangeCycles=templates.map(([id,,label])=>({id,label,data:projectCycles(id,1)}));
    const oneCycle=rangeCycles.filter(({id})=>selected.has(id));
    const shortest=entries=>Math.max(60,...entries.map(({id,data})=>startingTime[id]+data.elapsed));
    p.hours=shortest(rangeCycles)/3600;
    const continuous=chartMode==="continuous",slots=continuous?28:chartCycles;
    const duration=continuous?Math.max(shortest(rangeCycles),continuousDays*86400):null;
    // The cycle count sets a common time window. Faster plans keep repeating
    // throughout that window, with the same cooldowns, refills and inventory.
    const overrides=cycleOverrides.slice(0,slots);
    const manualOnly=showManual&&!active.length&&!optimize;
    const manualSequence=manualOnly?Array.from({length:slots},(_,i)=>overrides[i]||"natural"):null;
    const rangePlans=active.length?active:manualOnly?templates.filter(([id])=>id==="natural"):templates;
    const counted=rangePlans.map(([id,,label])=>({id,label,data:chartCycles===1||continuous?rangeCycles.find(entry=>entry.id===id).data:projectCycles(id,chartCycles)}));
    const forced=!continuous&&manualOnly?mixedProjection(manualSequence,Infinity,{matchTemplateStart:true,actionsFor:id=>id==="natural"&&!editedPlans.has(id)?cycleActions(id):steps[id]}):null;
    const end=duration??(forced?Math.max(60,forced.elapsed):shortest(counted));
    const budget=typeof tornRoadmap==="undefined"?null:tornRoadmap.preferences().weeklyBudget;
    const results=active.map(([id,,label])=>{
      const countedPlan=!continuous&&counted.find(plan=>plan.id===id);
      // A single selected plan must never repeat beyond its requested cycle count.
      // Faster plans may repeat only when another visible plan defines the window.
      const data=countedPlan&&(active.length===1||countedPlan.data.completed<chartCycles||
        startingTime[id]+countedPlan.data.elapsed===end)
        ?countedPlan.data:projectCycles(id,Infinity,{end,continuous:true,partialBudget:budget});
      return {id,label,data};
    });
    const candidates=optimize?templates.map(([id,,label])=>({id,label,data:projectCycles(id,Infinity,{end,continuous:true,liveStart:true})})):[];
    const budgetCandidates=showOptimalBudget?candidates.map(entry=>entry.data.partialSegment?{...entry,data:projectCycles(entry.id,Infinity,{end,continuous:true,partialBudget:budget,liveStart:true})}:entry):[];
    const mixed=showOptimal?optimizeChart(candidates.filter(({id})=>!excludedPlans.optimal.has(id)),slots,end,null,[],{projection:{respectOffset:false}}):null;
    const budgeted=showOptimalBudget?optimizeChart(budgetCandidates.filter(({id})=>!excludedPlans.budget.has(id)),slots,end,budget,[],{projection:{respectOffset:false}}):null;
    const samePlan=results.length===1&&Array.from({length:slots},(_,i)=>!overrides[i]||overrides[i]===results[0].id).every(Boolean);
    const manual=showManual?(samePlan?{data:results[0].data,sequence:Array(slots).fill(results[0].id)}:
      forced?{data:forced,sequence:manualSequence}:
      optimizeChart(results,slots,end,null,overrides,{manualMode:true,projection:{matchTemplateStart:true,partialBudget:budget}})):null;
    if(mixed)results.push({id:"mixed",label:"Optimal sequence",data:mixed.data});
    if(manual)results.push({id:"manual",label:"Manual",data:manual.data});
    if(budgeted)results.push({id:"budget",label:"Optimal Budget",data:budgeted.data});
    const chartHours=end/3600;
    return controls()+(results.length||showManual||optimize?'<div class="ts-layout" data-template-count="'+(oneCycle.length+Number(Boolean(mixed))+Number(Boolean(budgeted)))+'">'+oneCycle.map(x=>section(x.id,x.data,results.find(({id})=>id===x.id).data,chartHours,budget)).join("")+
      (mixed?optimizerCard("optimal","Optimal",mixed.data,chartHours):"")+(budgeted?optimizerCard("optimal-budget","Optimal Budget",budgeted.data,chartHours):"")+'</div>'+
      '<div class="ts-outcomes">'+comparisonControls(chartHours,slots,manual)+(showManual&&!manual?'<p class="fine-print">'+"The manual sequence does not fit this window."+'</p>':"")+
      (showOptimal&&!mixed?'<p class="fine-print">No plans included in Optimal.</p>':"")+(showOptimalBudget&&!budgeted?'<p class="fine-print">No sequence fits the weekly budget.</p>':"")+(results.length?chart(results,chartHours):"")+'</div>':'<p class="fine-print">Select one or more templates above.</p>')+
      '<p class="fine-print">Simulated actions only. Drug cooldown varies; overdoses and addiction are not predicted. '+(tornHappinessBook().active?"Ignorance Is Bliss: Happiness regenerates up to 99,999 without quarter-hour resets. Active effect assumed for the comparison window.":"Happiness resets on Torn quarter-hours.")+' Points refills are limited to one per Torn day.</p>';
  }
  function wire(view){
    if(view.dataset.tsBound==="yes")return;
    view.dataset.tsBound="yes";
    view.addEventListener("toggle",event=>{const el=event.target,id=el.dataset?.tsTimeline;if(!el.isConnected||!id)return;if(el.open)openTimelines.add(id);else openTimelines.delete(id);savePlanPreferences();},true);
    const rowControl=(side,index,attribute,value)=>'[data-ts-side="'+side+'"][data-ts-index="'+index+'"][data-ts-'+attribute+'="'+value+'"]';
    function positionEditor(editor,gear){
      if(!editor||!gear)return;
      const rect=gear.getBoundingClientRect(),w=editor.offsetWidth,h=editor.offsetHeight;
      editor.style.left=Math.max(8,Math.min(rect.left,window.innerWidth-w-8))+"px";
      editor.style.top=Math.max(8,rect.bottom+6+h<=window.innerHeight?rect.bottom+6:rect.top-h-6)+"px";
    }
    view.addEventListener("toggle",event=>{
      const editor=event.target;
      if(editor.matches?.("[data-ts-manual-settings]")&&editor.isConnected)overridesOpen=editor.open;
      const key=editor.dataset?.tsOptimizerSettings;
      if(key&&editor.isConnected){
        if(editor.open)optimizerSettingsOpen=key;
        else if(optimizerSettingsOpen===key)optimizerSettingsOpen="";
      }
      if(editor.matches?.(".ts-row-editor")&&editor.matches(":popover-open")){
        const gear=view.querySelector('[data-ts-gear="'+editor.id+'"]');
        positionEditor(editor,gear);
      }
    },true);
    const rebuild=(focusTarget,options)=>{
      const root=view.querySelector("#tc-sequencer");
      const editorId=root?.querySelector(".ts-row-editor:popover-open")?.id;
      if(root)root.innerHTML=render(undefined,options);
      if(editorId){
        const editor=view.querySelector("#"+editorId),gear=view.querySelector('[data-ts-gear="'+editorId+'"]');
        if(editor&&gear){editor.showPopover();positionEditor(editor,gear);}
      }
      const toggles=view.querySelector(".ts-template-toggles");if(toggles)toggles.outerHTML=templateButtons();
      if(focusTarget)view.querySelector(focusTarget)?.focus({preventScroll:true});
    };
    view.addEventListener("change",event=>{
      const el=event.target;
      if(el.matches("[data-ts-optimizer-plan]")){
        const key=el.closest("[data-ts-optimizer-settings]").dataset.tsOptimizerSettings;
        const id=el.dataset.tsOptimizerPlan;
        if(el.checked)excludedPlans[key].delete(id);else excludedPlans[key].add(id);
        optimizerSettingsOpen=key;
        savePlanPreferences();
        rebuild('[data-ts-optimizer-settings="'+key+'"] [data-ts-optimizer-plan="'+id+'"]',{keepClock:true});
        return;
      }
      if(el.matches("[data-ts-cycle-override]")){
        const index=Number(el.dataset.tsCycleOverride);
        cycleOverrides[index]=templates.some(([id])=>id===el.value)?el.value:"";
        overridesOpen=true;
        savePlanPreferences();
        rebuild('[data-ts-cycle-override="'+index+'"]',{keepClock:true});
        return;
      }
      if(el.matches("[data-ts-chart-mode],[data-ts-chart-cycles],[data-ts-chart-days]")){
        if(el.hasAttribute("data-ts-chart-mode"))chartMode=el.value==="continuous"?"continuous":"cycles";
        if(el.hasAttribute("data-ts-chart-cycles"))chartCycles=Math.floor(clamp(el.value,1,28));
        if(el.hasAttribute("data-ts-chart-days"))continuousDays=Math.floor(clamp(el.value,1,28));
        savePlanPreferences();
        rebuild(el.hasAttribute("data-ts-chart-mode")?"[data-ts-chart-mode]":el.hasAttribute("data-ts-chart-cycles")?"[data-ts-chart-cycles]":"[data-ts-chart-days]",{keepClock:true});
        return;
      }
      if(el.matches("[data-ts-choice]")){const button=el.closest(".ts-add")?.querySelector('[data-ts-op="add"]');if(button)button.disabled=!Object.hasOwn(names,el.value);return;}
      const {tsStartTime,tsStartEnergy}=el.dataset;
      if(tsStartTime&&Object.hasOwn(startingTime,tsStartTime)){
        const time=el.value.trim().match(/^(\d{1,4}):([0-5]?\d):([0-5]?\d)$/);
        if(time){
          startingTime[tsStartTime]=Number(time[1])*3600+Number(time[2])*60+Number(time[3]);
          savePlanPreferences();
          rebuild(el===document.activeElement?'[data-ts-start-time="'+tsStartTime+'"]':null);
        }else el.value=clock(startingTime[tsStartTime]);
        return;
      }
      if(tsStartEnergy&&Object.hasOwn(startingEnergy,tsStartEnergy)){
        startingEnergy[tsStartEnergy]=["zero","full","current"].includes(el.value)?el.value:defaultEnergy[tsStartEnergy];
        savePlanPreferences();
        rebuild(el===document.activeElement?'[data-ts-start-energy="'+tsStartEnergy+'"]':null);
        return;
      }
      if(el.matches("[data-ts-candy]")){p.candyHappy=Number(el.value);rebuild();return;}
      const param=el.dataset.tsParam;
      if(param && !["startDrugMin","startBoosterMin","resetAfterSec","tornClockMin","boosterCapH","dvdHappy","xanaxCDMin","ecstasyCDMin","candyCDMultiplier","dvdCDMultiplier"].includes(param) && Object.hasOwn(p,param)){p[param]=clamp(el.value,Number(el.min),Number(el.max));rebuild();return;}
      if(el.hasAttribute("data-ts-auto")){p.autoWait=el.checked;rebuild();return;}
      if(el.hasAttribute("data-ts-status")){
        if(["auto","standard","donator","subscriber"].includes(el.value))p.energyStatus=el.value;
        rebuild();return;
      }
      const edit=el.dataset.tsEdit,side=el.dataset.tsSide,index=Number(el.dataset.tsIndex);
      if(edit&&steps[side]&&steps[side][index]){
        const a=steps[side][index];
        editedPlans.add(side);
        if(edit==="type")steps[side][index]=make(el.value);
        if(edit==="qty"){a.max=false;a.qty=clamp(Math.floor(n(el.value,0)),0,a.type==="candy"?maxCandy(p):a.type==="dvd"?maxDvd(p):1);}
        if(edit==="candy-tier")a.candyHappy=el.value==="any"?"any":Number(el.value);
        if(edit==="minutes")a.minutes=clamp(el.value,0,10080);
        savePlanPreferences();
        rebuild(el===document.activeElement?rowControl(side,index,"edit",edit):null);
      }
    });
    view.addEventListener("click",event=>{
      const boundary=event.target.closest("[data-ts-cycle-boundaries]");
      if(boundary){
        showCycleBoundaries=!showCycleBoundaries;
        savePlanPreferences();
        view.querySelectorAll(".ts-chart").forEach(svg=>svg.classList.toggle("show-cycle-boundaries",showCycleBoundaries));
        boundary.outerHTML=cycleBoundaryButton();
        view.querySelector("[data-ts-cycle-boundaries]")?.focus({preventScroll:true});
        return;
      }
      if(event.target.closest("[data-ts-manual]")){
        showManual=!showManual;
        savePlanPreferences();
        rebuild("[data-ts-manual]",{keepClock:true});
        return;
      }
      if(event.target.closest("[data-ts-optimal-budget]")){
        showOptimalBudget=!showOptimalBudget;
        savePlanPreferences();
        rebuild("[data-ts-optimal-budget]");
        return;
      }
      if(event.target.closest("[data-ts-optimal]")){
        showOptimal=!showOptimal;
        savePlanPreferences();
        rebuild("[data-ts-optimal]");
        return;
      }
      const settings=event.target.closest("[data-ts-settings]");if(settings){settingsOpen=!settingsOpen;settings.setAttribute("aria-expanded",String(settingsOpen));settings.classList.toggle("is-selected",settingsOpen);const panel=view.querySelector("#ts-plan-settings");if(panel)panel.hidden=!settingsOpen;return;}
      const template=event.target.closest("[data-ts-template]");if(template){const id=template.dataset.tsTemplate;if(selected.has(id))selected.delete(id);else selected.add(id);savePlanPreferences();rebuild(undefined,{keepClock:true});view.querySelector('[data-ts-template="'+id+'"]')?.focus();return;}
      const mode=event.target.closest("[data-ts-cooldown-mode]");
      if(mode){event.preventDefault();if(mode.dataset.tsCooldownMode==="drug")liveDrug=!liveDrug;else liveBooster=!liveBooster;rebuild();return;}
      const cap=event.target.closest("[data-ts-cap]");if(cap){event.preventDefault();if(apiBoosterCap===null)manualBoosterCap=manualBoosterCap===24?48:24;rebuild();return;}
      const el=event.target.closest("[data-ts-op],[data-ts-sync]");
      if(!el)return;
      if(el.hasAttribute("data-ts-sync")){loadLive(true);rebuild();return;}
      const side=el.dataset.tsSide,op=el.dataset.tsOp,index=Number(el.dataset.tsIndex),list=steps[side];
      if(!list)return;
      let focusTarget;
      if(op==="max"&&list[index]){list[index].max=true;focusTarget=rowControl(side,index,"op",op);}
      else if(op==="preset"){editedPlans.delete(side);steps[side]=defaults[side]();}
      else if(op==="add"){
        const select=view.querySelector('[data-ts-choice="'+side+'"]');
        if(select&&Object.hasOwn(names,select.value)&&list.length<40)list.push(make(select.value));else return;
      }else if(op==="remove"){
        list.splice(index,1);
        focusTarget=list.length?rowControl(side,Math.min(index,list.length-1),"edit","type"):'[data-ts-choice="'+side+'"]';
      }else if(op==="up"||op==="down"){
        const target=index+(op==="up"?-1:1);
        if(target<0||target>=list.length)return;
        [list[target],list[index]]=[list[index],list[target]];
        focusTarget=rowControl(side,Math.max(0,Math.min(target,list.length-1)),"op",op);
      }else return;
      if(op!=="preset")editedPlans.add(side);
      savePlanPreferences();
      rebuild(el===document.activeElement?focusTarget:null);
    });
  }
  return {render,wire,simulate,weeklyPrograms,liveInputs,periodPurchases,replayRemaining,waitTitle,happyResetWait,energyRefillUsedToday,steps,settings:p,loadLive,templateButtons};
})();
