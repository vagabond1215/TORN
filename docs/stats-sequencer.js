"use strict";
const tornTrainSequence=(()=>{
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
  let settingsOpen=false,chartMode="cycles",chartCycles=1,continuousDays=7,cycleOverrides=[],overridesOpen=false,showOptimal=true,showOptimalBudget=false;
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
    showOptimal=saved?.showOptimal!==false;
    showOptimalBudget=saved?.showOptimalBudget===true;
    selected.clear();openTimelines.clear();editedPlans.clear();
    for(const id of (Array.isArray(saved?.selected)?saved.selected:["natural","jump"]))if(valid.has(id))selected.add(id);
    for(const id of (Array.isArray(saved?.expanded)?saved.expanded:[]))if(valid.has(id))openTimelines.add(id);
    for(const [id] of templates){
      const plan=saved?.plans?.[id];
      startingEnergy[id]=["zero","full"].includes(plan?.energy)?plan.energy:defaultEnergy[id];
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
    try{localStorage.setItem("torn-city-guide:plan-view:"+planPreferenceOwner,JSON.stringify({selected:[...selected],expanded:[...openTimelines],plans,chartMode,chartCycles,continuousDays,cycleOverrides,showOptimal,showOptimalBudget}));}catch{}
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
    const stock=candyStock(),pool=stock.rows.map(x=>({...x})).sort((a,b)=>b.happy-a.happy||(a.price??Infinity)-(b.price??Infinity));
    const dvdInventory=tornGuideApi.state.inventory.Booster;
    const dvdKnown=Array.isArray(dvdInventory)&&!tornGuideApi.state.inventoryErrors?.Booster;
    const dvdHeld=dvdKnown?dvdInventory.filter(x=>keyName(x.name??x.item?.name??itemList().find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id))?.name)===keyName("Erotic DVD")).reduce((sum,x)=>sum+Math.max(0,Math.floor(n(x.amount??x.quantity))),0):null;
    const rowInfo={},notices=[],actionStates={};let rowCandy=null,rowUsed=null;
    let candyCost=0,candyGain=0,unknownCandyPrice=false;
    const gym=ctx.gym,stat=ctx.state.compareStat,limit=cfg.limitSeconds??Math.floor(cfg.hours*3600);
    const rule=energyRules(),eCap=rule.cap;
    const boosterLimit=cfg.boosterCapH*3600;
    const regenTime=rule.minutes*60;
    const gymCost=Math.max(1,Math.floor(gym.energy));
    const mult=ctx.effectsFor(stat).multiplier;
    const initialE=cfg.startEnergy==="zero"?0:cfg.startEnergy==="full"?eCap:Math.min(Math.max(0,ctx.state.currentEnergy),1000);
    const v={time:0,stat:base,energy:initialE,happy:ctx.state.happy,drug:Math.round(cfg.startDrugMin*60),booster:Math.round(cfg.startBoosterMin*60),
      costs:{xanax:0,ecstasy:0,dvd:0,candy:0,refill:0},used:0,log:[],errors:[],series:[{h:0,s:base}],days:new Set(),lostRegen:0,warnings:[]};
    const snap=()=>({time:v.time,energy:v.energy,happy:v.happy,drug:v.drug,booster:v.booster,stat:v.stat});
    if(cfg.refillUsedToday)v.days.add(Math.floor(cfg.tornClockMin*60/86400));
    const initial=snap();
    const canTrain=n(gym[stat])>0&&gymCost<=eCap;
    const nextEnergyTick=()=>(Math.floor(v.time/regenTime)+1)*regenTime;
    function fullEnergyDelay(){
      const ticks=Math.max(0,Math.ceil((eCap-v.energy)/5));
      return ticks?nextEnergyTick()+(ticks-1)*regenTime-v.time:0;
    }
    v.peakHappy=v.happy;
    const point=()=>{v.peakHappy=Math.max(v.peakHappy,v.happy);const last=v.series[v.series.length-1],h=v.time/3600;if(Math.abs(last.h-h)<1e-8)last.s=v.stat;else v.series.push({h,s:v.stat});};
    function train(){
      if(v.energy<gymCost || n(gym[stat])<=0)return 0;
      const out=ctx.trainBlock(v.stat,v.happy,v.energy,gym,stat,mult);
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
        if(next===eTick){if(v.energy<eCap)v.energy=Math.min(eCap,v.energy+5);else v.lostRegen+=5;}
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
          if(candy.price===null)unknownCandyPrice=true;else candyCost+=candy.price;
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
      if(type==="train"){
        if(a.when==="full"&&!waitFor(fullEnergyDelay(),"Full Energy",false))return false;
        if(a.when==="drug"&&beforeXanax&&!waitFor(v.drug,"Drug cooldown before Xanax"))return false;
      }
      if(type==="refill"){
        const used=v.days.has(tornDay());
        if(used&&boostedRefill){
          notices.push({index:i,text:"Refill skipped: already used today. Train before Happiness resets."});
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
        const warning="99k assumes coordinated Poison Mistletoe use; its cost is not included.";
        if(!v.warnings.includes(warning))v.warnings.push(warning);
      }else if(type==="train")train();
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
      if(executed)v.log.push({i:i+1,type,parent:i,editable:!automatic,midnightRefill,start,end,reason:type==="wait"&&a.untilDrug?"Drug cooldown":undefined,quantity:isBooster?(type==="candy"?Object.values(rowUsed).reduce((sum,q)=>sum+q,0):v.costs.dvd-rowInfo[i].dvdBefore):1});
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
      if(cutoff)v.warnings.push("The "+cfg.hours+"-hour window ended before all actions could run.");
      const prices=[[v.costs.xanax,cfg.xanaxPrice],[v.costs.ecstasy,cfg.ecstasyPrice],[v.costs.dvd,cfg.dvdPrice],[v.costs.refill*30,cfg.pointPrice]];
      const missingPrice=unknownCandyPrice||prices.some(([qty,price])=>qty>0&&price==null);
      return {...v,final:v.stat,gain:v.stat-base,complete:v.errors.length===0,candyGain,rowInfo,notices,actionStates,initial,
        money:missingPrice||list.some(x=>x.type==="externalHappy")?null:candyCost+prices.reduce((sum,[qty,price])=>sum+qty*(price??0),0)};
    }
    return {state:v,limit,gymCost,canTrain,fullEnergyDelay,advance,waitFor,execute,run,finish};
  }
  function trainingPurchases(pointsHeld=0){
    const items=itemList();
    const owned=(name,category)=>{
      const list=tornGuideApi.state.inventory[category];
      if(!Array.isArray(list)||tornGuideApi.state.inventoryErrors?.[category])return 0;
      return list.reduce((sum,item)=>{
        const id=item.id??item.item_id??item.item?.id;
        const itemName=item.name??item.item?.name??items.find(entry=>String(entry.id)===String(id))?.name;
        return keyName(itemName)===keyName(name)?sum+Math.max(0,Math.floor(n(item.amount??item.quantity))):sum;
      },0);
    };
    const supplies=[
      ["xanax","Xanax",owned("Xanax","Drug"),p.xanaxPrice,1],
      ["ecstasy","Ecstasy",owned("Ecstasy","Drug"),p.ecstasyPrice,1],
      ["dvd","Erotic DVD",owned("Erotic DVD","Booster"),p.dvdPrice,1],
      ["refill","Points",pointsHeld,p.pointPrice,30]
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
      const now=new Date(),cd=readCooldowns(),stamp=Number(tornGuideApi.state.fetchedAt?.cooldowns),elapsed=stamp>0?Math.max(0,(Date.now()-stamp)/60000):0;
      const clockMin=now.getUTCHours()*60+now.getUTCMinutes()+now.getUTCSeconds()/60;
      Object.assign(p,{startDrugMin:Math.max(0,(cd?.drug??0)-elapsed),startBoosterMin:Math.max(0,(cd?.booster??0)-elapsed),boosterCapH:detectedBoosterCap()??manualBoosterCap,tornClockMin:clockMin,resetAfterSec:900-(now.getUTCMinutes()%15*60+now.getUTCSeconds()),autoWait:true});
      if(budget==null&&!options.naturalOnly)return [];
      const cash=Math.max(0,Number(budget)||0),excludeOwned=options.excludeOwned!==false;
      const purchases=trainingPurchases();
      const cashCost=result=>excludeOwned?purchases(result.costs).cost:result.money;
      const candidates=templates.filter(([id])=>options.naturalOnly?id==="natural":id!=="custom"||editedPlans.has(id));
      // Match the Plan comparison preparation window, including saved jump actions.
      let blockHours=24;
      for(const [id] of candidates.filter(([id])=>id==="jump"||id==="maxhappy")){
        const engine=createEngine({hours:Infinity,startEnergy:startingEnergy[id],autoWait:true,midnightJump:midnightJumps.has(id),refillUsedToday:energyRefillUsedToday()},true);
        engine.run(editedPlans.has(id)?steps[id]:defaults[id]());
        blockHours=Math.max(blockHours,Math.ceil(engine.state.time/36)/100);
      }
      if(!Number.isFinite(blockHours)||blockHours>168)blockHours=168;
      p.hours=blockHours;
      const cfg={startEnergy:"current",autoWait:true,refillUsedToday:energyRefillUsedToday(now)},results=[];
      function naturalUntil(engine,end){
        const v=engine.state;
        while(v.time<end&&!v.errors.length){
          if(v.energy>=energyRules().cap)engine.execute(make("train"),0);
          const delay=Math.min(end-v.time,engine.fullEnergyDelay()||end-v.time);
          if(delay<=0)break;
          engine.waitFor(delay,"Full Energy",false);
        }
        if(v.energy>=engine.gymCost)engine.execute(make("train"),0);
      }
      function runProgram(id,actions,cycles,hours,captureCycle=false,allowPartialDvd=false){
        const engine=createEngine({...cfg,hours,allowPartialDvd,midnightJump:midnightJumps.has(id)}),v=engine.state,executed=[];
        let cycle=null;
        for(let week=0;week<hours/168&&!v.errors.length;week++){
          const weekEnd=Math.min(engine.limit,(week+1)*604800);
          for(let k=0;k<cycles&&!v.errors.length&&v.time<weekEnd;k++){
            const end=Math.min(weekEnd,week*604800+Math.round((k+1)*blockHours*3600));
            // No free energy or cooldown reset between repetitions.
            if(startingEnergy[id]==="zero"&&v.energy>=engine.gymCost){
              if(actions[0]?.type==="xanax")engine.waitFor(v.drug,"Drug cooldown",false);
              engine.execute(make("train"),0);
            }else if(startingEnergy[id]==="full"&&v.energy<energyRules().cap)engine.waitFor(engine.fullEnergyDelay(),"Full Energy",false);
            if(!engine.run(actions))break;
            executed.push(...actions);
            if(captureCycle&&id!=="natural"&&!cycle){
              const first=engine.finish(executed,{tail:false});
              cycle={length:first.log.filter(step=>step.type!=="happyReset").length,spend:cashCost(first)};
            }
            if(v.time<end)naturalUntil(engine,end);
            else if(v.energy>=engine.gymCost)engine.execute(make("train"),0);
          }
          if(!v.errors.length)naturalUntil(engine,weekEnd);
        }
        return {result:engine.finish(executed),executed,cycle};
      }
      const templatesById=new Map();
      for(const [id,short,label] of candidates){
        const actions=(options.naturalOnly?[]:editedPlans.has(id)?steps[id]:defaultActions(id)).map(x=>({...x}));
        // External happiness has no verified price, so cannot establish affordability.
        if(actions.some(x=>x.type==="externalHappy"||options.blockDrugs&&["xanax","ecstasy"].includes(x.type)))continue;
        templatesById.set(id,actions);
        const maxCycles=id==="natural"?1:Math.max(1,Math.floor(168/blockHours));
        let best=null;
        const dvdModes=actions.some(step=>step.type==="dvd"&&!step.max)?[false,true]:[false];
        for(const allowPartialDvd of dvdModes)for(let cycles=1;cycles<=maxCycles;cycles++){
          const {result,executed}=runProgram(id,actions,cycles,168,false,allowPartialDvd);
          const spend=cashCost(result);
          if(!result.complete||spend==null||spend>cash||executed.length!==actions.length*cycles)continue;
          if(id!=="natural"&&result.costs.xanax+result.costs.ecstasy+result.costs.dvd+result.costs.candy+result.costs.refill===0)continue;
          const candidate={id,label:short+" · "+label,gain:result.gain,money:result.money,cashCost:spend,excludeOwned,used:result.used,costs:result.costs,cycles,blockHours,allowPartialDvd,drugRisk:result.costs.xanax+result.costs.ecstasy>0,source:"plan",timing:{xanaxCD:Math.round(p.xanaxCDMin*60),ecstasyCD:Math.round(p.ecstasyCDMin*60),boosterCap:p.boosterCapH*3600,candyCD:Math.round(1800*p.candyCDMultiplier),dvdCD:Math.round(21600*p.dvdCDMultiplier)},startEnergy:startingEnergy[id],generatedAt:now.getTime(),execution:trainingExecution(result.log)};
          if(!best||candidate.gain>best.gain||candidate.gain===best.gain&&candidate.cashCost<best.cashCost)best=candidate;
        }
        if(best)results.push(best);
      }
      results.sort((a,b)=>b.gain-a.gain||a.cashCost-b.cashCost);
      let selected=results[0];
      let mixed=null;
      const actionsFor=id=>editedPlans.has(id)?steps[id]:cycleActions(id);
      if(selected&&!options.naturalOnly){
        const ids=[...templatesById.keys()];
        const lead=Math.max(1,Math.ceil(168/blockHours));
        const proposal=optimizeCycles(ids,Math.min(14,2*lead),604800,true,{
          cap:cash,priceOf:cashCost,overrides:[],projection:{actionsFor,respectOffset:false,refillUsedToday:cfg.refillUsedToday}
        });
        if(proposal?.data.firstCycle&&proposal.data.gain>selected.gain){
          mixed=proposal;
          const id=mixed.sequence[0],first=mixed.data.firstCycle;
          const [,,label]=templates.find(entry=>entry[0]===id);
          const data=mixed.data;
          selected={...selected,id,label:label+" · Mixed weekly plan",source:"mixed",startEnergy:startingEnergy[id],
            gain:data.gain,money:data.money,used:data.used,costs:data.costs,cashCost:cashCost(data),cycles:mixed.sequence.length,
            drugRisk:first.costs.xanax+first.costs.ecstasy>0,execution:trainingExecution(data.log),
            cycleExecution:trainingExecution(first.log),cycleSpend:cashCost(first)};
          results.unshift(selected);
        }
      }
      if(selected){
        if(!mixed&&selected.id==="natural"){
          const train=selected.execution.findIndex(step=>step.type==="train"&&step.energy>0);
          selected.cycleExecution=train<0?[]:selected.execution.slice(0,train+1);
          selected.cycleSpend=0;
        }else if(!mixed){
          const {cycle}=runProgram(selected.id,templatesById.get(selected.id),selected.cycles,168,true,selected.allowPartialDvd);
          selected.cycleExecution=cycle?selected.execution.slice(0,cycle.length):selected.execution;
          selected.cycleSpend=cycle?.spend??null;
        }
        const forecastDays=options.restockForecastDays;
        const horizons=[...new Set([1,7,28,...(Number.isInteger(forecastDays)&&forecastDays>=1&&forecastDays<=28?[forecastDays]:[])])];
        const periods=horizons.map(days=>{
          const result=days===7?selected:mixed?
            mixedProjection(Array.from({length:Math.ceil(days/7)},()=>mixed.sequence).flat(),days*86400,
              {actionsFor,respectOffset:false,fill:true,refillUsedToday:cfg.refillUsedToday}):
            runProgram(selected.id,templatesById.get(selected.id),selected.cycles,days*24,false,selected.allowPartialDvd).result;
          if(days===forecastDays)selected.restockCosts=result.costs;
          const unavailable=result.complete===false&&(!mixed||result.errors?.length);
          return {days,gain:unavailable?null:result.gain,value:unavailable?null:result.money,
            energy:unavailable?null:result.used,costs:unavailable?null:result.costs};
        });
        selected.periods=periods.filter(period=>[1,7,28].includes(period.days));
      }
      return results;
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
          const wanted=Math.min(context.state.maxEnergy,Math.max(engine.gymCost,Number(row.energy)||engine.gymCost));
          if(next?.type==="xanax"&&Number(next.at)===Number(row.at))engine.advance(v.drug);
          if(v.energy<wanted)engine.advance(Math.max(0,Math.ceil((wanted-v.energy)/5))*energyRules().minutes*60);
        }
        if(type==="refill"&&v.energy>=context.state.maxEnergy)continue; // no benefit from refilling full energy
        const a=make(type,Math.max(1,Math.floor(Number(row.quantity)||1)));
        if(type==="candy")a.candyHappy="any";
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
    engine.run(list);
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
    const label=e.type==="autoWait"?waitTitle(e.reason)+" "+clock(e.end.time-e.start.time):e.type==="happyReset"?"Happiness reset":(names[e.type]??e.type)+(e.reason?" · "+e.reason:"");
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
    let rows='<tr class="ts-initial"><td><input class="ts-start-time" type="text" inputmode="numeric" data-ts-start-time="'+side+'" value="'+clock(offset)+'" aria-label="Starting time in hours, minutes and seconds" title="Timeline start (H:MM:SS)"></td><td><div class="ts-start-energy"><strong>Starting Energy</strong><select data-ts-start-energy="'+side+'" aria-label="Starting Energy"><option value="zero" '+(startingEnergy[side]==="zero"?"selected":"")+'>0 E</option><option value="full" '+(startingEnergy[side]==="full"?"selected":"")+'>'+energyRules().cap+' E</option></select></div></td>'+timelineCells(data.initial)+'</tr>';
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
  function section(side,data){
    const heading=templates.find(x=>x[0]===side)?.[2]??side;
    const metric=(label,value,extra="")=>'<span class="ts-title-metric '+extra+'"><small>'+label+'</small><strong>'+value+'</strong></span>';
    return '<details class="ts-side ts-template-card" data-ts-timeline="'+side+'" '+(openTimelines.has(side)?"open":"")+'><summary class="ts-template-header"><span class="ts-template-name">'+$(heading)+'</span>'+
      metric("Cycle",fmt(data.elapsed/3600,2)+"h")+metric("Energy used",fmt(data.used)+" E")+metric("Stat change",data.complete?(data.gain>=0?"+":"")+fmt(data.gain,2):"Blocked","ts-title-gain")+metric("Ending stat",data.complete?fmt(data.final,2):"—")+metric("Cost",data.money==null?"Unavailable":"$"+fmt(data.money))+
      '<span class="ts-template-chevron" aria-hidden="true"></span></summary>'+mergedTimeline(side,data)+
      (side==="maxhappy"?'<p class="fine-print">99,999 Happy target · Peak '+fmt(data.peakHappy??0)+' · '+((data.peakHappy??0)>=99999?"Target reached":"Additional happiness source required")+'</p>':"")+(data.warnings.length?'<p class="fine-print">'+data.warnings.map($).join("; ")+'</p>':"")+(data.errors.length?'<p class="ts-error">'+data.errors.map($).join("; ")+'</p>':"")+
      '</details>';
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
    const seriesClass=(id,data)=>"ts-series ts-series-"+id+(data.complete?"":" is-blocked");
    const endpoint=(x,y)=>'<circle class="ts-series-end" cx="'+x+'" cy="'+y+'" r="3"/>';
    let out='<svg viewBox="0 0 910 260" class="ts-chart" role="img" aria-label="Projected stat growth over '+hours+' hours">';
    for(let i=0;i<5;i++){
      const val=bottom+(top-bottom)*i/4,y=yval(val),hr=hours*i/4;
      out+='<line x1="80" y1="'+y+'" x2="'+xval(hours)+'" y2="'+y+'" class="ts-gridline"/><text x="74" y="'+(y+4)+'" font-size="11" text-anchor="end">'+fmt(val)+'</text><text x="'+xval(hr)+'" y="234" font-size="11" text-anchor="middle">'+fmt(hr,2)+'h</text>';
    }
    for(const {id,data} of results){
      // The simulator coalesces events at the same time. Restore the pre-action
      // value for the chart when an immediate train changes the first point.
      const points=[...data.series,{h:hours,s:data.final}];
      if(points[0].h!==0||points[0].s!==data.initial.stat)points.unshift({h:0,s:data.initial.stat});
      out+='<g class="'+seriesClass(id,data)+'"><path class="ts-series-stroke" d="'+path(points)+'"/>'+endpoint(xval(hours),yval(data.final))+'</g>';
    }
    return out+'</svg><div class="ts-legend ts-multi-legend">'+results.map(({id,label,data})=>'<span><svg class="'+seriesClass(id,data)+'" width="44" height="10" aria-hidden="true"><line class="ts-series-stroke" x1="2" y1="5" x2="42" y2="5"/>'+endpoint(35,5)+'</svg> '+$(label)+(data.complete?"":" (blocked)")+'</span>').join("")+'</div>';
  }
  function cycleActions(id){
    return id==="natural"?[{...make("train"),when:"full"}]:defaults[id]();
  }
  function projectCycles(id,cycles,{end=Infinity,continuous=false}={}){
    const list=id==="natural"&&!editedPlans.has(id)?cycleActions(id):steps[id];
    const offset=startingTime[id],clockSeconds=Math.round(p.tornClockMin*60)+offset;
    const engine=createEngine({
      limitSeconds:Math.max(0,end-offset),startEnergy:startingEnergy[id],midnightJump:midnightJumps.has(id),

      startDrugMin:Math.max(0,p.startDrugMin-offset/60),startBoosterMin:Math.max(0,p.startBoosterMin-offset/60),
      tornClockMin:clockSeconds/60,resetAfterSec:900-clockSeconds%900
    });
    const v=engine.state;
    let completed=0;
    const segments=[];
    while(list.length&&completed<cycles&&v.time<=engine.limit){
      const before=v.time,statBefore=v.stat;
      if(completed>0){
        const delay=startingEnergy[id]==="full"?engine.fullEnergyDelay():0;
        if(delay&&!engine.waitFor(delay,"Full Energy",false))break;
      }
      if(!engine.run(list))break;
      completed++;
      segments.push({id,at:offset+v.time,gain:v.stat-statBefore});
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
    return {...data,elapsed:v.time,completed,segments,series:data.series.map(point=>({...point,h:point.h+offset/3600}))};
  }
  function mixedProjection(sequence,end,{fill=false,actionsFor=id=>steps[id],respectOffset=true,allowPartialDvd=false,refillUsedToday=false}={}){
    const first=sequence[0],offset=respectOffset?Math.min(end,startingTime[first]??0):0;
    const clockSeconds=Math.round(p.tornClockMin*60)+offset;
    const engine=createEngine({limitSeconds:end-offset,startEnergy:"current",allowPartialDvd,
      refillUsedToday:refillUsedToday&&clockSeconds<86400,
      startDrugMin:Math.max(0,p.startDrugMin-offset/60),startBoosterMin:Math.max(0,p.startBoosterMin-offset/60),
      tornClockMin:clockSeconds/60,resetAfterSec:900-clockSeconds%900});
    const segments=[];
    let firstCycle=null;
    for(const id of sequence){
      const actions=actionsFor(id),v=engine.state;
      if(!actions.length||v.time>engine.limit)break;
      const before=v.stat;
      if(startingEnergy[id]==="zero"&&actions[0]?.type==="xanax"){
        if(!engine.waitFor(v.drug,"Drug cooldown"))break;
        if(v.energy>=engine.gymCost&&!engine.execute(make("train"),0))break;
      }
      if(startingEnergy[id]==="full"&&v.energy<energyRules().cap&&
        !engine.waitFor(engine.fullEnergyDelay(),"Full Energy",false))break;
      if(!engine.run(actions,{midnightJump:midnightJumps.has(id)}))break;
      segments.push({id,at:offset+v.time,gain:v.stat-before});
      if(!firstCycle){const snapshot=engine.finish(actions,{tail:false});firstCycle={...snapshot,costs:{...snapshot.costs},log:snapshot.log.slice()};}
    }
    const cycleState=engine.finish(sequence.flatMap(actionsFor),{tail:false});
    if(fill&&(segments.length===sequence.length||engine.state.time===engine.limit)){
      while(engine.canTrain){
        const delay=engine.fullEnergyDelay();
        if(engine.state.time+delay>engine.limit)break;
        if(!engine.waitFor(delay,"Full Energy",false)||!engine.execute(make("train"),0))break;
      }
    }
    const data=fill?engine.finish(sequence.flatMap(actionsFor),{tail:!engine.state.errors.length}):cycleState;
    return {...data,complete:data.complete&&segments.length===sequence.length,
      elapsed:offset+data.time,segments,firstCycle,series:data.series.map(point=>({...point,h:point.h+offset/3600}))};
  }
  function weeklyPurchaseCost(){
    const credits=payload("money","money")?.points;
    const purchases=trainingPurchases(Math.floor(positive(credits?.current??credits)??0));
    return data=>{
      const costs={};
      const payments=[];
      let spent=0,previous=0,max=0,first=0;
      for(const event of data.log){
        if(!["xanax","ecstasy","dvd","refill"].includes(event.type))continue;
        costs[event.type]=(costs[event.type]??0)+(event.quantity??1);
        const cost=purchases(costs).cost;
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
  function optimizeChart(results,slots,end,budget=null){
    const weeklySpend=budget==null?null:weeklyPurchaseCost();
    const overrides=cycleOverrides.slice(0,slots);
    const lastOverride=overrides.findLastIndex(Boolean);
    const actionsFor=id=>id==="natural"&&!editedPlans.has(id)?cycleActions(id):steps[id];
    const ids=[...new Set(["natural",...results.map(({id})=>id)])].filter(id=>actionsFor(id).length);
    const maxDepth=Math.max(lastOverride+1, ...results.map(({data})=>data.completed+1),1)+4;
    let best=null,frontier=[{sequence:[]}];
    const consider=data=>{
      if(!best||data.gain>best.data.gain)best={data};
    };
    const affordable=data=>{
      if(!weeklySpend)return true;
      const cost=weeklySpend(data);
      return cost!==null&&cost<=budget;
    };
    if(lastOverride<0){
      for(const {data} of results)if(affordable(data))consider(data);
      if(weeklySpend&&ids.includes("natural")&&!results.some(({id})=>id==="natural")){
        const natural=projectCycles("natural",Infinity,{end,continuous:true});
        if(affordable(natural))consider(natural);
      }
    }
    for(let index=0;index<maxDepth&&frontier.length;index++){
      const next=[];
      const choices=overrides[index]?[overrides[index]]:ids;
      for(const parent of frontier)for(const id of choices){
        const sequence=[...parent.sequence,id],data=mixedProjection(sequence,end,{actionsFor});
        if(!affordable(data))continue;
        if(index>=lastOverride&&data.segments.length>lastOverride&&!data.errors.length)consider(data);
        if(data.complete&&data.elapsed<end&&(!parent.data||data.elapsed>parent.data.elapsed||
          data.gain>parent.data.gain))next.push({sequence,data});
      }
      next.sort((a,b)=>b.data.gain-a.data.gain||a.data.elapsed-b.data.elapsed);
      frontier=next.slice(0,4);
    }
    return best;
  }
  function cycleOverrideControls(slots,mixed){
    return '<details class="ts-cycle-overrides" '+(overridesOpen?"open":"")+'><summary>Cycle overrides</summary>'+
      '<div class="ts-cycle-choices">'+Array.from({length:slots},(_,i)=>{
        const picked=cycleOverrides[i]??"",segment=mixed?.data.segments[i];
        const automatic=templates.find(([id])=>id===segment?.id)?.[2];
        return '<label>Cycle '+(i+1)+' <select data-ts-cycle-override="'+i+'">'+
          '<option value="">'+$(automatic?"Auto · "+automatic:"Auto")+'</option>'+
          templates.map(([id,,name])=>'<option value="'+id+'" '+(id===picked?"selected":"")+'>'+$(name)+'</option>').join("")+'</select>'+
          (segment?'<small>'+clock(segment.at)+' · +'+fmt(segment.gain,2)+'</small>':"")+'</label>';
      }).join("")+'</div></details>';
  }
  function comparisonControls(hours,slots,mixed){
    return '<div class="ts-cycle-controls" aria-label="Stat growth chart range">'+
      '<label>Projection <select data-ts-chart-mode><option value="cycles" '+(chartMode==="cycles"?"selected":"")+'>Cycles</option><option value="continuous" '+(chartMode==="continuous"?"selected":"")+'>Continuous</option></select></label>'+
      (chartMode==="cycles"?'<label>Cycles <input type="number" min="1" max="28" step="1" data-ts-chart-cycles value="'+chartCycles+'"></label>':
      '<label>Days <input type="number" min="1" max="28" step="1" data-ts-chart-days value="'+continuousDays+'"></label>')+
      '<span class="fine-print" title="Each plan repeats within the same comparison window">'+fmt(hours,2)+'h shown</span>'+
      '<div class="ts-cycle-actions"><button type="button" class="tc-stat-tab '+(showOptimal?"is-selected":"")+'" title="Maximize projected stat gain without a cash budget" data-ts-optimal aria-pressed="'+showOptimal+'">Optimal</button>'+
      '<button type="button" class="tc-stat-tab '+(showOptimalBudget?"is-selected":"")+'" title="Maximize projected stat gain within your weekly Energy budget" data-ts-optimal-budget aria-pressed="'+showOptimalBudget+'">Optimal Budget</button>'+
      cycleOverrideControls(slots,mixed)+'</div></div>';
  }
  function render(context){
    if(context)ctx=context;
    if(!ctx)return "<p>Connect a stats calculator context first.</p>";
    loadPlanPreferences();loadLive();marketInputs();cooldownEffects=applyCooldownPerks();
    const active=activeTemplates();
    for(const [id] of templates)if(!editedPlans.has(id))steps[id]=cycleActions(id);
    const oneCycle=active.map(([id,,label])=>({id,label,data:projectCycles(id,1)}));
    const shortest=entries=>Math.max(60,...entries.map(({id,data})=>startingTime[id]+data.elapsed));
    p.hours=shortest(oneCycle)/3600;
    const continuous=chartMode==="continuous",slots=continuous?28:chartCycles;
    const duration=continuous?Math.max(shortest(oneCycle),continuousDays*86400):null;
    // The cycle count sets a common time window. Faster plans keep repeating
    // throughout that window, with the same cooldowns, refills and inventory.
    const counted=continuous||chartCycles===1?oneCycle:active.map(([id,,label])=>({
      id,label,data:projectCycles(id,chartCycles)
    }));
    let end=duration??shortest(counted);
    const overrides=cycleOverrides.slice(0,slots);
    const hasOverrides=overrides.some(Boolean);
    if(!continuous&&hasOverrides){
      const forced=mixedProjection(Array.from({length:slots},(_,i)=>overrides[i]||active[0]?.[0]||"natural"),Infinity);
      end=Math.max(end,forced.elapsed);
    }
    const results=active.map(([id,,label])=>({id,label,data:projectCycles(id,Infinity,{end,continuous:true})}));
    const budget=typeof tornRoadmap==="undefined"?null:tornRoadmap.preferences().weeklyBudget;
    const mixed=(showOptimal||(hasOverrides&&!showOptimalBudget))&&(results.length||hasOverrides)?optimizeChart(results,slots,end):null;
    const budgeted=showOptimalBudget&&(results.length||hasOverrides)?optimizeChart(results,slots,end,budget):null;
    if(mixed)results.push({id:"mixed",label:hasOverrides?"Mixed plan":"Optimal sequence",data:mixed.data});
    if(budgeted)results.push({id:"budget",label:"Optimal Budget",data:budgeted.data});
    const chartHours=end/3600;
    return controls()+(results.length||hasOverrides?'<div class="ts-layout" data-template-count="'+oneCycle.length+'">'+oneCycle.map(x=>section(x.id,x.data)).join("")+'</div>'+
      '<div class="ts-outcomes">'+comparisonControls(chartHours,slots,mixed??budgeted)+(mixed||budgeted||(!showOptimal&&(showOptimalBudget||!hasOverrides))?"" : '<p class="fine-print">No complete mixed sequence fits these settings.</p>')+
      (showOptimalBudget&&!budgeted?'<p class="fine-print">No sequence fits the weekly budget and cycle overrides.</p>':"")+(results.length?chart(results,chartHours):"")+'</div>':'<p class="fine-print">Select one or more templates above.</p>')+
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
      if(editor.matches?.(".ts-cycle-overrides")&&editor.isConnected)overridesOpen=editor.open;
      if(editor.matches?.(".ts-row-editor")&&editor.matches(":popover-open")){
        const gear=view.querySelector('[data-ts-gear="'+editor.id+'"]');
        positionEditor(editor,gear);
      }
    },true);
    const rebuild=(focusTarget)=>{
      const root=view.querySelector("#tc-sequencer");
      const editorId=root?.querySelector(".ts-row-editor:popover-open")?.id;
      if(root)root.innerHTML=render();
      if(editorId){
        const editor=view.querySelector("#"+editorId),gear=view.querySelector('[data-ts-gear="'+editorId+'"]');
        if(editor&&gear){editor.showPopover();positionEditor(editor,gear);}
      }
      const toggles=view.querySelector(".ts-template-toggles");if(toggles)toggles.outerHTML=templateButtons();
      if(focusTarget)view.querySelector(focusTarget)?.focus({preventScroll:true});
    };
    view.addEventListener("change",event=>{
      const el=event.target;
      if(el.matches("[data-ts-cycle-override]")){
        const index=Number(el.dataset.tsCycleOverride);
        cycleOverrides[index]=templates.some(([id])=>id===el.value)?el.value:"";
        overridesOpen=true;
        savePlanPreferences();
        rebuild('[data-ts-cycle-override="'+index+'"]');
        return;
      }
      if(el.matches("[data-ts-chart-mode],[data-ts-chart-cycles],[data-ts-chart-days]")){
        if(el.hasAttribute("data-ts-chart-mode"))chartMode=el.value==="continuous"?"continuous":"cycles";
        if(el.hasAttribute("data-ts-chart-cycles"))chartCycles=Math.floor(clamp(el.value,1,28));
        if(el.hasAttribute("data-ts-chart-days"))continuousDays=Math.floor(clamp(el.value,1,28));
        savePlanPreferences();
        rebuild(el.hasAttribute("data-ts-chart-mode")?"[data-ts-chart-mode]":el.hasAttribute("data-ts-chart-cycles")?"[data-ts-chart-cycles]":"[data-ts-chart-days]");
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
        startingEnergy[tsStartEnergy]=el.value==="zero"?"zero":"full";
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
      const template=event.target.closest("[data-ts-template]");if(template){const id=template.dataset.tsTemplate;if(selected.has(id))selected.delete(id);else selected.add(id);savePlanPreferences();rebuild();view.querySelector('[data-ts-template="'+id+'"]')?.focus();return;}
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
  return {render,wire,simulate,weeklyPrograms,periodPurchases,replayRemaining,waitTitle,happyResetWait,energyRefillUsedToday,steps,settings:p,loadLive,templateButtons};
})();
