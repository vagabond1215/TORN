"use strict";
const tornTrainSequence=(()=>{
  const names={xanax:"Xanax (+250 E)",ecstasy:"Ecstasy (double Happy)",candy:"Candy (+Happy)",dvd:"Erotic DVD (+2,500 Happy)",train:"Train available Energy",refill:"Points energy refill",wait:"Wait minutes",waitDrug:"Wait for drug cooldown",waitBooster:"Wait for booster space",autoOn:"Train at full E / drug ready ON",autoOff:"Automatic check-ins OFF",checkin:"Scheduled gym check-in"};
  const make=(type,qty=1,minutes=0)=>({type,qty,minutes});
  const defaults={
    natural:()=>[make("xanax"),make("candy",2),make("train"),make("refill"),make("train"),make("autoOn"),make("waitDrug"),make("xanax")],
    jump:()=>[make("train"),make("xanax"),make("xanax"),make("xanax"),make("xanax"),make("dvd",5),make("ecstasy"),make("train"),make("refill"),make("train"),make("autoOn")]
  };
  const steps={natural:defaults.natural(),jump:defaults.jump()};
  // Booster quantities are immediate batches. They never hide several hours
  // of waiting between candy and training; users add separate Wait rows.
  const maxCandy=cfg=>Math.max(1,Math.ceil(cfg.boosterCapH*3600/
    Math.max(1,Math.round(1800*cfg.candyCDMultiplier))));
  const maxDvd=cfg=>Math.max(1,Math.ceil(cfg.boosterCapH*3600/
    Math.max(1,Math.round(21600*cfg.dvdCDMultiplier)))+1);
  const p={hours:32,regenMin:0,energyStatus:"auto",boosterCapH:24,startDrugMin:0,startBoosterMin:0,xanaxCDMin:420,ecstasyCDMin:215,resetAfterSec:600,tornClockMin:720,candyCDMultiplier:1,dvdCDMultiplier:1,candyHappy:25,dvdHappy:2500,autoWait:true,
    xanaxPrice:null,ecstasyPrice:null,candyPrice:null,dvdPrice:null,pointPrice:null};
  const $=v=>String(v==null?"":v).replace(/[&<>"']/g,x=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]));
  const n=(v,f=0)=>v===null||v===undefined||v===""||!Number.isFinite(Number(v))?f:Number(v);
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,n(v,a)));
  const fmt=(v,d=0)=>Number(v).toLocaleString(undefined,{maximumFractionDigits:d});
  const clock=v=>{const s=Math.max(0,Math.round(v));return Math.floor(s/3600)+":"+String(Math.floor(s/60)%60).padStart(2,"0")+":"+String(s%60).padStart(2,"0");};
  let ctx=null,loadedPlayer=null;
  const candyTiers={
    25:["Bag of Bon Bons","Bag of Chocolate Kisses","Box of Chocolate Bars","Lollipop"],
    35:["Birthday Cupcake"],
    50:["Bag of Candy Kisses","Chocolate Egg"],
    75:["Bag of Bloody Eyeballs","Bag of Tootsie Rolls"],
    100:["Bag of Chocolate Truffles","Bag of Reindeer Droppings"],
    150:["Bag of Humbugs","Bag of Sherbet","Jawbreaker"]
  };
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
    const rows=(inventory||[]).map(x=>{
      const item=items.find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id)||keyName(i.name)===keyName(x.name??x.item?.name));
      const name=x.name??x.item?.name??item?.name, tier=Object.keys(candyTiers).find(k=>candyTiers[k].some(v=>keyName(v)===keyName(name)));
      const text=String(item?.effect??item?.description??"");
      const matched=text.match(/(?:increases?|increased)\s+(?:your\s+)?happiness\s+by\s+(\d+)/i);
      const happy=Number(tier??matched?.[1]??0);
      return {name,happy,qty:Math.max(0,Math.floor(n(x.amount??x.quantity))),price:marketPrice(item)};
    }).filter(x=>x.happy>0&&x.qty>0);
    return {loaded:Array.isArray(inventory),rows,tiers:[...new Set(rows.map(x=>x.happy))].sort((a,b)=>a-b)};
  }
  function priceFor(name){
    return marketPrice(itemList().find(i=>keyName(i.name)===keyName(name)));
  }
  function marketInputs(){
    const stock=candyStock();
    if(stock.tiers.length&&!stock.tiers.includes(p.candyHappy))p.candyHappy=stock.tiers[stock.tiers.length-1];
    p.xanaxPrice=priceFor("Xanax");p.ecstasyPrice=priceFor("Ecstasy");p.dvdPrice=priceFor("Erotic DVD");
    const points=payload("pointsCatalog","pointsmarket");
    const list=Array.isArray(points)?points:Object.values(points||{});
    const prices=list.map(x=>positive(x?.cost??x?.price??x?.cost_per_point)).filter(x=>x!==null);
    p.pointPrice=prices.length?Math.min(...prices):null;
    return stock;
  }
  function candyPool(cfg){
    const stock=candyStock();
    return stock.rows.filter(x=>x.happy<=cfg.candyHappy).sort((a,b)=>b.happy-a.happy||(a.price??Infinity)-(b.price??Infinity)).map(x=>({...x}));
  }
  function readCooldowns(){
    const data=tornGuideApi.state.data.cooldowns;
    const cd=data&&(data.cooldowns||data);
    return cd && typeof cd==="object"?{drug:n(cd.drug)/60,booster:n(cd.booster)/60}:null;
  }
  function loadLive(force=false){
    const id=tornGuideApi.state.identity&&tornGuideApi.state.identity.id;
    if(!force && loadedPlayer===id)return;
    loadedPlayer=id||null;
    const cd=readCooldowns();
    if(cd){p.startDrugMin=cd.drug;p.startBoosterMin=cd.booster;}
    const now=new Date();
    p.tornClockMin=now.getUTCHours()*60+now.getUTCMinutes();
    p.resetAfterSec=900-(now.getUTCMinutes()%15*60+now.getUTCSeconds());
  }
  function activePerks(){
    const val=tornGuideApi.state.data.perks;
    const collections=val&&(val.perks||val);
    if(!collections||typeof collections!=="object")return [];
    return Object.values(collections).flatMap(value=>Array.isArray(value)?value:[]).map(v=>typeof v==="string"?v:v&&(v.name||v.effect||v.description)||"").filter(v=>/cooldown|voracity|metabolism|erotic dvd|candy/i.test(v));
  }
  function energyRules(config){
    const mode=config.energyStatus||"auto", observed=ctx&&ctx.state?Number(ctx.state.maxEnergy):150;
    const cap=mode==="standard"?100:mode==="donator"||mode==="subscriber"?150:Math.max(1,Number.isFinite(observed)?observed:150);
    const minutes=mode==="standard"?15:mode==="donator"||mode==="subscriber"?10:cap>=150?10:15;
    const label=mode==="auto"?(cap>=150?"Observed Donator/Subscriber-equivalent bar":"Observed standard-equivalent bar"):
      mode==="standard"?"Standard":mode==="donator"?"Donator":"Subscriber";
    return {cap,minutes:config.regenMin>0?Number(config.regenMin):minutes,label,mode};
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
    const cfg={...p,...overrides},base=ctx.state.statValues[ctx.state.compareStat];
    const pool=candyPool(cfg),stock=candyStock();
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
    const point=()=>{const last=v.series[v.series.length-1],h=v.time/3600;if(Math.abs(last.h-h)<1e-8)last.s=v.stat;else v.series.push({h,s:v.stat});};
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
      advance(seconds);
      if(v.time>=limit){v.errors.push(label+" could not fit in the remaining time.");return false;}
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
        }else if(v.booster>=boosterLimit){
          v.errors.push("Candy has reached the booster use threshold. Add a separate Wait for booster space and another Candy row; no hidden waiting occurs before training.");
          return false;
        }
        let candy=null;
        if(type==="candy"){
          candy=pool.find(x=>x.qty>0);
          if(!candy){v.errors.push(stock.loaded?"Insufficient candy in inventory for the selected Max Happy tier.":"Candy inventory not loaded.");return false;}
          candy.qty--;candyGain+=candy.happy;
          if(candy.price===null)unknownCandyPrice=true;else candyCost+=candy.price;
        }
        const secs=type==="dvd"?21600*cfg.dvdCDMultiplier:1800*cfg.candyCDMultiplier;
        v.booster+=Math.round(secs);
        v.happy=Math.min(99999,v.happy+(type==="dvd"?cfg.dvdHappy:candy.happy));
        v.costs[type]++;
      }
      return true;
    }
    for(let i=0;i<list.length;i++){
      if(v.errors.length)break;
      const a=list[i],start=snap(),type=a.type;
      const qty=Math.floor(clamp(a.qty,1,type==="candy"?maxCandy(cfg):type==="dvd"?maxDvd(cfg):1));
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
      point();
      v.log.push({i:i+1,type,start,end:snap()});
      if(v.time>=limit && i<list.length-1){v.errors.push("The "+cfg.hours+"-hour window ended before all steps.");break;}
    }
    if(v.time<limit)advance(limit-v.time);
    point();
    const prices=[[v.costs.xanax,cfg.xanaxPrice],[v.costs.ecstasy,cfg.ecstasyPrice],[v.costs.dvd,cfg.dvdPrice],[v.costs.refill*30,cfg.pointPrice]];
    const missingPrice=unknownCandyPrice||prices.some(([qty,price])=>qty>0&&price==null);
    return {...v,final:v.stat,gain:v.stat-base,complete:v.errors.length===0,candyGain,
      money:missingPrice?null:candyCost+prices.reduce((sum,[qty,price])=>sum+qty*(price??0),0)};
  }
  function controls(){
    const fields=[
      ["hours","Time window (hours)",1,168,1],["regenMin","Energy +5 interval (0 = status)",0,15,5],
      ["boosterCapH","Booster use threshold (hours)",1,72,1],
      ["startDrugMin","Starting drug CD (min)",0,20000,1],["startBoosterMin","Starting booster CD (min)",0,20000,1],
      ["xanaxCDMin","Xanax CD (360–480 min)",360,480,1],["ecstasyCDMin","Ecstasy CD (200–230 min)",200,230,1],
      ["resetAfterSec","Next Happy reset in (seconds)",1,900,1],
      ["tornClockMin","Torn minutes since midnight",0,1439,1],
      ["candyCDMultiplier","Candy CD multiplier",0.1,3,0.05],
      ["dvdCDMultiplier","eDVD CD multiplier",0.1,3,0.05],
      ["dvdHappy","Happy per eDVD",0,10000,1]
    ];
    const stock=candyStock(),pool=candyPool(p);
    const remaining=Math.max(0,Math.ceil((p.boosterCapH*3600-p.startBoosterMin*60)/Math.max(1,Math.round(1800*p.candyCDMultiplier))));
    let capacity=remaining,totalHappy=0,usable=0;
    for(const item of pool){const qty=Math.min(capacity,item.qty);capacity-=qty;usable+=qty;totalHappy+=qty*item.happy;}
    const priceText=v=>v==null?"Unavailable":"$"+fmt(v);
    return '<details class="ts-settings" open><summary>Time, cooldowns, effects, prices</summary>'+
      '<label class="ts-membership">Energy account model <select data-ts-status>'+
        [['auto','Use current Torn Energy bar'],['standard','Standard (100 E)'],['donator','Donator (150 E)'],['subscriber','Subscriber (150 E)']].map(([key,text])=>
          '<option value="'+key+'" '+(p.energyStatus===key?'selected':'')+'>'+text+'</option>').join('')+
      '</select></label><div class="ts-settings-grid">'+fields.map(([key,label,min,max,step])=>
      '<label><span>'+$(label)+'</span><input type="number" data-ts-param="'+key+'" value="'+$(p[key])+'" min="'+min+'" max="'+max+'" step="'+step+'"></label>').join("")+
      '<label><span>Max Happy</span><select data-ts-candy '+(!stock.tiers.length?"disabled":"")+'>'+(!stock.tiers.length?'<option>No available candy</option>':stock.tiers.map(t=>'<option value="'+t+'" '+(p.candyHappy===t?"selected":"")+'">'+t+' Happy</option>').join(""))+'</select></label>'+
      '</div><div class="ts-candy-stock"><strong>'+(!stock.loaded?"Candy inventory not loaded":fmt(usable)+' usable candy · +'+fmt(totalHappy)+' Happy')+'</strong><small>'+pool.map(x=>$(x.name)+' ×'+fmt(x.qty)).join(" · ")+'</small></div>'+
      '<div class="ts-market-prices"><span>Xanax '+priceText(p.xanaxPrice)+'</span><span>Ecstasy '+priceText(p.ecstasyPrice)+'</span><span>eDVD '+priceText(p.dvdPrice)+'</span><span>Point '+priceText(p.pointPrice)+'</span></div><div class="ts-bonus-presets"><span>Useful presets:</span>'+
      '<button type="button" data-ts-bonus="baseline">24h base cap</button>'+
      '<button type="button" data-ts-bonus="maxVoracity">48h faction cap</button>'+
      '<button type="button" data-ts-bonus="grocery">Grocery -10% candy CD</button>'+
      '<button type="button" data-ts-bonus="restaurant">Restaurant -25% candy CD</button>'+
      '<button type="button" data-ts-bonus="book">Book -50% candy CD</button>'+
      '<button type="button" data-ts-bonus="adult">Adult Novelties 5,000 Happy/eDVD</button>'+
      '</div><label class="ts-switch"><input type="checkbox" data-ts-auto '+(p.autoWait?"checked":"")+'>Automatically wait when a cooldown blocks an action</label>'+
      '<button type="button" class="button secondary" data-ts-sync>Re-import live cooldowns</button>'+
      '<p class="fine-print">Candy cooldown can be shortened by Grocery Store/Restaurant company perks and some books. The consumable-cooldown book does not shorten eDVD cooldown; keep its multiplier at 1 unless you have a specific applicable perk. Starting cooldowns come from the Torn API when present.</p></details>';
  }
  function row(side,a,index){
    const types=Object.entries(names).map(([id,label])=>'<option value="'+id+'" '+(a.type===id?"selected":"")+'>'+$(label)+'</option>').join("");
    const qty=["candy","dvd"].includes(a.type);
    const wait=a.type==="wait";
    const ceiling=a.type==="candy"?maxCandy(p):a.type==="dvd"?maxDvd(p):1;
    return '<div class="ts-step"><span>'+(index+1)+'</span><select data-ts-side="'+side+'" data-ts-index="'+index+'" data-ts-edit="type">'+types+'</select>'+
      (qty||wait?'<input type="number" min="'+(qty?1:0)+'" max="'+(qty?ceiling:10080)+'" step="'+(qty?1:.01)+'" value="'+(qty?a.qty:a.minutes)+'" data-ts-side="'+side+'" data-ts-index="'+index+'" data-ts-edit="'+(qty?"qty":"minutes")+'" aria-label="'+(qty?"Quantity":"Minutes")+'">':'<span></span>')+
      '<div class="ts-arrows"><button type="button" title="Move up" data-ts-op="up" data-ts-side="'+side+'" data-ts-index="'+index+'">↑</button>'+
      '<button type="button" title="Move down" data-ts-op="down" data-ts-side="'+side+'" data-ts-index="'+index+'">↓</button>'+
      '<button type="button" title="Remove" data-ts-op="remove" data-ts-side="'+side+'" data-ts-index="'+index+'">×</button></div></div>';
  }
  function log(data){
    return '<details class="ts-log"><summary>Execution timeline ('+data.log.length+' steps)</summary><div class="ts-log-scroller"><table><thead><tr><th>Step</th><th>Time</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th></tr></thead><tbody>'+
      data.log.map(a=>'<tr><td>'+$(names[a.type])+(a.reason?" · "+$(a.reason):"")+'</td><td>'+clock(a.end.time)+'</td><td>'+fmt(a.end.energy)+'</td><td>'+fmt(a.end.happy)+'</td><td>'+clock(a.end.drug)+'</td><td>'+clock(a.end.booster)+'</td></tr>').join("")+
      '</tbody></table></div></details>';
  }
  function section(side){
    const data=simulate(steps[side]);
    const heading=side==="jump"?"Happy jump":"Natural energy";
    return '<section class="ts-side"><h3>'+heading+'</h3><div class="ts-list">'+steps[side].map((a,i)=>row(side,a,i)).join("")+'</div>'+
      '<div class="ts-add"><select data-ts-choice="'+side+'">'+Object.entries(names).map(([id,label])=>'<option value="'+id+'">'+$(label)+'</option>').join("")+'</select>'+
      '<button type="button" class="button secondary" data-ts-op="add" data-ts-side="'+side+'">Add action</button>'+
      '<button type="button" class="text-button" data-ts-op="preset" data-ts-side="'+side+'">Reset</button></div>'+
      (data.errors.length?'<p class="ts-error">'+data.errors.map($).join("; ")+'</p>':"")+
      '<p class="ts-stat">Final: '+(data.complete?fmt(data.final,2):"Blocked")+' <small>+'+fmt(data.gain,2)+' gain, '+fmt(data.used)+' E, '+(data.money==null?"Cost unavailable":"$"+fmt(data.money))+'</small></p>'+
      log(data)+'</section>';
  }
  function chart(natural,jump){
    const xval=hour=>80+hour/p.hours*800;
    const bottom=Math.min(ctx.state.statValues[ctx.state.compareStat],natural.final,jump.final);
    const top=Math.max(natural.final,jump.final,bottom+1);
    const yval=val=>210-(val-bottom)/(top-bottom)*190;
    const path=serie=>serie.map((v,i)=>(i?"L":"M")+xval(v.h).toFixed(1)+","+yval(v.s).toFixed(1)).join(" ");
    let out='<svg viewBox="0 0 910 260" class="ts-chart" role="img" aria-label="Projected stat growth over '+p.hours+' hours">';
    for(let i=0;i<5;i++){
      const val=bottom+(top-bottom)*i/4,y=yval(val);
      out+='<line x1="80" y1="'+y+'" x2="880" y2="'+y+'" stroke="#41463a"/><text x="74" y="'+(y+4)+'" fill="#c9c4a8" font-size="11" text-anchor="end">'+fmt(val)+'</text>';
      const hr=p.hours*i/4;
      out+='<text x="'+xval(hr)+'" y="243" font-size="11" text-anchor="middle" fill="#c9c4a8">'+fmt(hr,1)+'h</text>';
    }
    out+='<path d="'+path(natural.series)+'" fill="none" stroke="#78b5db" stroke-width="3"/>';
    if(jump.complete)out+='<path d="'+path(jump.series)+'" fill="none" stroke="#dfc379" stroke-width="3"/>';
    return out+'</svg><p class="ts-legend">Blue: Natural training · Gold: Happy jump</p>';
  }
  function render(context){
    if(context)ctx=context;
    if(!ctx)return "<p>Connect a stats calculator context first.</p>";
    loadLive();
    marketInputs();
    const a=simulate(steps.natural),b=simulate(steps.jump);
    const rule=energyRules(p);
    const diff=b.gain-a.gain;
    const perks=activePerks();
    return controls()+
      (perks.length?'<p class="fine-print">Possibly relevant current perks: '+perks.map($).join(" • ")+'</p>':"")+
      '<div class="ts-layout">'+section("natural")+section("jump")+'</div>'+
      '<div class="ts-outcomes"><h3>Same '+p.hours+'-hour window</h3><p>Natural: <strong>'+fmt(a.final,2)+'</strong> ('+fmt(a.used)+' E) · Jump: <strong>'+fmt(b.final,2)+'</strong> ('+fmt(b.used)+' E)</p>'+
      '<p><strong>'+(!a.complete||!b.complete?"Review blocked timeline steps":(diff>=0?"Jump exceeds natural by +"+fmt(diff,2):"Natural exceeds jump by +"+fmt(-diff,2)))+'</strong></p>'+
      chart(a,b)+'</div>'+
      '<p class="fine-print">Simulated, not actual in-game actions. Drug cooldown varies; overdoses, addiction, book-specific gym effects and fluctuating prices are not predicted. Happiness above your normal cap resets on Torn quarter-hours. Points refills are limited to one per Torn day. <a target="_blank" rel="noopener noreferrer" href="https://wiki.torn.com/wiki/Item_Cooldowns">Booster cooldown rules</a></p>';
  }
  function wire(view){
    if(view.dataset.tsBound==="yes")return;
    view.dataset.tsBound="yes";
    const rebuild=()=>{const root=view.querySelector("#tc-sequencer");if(root)root.innerHTML=render();};
    view.addEventListener("change",event=>{
      const el=event.target;
      if(el.matches("[data-ts-candy]")){p.candyHappy=Number(el.value);rebuild();return;}
      const param=el.dataset.tsParam;
      if(param && Object.hasOwn(p,param)){p[param]=clamp(el.value,Number(el.min),Number(el.max));rebuild();return;}
      if(el.hasAttribute("data-ts-auto")){p.autoWait=el.checked;rebuild();return;}
      if(el.hasAttribute("data-ts-status")){
        if(["auto","standard","donator","subscriber"].includes(el.value))p.energyStatus=el.value;
        rebuild();return;
      }
      const edit=el.dataset.tsEdit,side=el.dataset.tsSide,index=Number(el.dataset.tsIndex);
      if(edit&&steps[side]&&steps[side][index]){
        const a=steps[side][index];
        if(edit==="type"){a.type=el.value;a.qty=1;a.minutes=0;}
        if(edit==="qty")a.qty=clamp(Math.floor(n(el.value,1)),1,a.type==="candy"?maxCandy(p):a.type==="dvd"?maxDvd(p):1);
        if(edit==="minutes")a.minutes=clamp(el.value,0,10080);
        rebuild();
      }
    });
    view.addEventListener("click",event=>{
      const bonus=event.target.closest("[data-ts-bonus]");
      if(bonus){
        if(bonus.dataset.tsBonus==="baseline")p.boosterCapH=24;
        if(bonus.dataset.tsBonus==="maxVoracity")p.boosterCapH=48;
        if(bonus.dataset.tsBonus==="grocery")p.candyCDMultiplier=0.90;
        if(bonus.dataset.tsBonus==="restaurant")p.candyCDMultiplier=0.75;
        if(bonus.dataset.tsBonus==="book")p.candyCDMultiplier=0.50;
        if(bonus.dataset.tsBonus==="adult")p.dvdHappy=5000;
        rebuild();
        return;
      }
      const el=event.target.closest("[data-ts-op],[data-ts-sync]");
      if(!el)return;
      if(el.hasAttribute("data-ts-sync")){loadLive(true);rebuild();return;}
      const side=el.dataset.tsSide,op=el.dataset.tsOp,index=Number(el.dataset.tsIndex),list=steps[side];
      if(!list)return;
      if(op==="preset")steps[side]=defaults[side]();
      else if(op==="add"){
        const select=view.querySelector('[data-ts-choice="'+side+'"]');
        if(list.length<40)list.push(make(select?select.value:"train"));
      }else if(op==="remove")list.splice(index,1);
      else if(op==="up"&&index>0)[list[index-1],list[index]]=[list[index],list[index-1]];
      else if(op==="down"&&index<list.length-1)[list[index+1],list[index]]=[list[index],list[index+1]];
      rebuild();
    });
  }
  return {render,wire,simulate,steps,settings:p,loadLive};
})();
