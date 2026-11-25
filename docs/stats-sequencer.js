"use strict";
const tornTrainSequence=(()=>{
  const names={externalHappy:"Poison Mistletoe",xanax:"Xanax (+250 E)",ecstasy:"Ecstasy (double Happy)",candy:"Candy (+Happy)",dvd:"Erotic DVD (+2,500 Happy)",train:"Train",refill:"Points energy refill",wait:"Wait minutes"};
  const make=(type,qty=1,minutes=0)=>({type,qty,minutes});
  const actionOptions=Object.entries(names);
  const maxCandyAction=()=>({...make("candy"),max:true});
  const jumpStart=()=>Array.from({length:4},()=>make("xanax"));
  const defaults={
    natural:()=>[],
    maxenergy:()=>[make("xanax"),maxCandyAction(),make("train"),make("refill"),make("train")],
    mini:()=>[make("xanax"),maxCandyAction(),make("ecstasy"),make("train"),make("refill"),make("train")],
    low:()=>[maxCandyAction(),make("ecstasy"),make("train"),make("refill"),make("train")],
    jump:()=>[...jumpStart(),make("dvd",5),make("ecstasy"),make("train"),make("refill"),make("train")],
    maxhappy:()=>[...jumpStart(),make("externalHappy"),make("ecstasy"),make("train"),make("refill"),make("train")],
    custom:()=>[make("train")]
  };
  const recurringTemplates=new Set(["maxenergy","mini","low"]);
  const templates=[["natural","NAT","Natural training"],["maxenergy","MAX E","Maximum Energy"],["mini","MINI","Mini jump"],["low","LOW#","Low-stat jump"],["jump","HJ","Happy jump"],["maxhappy","99k","99k Happy jump"],["custom","CUSTOM","Custom"]];
  const defaultEnergy=Object.fromEntries(templates.map(([id])=>[id,["natural","jump","maxhappy"].includes(id)?"zero":"full"]));
  const startingEnergy={...defaultEnergy};
  const startingTime=Object.fromEntries(templates.map(([id])=>[id,0]));
  const steps=Object.fromEntries(templates.map(([id])=>[id,defaults[id]()]));
  const selected=new Set(["natural","jump"]),openTimelines=new Set(),editedPlans=new Set();
  let settingsOpen=false;
  let planPreferenceOwner;
  function restoreAction(saved){
    if(!saved||typeof saved.type!=="string"||!Object.hasOwn(names,saved.type))return null;
    const action=make(saved.type,Math.floor(clamp(saved.qty,0,10000)),clamp(saved.minutes,0,10080));
    if(saved.type==="train"&&["full","drug"].includes(saved.when))action.when=saved.when;
    if(["candy","dvd"].includes(saved.type)&&saved.max===true)action.max=true;
    if(saved.type==="candy"&&(saved.candyHappy==="any"||positive(saved.candyHappy)))action.candyHappy=saved.candyHappy==="any"?"any":Number(saved.candyHappy);
    return action;
  }
  function loadPlanPreferences(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(planPreferenceOwner===owner)return;
    planPreferenceOwner=owner;
    let saved=null;try{saved=JSON.parse(localStorage.getItem("torn-city-guide:plan-view:"+owner));}catch{}
    const valid=new Set(templates.map(([id])=>id));
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
    try{localStorage.setItem("torn-city-guide:plan-view:"+planPreferenceOwner,JSON.stringify({selected:[...selected],expanded:[...openTimelines],plans}));}catch{}
  }
  function templateButtons(){loadPlanPreferences();return '<div class="ts-template-toggles" role="group" aria-label="Compare templates">'+templates.map(([id,short,label])=>'<button type="button" class="tc-stat-tab '+(selected.has(id)?"is-selected":"")+'" data-ts-template="'+id+'" aria-pressed="'+selected.has(id)+'" title="'+label+'">'+short+'</button>').join("")+'<button type="button" class="tc-stat-tab ts-settings-toggle '+(settingsOpen?"is-selected":"")+'" data-ts-settings aria-expanded="'+settingsOpen+'" aria-controls="ts-plan-settings" title="Time, cooldowns, effects, prices"><span aria-hidden="true">⚙</span> Settings</button></div>';}
  function activeTemplates(){return templates.filter(([id])=>selected.has(id));}
  // Booster quantities are immediate batches. They never hide several hours
  // of waiting between candy and training; users add separate Wait rows.
  const maxCandy=cfg=>Math.max(1,Math.floor(cfg.boosterCapH*3600/
    Math.max(1,Math.round(1800*cfg.candyCDMultiplier)))+1);
  const maxDvd=cfg=>Math.max(1,Math.floor(cfg.boosterCapH*3600/
    Math.max(1,Math.round(21600*cfg.dvdCDMultiplier)))+1);
  const p={hours:28,boosterCapH:24,startDrugMin:0,startBoosterMin:0,xanaxCDMin:420,ecstasyCDMin:215,resetAfterSec:600,tornClockMin:720,candyCDMultiplier:1,dvdCDMultiplier:1,candyHappy:"any",autoWait:true,
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
  function preparationHours(){
    let hours=24;
    for(const [id] of activeTemplates()){
      if(id!=="jump"&&id!=="maxhappy")continue;
      const engine=createEngine({hours:Infinity,startEnergy:startingEnergy[id],autoWait:true},true);
      engine.run(steps[id]);
      hours=Math.max(hours,Math.ceil(engine.state.time/36)/100);
    }
    return hours;
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
    const gym=ctx.gym,stat=ctx.state.compareStat,limit=Math.floor(cfg.hours*3600);
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
        v.happy=Math.min(99999,v.happy+(type==="dvd"?2500:candy.happy));
        v.costs[type]++;
      }
      return true;
    }
    function execute(a,i,{beforeEcstasy=false,beforeXanax=false}={}){
      if(v.errors.length||cutoff)return false;
      rowIndex=i;
      const {type}=a;
      // Wait BEFORE happiness boosters when an Ecstasy action is next, so a
      // drug cooldown does not waste the boost at a quarter-hour reset.
      if(beforeEcstasy&&!waitFor(v.drug,"Drug cooldown before happiness boost"))return false;
      const isBooster=type==="candy"||type==="dvd",tier=a.candyHappy??cfg.candyHappy;
      rowCandy=pool.filter(x=>tier==="any"||x.happy===tier);rowUsed={};
      const itemCD=Math.max(1,Math.round(type==="dvd"?21600*cfg.dvdCDMultiplier:1800*cfg.candyCDMultiplier));
      let allowance=v.booster>boosterLimit?0:Math.floor((boosterLimit-v.booster)/itemCD)+1;
      const held=type==="candy"?(stock.loaded?rowCandy.reduce((sum,x)=>sum+x.qty,0):null):dvdKnown?Math.max(0,dvdHeld-v.costs.dvd):null;
      if(isBooster&&allowance===0&&cfg.startBoosterMin*60>v.time&&v.costs.candy+v.costs.dvd===0&&(a.max?held>0:a.qty>0)){const delay=v.booster-boosterLimit;if(!waitFor(delay,"Booster cooldown"))return false;allowance=Math.floor((boosterLimit-v.booster)/itemCD)+1;}
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
      if(type==="refill"&&v.days.has(tornDay())&&!waitFor((tornDay()+1)*86400-cfg.tornClockMin*60-v.time,"Daily points refill"))return false;
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
        const seconds=Math.max(0,Math.ceil(n(a.minutes)*60));
        cutoff=v.time+seconds>limit;
        advance(seconds);
      }
      else if(type==="refill"){
        v.days.add(tornDay());v.energy=eCap;v.costs.refill++;
      }else{v.errors.push("Unrecognized action: "+type);}
      if(isBooster)rowInfo[i].happy=type==="dvd"?(v.costs.dvd-rowInfo[i].dvdBefore)*2500:Object.entries(rowUsed).reduce((sum,[name,q])=>sum+q*(pool.find(x=>x.name===name)?.happy??0),0);
      point();
      const executed=!v.errors.length&&!cutoff,end=snap();
      actionStates[i]={start,end,executed};
      if(executed)v.log.push({i:i+1,type,parent:i,editable:true,start,end,quantity:isBooster?(type==="candy"?Object.values(rowUsed).reduce((sum,q)=>sum+q,0):v.costs.dvd-rowInfo[i].dvdBefore):1});
      return executed;
    }
    function tornDay(){return Math.floor((cfg.tornClockMin*60+v.time)/86400);}
    function run(list){
      for(let i=0;i<list.length;i++){
        const type=list[i].type;
        const next=["candy","dvd","externalHappy"].includes(type)&&list.slice(i+1).find(x=>["xanax","ecstasy","train","refill"].includes(x.type));
        if(!execute(list[i],i,{beforeEcstasy:next?.type==="ecstasy",beforeXanax:list[i+1]?.type==="xanax"}))return false;
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
    return {state:v,limit,gymCost,canTrain,fullEnergyDelay,advance,execute,run,finish};
  }
  // Home recommendations replay the same saved/default Plan templates with
  // one continuous weekly engine; no independent strategy definitions.
  function weeklyPrograms(context,budget,risk,options={}){
    const previous=ctx,old={...p};
    try{
      ctx=context;loadPlanPreferences();marketInputs();applyCooldownPerks();
      const now=new Date(),cd=readCooldowns(),stamp=Number(tornGuideApi.state.fetchedAt?.cooldowns),elapsed=stamp>0?Math.max(0,(Date.now()-stamp)/60000):0;
      const clockMin=now.getUTCHours()*60+now.getUTCMinutes()+now.getUTCSeconds()/60;
      Object.assign(p,{startDrugMin:Math.max(0,(cd?.drug??0)-elapsed),startBoosterMin:Math.max(0,(cd?.booster??0)-elapsed),boosterCapH:detectedBoosterCap()??manualBoosterCap,tornClockMin:clockMin,resetAfterSec:900-(now.getUTCMinutes()%15*60+now.getUTCSeconds()),autoWait:true});
      if(budget==null)return [];
      const cash=Math.max(0,Number(budget)||0),excludeOwned=options.excludeOwned!==false;
      const owned=(name,cat)=>{
        const list=tornGuideApi.state.inventory[cat];
        if(!Array.isArray(list)||tornGuideApi.state.inventoryErrors?.[cat])return 0;
        const items=itemList();
        return list.filter(x=>keyName(x.name??x.item?.name??items.find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id))?.name)===keyName(name)).reduce((sum,x)=>sum+Math.max(0,Math.floor(n(x.amount??x.quantity))),0);
      };
      const held={xanax:owned("Xanax","Drug"),ecstasy:owned("Ecstasy","Drug"),dvd:owned("Erotic DVD","Booster")};
      function cashCost(result){
        if(!excludeOwned)return result.money;
        // Candy simulation consumes only verified inventory; count each owned unit once.
        const prices=[[Math.max(0,result.costs.xanax-held.xanax),p.xanaxPrice],[Math.max(0,result.costs.ecstasy-held.ecstasy),p.ecstasyPrice],[Math.max(0,result.costs.dvd-held.dvd),p.dvdPrice],[result.costs.refill*30,p.pointPrice]];
        return prices.some(([qty,price])=>qty>0&&price==null)?null:prices.reduce((sum,[qty,price])=>sum+qty*(price??0),0);
      }
      const candidates=templates.filter(([id])=>id!=="custom"||editedPlans.has(id));
      // Match the Plan comparison preparation window, including saved jump actions.
      let blockHours=24;
      for(const [id] of candidates.filter(([id])=>id==="jump"||id==="maxhappy")){
        const engine=createEngine({hours:Infinity,startEnergy:startingEnergy[id],autoWait:true},true);
        engine.run(editedPlans.has(id)?steps[id]:defaults[id]());
        blockHours=Math.max(blockHours,Math.ceil(engine.state.time/36)/100);
      }
      if(!Number.isFinite(blockHours)||blockHours>168)blockHours=168;
      p.hours=blockHours;
      const cfg={hours:168,startEnergy:"current",autoWait:true},results=[];
      function naturalUntil(engine,end){
        const v=engine.state;
        while(v.time<end&&!v.errors.length){
          if(v.energy>=energyRules().cap)engine.execute(make("train"),0);
          const delay=Math.min(end-v.time,engine.fullEnergyDelay()||end-v.time);
          if(delay<=0)break;
          engine.advance(delay);
        }
        if(v.energy>=engine.gymCost)engine.execute(make("train"),0);
      }
      for(const [id,short,label] of candidates){
        const actions=(editedPlans.has(id)?steps[id]:defaultActions(id)).map(x=>({...x}));
        // External happiness has no verified price, so cannot establish affordability.
        if(actions.some(x=>x.type==="externalHappy"||options.blockDrugs&&["xanax","ecstasy"].includes(x.type)))continue;
        const maxCycles=id==="natural"?1:Math.max(1,Math.floor(168/blockHours));
        let best=null;
        for(let cycles=1;cycles<=maxCycles;cycles++){
          const engine=createEngine(cfg),v=engine.state,executed=[];
          for(let k=0;k<cycles&&!v.errors.length&&v.time<engine.limit;k++){
            const end=Math.min(engine.limit,Math.round((k+1)*blockHours*3600));
            // No free energy or cooldown reset between repetitions.
            if(startingEnergy[id]==="zero"&&v.energy>=engine.gymCost){
              if(actions[0]?.type==="xanax")engine.advance(v.drug);
              engine.execute(make("train"),0);
            }else if(startingEnergy[id]==="full"&&v.energy<energyRules().cap)engine.advance(engine.fullEnergyDelay());
            if(!engine.run(actions))break;
            executed.push(...actions);
            if(v.time<end)naturalUntil(engine,end);
            else if(v.energy>=engine.gymCost)engine.execute(make("train"),0);
          }
          if(!v.errors.length)naturalUntil(engine,engine.limit);
          const result=engine.finish(executed);
          const spend=cashCost(result);
          if(!result.complete||spend==null||spend>cash||executed.length!==actions.length*cycles)continue;
          if(id!=="natural"&&result.costs.xanax+result.costs.ecstasy+result.costs.dvd+result.costs.candy+result.costs.refill===0)continue;
          const candidate={id,label:short+" · "+label,gain:result.gain,money:result.money,cashCost:spend,excludeOwned,used:result.used,costs:result.costs,cycles,blockHours,drugRisk:result.costs.xanax+result.costs.ecstasy>0,source:"plan",timing:{xanaxCD:Math.round(p.xanaxCDMin*60),ecstasyCD:Math.round(p.ecstasyCDMin*60),boosterCap:p.boosterCapH*3600,candyCD:Math.round(1800*p.candyCDMultiplier),dvdCD:Math.round(21600*p.dvdCDMultiplier)},startEnergy:startingEnergy[id],generatedAt:now.getTime(),execution:result.log.filter(x=>x.type!=="happyReset").map(x=>({type:x.type,at:x.start.time,end:x.end.time,quantity:x.quantity??1,energy:x.type==="train"?Math.max(0,x.start.energy-x.end.energy):null,before:{energy:x.start.energy,happy:x.start.happy,drug:x.start.drug,booster:x.start.booster,stat:x.start.stat},after:{energy:x.end.energy,happy:x.end.happy,drug:x.end.drug,booster:x.end.booster,stat:x.end.stat},reason:x.reason??null}))};
          if(!best||candidate.gain>best.gain||candidate.gain===best.gain&&candidate.cashCost<best.cashCost)best=candidate;
        }
        if(best)results.push(best);
      }
      return results.sort((a,b)=>b.gain-a.gain||a.cashCost-b.cashCost);
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
      const cfg={hours:Math.min(336,Math.max(24,((remaining.at(-1)?.at??0)-(remaining[0]?.at??0))/3600+48)),startEnergy:"current",autoWait:true,startDrugMin:drugMin,startBoosterMin:boosterMin,boosterCapH:detectedBoosterCap()??manualBoosterCap,tornClockMin:clockMin,resetAfterSec:900-(now.getUTCMinutes()%15*60+now.getUTCSeconds()),refillUsedToday:session.refillDay===Math.floor(now/86400000)};
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
    const engine=createEngine({startEnergy:startingEnergy[side],...overrides});
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
    return {tiles,known,sources:{candy:tiles.filter(x=>x.active).map(x=>x.source),dvd:[]}};
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
  function row(side,a,index,info){
    const booster=["candy","dvd"].includes(a.type),wait=a.type==="wait";
    const ceiling=a.type==="candy"?maxCandy(p):maxDvd(p);
    const tier=a.candyHappy??p.candyHappy,attr=' data-ts-side="'+side+'" data-ts-index="'+index+'"';
    const candyOptions=["any",...new Set([25,35,50,75,100,150,250,...candyStock().tiers])];
    const configurable=booster||wait,editorId="ts-editor-"+side+"-"+index;
    const short=a.type==="candy"?"Candy ×"+(info?.qty??a.qty):a.type==="dvd"?"eDVD ×"+(info?.qty??a.qty):wait?"Wait "+fmt(a.minutes,2)+"m":"";
    const types=actionOptions.map(([id,label])=>'<option value="'+id+'" '+(a.type===id?"selected":"")+'>'+$(a.type===id&&short?short:label)+'</option>').join("");
    const detail=booster?'<div class="ts-booster-row"><label>'+(a.type==="candy"?"Candy:":"eDVD:")+'</label><input type="number" min="0" max="'+ceiling+'" step="1" value="'+(info?.qty??a.qty)+'"'+attr+' data-ts-edit="qty" aria-label="Quantity"><button type="button" class="button secondary" data-ts-op="max"'+attr+' aria-pressed="'+Boolean(a.max)+'" '+(info?.maximum==null?"disabled":"")+'>MAX</button>'+(a.type==="candy"?'<select'+attr+' data-ts-edit="candy-tier" aria-label="Candy happiness">'+candyOptions.map(h=>'<option value="'+h+'" '+(h===tier?"selected":"")+'>'+(h==="any"?"Any":h+" Happy")+'</option>').join("")+'</select>':'<small>2,500 Happy</small>')+'</div><div class="ts-booster-summary">'+(a.type==="candy"&&tier==="any"?Object.entries(info?.used??{}).map(([name,q])=>$(q+"× "+name)).join(" · "):"")+(info?.happy?' <strong>+'+fmt(info.happy)+' Happy</strong>':"")+(info?.held==null?' <small>Inventory or preceding step unavailable</small>':' <small>'+fmt(info.held)+' held · '+fmt(info.allowance)+' CD allowance'+(a.type==="dvd"&&info.qty>info.held?' · '+fmt(info.qty-info.held)+' to purchase':"")+'</small>')+'</div>':"";
    const editor= configurable?'<div class="ts-row-editor" id="'+editorId+'" popover="auto" data-ts-editor="'+editorId+'" role="dialog" aria-label="'+$(names[a.type])+' settings"><div class="ts-row-editor-title"><strong>'+$(names[a.type])+'</strong><button type="button" class="ts-editor-close" popovertarget="'+editorId+'" popovertargetaction="hide" aria-label="Close settings">×</button></div>'+
      (booster?detail:'<label class="ts-editor-wait">Minutes <input type="number" min="0" max="10080" step=".01" value="'+a.minutes+'"'+attr+' data-ts-edit="minutes" aria-label="Minutes"></label>')+'</div>':"";
    return '<div class="ts-step"><select'+attr+' data-ts-edit="type" aria-label="Training action">'+types+'</select>'+
      '<div class="ts-arrows">'+(configurable?'<button type="button" class="ts-row-gear" data-ts-gear="'+editorId+'" popovertarget="'+editorId+'" title="Action settings" aria-label="Edit '+$(names[a.type])+' settings"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"/><path d="M10.4 2h3.2l.6 2.6 1.8.8 2.3-1.4 2.3 2.3-1.4 2.3.8 1.8 2.6.6v3.2l-2.6.6-.8 1.8 1.4 2.3-2.3 2.3-2.3-1.4-1.8.8-.6 2.6h-3.2l-.6-2.6-1.8-.8-2.3 1.4-2.3-2.3 1.4-2.3-.8-1.8-2.6-.6V11l2.6-.6.8-1.8-1.4-2.3L5.7 4 8 5.4l1.8-.8z" transform="translate(0 -0.6)"/></svg></button>':'<span class="ts-gear-spacer" aria-hidden="true"></span>')+
      '<button type="button" title="Move up" aria-label="Move up" data-ts-op="up"'+attr+'>↑</button><button type="button" title="Move down" aria-label="Move down" data-ts-op="down"'+attr+'>↓</button><button type="button" title="Remove" aria-label="Remove" data-ts-op="remove"'+attr+'>×</button></div>'+editor+'</div>';
  }
  function timelineCells(state,previous=state){
    if(!state)return '<td>—</td>'.repeat(6);
    const change=state.stat-(previous?.stat??state.stat);
    return '<td>'+fmt(state.energy)+'</td><td>'+fmt(state.happy)+'</td><td>'+clock(state.drug)+'</td><td>'+clock(state.booster)+'</td><td class="ts-row-gain '+(change>0?"is-positive":"")+'">'+(change>0?"+":"")+fmt(change,2)+'</td><td class="ts-row-stat">'+fmt(state.stat,2)+'</td>';
  }
  function dependencyRow(e,offset=0){
    const label=e.type==="autoWait"?"Wait "+clock(e.end.time-e.start.time)+" · "+e.reason:e.type==="happyReset"?"Happiness reset":(names[e.type]??e.type)+(e.reason?" · "+e.reason:"");
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
      rows+='<tr class="ts-editable-row"><td>'+(main?clock(offset+main.end.time):"—")+'</td><td>'+data.notices.filter(x=>x.index===i).map(x=>'<div class="ts-cd-notice '+(x.critical?"critical":"hazard")+'">'+(x.critical?"":"⚠ ")+$(x.text)+'</div>').join("")+row(side,action,i,data.rowInfo[i])+'</td>'+timelineCells(main?.end,main?.start)+'</tr>';
    });
    rows+=(byParent.get(list.length)||[]).map(e=>dependencyRow(e,offset)).join("");
    return '<div class="ts-log ts-merged"><div class="ts-log-scroller"><table><thead><tr><th>Time</th><th>Action</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th><th>Stat change</th><th>Current stat</th></tr></thead><tbody>'+rows+'</tbody></table></div>'+
      '<div class="ts-add"><select data-ts-choice="'+side+'" aria-label="Select action"><option value="" selected>Select action</option>'+actionOptions.map(([id,label])=>'<option value="'+id+'">'+$(label)+'</option>').join("")+'</select><button type="button" class="button secondary" data-ts-op="add" data-ts-side="'+side+'" disabled>Add action</button><button type="button" class="text-button" data-ts-op="preset" data-ts-side="'+side+'">Reset</button></div></div>';
  }
  function section(side,data){
    const heading=templates.find(x=>x[0]===side)?.[2]??side;
    const metric=(label,value,extra="")=>'<span class="ts-title-metric '+extra+'"><small>'+label+'</small><strong>'+value+'</strong></span>';
    return '<details class="ts-side ts-template-card" data-ts-timeline="'+side+'" '+(openTimelines.has(side)?"open":"")+'><summary class="ts-template-header"><span class="ts-template-name">'+$(heading)+'</span>'+
      metric("Duration",fmt(p.hours,2)+"h")+metric("Energy used",fmt(data.used)+" E")+metric("Stat change",data.complete?(data.gain>=0?"+":"")+fmt(data.gain,2):"Blocked","ts-title-gain")+metric("Ending stat",data.complete?fmt(data.final,2):"—")+metric("Cost",data.money==null?"Unavailable":"$"+fmt(data.money))+
      '<span class="ts-template-chevron" aria-hidden="true"></span></summary>'+mergedTimeline(side,data)+
      (side==="maxhappy"?'<p class="fine-print">99,999 Happy target · Peak '+fmt(data.peakHappy??0)+' · '+((data.peakHappy??0)>=99999?"Target reached":"Additional happiness source required")+'</p>':"")+(data.warnings.length?'<p class="fine-print">'+data.warnings.map($).join("; ")+'</p>':"")+(data.errors.length?'<p class="ts-error">'+data.errors.map($).join("; ")+'</p>':"")+
      '</details>';
  }
  function chart(results){
    const chartEnd=p.hours+1;
    const xval=hour=>80+hour/chartEnd*800;
    const values=results.flatMap(({data})=>[data.initial.stat,data.final,...data.series.map(point=>point.s)]);
    const bottom=Math.min(...values),top=Math.max(bottom+1,...values);
    const yval=val=>210-(val-bottom)/(top-bottom)*190;
    const path=points=>points.map(({h,s},i)=>{
      const x=xval(h).toFixed(1),y=yval(s).toFixed(1);
      return i?"H"+x+"V"+y:"M"+x+","+y;
    }).join(" ");
    const windowX=xval(p.hours),extensionX=xval(chartEnd);
    const seriesClass=(id,data)=>"ts-series ts-series-"+id+(data.complete?"":" is-blocked");
    const endpoint=(x,y)=>'<circle class="ts-series-end" cx="'+x+'" cy="'+y+'" r="3"/>';
    let out='<svg viewBox="0 0 910 260" class="ts-chart" role="img" aria-label="Projected stat growth over '+p.hours+' hours with a one-hour visual extension">';
    out+='<rect class="ts-extension" x="'+windowX+'" y="20" width="'+(extensionX-windowX)+'" height="190"/>';
    for(let i=0;i<5;i++){
      const val=bottom+(top-bottom)*i/4,y=yval(val),hr=p.hours*i/4;
      out+='<line x1="80" y1="'+y+'" x2="'+extensionX+'" y2="'+y+'" class="ts-gridline"/><text x="74" y="'+(y+4)+'" font-size="11" text-anchor="end">'+fmt(val)+'</text><text x="'+xval(hr)+'" y="234" font-size="11" text-anchor="middle">'+fmt(hr,2)+'h</text>';
    }
    out+='<line class="ts-window-end" x1="'+windowX+'" y1="20" x2="'+windowX+'" y2="221"/><text x="'+extensionX+'" y="251" font-size="11" text-anchor="end">'+fmt(chartEnd,2)+'h</text>';
    for(const {id,data} of results){
      // The simulator coalesces events at the same time. Restore the pre-action
      // value for the chart when an immediate train changes the first point.
      const points=[...data.series,{h:chartEnd,s:data.final}];
      if(points[0].s!==data.initial.stat)points.unshift({h:0,s:data.initial.stat});
      out+='<g class="'+seriesClass(id,data)+'"><path class="ts-series-stroke" d="'+path(points)+'"/>'+endpoint(windowX,yval(data.final))+'</g>';
    }
    return out+'</svg><div class="ts-legend ts-multi-legend">'+results.map(({id,label,data})=>'<span><svg class="'+seriesClass(id,data)+'" width="44" height="10" aria-hidden="true"><line class="ts-series-stroke" x1="2" y1="5" x2="42" y2="5"/>'+endpoint(35,5)+'</svg> '+$(label)+(data.complete?"":" (blocked)")+'</span>').join("")+'</div>';
  }
  function render(context){
    if(context)ctx=context;
    if(!ctx)return "<p>Connect a stats calculator context first.</p>";
    loadPlanPreferences();loadLive();marketInputs();cooldownEffects=applyCooldownPerks();
    p.hours=preparationHours();
    const active=activeTemplates();
    for(const [id] of active)if(!editedPlans.has(id))steps[id]=defaultActions(id);
    const results=active.map(([id,,label])=>({id,label,data:simulate(steps[id])}));
    return controls()+(results.length?'<div class="ts-layout" data-template-count="'+results.length+'">'+results.map(x=>section(x.id,x.data)).join("")+'</div><div class="ts-outcomes"><h3>Same '+fmt(p.hours,2)+'-hour window</h3><div class="ts-comparison-results">'+results.map(({label,data})=>'<span>'+$(label)+': <strong>'+(data.complete?fmt(data.final,2):"Blocked")+'</strong> ('+fmt(data.used)+' E)</span>').join("")+'</div>'+chart(results)+'</div>':'<p class="fine-print">Select one or more templates above.</p>')+
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
  return {render,wire,simulate,weeklyPrograms,replayRemaining,steps,settings:p,loadLive,templateButtons};
})();
