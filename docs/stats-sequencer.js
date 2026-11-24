"use strict";
const tornTrainSequence=(()=>{
  const names={xanax:"Xanax (+250 E)",ecstasy:"Ecstasy (double Happy)",candy:"Candy (+Happy)",dvd:"Erotic DVD (+2,500 Happy)",train:"Train available Energy",refill:"Points energy refill",wait:"Wait minutes",waitDrug:"Wait for drug cooldown",waitBooster:"Wait for booster space",autoOn:"Train at full E / drug ready ON",autoOff:"Automatic check-ins OFF",checkin:"Scheduled gym check-in"};
  const make=(type,qty=1,minutes=0)=>({type,qty,minutes});
  const defaults={
    natural:()=>[make("xanax"),make("candy",2),make("train"),make("refill"),make("train"),make("autoOn"),make("waitDrug"),make("xanax")],
    jump:()=>[make("train"),make("xanax"),make("xanax"),make("xanax"),make("xanax"),make("dvd",5),make("ecstasy"),make("train"),make("refill"),make("train"),make("autoOn")]
  };
  const maxAction=type=>({...make(type),max:true});
  defaults.natural=()=>[make("train"),make("autoOn")];
  defaults.mini=()=>[make("train"),make("xanax"),maxAction("candy"),make("ecstasy"),make("train"),make("refill"),make("train"),make("autoOn")];
  defaults.jump=()=>[make("train"),...Array.from({length:4},()=>make("xanax")),make("waitDrug"),make("dvd",5),make("ecstasy"),make("train"),make("refill"),make("train"),make("autoOn")];
  // 99k is a target template: DVDs alone do not guarantee 99,999 Happy.
  defaults.maxhappy=()=>[make("train"),...Array.from({length:4},()=>make("xanax")),make("waitDrug"),maxAction("dvd"),make("ecstasy"),make("train"),make("refill"),make("train"),make("autoOn")];
  defaults.custom=()=>[make("train")];
  const templates=[["natural","NAT","Natural training"],["mini","MINI","Mini jump"],["jump","HJ","Happy jump"],["maxhappy","99k","99k Happy jump"],["custom","CUSTOM","Custom"]];
  const steps=Object.fromEntries(templates.map(([id])=>[id,defaults[id]()]));
  const selected=new Set(["natural","jump"]);
  function templateButtons(){return '<div class="ts-template-toggles" role="group" aria-label="Compare templates">'+templates.map(([id,short,label])=>'<button type="button" class="tc-stat-tab '+(selected.has(id)?"is-selected":"")+'" data-ts-template="'+id+'" aria-pressed="'+selected.has(id)+'" title="'+label+'">'+short+'</button>').join("")+'</div>';}
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
    return '<div class="ts-cooldown-mode">'+toggle("drug",liveDrug,cd?.drug!=null)+toggle("booster",liveBooster,cd?.booster!=null)+cap+'<small>Drug '+fmt(p.startDrugMin,1)+'m · Booster '+fmt(p.startBoosterMin,1)+'m</small><small title="Fixed Torn quarter-hour schedule">Next Happy reset: '+String(Math.floor(p.resetAfterSec/60)).padStart(2,"0")+':'+String(p.resetAfterSec%60).padStart(2,"0")+'</small></div>';
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
    const jumps=activeTemplates().filter(([id])=>["jump","maxhappy"].includes(id));
    if(!jumps.length)return 24;
    return Math.max(24,...jumps.map(([id])=>{
      let time=0,drug=Math.round(p.startDrugMin*60);
      for(const step of steps[id]){
        if(step.type==="waitDrug"){time+=drug;drug=0;}
        else if(step.type==="wait"){const wait=Math.max(0,Math.ceil(n(step.minutes)*60));time+=wait;drug=Math.max(0,drug-wait);}
        else if(step.type==="xanax"||step.type==="ecstasy"){time+=drug;drug=Math.round((step.type==="xanax"?p.xanaxCDMin:p.ecstasyCDMin)*60);}
        else if(step.type==="dvd"||step.type==="candy")time+=1; // allowance for exact-threshold final item
      }
      return Math.ceil(time/3600*100)/100;
    }));
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
  function simulate(list,overrides={}){
    const cfg={...p,hours:preparationHours(),...overrides},base=ctx.state.statValues[ctx.state.compareStat];
    const stock=candyStock(),pool=stock.rows.map(x=>({...x})).sort((a,b)=>b.happy-a.happy||(a.price??Infinity)-(b.price??Infinity));
    const dvdInventory=tornGuideApi.state.inventory.Booster;
    const dvdKnown=Array.isArray(dvdInventory)&&!tornGuideApi.state.inventoryErrors?.Booster;
    const dvdHeld=dvdKnown?dvdInventory.filter(x=>keyName(x.name??x.item?.name??itemList().find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id))?.name)===keyName("Erotic DVD")).reduce((sum,x)=>sum+Math.max(0,Math.floor(n(x.amount??x.quantity))),0):null;
    const rowInfo={};let rowCandy=null,rowUsed=null;
    let candyCost=0,candyGain=0,unknownCandyPrice=false;
    const gym=ctx.gym,stat=ctx.state.compareStat,limit=Math.floor(cfg.hours*3600);
    const rule=energyRules(cfg),eCap=rule.cap;
    const boosterLimit=cfg.boosterCapH*3600;
    const regenTime=rule.minutes*60;
    const gymCost=Math.max(1,Math.floor(gym.energy));
    const mult=ctx.effectsFor(stat).multiplier;
    const initialE=rule.mode==="auto"?ctx.state.currentEnergy:
      Math.min(ctx.state.currentEnergy,eCap);
    const v={time:0,stat:base,energy:initialE,happy:ctx.state.happy,drug:Math.round(cfg.startDrugMin*60),booster:Math.round(cfg.startBoosterMin*60),auto:false,
      costs:{xanax:0,ecstasy:0,dvd:0,candy:0,refill:0},used:0,log:[],errors:[],series:[{h:0,s:base}],days:new Set(),lostRegen:0,warnings:[]};
    const snap=()=>({time:v.time,energy:v.energy,happy:v.happy,drug:v.drug,booster:v.booster,stat:v.stat});
    v.peakHappy=v.happy;
    const point=()=>{v.peakHappy=Math.max(v.peakHappy,v.happy);const last=v.series[v.series.length-1],h=v.time/3600;if(Math.abs(last.h-h)<1e-8)last.s=v.stat;else v.series.push({h,s:v.stat});};
    function train(){
      if(v.energy<gymCost || n(gym[stat])<=0)return 0;
      const out=ctx.trainBlock(v.stat,v.happy,v.energy,gym,stat,mult);
      v.energy-=out.used;v.happy=out.happy;v.stat=out.stat;v.used+=out.used;
      return out.used;
    }
    function checkin(reason){
      if(!v.auto)return;
      const start=snap(),used=train();
      if(used>0){
        point();
        v.log.push({i:"•",type:"checkin",reason,start,end:snap()});
      }
    }
    function advance(duration){
      const until=Math.min(limit,v.time+Math.max(0,Math.ceil(duration)));
      while(v.time<until){
        const eTick=(Math.floor(v.time/regenTime)+1)*regenTime;
        const first=Math.max(1,Math.round(cfg.resetAfterSec));
        const hTick=first+Math.max(0,Math.floor((v.time-first)/900)+1)*900;
        const drugTick=v.drug>0?v.time+v.drug:Infinity;
        const next=Math.min(until,eTick,hTick,drugTick),passed=next-v.time,priorDrug=v.drug;
        v.time=next;v.drug=Math.max(0,v.drug-passed);v.booster=Math.max(0,v.booster-passed);
        if(next===eTick){if(v.energy<eCap)v.energy=Math.min(eCap,v.energy+5);else v.lostRegen+=5;}
        if(next===hTick){v.happy=v.happy>ctx.state.maxHappy?ctx.state.maxHappy:Math.min(ctx.state.maxHappy,v.happy+5);}
        if(v.auto && (priorDrug>0&&v.drug===0 || next===eTick&&v.energy>=eCap))
          checkin(priorDrug>0&&v.drug===0?"Drug cooldown expired":"Energy bar filled");
        if(next===hTick||next===until||next%3600===0)point();
      }
    }
    function waitFor(seconds,label){
      if(seconds<=0)return true;
      if(!cfg.autoWait){v.errors.push(label+" blocked ("+clock(seconds)+" left).");return false;}
      const target=v.time+Math.ceil(seconds);
      advance(seconds);
      if(target>limit){v.errors.push(label+" could not fit in the remaining time.");return false;}
      return true;
    }
    function useItem(type){
      if(type==="xanax"||type==="ecstasy"){
        if(!waitFor(v.drug,"Drug cooldown"))return false;
        if(type==="xanax"){
          v.energy=Math.min(1000,v.energy+250);v.happy=Math.min(99999,v.happy+75);
          v.drug=Math.round(cfg.xanaxCDMin*60);
        }else{v.happy=Math.min(99999,v.happy*2);v.drug=Math.round(cfg.ecstasyCDMin*60);}
        v.costs[type]++;
        // A Xanax dose is not automatically a gym check-in. The next
        // full-energy or drug-cooldown event triggers the scheduled train.
      }else{
        // The threshold is evaluated BEFORE each consumption. A final item
        // can push the cooldown over the cap; after 4 DVDs, wait one second.
        if(type==="dvd"){
          // A fifth DVD may wait ONE SECOND at exactly 24h; eDVDs support
          // deliberate cooldown sequencing, unlike candy's instant batch.
          if(!waitFor(Math.max(0,v.booster-boosterLimit+1),"Booster cooldown"))return false;
        }else if(v.booster===boosterLimit){
          if(!waitFor(1,"Booster cooldown"))return false;
        }else if(v.booster>boosterLimit){
          v.errors.push("Candy has reached the booster use threshold. Add a separate Wait for booster space and another Candy row; no hidden waiting occurs before training.");
          return false;
        }
        let candy=null;
        if(type==="candy"){
          candy=rowCandy.find(x=>x.qty>0);
          if(!candy){v.errors.push(stock.loaded?"Insufficient candy in inventory for the selected Max Happy tier.":"Candy inventory not loaded.");return false;}
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
    for(let i=0;i<list.length;i++){
      if(v.errors.length)break;
      const a=list[i],start=snap(),type=a.type;
      const isBooster=type==="candy"||type==="dvd",tier=a.candyHappy??cfg.candyHappy;
      rowCandy=pool.filter(x=>tier==="any"||x.happy===tier);rowUsed={};
      const itemCD=Math.max(1,Math.round(type==="dvd"?21600*cfg.dvdCDMultiplier:1800*cfg.candyCDMultiplier));
      const allowance=v.booster>boosterLimit?0:Math.floor((boosterLimit-v.booster)/itemCD)+1;
      const held=type==="candy"?(stock.loaded?rowCandy.reduce((sum,x)=>sum+x.qty,0):null):dvdKnown?Math.max(0,dvdHeld-v.costs.dvd):null;
      const maximum=held===null?null:Math.min(held,allowance);
      const qty=isBooster?(a.max?(maximum??0):Math.floor(clamp(a.qty,0,type==="candy"?maxCandy(cfg):maxDvd(cfg)))):1;
      if(isBooster)rowInfo[i]={maximum,allowance,held,qty,used:rowUsed,tier,happy:0,dvdBefore:v.costs.dvd};
      if(isBooster&&a.max&&maximum===null){v.errors.push("MAX requires loaded inventory.");break;}
      if(["xanax","ecstasy","dvd","candy"].includes(type)){
        for(let k=0;k<qty;k++){
          if(!useItem(type))break;
        }
      }else if(type==="train")train();
      else if(type==="wait")advance(n(a.minutes)*60);
      else if(type==="waitDrug")advance(v.drug);
      else if(type==="waitBooster")advance(Math.max(0,v.booster-boosterLimit+1));
      else if(type==="autoOn"){v.auto=true;if(v.energy>=eCap)checkin("Energy already full");}
      else if(type==="autoOff")v.auto=false;
      else if(type==="refill"){
        let day=Math.floor((cfg.tornClockMin*60+v.time)/86400);
        if(v.days.has(day)){
          if(!waitFor((day+1)*86400-cfg.tornClockMin*60-v.time,"Daily points refill"))break;
          day=Math.floor((cfg.tornClockMin*60+v.time)/86400);
        }
        if(!v.days.has(day)){v.days.add(day);v.energy=eCap;v.costs.refill++;checkin("Points refill filled Energy");}
      }else{v.errors.push("Unrecognized action: "+type);}
      if(isBooster)rowInfo[i].happy=type==="dvd"?(v.costs.dvd-rowInfo[i].dvdBefore)*2500:Object.entries(rowUsed).reduce((sum,[name,q])=>sum+q*(pool.find(x=>x.name===name)?.happy??0),0);
      point();
      v.log.push({i:i+1,type,start,end:snap()});
      if(v.time>=limit && i<list.length-1 && list.slice(i+1).some(step=>["wait","waitDrug","waitBooster","xanax","ecstasy"].includes(step.type))){v.errors.push("The "+cfg.hours+"-hour window ended before all steps.");break;}
    }
    // Natural and mini profiles continue using available drug cycles and daily
    // refills through the common comparison window, without modifying their rows.
    if(cfg.repeatTraining&&!v.errors.length){
      v.auto=true;
      while(v.time<limit){
        const day=Math.floor((cfg.tornClockMin*60+v.time)/86400);
        if(!v.days.has(day)){const start=snap();train();v.days.add(day);v.energy=eCap;v.costs.refill++;train();v.log.push({i:"•",type:"refill",reason:"Daily refill",start,end:snap()});}
        if(v.drug===0){const start=snap();train();useItem("xanax");train();v.log.push({i:"•",type:"xanax",reason:"Available drug cycle",start,end:snap()});}
        const midnight=(day+1)*86400-cfg.tornClockMin*60-v.time;
        advance(Math.min(limit-v.time,v.drug||Infinity,Math.max(1,midnight)));
      }
      train();
    }
    if(v.time<limit)advance(limit-v.time);
    point();
    const prices=[[v.costs.xanax,cfg.xanaxPrice],[v.costs.ecstasy,cfg.ecstasyPrice],[v.costs.dvd,cfg.dvdPrice],[v.costs.refill*30,cfg.pointPrice]];
    const missingPrice=unknownCandyPrice||prices.some(([qty,price])=>qty>0&&price==null);
    return {...v,final:v.stat,gain:v.stat-base,complete:v.errors.length===0,candyGain,rowInfo,
      money:missingPrice?null:candyCost+prices.reduce((sum,[qty,price])=>sum+qty*(price??0),0)};
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
    return '<div class="ts-perk-tiles" aria-label="Cooldown perk status">'+cooldownEffects.tiles.map(x=>'<div class="ts-perk-tile '+(x.active?"is-active":"")+'" title="'+$(x.source||x.detail)+'"><strong>'+$(x.label)+'</strong><small>'+$(x.detail)+'</small><small>'+ (x.active?"Active":cooldownEffects.known?"Not detected":"Unknown")+'</small></div>').join("")+'</div>';
  }
  function controls(){
    const priceText=v=>v==null?"Unavailable":"$"+fmt(v);
    const effect=(label,minutes,source)=>'<span title="'+$(source.join("\n")|| (cooldownEffects.known?"No applicable reduction reported":"Perks unavailable; base cooldown assumed"))+'">'+label+' <strong>'+fmt(minutes,2)+'m</strong></span>';
    return '<details class="ts-settings" open><summary class="ts-settings-summary"><span>Time, cooldowns, effects, prices</span>'+cooldownControls()+'</summary>'+
      '<div class="ts-membership">Preparation window: <strong>'+fmt(p.hours,2)+'h</strong> · '+$(energyRules().label)+'</div>'+
      '<div class="ts-market-prices ts-auto-cooldowns">'+effect("Xanax",p.xanaxCDMin,[])+effect("Ecstasy",p.ecstasyCDMin,[])+effect("Candy",30*p.candyCDMultiplier,cooldownEffects.sources.candy)+effect("eDVD",360*p.dvdCDMultiplier,cooldownEffects.sources.dvd)+'</div>'+cooldownTiles()+
      '<div class="ts-market-prices"><span>Xanax '+priceText(p.xanaxPrice)+'</span><span>Ecstasy '+priceText(p.ecstasyPrice)+'</span><span>eDVD '+priceText(p.dvdPrice)+'</span><span>Point '+priceText(p.pointPrice)+'</span></div>'+
      '<label class="ts-switch"><input type="checkbox" data-ts-auto '+(p.autoWait?"checked":"")+'>Automatically wait when a cooldown blocks an action</label></details>';
  }
  function row(side,a,index,info){
    const types=Object.entries(names).map(([id,label])=>'<option value="'+id+'" '+(a.type===id?"selected":"")+'>'+$(label)+'</option>').join("");
    const booster=["candy","dvd"].includes(a.type),wait=a.type==="wait";
    const ceiling=a.type==="candy"?maxCandy(p):maxDvd(p);
    const tier=a.candyHappy??p.candyHappy,attr=' data-ts-side="'+side+'" data-ts-index="'+index+'"';
    const candyOptions=["any",...new Set([25,35,50,75,100,150,250,...candyStock().tiers])];
    const detail=booster?'<div class="ts-booster-row"><label>'+(a.type==="candy"?"Candy:":"eDVD:")+'</label><input type="number" min="0" max="'+ceiling+'" step="1" value="'+(info?.qty??a.qty)+'"'+attr+' data-ts-edit="qty" aria-label="Quantity"><button type="button" class="button secondary" data-ts-op="max"'+attr+' aria-pressed="'+Boolean(a.max)+'" '+(info?.maximum==null?"disabled":"")+'>MAX</button>'+(a.type==="candy"?'<select'+attr+' data-ts-edit="candy-tier" aria-label="Candy happiness">'+candyOptions.map(h=>'<option value="'+h+'" '+(h===tier?"selected":"")+'>'+(h==="any"?"Any":h+" Happy")+'</option>').join("")+'</select>':'<small>2,500 Happy</small>')+'</div><div class="ts-booster-summary">'+(a.type==="candy"&&tier==="any"?Object.entries(info?.used??{}).map(([name,q])=>$(q+"× "+name)).join(" · "):"")+(info?.happy?' <strong>+'+fmt(info.happy)+' Happy</strong>':"")+(info?.held==null?' <small>Inventory or preceding step unavailable</small>':' <small>'+fmt(info.held)+' held · '+fmt(info.allowance)+' CD allowance'+(a.type==="dvd"&&info.qty>info.held?' · '+fmt(info.qty-info.held)+' to purchase':"")+'</small>')+'</div>':"";
    return '<div class="ts-step"><span>'+(index+1)+'</span><select'+attr+' data-ts-edit="type">'+types+'</select>'+
      (wait?'<input type="number" min="0" max="10080" step=".01" value="'+a.minutes+'"'+attr+' data-ts-edit="minutes" aria-label="Minutes">':'<span></span>')+
      '<div class="ts-arrows"><button type="button" title="Move up" data-ts-op="up"'+attr+'>↑</button><button type="button" title="Move down" data-ts-op="down"'+attr+'>↓</button><button type="button" title="Remove" data-ts-op="remove"'+attr+'>×</button></div>'+detail+'</div>';
  }
  function log(data){
    return '<details class="ts-log"><summary>Execution timeline ('+data.log.length+' steps)</summary><div class="ts-log-scroller"><table><thead><tr><th>Step</th><th>Time</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th></tr></thead><tbody>'+
      data.log.map(a=>'<tr><td>'+$(names[a.type])+(a.reason?" · "+$(a.reason):"")+'</td><td>'+clock(a.end.time)+'</td><td>'+fmt(a.end.energy)+'</td><td>'+fmt(a.end.happy)+'</td><td>'+clock(a.end.drug)+'</td><td>'+clock(a.end.booster)+'</td></tr>').join("")+
      '</tbody></table></div></details>';
  }
  function section(side,data){
    const heading=templates.find(x=>x[0]===side)?.[2]??side;
    return '<section class="ts-side"><h3>'+heading+' <small>'+fmt(p.hours,2)+'h</small></h3><div class="ts-list">'+steps[side].map((a,i)=>row(side,a,i,data.rowInfo[i])).join("")+'</div>'+
      '<div class="ts-add"><select data-ts-choice="'+side+'">'+Object.entries(names).map(([id,label])=>'<option value="'+id+'">'+$(label)+'</option>').join("")+'</select>'+
      '<button type="button" class="button secondary" data-ts-op="add" data-ts-side="'+side+'">Add action</button>'+
      '<button type="button" class="text-button" data-ts-op="preset" data-ts-side="'+side+'">Reset</button></div>'+
      (side==="maxhappy"?'<p class="fine-print">99,999 Happy target · Peak '+fmt(data.peakHappy??0)+' · '+((data.peakHappy??0)>=99999?"Target reached":"Additional happiness source required")+'</p>':"")+(data.errors.length?'<p class="ts-error">'+data.errors.map($).join("; ")+'</p>':"")+
      '<p class="ts-stat">Final: '+(data.complete?fmt(data.final,2):"Blocked")+' <small>+'+fmt(data.gain,2)+' gain, '+fmt(data.used)+' E, '+(data.money==null?"Cost unavailable":"$"+fmt(data.money))+'</small></p>'+
      log(data)+'</section>';
  }
  function chart(results){
    const xval=hour=>80+hour/p.hours*800;
    const bottom=Math.min(ctx.state.statValues[ctx.state.compareStat],...results.map(x=>x.data.final));
    const top=Math.max(bottom+1,...results.map(x=>x.data.final));
    const yval=val=>210-(val-bottom)/(top-bottom)*190;
    const path=serie=>serie.map((v,i)=>(i?"L":"M")+xval(v.h).toFixed(1)+","+yval(v.s).toFixed(1)).join(" ");
    const styles={natural:["var(--text)",""],mini:["var(--text)","7 4"],jump:["var(--accent)",""],maxhappy:["var(--accent)","8 4"],custom:["var(--muted)","2 4"]};
    let out='<svg viewBox="0 0 910 260" class="ts-chart" role="img" aria-label="Projected stat growth over '+p.hours+' hours">';
    for(let i=0;i<5;i++){
      const val=bottom+(top-bottom)*i/4,y=yval(val),hr=p.hours*i/4;
      out+='<line x1="80" y1="'+y+'" x2="880" y2="'+y+'" class="ts-gridline"/><text x="74" y="'+(y+4)+'" font-size="11" text-anchor="end">'+fmt(val)+'</text><text x="'+xval(hr)+'" y="243" font-size="11" text-anchor="middle">'+fmt(hr,1)+'h</text>';
    }
    for(const {id,data} of results){const [color,dash]=styles[id];out+='<path d="'+path(data.series)+'" fill="none" stroke="'+color+'" stroke-dasharray="'+(data.complete?dash:"2 4")+'" stroke-width="3"/>';}
    return out+'</svg><div class="ts-legend ts-multi-legend">'+results.map(({id,label,data})=>'<span><svg width="26" height="8" aria-hidden="true"><line x1="0" y1="4" x2="26" y2="4" stroke="'+styles[id][0]+'" stroke-dasharray="'+(data.complete?styles[id][1]:"2 4")+'" stroke-width="3"/></svg> '+$(label)+(data.complete?"":" (blocked)")+'</span>').join("")+'</div>';
  }
  function render(context){
    if(context)ctx=context;
    if(!ctx)return "<p>Connect a stats calculator context first.</p>";
    loadLive();marketInputs();cooldownEffects=applyCooldownPerks();
    p.hours=preparationHours();
    const results=activeTemplates().map(([id,short,label])=>({id,label,data:simulate(steps[id],{hours:p.hours,repeatTraining:id==="natural"||id==="mini"})}));
    return controls()+(results.length?'<div class="ts-layout" data-template-count="'+results.length+'">'+results.map(x=>section(x.id,x.data)).join("")+'</div><div class="ts-outcomes"><h3>Same '+fmt(p.hours,2)+'-hour window</h3><div class="ts-comparison-results">'+results.map(({label,data})=>'<span>'+$(label)+': <strong>'+(data.complete?fmt(data.final,2):"Blocked")+'</strong> ('+fmt(data.used)+' E)</span>').join("")+'</div>'+chart(results)+'</div>':'<p class="fine-print">Select one or more templates above.</p>')+
      '<p class="fine-print">Simulated actions only. Drug cooldown varies; overdoses and addiction are not predicted. Happiness resets on Torn quarter-hours. Points refills are limited to one per Torn day.</p>';
  }
  function wire(view){
    if(view.dataset.tsBound==="yes")return;
    view.dataset.tsBound="yes";
    const rebuild=()=>{const root=view.querySelector("#tc-sequencer");if(root)root.innerHTML=render();const toggles=view.querySelector(".ts-template-toggles");if(toggles)toggles.outerHTML=templateButtons();};
    view.addEventListener("change",event=>{
      const el=event.target;
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
        if(edit==="type"){a.type=el.value;a.qty=1;a.minutes=0;a.max=false;delete a.candyHappy;}
        if(edit==="qty"){a.max=false;a.qty=clamp(Math.floor(n(el.value,0)),0,a.type==="candy"?maxCandy(p):a.type==="dvd"?maxDvd(p):1);}
        if(edit==="candy-tier")a.candyHappy=el.value==="any"?"any":Number(el.value);
        if(edit==="minutes")a.minutes=clamp(el.value,0,10080);
        rebuild();
      }
    });
    view.addEventListener("click",event=>{
      const template=event.target.closest("[data-ts-template]");if(template){const id=template.dataset.tsTemplate;if(selected.has(id))selected.delete(id);else selected.add(id);rebuild();view.querySelector('[data-ts-template="'+id+'"]')?.focus();return;}
      const mode=event.target.closest("[data-ts-cooldown-mode]");
      if(mode){event.preventDefault();if(mode.dataset.tsCooldownMode==="drug")liveDrug=!liveDrug;else liveBooster=!liveBooster;rebuild();return;}
      const cap=event.target.closest("[data-ts-cap]");if(cap){event.preventDefault();if(apiBoosterCap===null)manualBoosterCap=manualBoosterCap===24?48:24;rebuild();return;}
      const el=event.target.closest("[data-ts-op],[data-ts-sync]");
      if(!el)return;
      if(el.hasAttribute("data-ts-sync")){loadLive(true);rebuild();return;}
      const side=el.dataset.tsSide,op=el.dataset.tsOp,index=Number(el.dataset.tsIndex),list=steps[side];
      if(!list)return;
      if(op==="max"&&list[index]){list[index].max=true;}
      else if(op==="preset")steps[side]=defaults[side]();
      else if(op==="add"){
        const select=view.querySelector('[data-ts-choice="'+side+'"]');
        if(list.length<40)list.push(make(select?select.value:"train"));
      }else if(op==="remove")list.splice(index,1);
      else if(op==="up"&&index>0)[list[index-1],list[index]]=[list[index],list[index-1]];
      else if(op==="down"&&index<list.length-1)[list[index+1],list[index]]=[list[index],list[index+1]];
      rebuild();
    });
  }
  return {render,wire,simulate,steps,settings:p,loadLive,templateButtons};
})();
