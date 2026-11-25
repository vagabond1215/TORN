"use strict";
/* Torn City guide stats calculator.
   Uses publicly documented Torn gain models; estimates are not promises.
   API key stays in guide-features.js memory and is never accessed by this module. */
const tornStatPlanner = (() => {
  const statNames = ["strength","defense","speed","dexterity"];
  const readable = {strength:"Strength",defense:"Defense",speed:"Speed",dexterity:"Dexterity"};
  const groups = ["faction","education","property","job","book","merit","stock","enhancer"];
  // Offline fallback from Torn wiki /Gym. The API catalog overrides these values.
  // Order: name, energy/train, STR/SPD/DEF/DEX dots.
  const fallback = [
    ["Premier Fitness",5,2,2,2,2],["Average Joes",5,2.4,2.4,2.8,2.4],
    ["Woody's Workout Club",5,2.8,3.2,3.0,2.8],["Beach Bods",5,3.2,3.2,3.2,0],
    ["Silver Gym",5,3.4,3.6,3.4,3.2],["Pour Femme",5,3.4,3.6,3.6,3.8],
    ["Davies Den",5,3.7,0,3.7,3.7],["Global Gym",5,4,4,4,4],
    ["Knuckle Heads",10,4.8,4.4,4,4.2],["Pioneer Fitness",10,4.4,4.5,4.8,4.4],
    ["Anabolic Anomalies",10,5,4.5,5.2,4.5],["Core",10,5,5.2,5,5],
    ["Racing Fitness",10,5,5.4,4.8,5.2],["Complete Cardio",10,5.5,5.8,5.5,5.2],
    ["Legs, Bums and Tums",10,0,5.6,5.6,5.8],["Deep Burn",10,6,6,6,6],
    ["Apollo Gym",10,6,6.2,6.4,6.2],["Gun Shop",10,6.6,6.4,6.2,6.2],
    ["Force Training",10,6.4,6.6,6.4,6.8],["Cha Cha's",10,6.4,6.4,6.8,7],
    ["Atlas",10,7,6.4,6.4,6.6],["Last Round",10,6.8,6.6,7,6.6],
    ["The Edge",10,6.8,7,7,6.8],["George's",10,7.3,7.3,7.3,7.3],
    ["Balboas Gym",25,0,0,7.5,7.5],["Frontline Fitness",25,7.5,7.5,0,0],
    ["Gym 3000",50,8,0,0,0],["Mr. Isoyamas",50,0,0,8,0],
    ["Total Rebound",50,0,8,0,0],["Elites",50,0,0,0,8],
    ["The Sports Science Lab",25,9,9,9,9]
  ].map((g,i) => ({id:i+1,name:g[0],energy:g[1],strength:g[2],speed:g[3],defense:g[4],dexterity:g[5],offline:true}));
  const state = {
    bonusOpen:{}, gymInfoOpen:false, selectedGym:null, currentPlayer:null, imported:false, apiStamp:null, subpage:"gym",
    statValues:{strength:1000,defense:1000,speed:1000,dexterity:1000},
    trainCount:1, trainMax:false, trainFull:false, calcCandyQty:0, calcCandyHappy:25, calcCandyMax:false,calcHappyMode:"current",
    extra:{strength:0,defense:0,speed:0,dexterity:0},
    currentEnergy:150, maxEnergy:150, happy:1000, maxHappy:1000,
    compareStat:"strength",hours:32,regenMinutes:10,
    naturalXan:3,naturalEcstasy:0,naturalCandy:0,naturalRefill:1,
    jumpXan:4,jumpEcstasy:1,jumpCandy:0,jumpDvd:4,jumpRefill:1,
    candyHappy:25,dvdHappy:2500,boosterCap:24,
    priceXan:850000,priceEcstasy:40000,priceCandy:850,priceDvd:4300000,pricePoint:30000
  };
  const numeric = (value,fallbackValue=0) => {
    if (value===null || value===undefined || value==="") return fallbackValue;
    const n=Number(value); return Number.isFinite(n)?n:fallbackValue;
  };
  const clamp=(value,lo,hi)=>Math.max(lo,Math.min(hi,numeric(value,lo)));
  const nice=(value,decimals=0)=>Number.isFinite(value)?value.toLocaleString(undefined,{maximumFractionDigits:decimals}):"Unavailable";
  const esc=(value)=>String(value===null||value===undefined?"":value).replace(/[&<>"']/g,x=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]));
  const api=(name)=>tornGuideApi.state.data[name]||null;
  const rawStats=()=>{const p=api("battlestats");return p && p.battlestats?p.battlestats:null;};
  const rawBars=()=>{const p=api("bars");return p?.bars??p??null;};
  function syncLiveBars(){
    const bars=rawBars();
    if(!bars)return;
    if(bars.energy){state.currentEnergy=clamp(bars.energy.current,0,1000);state.maxEnergy=clamp(bars.energy.maximum,1,1000);}
    if(bars.happy){
      const source=tornGuideApi.state,bar=bars.happy;
      const bridge=source.bridge?.fields?.includes("happy")&&source.bridge.timestamp>Number(source.fetchedAt.bars||0);
      const stamp=bridge?source.bridge.timestamp:source.fetchedAt.bars;
      const observed=numeric(bar.current,NaN),maximum=numeric(bar.maximum,NaN);
      if(Number.isFinite(maximum)&&maximum>0)state.maxHappy=clamp(maximum,1,99999);
      if(Number.isFinite(observed)&&observed>=0){
        const projected=typeof tornBarProjection==="function"?tornBarProjection("happy",bar,stamp):null;
        state.happy=clamp(projected?.current??observed,0,99999);
      }
    }
    state.regenMinutes=state.maxEnergy>100?10:15;
  }
  function hydrateFromApi(force=false) {
    const id=tornGuideApi.state.identity&&tornGuideApi.state.identity.id;
    if (!id) {
      if (state.currentPlayer!==null) { state.currentPlayer=null;state.imported=false;state.apiStamp=null;state.selectedGym=null; }
      return;
    }
    if (!force && state.currentPlayer===id && state.imported) { syncLiveBars(); return; }
    if(state.currentPlayer!==id || force) state.selectedGym=null;
    state.currentPlayer=id;
    const bars=rawBars(),stats=rawStats();
    if (bars) {
      state.currentEnergy=clamp(bars.energy&&bars.energy.current,0,1000);
      state.maxEnergy=clamp(bars.energy&&bars.energy.maximum,1,1000);
      syncLiveBars();

      const donor=state.maxEnergy>100;
      state.regenMinutes=donor?10:15;
    }
    if (stats) {
      for(const stat of statNames) {
        const detail=stats[stat];
        const actual=typeof detail==="number"?detail:detail&&detail.value;
        if(Number.isFinite(Number(actual))) state.statValues[stat]=Math.max(0,Number(actual));
      }
    }
    if(!bars || !stats) {state.imported=false;return;}
    // Null selection follows the API gym, including late arrivals and refreshes.
    state.imported=true;
    state.apiStamp=tornGuideApi.state.updated;
  }
  const gymKey=name=>String(name||"").toLowerCase().replace(/[^a-z0-9]/g,"").replace(/^the/,"").replace(/workoutclub$/,"workout");
  const gymCosts=[10,100,250,500,1000,2500,5000,10000,50000,100000,250000,500000,1000000,2000000,3000000,5000000,7500000,10000000,15000000,20000000,30000000,50000000,75000000,100000000,50000000,50000000,100000000,100000000,100000000,100000000,500000000,2147483647];
  function gymRank(g){return fallback.findIndex(x=>gymKey(x.name)===gymKey(g.name));}
  function gyms() {
    const source=api("gymCatalog");
    const raw=source && source.gyms;
    if (!raw || typeof raw!=="object") return fallback;
    const pairs=Array.isArray(raw)?raw.map((item,index)=>[String(item.id??index+1),item]):Object.entries(raw);
    const pick=(...values)=>values.find(value=>value!==null && value!==undefined && Number.isFinite(Number(value)));
    const normalized=pairs.filter(([key,item])=>item && typeof item==="object" && item.name).map(([key,item])=>{
      const known=fallback.find(g=>gymKey(g.name)===gymKey(item.name))||fallback.find(g=>String(g.id)===String(item.id??key));
      const result={id:item.id??Number(key),name:String(item.name),energy:5,offline:false,category:item.category??item.type,price:pick(item.membership_cost,item.cost,item.price),rank:known?fallback.indexOf(known):-1};
      const cost=pick(item.energy_cost,item.energy_per_train,item.energy,item.cost_energy,known&&known.energy);
      result.energy=Math.max(1,numeric(cost,10));
      let needsFallback=false;
      for(const stat of statNames) {
        const dots=pick(item[stat],item.gains&&item.gains[stat],item.stats&&item.stats[stat],item.bonuses&&item.bonuses[stat]);
        if(dots!==undefined) result[stat]=Math.max(0,Number(dots)/10);
        else if(known){result[stat]=known[stat];needsFallback=true;}
        else {result[stat]=0;needsFallback=true;}
      }
      result.offline=needsFallback || cost===undefined;
      return result;
    });
    // Merge rather than replace: partial API catalogs must not hide known gyms.
    const merged=fallback.map((g,i)=>normalized.find(n=>n.rank===i)||g);
    return merged.concat(normalized.filter(n=>n.rank<0&&!/^(unknown|fightclub)$/.test(gymKey(n.name))&&String(n.id)!=="32"));
  }
  function activeGym(all=gyms()) {
    const g=api("gym"), info=g&&(g.gym||g);
    const current=info&&(info.active_gym??g.active_gym??info.id??info.name);
    const id=typeof current==="object"&&current?current.id:current;
    const name=typeof current==="object"&&current?current.name:current;
    return all.find(item=>(id!=null&&String(item.id)===String(id))||(name!=null&&item.name.toLowerCase()===String(name).toLowerCase()))||null;
  }
  function selectedGym() {
    const all=gyms();
    return all.find(item=>state.selectedGym!==null&&item.name===state.selectedGym)||activeGym(all)||all[0];
  }
  function perkCollections() {
    const p=api("perks");
    const obj=p&&(p.perks||p);
    if(!obj||typeof obj!=="object") return null;
    return groups.map(group=>{
      const entries=obj[group]||obj[group+"_perks"];
      return {group,entries:Array.isArray(entries)?entries:[]};
    });
  }
  function percentage(text) {
    const s=String(text);
    const match=s.match(/([+-])\s*(\d+(?:\.\d+)?)\s*%/i)||s.match(/(?:by|of)\s*(\d+(?:\.\d+)?)\s*%/i);
    if(!match) return null;
    const n=match.length===3?Number(match[2]):Number(match[1]);
    if(!Number.isFinite(n)||Math.abs(n)>300) return null;
    const negative=(match.length===3&&match[1]==="-")||/\b(decreas(?:e|es|ed)|reduc(?:e|es|ed)|less)\b/i.test(s);
    return negative?-n:n;
  }
  function gainPerks(stat) {
    const collections=perkCollections();
    if(!collections) return null;
    return collections.map(({group,entries})=>{
      const matches=[];
      for(const entry of entries) {
        const text=typeof entry==="string"?entry:entry&&(entry.name||entry.effect||entry.description);
        if(!text || !/(gym\s*(?:gains?|training)|(?:gains?|training).{0,12}gym)/i.test(text)) continue;
        const targets=[...String(text).matchAll(/\b(strength|defense|speed|dexterity)\b/gi)].map(m=>m[1].toLowerCase());
        if(targets.length && !targets.includes(stat)) continue;
        const percent=percentage(text);
        if(percent!==null) matches.push({text:String(text),value:percent});
      }
      return {group,items:matches,total:matches.reduce((sum,item)=>sum+item.value,0)};
    });
  }
  function effectsFor(stat) {
    const loaded=gainPerks(stat);
    const manual=clamp(state.extra[stat],-95,300);
    const groupsData=loaded||groups.map(group=>({group,items:[],total:0}));
    const multiplier=groupsData.reduce((result,entry)=>result*Math.max(0,1+entry.total/100),1)*(1+manual/100);
    return {sourceAvailable:loaded!==null,groups:groupsData,manual,multiplier};
  }
  function battleEffects(stat) {
    const raw=rawStats(),detail=raw&&raw[stat];
    if(!detail||typeof detail!=="object") return null;
    const mods=Array.isArray(detail.modifiers)?detail.modifiers:[];
    return {total:numeric(detail.modifier,0),lines:mods.map(item=>({
      text:String(item.effect||item.type||"Modifier"),
      value:typeof item.value==="number"?item.value:null
    }))};
  }
  // The up-to-date calibrated per-train formula, with >50M soft cap and 0.5 happy/E loss.
  // See docs/STAT_CALCULATOR.md for sources and deliberately unmodeled RNG.
  function oneTrain(stat,happy,dots,energy,multiplier,which) {
    const S=Math.max(0,stat);
    const H=clamp(happy,0,99999);
    const capped=S>50000000?50000000+0.057406*Math.pow(S-50000000,0.928996):S;
    const hm=1+0.07*Math.log(1+H/250);
    const A={strength:1600,defense:2100,speed:1600,dexterity:1800}[which];
    const B={strength:1700,defense:-600,speed:2000,dexterity:1500}[which];
    const adj=(1-Math.pow(H/99999,2))*A;
    const raw=(capped*hm+8*Math.pow(H,1.05)+adj+B)/200000*dots*energy*multiplier;
    return Math.max(0,raw);
  }
  function trainBlock(baseStat,baseHappy,energyToUse,gym,stat,factor) {
    const dots=numeric(gym[stat]);
    if(dots<=0 || !gym.energy) return {stat:baseStat,happy:baseHappy,used:0};
    const cost=Math.max(1,Math.floor(gym.energy));
    const count=Math.min(10000,Math.floor(energyToUse/cost));
    let after=baseStat,happy=baseHappy;
    for(let i=0;i<count;i++) {
      after+=oneTrain(after,happy,dots,cost,factor,stat);
      happy=Math.max(0,happy-cost*0.5);
    }
    return {stat:after,happy,used:count*cost};
  }
  // Base candy happiness: https://wiki.torn.com/wiki/Candy
  const calcCandyTiers={"25":["Bag of Bon Bons","Bag of Chocolate Kisses","Box of Bon Bons","Box of Extra Strong Mints","Box of Sweet Hearts","Lollipop","Box of Chocolate Bars"],"35":["Big Box of Chocolate Bars"],"50":["Bag of Candy Kisses","Chocolate Egg"],"75":["Bag of Bloody Eyeballs","Bag of Tootsie Rolls"],"100":["Bag of Chocolate Truffles","Bag of Reindeer Droppings"],"150":["Bag of Humbugs","Bag of Sherbet","Jawbreaker","Pixie Sticks"],"250":["Birthday Cupcake"]};
  const candyKey=v=>String(v??"").toLowerCase().replace(/[^a-z0-9]/g,"");
  function calcCandyStock(){
    const inventory=tornGuideApi.state.inventory.Candy;
    if(!Array.isArray(inventory)||tornGuideApi.state.inventoryErrors.Candy)return null;
    const raw=payload("itemCatalog","items"),catalog=Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
    const rows=new Map();
    for(const x of inventory){
      const item=catalog.find(i=>String(i.id)===String(x.id??x.item_id??x.item?.id)||candyKey(i.name)===candyKey(x.name??x.item?.name));
      const name=x.name??x.item?.name??item?.name;
      if(!name)continue;
      const tier=Object.keys(calcCandyTiers).find(k=>calcCandyTiers[k].some(v=>candyKey(v)===candyKey(name)));
      const effect=JSON.stringify(item?.effect??item?.effects??"");
      const happy=Number(tier??effect.match(/happiness\s+by\s+(\d+)/i)?.[1]??0);
      const qty=Math.max(0,Math.floor(numeric(x.amount??x.quantity)));
      if(!happy||!qty)continue;
      const key=candyKey(name),old=rows.get(key);
      if(old)old.qty+=qty;
      else rows.set(key,{name,happy,qty,price:numeric(item?.market_value??item?.value?.market_price??item?.value?.market_value??item?.market_price,Infinity)});
    }
    return [...rows.values()].sort((a,b)=>b.happy-a.happy||a.price-b.price||a.name.localeCompare(b.name));
  }
  function candyCooldownAllowance(){
    const raw=api("cooldowns"),cd=raw?.cooldowns??raw;
    const seconds=cd?.booster==null?null:Math.max(0,numeric(cd.booster));
    const faction=perkCollections()?.find(x=>x.group==="faction")?.entries||[];
    const text=faction.map(x=>typeof x==="string"?x:[x?.name,x?.description,x?.effect].filter(Boolean).join(" ")).join("\n");
    // Recognize explicit faction increases to maximum booster cooldown.
    // Do not confuse reduced item cooldown with increased capacity.
    let cap=24;
    for(const line of text.split("\n")){
      if(!/booster/i.test(line)||!/cooldown/i.test(line)||!/max(?:imum)?|limit|cap|capacity/i.test(line))continue;
      const absolute=line.match(/(?:to|of|:)\s*(\d+(?:\.\d+)?)\s*(?:h\b|hours?)/i);
      const added=line.match(/(?:\+|by\s+|increase(?:d|s)?\s+(?:by\s+)?)\s*(\d+(?:\.\d+)?)\s*(?:h\b|hours?)/i);
      const pct=line.match(/(?:\+|by\s+)\s*(\d+(?:\.\d+)?)\s*%/i);
      if(absolute)cap=Math.max(cap,Number(absolute[1]));
      else if(added)cap=Math.max(cap,24+Number(added[1]));
      else if(pct)cap=Math.max(cap,24*(1+Number(pct[1])/100));
      else if(/\b48\s*(?:h\b|hours?)/i.test(line))cap=Math.max(cap,48);
    }
    const limit=cap*3600;
    // At the exact threshold allow one second of decay before consuming
    // the final candy. An already over-cap cooldown allows no immediate use.
    const allowed=seconds===null?null:seconds>limit?0:Math.floor((limit-seconds)/1800)+1;
    return {cap,seconds,allowed};
  }
  function calcCandyPlan(){
    const stock=calcCandyStock(),any=state.calcCandyHappy==="any";
    const eligible=(stock||[]).filter(x=>any||x.happy===state.calcCandyHappy);
    const held=eligible.reduce((sum,x)=>sum+x.qty,0),cooldown=candyCooldownAllowance();
    const capacity=cooldown.allowed===null?0:Math.min(held,cooldown.allowed);
    const requested=state.calcCandyMax&&stock!==null?capacity:state.calcCandyQty;
    let remaining=requested,happy=0;const used=[];
    if(stock!==null){
      for(const item of eligible){
        const qty=Math.min(remaining,item.qty);if(!qty)continue;
        used.push({...item,qty});remaining-=qty;happy+=qty*item.happy;
        if(!remaining)break;
      }
    }else if(!any&&!state.calcCandyMax){happy=requested*state.calcCandyHappy;remaining=0;}
    return {any,loaded:stock!==null,capacity,requested,remaining,happy,used,cooldown,held};
  }
  function calcCandySummary(){
    if(state.calcHappyMode!=="current")return '<div class="tc-candy-summary"><strong>Simulated Happy: '+nice(calcStartingHappy())+'</strong><small>'+(state.calcHappyMode==="hj"?"Normal maximum + 5 eDVDs, doubled by Ecstasy":"99,999 Happy override")+' · Candy settings retained, not added to override.</small></div>';
    const p=calcCandyPlan();
    if(!p.requested&&!p.any&&!state.calcCandyMax)return "";
    const used=p.used.map(x=>esc(x.qty+"× "+x.name)).join(" · ");
    const note=!p.loaded?(p.any?"Candy inventory unavailable; no candy simulated.":"Inventory unavailable; manual estimate."):p.remaining>0?p.remaining+" more requested than available.":"";
    return '<div class="tc-candy-summary">'+(p.any&&used?'<span>'+used+'</span>':"")+
      (p.happy?'<strong>+'+nice(p.happy)+' Happy</strong>':"")+(state.calcCandyMax?'<small>'+(p.cooldown.allowed===null?"Booster cooldown unavailable":p.cooldown.cap+"h booster cap · "+p.cooldown.allowed+" candy allowance · "+p.held+" held")+', including final candy after cooldown decay</small>':"")+(note?'<small>'+esc(note)+'</small>':"")+
      (p.loaded&&p.requested===0&&p.any?'<small>Select a quantity or MAX.</small>':"")+'</div>';
  }
  function calcStartingHappy(){
    return state.calcHappyMode==="99k"?99999:state.calcHappyMode==="hj"?Math.min(99999,(state.maxHappy+5*2500)*2):Math.min(99999,state.happy+calcCandyPlan().happy);
  }
  function singleStatSession(stat,energy,gym) {
    const start=state.statValues[stat];
    return trainBlock(start,calcStartingHappy(),energy,gym,stat,effectsFor(stat).multiplier);
  }
  const shorthand={strength:"STR",defense:"DEF",speed:"SPD",dexterity:"DEX"};
  const gymCategories=["Lightweight","Middleweight","Heavyweight","Specialty"];
  function gymCategory(g) {
    const index=g.rank>=0?g.rank:gymRank(g);
    if(index>=0)return Math.min(3,Math.floor(index/8));
    const type=String(g.category||"").toLowerCase();
    return /light/.test(type)?0:/middle/.test(type)?1:/heavy/.test(type)?2:3;
  }
  function fullJumpEnergy(){
    const profile=api("profile"),status=String((profile?.profile??profile)?.donator_status??"").toLowerCase();
    const premium=/donator|subscriber/.test(status)||(!/standard|non.?donator|none/.test(status)&&state.maxEnergy>=150);
    return 1000+(premium?150:100);
  }
  function trainingCount(gym) {
    if(state.trainFull)return Math.floor(1000/gym.energy)+Math.floor((fullJumpEnergy()-1000)/gym.energy);
    return state.trainMax?Math.floor(state.currentEnergy/gym.energy):Math.max(1,Math.min(10000,Math.floor(state.trainCount)));
  }
  function gymIcon(g) {
    const i=g.rank>=0?g.rank:gymRank(g);
    const marks=["⚑","J","WW","✿","♟","⚝","D","G","⚔","▲","AA","C","◴","♥","LB","DB","♟","⚒","FT","CC","A","LR","E","G","B","FF","3K","MI","TR","E","SSL","FC"];
    const colors=["#89c9ff","#df8b25","#619dc4","#32ac8e","#c0b9b5","#db8e93","#c2c4c7","#91a96b","#d0d5d7","#7eb395","#9bd5c0","#d1d2cf","#abb5c0","#84a8e9","#bc8cc7","#d86a43","#d99bb9","#c8d0c4"];
    const mark=marks[i]||g.name.split(/\s+/).map(w=>w[0]).join("").slice(0,3);
    return '<svg viewBox="0 0 32 32" width="34" height="34" aria-hidden="true"><text x="16" y="22" text-anchor="middle" font-family="Georgia,serif" font-weight="bold" font-size="'+(mark.length>2?11:mark.length>1?15:23)+'" fill="'+(colors[i]||"#b9c5cb")+'">'+esc(mark)+'</text></svg>';
  }
  function gymInfoHeading(g){
    const price=g.price??gymCosts[g.rank>=0?g.rank:gymRank(g)];
    return '<strong>'+esc(g.name)+'</strong><small>'+nice(g.energy)+'E</small><small>'+esc(gymCategories[gymCategory(g)])+'</small><small>Membership: '+(price!=null?"$"+nice(Number(price)):"Unavailable")+'</small>';
  }
  function gymDotRow(g,baseline=null){
    return '<div class="tc-gym-info-dots">'+statNames.map(stat=>{
      const value=numeric(g[stat]),delta=baseline?Math.round((value-numeric(baseline[stat]))*100)/100:0;
      return '<div><span>'+shorthand[stat]+'</span><meter aria-label="'+readable[stat]+' gym dots" min="0" max="10" value="'+Math.min(10,Math.max(0,value))+'"></meter><strong>'+nice(value,1)+'</strong>'+(baseline?'<small class="tc-gym-delta '+(delta>0?'tc-pos':delta<0?'tc-neg':'')+'">'+(delta>0?'+':'')+nice(delta,1)+'</small>':'')+'</div>';
    }).join("")+'</div>';
  }
  function apiStatValue(stat) {
    const raw=rawStats(),detail=raw&&raw[stat];
    const value=typeof detail==="number"?detail:detail&&detail.value;
    return value!==null&&value!==undefined&&Number.isFinite(Number(value))?Math.max(0,Number(value)):null;
  }
  function statPanel(stat,gym) {
    const eff=effectsFor(stat);
    const energy=trainingCount(gym)*gym.energy,start=state.statValues[stat];
    const projected=singleStatSession(stat,energy,gym);
    const baseline=trainBlock(start,state.maxHappy,energy,gym,stat,eff.multiplier);
    const baseGain=baseline.stat-start,estimatedGain=projected.stat-start;
    const happyGain=baseGain>0?((estimatedGain-baseGain)/baseGain)*100:null;
    const disabled=!gym[stat];
    const totalBonus=(eff.multiplier-1)*100;
    let bonuses='<details class="tc-total-bonus" data-tc-bonus-stat="'+stat+'" '+(state.bonusOpen[stat]?"open":"")+'><summary><span>Total Bonus</span><strong class="'+(totalBonus<0?"tc-neg":totalBonus>0?"tc-pos":"")+'" title="'+(eff.sourceAvailable?"Combined training multiplier":"Partial estimate: API perks unavailable")+'">'+(totalBonus>=0?"+":"")+nice(totalBonus,2)+'%</strong></summary><div class="tc-gain-sources">';
    for(const group of eff.groups) {
      const label=group.group==="job"?"Job / workplace":group.group[0].toUpperCase()+group.group.slice(1);
      bonuses+='<div class="tc-mod-row" title="'+esc([...group.items.map(entry=>entry.text),...(group.group==="book"&&tornHappinessBook().active?["Ignorance Is Bliss: active; indirect benefit through current Happiness, not a fixed percentage multiplier"]:[])].join("\n"))+'"><span>'+esc(label)+(group.group==="book"&&tornHappinessBook().active?' <small class="tc-pos">· Bliss active</small>':"")+'</span><strong class="'+(group.total<0?"tc-neg":group.total>0?"tc-pos":"")+'">'+(group.total>=0?"+":"")+nice(group.total,2)+'%</strong></div>';
    }
    bonuses+='</div>';
    bonuses+='<label class="tc-manual"><span>Custom gym-gain %</span><input type="number" min="-95" max="300" step="0.1" data-tc-extra="'+stat+'" value="'+esc(state.extra[stat])+'"></label>';
    bonuses+='<p class="tc-multiplier">Training multiplier ×'+nice(eff.multiplier,3)+(eff.sourceAvailable?"":" · API perks unavailable")+'</p></details>';
    return '<div class="tc-stat-col '+(disabled?"tc-disabled":"")+'"><div class="tc-stat-title">'+readable[stat]+'</div>'+
      '<div class="tc-field"><label for="tc-stat-'+stat+'">Current stat</label><div class="tc-stat-input-row"><input id="tc-stat-'+stat+'" data-tc-stat="'+stat+'" type="number" min="0" step="1" value="'+esc(state.statValues[stat])+'"><button type="button" class="tc-stat-reset" data-tc-reset="'+stat+'" title="Reset '+readable[stat]+' to current API value" aria-label="Reset '+readable[stat]+'" '+(apiStatValue(stat)===null?'disabled':'')+'><svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 11a8 8 0 0 0-14.6-4.6L3 9m0-6v6h6"/><path d="M4 13a8 8 0 0 0 14.6 4.6L21 15m0 6v-6h-6"/></svg></button></div></div>'+
      '<div class="tc-stat-meta"><span>Gym dots</span><strong>'+(disabled?"Unavailable":nice(gym[stat],1))+'</strong></div>'+
      '<div class="tc-stat-meta" title="Same gym, Energy, starting stat and perks at normal maximum Happiness ('+nice(state.maxHappy)+')"><span>Base gain</span><strong>'+(disabled?"Unavailable":"+"+nice(baseGain,2))+'</strong></div>'+
      '<div class="tc-stat-meta"><span>Est. gain</span><strong>+'+nice(estimatedGain,2)+'</strong></div>'+
      '<div class="tc-stat-meta" title="Additional battle-stat growth due to Happiness alone: (Est. gain minus Base gain) divided by Base gain, times 100. Gym, Energy, starting stat and perks are unchanged."><span>Happy Growth</span><strong class="'+(happyGain>0?"tc-pos":happyGain<0?"tc-neg":"")+'">'+(happyGain===null?"—":(happyGain>0?"+":"")+nice(happyGain,2)+"%")+'</strong></div>'+
      '<div class="tc-stat-meta"><span>Est. final</span><strong>'+nice(projected.stat,2)+'</strong></div>'+
      bonuses+'</div>';
  }
  function effectiveOverview(){
    const rows=statNames.map(stat=>{
      const base=apiStatValue(stat),effect=battleEffects(stat);
      const effective=base!==null&&effect?Math.max(0,base*(1+effect.total/100)):null;
      return {stat,base,effect,effective,changed:effective!==null&&effective!==base};
    });
    if(!rows.some(row=>row.changed))return "";
    return '<div class="tc-stat-overview tc-effective-overview" aria-label="Effective battle stats">'+rows.map(row=>{
      const {stat,base,effect,effective,changed}=row;
      const signed=value=>(value>0?"+":"")+nice(value,2)+"%";
      const tooltip=changed?["Effective "+readable[stat]+" · "+signed(effect.total),...effect.lines.map(line=>line.text+(line.value!==null&&!line.text.includes("%")?" ("+signed(line.value)+")":""))].join("\n"):"";
      return '<div class="tc-overview-item" '+(changed?'title="'+esc(tooltip)+'" tabindex="0"':'')+'><small>'+shorthand[stat]+'</small><strong class="'+(changed?(effect.total>0?"tc-pos":"tc-neg"):"")+'">'+(changed?nice(effective):"—")+'</strong></div>';
    }).join("")+'</div>';
  }
  // Build targets are buffered planning ratios, not hard combat requirements.
  const buildOptions=[
    ["balanced","Balanced",[25,25,25,25],null,null],
    ["hank-str","Hank's – Strength",[1.30,.20,1,1],"strength","defensive"],
    ["hank-def","Hank's – Defense",[1,1.30,1,.20],"defense","offensive"],
    ["hank-spd","Hank's – Speed",[.20,1,1.30,1],"speed","defensive"],
    ["hank-dex","Hank's – Dexterity",[1,.20,1,1.30],"dexterity","offensive"],
    ["pair-off","Two-stat – Str + Spd",[28,22,28,22],null,"offensive"],
    ["pair-def","Two-stat – Def + Dex",[22,28,22,28],null,"defensive"],
    ["baldr-str","Baldr's – Strength",[1.30,.90,1,.90],"strength","offensive"],
    ["baldr-def","Baldr's – Defense",[.90,1.30,.90,1],"defense","defensive"],
    ["baldr-spd","Baldr's – Speed",[1,.90,1.30,.90],"speed","offensive"],
    ["baldr-dex","Baldr's – Dexterity",[.90,1,.90,1.30],"dexterity","defensive"]
  ];
  const singleGyms={strength:"Gym 3000",defense:"Mr. Isoyamas",speed:"Total Rebound",dexterity:"Elites"};
  const pairGyms={offensive:"Frontline Fitness",defensive:"Balboas Gym"};
  const bookNames={strength:"Gym Grunting - Shouting to Success",defense:"Self Defense In The Workplace",speed:"Speed 3 - The Rejected Script",dexterity:"Limbo Lovers 101"};
  let buildOwner=null,buildChoice="balanced",buildTotal=0;
  function loadBuild(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(buildOwner===owner)return;
    buildOwner=owner;buildChoice="balanced";buildTotal=0;
    try{const saved=JSON.parse(localStorage.getItem("torn-city-guide:build:"+owner));if(buildOptions.some(x=>x[0]===saved?.choice))buildChoice=saved.choice;buildTotal=clamp(saved?.total,0,1e15);}catch{}
  }
  function saveBuild(){try{localStorage.setItem("torn-city-guide:build:"+buildOwner,JSON.stringify({choice:buildChoice,total:buildTotal}));}catch{}}
  function homeTrainingAdvice(budget,risk,options={}){
    loadBuild();
    const actual=statNames.map(apiStatValue);
    if(actual.some(x=>x===null))return null;
    const option=buildOptions.find(x=>x[0]===buildChoice)||buildOptions[0],weights=option[2],sum=weights.reduce((a,b)=>a+b,0),shares=weights.map(x=>x/sum);
    const total=Math.max(buildTotal||actual.reduce((a,b)=>a+b,0)*1.1,1,...actual.map((v,i)=>v/shares[i]));
    const rows=statNames.map((stat,i)=>({stat,remaining:Math.max(0,Math.ceil(total*shares[i])-actual[i]),progress:actual[i]/Math.max(1,total*shares[i]),effects:effectsFor(stat)}));
    const active=activeGym(),book=row=>row.effects.groups.find(g=>g.group==="book")?.total||0;
    const next=rows.filter(x=>x.remaining>0).sort((a,b)=>a.progress-b.progress||book(b)-book(a)||b.effects.multiplier-a.effects.multiplier)[0];
    if(!next)return {stat:"your selected build",detail:"Current target reached; set the next milestone."};
    const bars=rawBars(),programs=active&&bars?.energy&&bars?.happy&&active[next.stat]>0?tornTrainSequence.weeklyPrograms({state:{...state,statValues:Object.fromEntries(statNames.map((stat,i)=>[stat,actual[i]])),compareStat:next.stat,currentEnergy:Number(bars.energy.current),maxEnergy:Number(bars.energy.maximum),happy:Number(bars.happy.current),maxHappy:Number(bars.happy.maximum)},gym:active,trainBlock,effectsFor},budget,risk,options):[];
    return {stat:readable[next.stat],program:programs[0]??null,detail:option[1]+" · "+nice(next.remaining)+" remaining to target"+(active?" · Current gym "+active.name:"")+(next.effects.sourceAvailable?" · "+nice((next.effects.multiplier-1)*100,1)+"% modeled gain modifier":" · Perks not loaded")+(book(next)>0?" · Active gym-gain book":"")+(tornHappinessBook().active?" · Ignorance Is Bliss active":"")};
  }
  function homeCandyAdvice(){return calcCandyStock()?.[0]||null;}
  function renderBuild(gym,active){
    loadBuild();
    const option=buildOptions.find(x=>x[0]===buildChoice)||buildOptions[0],weights=option[2],weightSum=weights.reduce((a,b)=>a+b,0),shares=weights.map(w=>w/weightSum);
    const actual=statNames.map(stat=>apiStatValue(stat)),live=actual.every(v=>v!==null),current=actual.map((v,i)=>v??state.statValues[statNames[i]]),sum=current.reduce((a,b)=>a+b,0);
    // Training cannot reduce existing stats: scale every target up until
    // all four target values are at least their current raw values.
    const minimum=Math.max(sum,...current.map((v,i)=>v/shares[i]));
    const targetTotal=Math.max(minimum,buildTotal||sum*1.10,1);
    const targets=shares.map(p=>Math.ceil(p*targetTotal));
    const catalog=gyms(),info=api("gym"),data=info?.gym??info;
    const known=data?.unlocked_gyms??info?.unlocked_gyms??data?.available_gyms??info?.available_gyms;
    const gymIds=Array.isArray(known)?known.map(x=>String(typeof x==="object"?x.id??x.name:x)):null;
    const unlocked=g=>Boolean(g&&(g.name===active?.name||gymIds?.includes(String(g.id))||gymIds?.includes(g.name)));
    // Never assume the simulation selection is an owned gym.
    const available=catalog.filter(unlocked);
    const entries=statNames.map((stat,i)=>{
      const eff=effectsFor(stat);
      const best=[...available].filter(g=>g[stat]>0).sort((a,b)=>b[stat]-a[stat])[0];
      const estimateGym=best||null,delta=Math.max(0,targets[i]-current[i]);
      const gain=estimateGym?oneTrain(current[i],state.happy,estimateGym[stat],1,eff.multiplier,stat):null;
      const energy=gain>0?Math.ceil(delta/gain):null;
      return {stat,i,eff,best,delta,energy,progress:targets[i]>0?Math.min(1,current[i]/targets[i]):1};
    });
    const priority=[...entries].filter(e=>e.delta>0).sort((a,b)=>a.progress-b.progress||(b.eff.multiplier-a.eff.multiplier))[0];
    const high=option[3],pair=option[4],requirements=[];
    if(high){
      const i=statNames.indexOf(high),other=Math.max(...current.filter((_,j)=>j!==i));
      const need=Math.ceil(1.25*other);
      requirements.push([singleGyms[high],current[i]>=need,readable[high]+" ≥ "+nice(need)+" · George's unlocked · $100m",catalog.find(g=>gymKey(g.name)===gymKey(singleGyms[high]))]);
    }
    if(pair){
      const ids=pair==="offensive"?[0,2]:[1,3],own=ids.reduce((n,i)=>n+current[i],0),other=sum-own,need=Math.ceil(1.25*other);
      requirements.push([pairGyms[pair],own>=need,"Pair total "+nice(own)+" / "+nice(need)+" · Cha Cha's unlocked · $50m",catalog.find(g=>gymKey(g.name)===gymKey(pairGyms[pair]))]);
    }
    const activeBook=entries.flatMap(e=>e.eff.groups.filter(g=>g.group==="book").flatMap(g=>g.items.map(x=>({stat:e.stat,text:x.text}))));
    const bliss=tornHappinessBook();
    const uniqueBooks=[...new Set([...activeBook.map(x=>x.text),...(bliss.active?["Ignorance Is Bliss · Elevated Happiness retained; affects all four stats"]:[])])];
    const reading=uniqueBooks.length?uniqueBooks.join(" · "):(bliss.known?"No active growth book identified in loaded perks.":"Active book status unavailable.");
    const label=stat=>readable[stat];
    return '<section class="panel tc-build-panel"><div class="panel-heading"><h2>Train next: '+(priority?esc(label(priority.stat))+" to "+nice(targets[priority.i]):"Target reached")+'</h2></div><div class="panel-content">'+
      '<div class="tc-build-controls"><label>Build <select data-tc-build="choice">'+buildOptions.map(([id,name])=>'<option value="'+id+'" '+(buildChoice===id?"selected":"")+'>'+esc(name)+'</option>').join("")+'</select></label>'+
      '<label>Target total <input type="number" min="0" max="1000000000000000" step="any" data-tc-build="total" value="'+(buildTotal||"")+'" placeholder="'+Math.ceil(targetTotal)+'"></label><button class="button secondary" type="button" data-tc-build-reset>Auto</button><small>'+(!live?"Sample / simulated stats · ":"")+'Minimum feasible '+nice(Math.ceil(minimum))+'</small></div>'+
      '<div class="tc-build-ratio">'+entries.map(e=>'<span class="tc-build-segment tc-build-'+e.stat+'" style="flex:'+weights[e.i]+'" title="'+label(e.stat)+' '+nice(shares[e.i]*100,1)+'%">'+shorthand[e.stat]+' '+nice(shares[e.i]*100,1)+'%</span>').join("")+'</div>'+
      '<div class="tc-build-scroll"><table class="tc-build-table"><thead><tr><th>Stat</th><th>Current / %</th><th>Target / %</th><th>Remaining</th><th>Gain perks</th><th>Known gym</th><th>Est. E</th></tr></thead><tbody>'+
      entries.map(e=>'<tr><td><strong>'+shorthand[e.stat]+'</strong></td><td>'+nice(current[e.i])+' <small>'+nice(sum?current[e.i]/sum*100:0,1)+'%</small></td><td>'+nice(targets[e.i])+' <small>'+nice(shares[e.i]*100,1)+'%</small></td><td class="'+(e.delta?"":"tc-pos")+'">'+nice(e.delta)+'</td><td title="'+esc(e.eff.groups.flatMap(g=>g.items.map(x=>x.text)).join("\n"))+'">'+(e.eff.sourceAvailable?nice((e.eff.multiplier-1)*100,1)+"%":"—")+'</td><td>'+esc(e.best?.name??"Unknown")+'</td><td>'+nice(e.energy??NaN)+'</td></tr>').join("")+'</tbody></table></div>'+
      (uniqueBooks.length?'<div class="tc-build-recommend"><p>Active book: '+esc(reading)+'</p></div>':"")+
      (requirements.length?'<div class="tc-build-gyms ts-perk-tiles" aria-label="Specialty gym requirements">'+requirements.map(([name,met,desc,g])=>'<div class="ts-perk-tile '+(unlocked(g)?"is-owned":"")+'"><strong>'+esc(name)+'</strong><small>'+esc(desc)+'</small><small class="'+(met?"tc-pos":"tc-neg")+'">'+(met?"Ratio met":"Ratio not met")+'</small><small>'+(unlocked(g)?"Access reported":"Access not verified")+'</small></div>').join("")+'</div>':"")+
      '<details class="tc-build-books"><summary>Books &amp; training priorities</summary><p>'+esc(reading)+'</p><div class="ts-perk-tiles">'+[
        ...statNames.map(stat=>({name:bookNames[stat],detail:"+30% "+label(stat)+" gym gains for 31 days",active:activeBook.some(x=>x.stat===stat&&x.text.toLowerCase().includes(bookNames[stat].toLowerCase()))})),
        {name:"Get Hard Or Go Home",detail:"+20% all gym gains for 31 days",active:uniqueBooks.some(x=>/get hard or go home/i.test(x))},
        {name:"Higher Daddy, Higher!",detail:"+20% energy regeneration for 31 days",active:(perkCollections()?.find(x=>x.group==="book")?.entries??[]).some(x=>/higher daddy|energy regeneration/i.test(typeof x==="string"?x:[x?.name,x?.effect,x?.description].join(" ")))},
        {name:"Ignorance Is Bliss",detail:"Happy regenerates up to 99,999 for 31 days",active:bliss.active}
      ].map(book=>{const status=tornBookTileStatus(book.name,book.active);return '<div class="ts-perk-tile '+(status?"is-"+status:"")+'"><strong>'+esc(book.name)+'</strong><small>'+esc(book.detail)+'</small>'+(status?'<small>'+esc(status[0].toUpperCase()+status.slice(1))+'</small>':"")+'</div>';}).join("")+'</div><p>Save unread books until you have a suitable gym, perks, supplies and time to use the entire duration. Ownership is not inferred.</p></details>'+
      '<p class="fine-print">Targets are suggested buffered ratios. Estimated energy uses the current per-energy gain at current happiness in a reported gym; future growth, cooldowns and membership changes are not simulated. <a href="https://wiki.torn.com/wiki/Gym" target="_blank" rel="noopener noreferrer">Gym requirements</a> · <a href="https://www.torn.com/forums.php?f=61&p=threads&t=16132234" target="_blank" rel="noopener noreferrer">Hank / Baldr guide</a></p></div></section>';
  }
  function happinessStatus(){
    const happy=calcStartingHappy(),book=tornHappinessBook();
    const title="Simulated Happy: "+nice(happy)+" / "+nice(state.maxHappy)+" normal maximum"+(book.active?" · Ignorance Is Bliss active; 99,999 ceiling":"");
    return '<div class="tc-happy-inline">'+(happy<state.maxHappy?'<span class="tc-low-happy" role="status" title="'+esc(title)+'">Low Happy</span>':"")+'</div>';
  }
  function render() {
    hydrateFromApi();
    const gym=selectedGym();
    const active=activeGym();
    const available=tornGuideApi.isConnected();
    let markup='<h1 id="topic-title" tabindex="-1" class="sr-only">Battle stats</h1><div class="tc-subbar"><nav class="tc-subnav" aria-label="Stats sections">'+
      '<button type="button" data-tc-view="gym" class="tc-subtab '+(state.subpage==="gym"?"is-current":"")+'" aria-current="'+(state.subpage==="gym"?"page":"false")+'">Gym</button>'+
      '<button type="button" data-tc-view="calc" class="tc-subtab '+(state.subpage==="calc"?"is-current":"")+'" aria-current="'+(state.subpage==="calc"?"page":"false")+'">Calc</button>'+
      '<button type="button" data-tc-view="compare" class="tc-subtab '+(state.subpage==="compare"?"is-current":"")+'" aria-current="'+(state.subpage==="compare"?"page":"false")+'">Plan</button></nav>'+
      '<div class="tc-overview"><div class="tc-stat-overview">'+statNames.map(stat=>
      '<div class="tc-overview-item"><small title="'+readable[stat]+'">'+shorthand[stat]+'</small><strong>'+nice(apiStatValue(stat)??state.statValues[stat])+'</strong></div>').join("")+'</div>'+effectiveOverview()+'</div></div>';
    if(state.subpage==="gym"){
    const catalog=gyms();
    const ordered=[...catalog].sort((a,b)=>{
      const rank=g=>{const i=g.rank>=0?g.rank:gymRank(g);return i<0?999:i;};
      return rank(a)-rank(b);
    });
    markup+='<section class="panel tc-calc-panel"><div class="panel-content tc-gym-picker"><div class="tc-gym-board" role="group" aria-label="Select simulation gym">'+gymCategories.map((label,i)=>{
      const list=ordered.filter(g=>gymCategory(g)===i);
      return '<div class="tc-gym-group" role="group" aria-label="'+label+'"><div class="tc-gym-tiles">'+list.map(g=>
        '<button type="button" class="tc-gym-tile '+(g.name===gym.name?"is-selected":"")+(active&&g.name===active.name?" is-active-gym":"")+'" data-tc-gym="'+esc(g.name)+'" title="'+esc(g.name)+' · '+g.energy+' E/train'+(active&&g.name===active.name?' · Current gym':'')+'" aria-label="'+esc(g.name)+'" aria-pressed="'+(g.name===gym.name)+'">'+gymIcon(g)+'<span>'+esc(g.name)+'</span></button>').join("")+'</div></div>';
    }).join("")+'</div>'+
      '<details class="tc-gym-info" '+(state.gymInfoOpen?"open":"")+'><summary>'+gymInfoHeading(active||gym)+'</summary><div class="tc-gym-info-body">'+
      gymDotRow(active||gym)+(active&&active.name!==gym.name?'<div class="tc-gym-alternate"><div class="tc-gym-comparison-heading">'+gymInfoHeading(gym)+'</div>'+gymDotRow(gym,active)+'</div>':'')+'</div></details></div></section>';
    markup+=renderBuild(gym,active);
    }
    if(state.subpage==="calc"){
    markup+='<section class="panel tc-calc-panel"><div class="tc-selected-gym"><button type="button" class="text-button" data-tc-view="gym" title="Change simulation gym">'+esc(gym.name)+'</button><small>'+nice(gym.energy)+'E</small>'+happinessStatus()+'<div class="tc-train-control"><label for="tc-train-count">Train:</label><input id="tc-train-count" data-tc="trainCount" type="number" min="1" max="10000" step="1" value="'+trainingCount(gym)+'"><button type="button" class="button secondary '+(state.trainMax?"is-selected":"")+'" data-tc-action="max" aria-pressed="'+state.trainMax+'">MAX</button><button type="button" class="button secondary '+(state.trainFull?"is-selected":"")+'" data-tc-action="full" aria-pressed="'+state.trainFull+'" title="Full jump: '+fullJumpEnergy()+' E (1,000 E stack plus points refill)">FULL</button><div class="tc-candy-control"><label for="tc-candy-qty">Candy:</label><input id="tc-candy-qty" type="number" data-tc="calcCandyQty" min="0" max="1000000000" step="1" value="'+calcCandyPlan().requested+'" title="Candy quantity (simulation only)"><button type="button" class="button secondary '+(state.calcCandyMax?"is-selected":"")+'" data-tc-action="candy-max" aria-pressed="'+state.calcCandyMax+'" '+(!calcCandyPlan().loaded||calcCandyPlan().cooldown.allowed===null?"disabled":"")+' title="Maximum candy within inventory and booster cooldown (simulation)">MAX</button><select data-tc="calcCandyHappy" aria-label="Happiness per candy" title="Happiness per candy">'+["any",25,35,50,75,100,150,250].map(h=>'<option value="'+h+'" '+(state.calcCandyHappy===h?"selected":"")+'>'+(h==="any"?"Any":h+" Happy")+'</option>').join("")+'</select><button type="button" class="button secondary tc-happy-mode '+(state.calcHappyMode!=="current"?"is-selected":"")+'" data-tc-action="happy-mode" title="Cycle Happiness: Current, HJ, 99k">'+({current:"Current",hj:"HJ","99k":"99k"}[state.calcHappyMode])+'</button></div></div>'+'</div>'+calcCandySummary();
    if(!available) markup+='<div class="tc-notice">Connect your <a href="#profile">Torn account</a> to load real battle stats, live energy/happiness, gym membership and active perks. Sample values are displayed until then.</div>';
    else if(!api("battlestats")||!api("perks"))markup+='<div class="tc-notice">Some API selections are missing. Values and modifiers not provided by Torn will be marked as unavailable or treated as zero in estimates.</div>';
    markup+='<div class="panel-content tc-simulator-body">'+
      '<div class="tc-stat-scroll"><div class="tc-four">'+statNames.map(stat=>statPanel(stat,gym)).join("")+'</div></div>'+
      '</div></section>';
    }
    if(state.subpage==="compare"){
      markup+='<section class="panel tc-calc-panel tc-plan-panel"><div class="panel-content">'+
      '<div class="ts-plan-toolbar">'+'<div class="tc-stat-tabs" role="group" aria-label="Compare stat">'+statNames.map(stat=>'<button type="button" class="tc-stat-tab '+(state.compareStat===stat?"is-selected":"")+'" data-tc-pick="'+stat+'">'+shorthand[stat]+'</button>').join("")+'</div>'+tornTrainSequence.templateButtons()+'</div>'+
      '<div id="tc-sequencer">'+tornTrainSequence.render({state,gym,trainBlock,effectsFor})+'</div></div></section>';
    }
    return markup;
  }
  function wire(view) {
    if (view.dataset.tcPlannerBound === "1") return;
    view.dataset.tcPlannerBound = "1";
    tornTrainSequence.wire(view);
    view.addEventListener("toggle",event=>{if(event.target.matches?.(".tc-gym-info")&&event.target.isConnected)state.gymInfoOpen=event.target.open;if(event.target.matches?.("[data-tc-bonus-stat]")&&event.target.isConnected)state.bonusOpen[event.target.dataset.tcBonusStat]=event.target.open;},true);
    view.addEventListener("change",event=>{
      if(event.target.closest("#tc-sequencer") || Object.keys(event.target.dataset||{}).some(key=>key.startsWith("ts"))) return;
      const el=event.target;
      if(location.hash==="#stats"&&el.matches("[data-tc-build]")){
        loadBuild();
        if(el.dataset.tcBuild==="choice"&&buildOptions.some(x=>x[0]===el.value))buildChoice=el.value;
        if(el.dataset.tcBuild==="total")buildTotal=clamp(el.value,0,1e15);
        saveBuild();view.innerHTML=render();return;
      }
      if(location.hash!=="#stats" || !el.matches("[data-tc],[data-tc-stat],[data-tc-extra]")) return;
      if(el.dataset.tc) {
        const key=el.dataset.tc;
        if(key==="selectedGym") state.selectedGym=el.value;
        else if(key==="trainCount"){state.trainCount=Math.floor(clamp(el.value,1,10000));state.trainMax=false;state.trainFull=false;}
        else if(key==="calcCandyQty"){state.calcCandyQty=Math.floor(clamp(el.value,0,1000000000));state.calcCandyMax=false;}
        else if(key==="calcCandyHappy"){const h=el.value==="any"?"any":Number(el.value);if(["any",25,35,50,75,100,150,250].includes(h))state.calcCandyHappy=h;}
        else if(Object.prototype.hasOwnProperty.call(state,key)) {
          let n=numeric(el.value,state[key]);
          const integerFields=["hours","regenMinutes","naturalXan","naturalEcstasy","naturalCandy","naturalRefill","jumpXan","jumpEcstasy","jumpCandy","jumpDvd","jumpRefill"];
          const max={hours:168,regenMinutes:15,naturalXan:16,naturalEcstasy:1,naturalCandy:60,naturalRefill:7,jumpXan:4,jumpEcstasy:1,jumpCandy:60,jumpDvd:9,jumpRefill:1,boosterCap:96};
          const min=key==="hours"?1:key==="regenMinutes"?10:0;
          n=clamp(integerFields.includes(key)?Math.floor(n):n,min,Object.prototype.hasOwnProperty.call(max,key)?max[key]:100000000);
          state[key]=n;
        }
      }
      if(el.dataset.tcStat)state.statValues[el.dataset.tcStat]=clamp(el.value,0,1e15);
      if(el.dataset.tcExtra)state.extra[el.dataset.tcExtra]=clamp(el.value,-95,300);
      // Refresh calculated results without losing the browser route or API key.
      view.innerHTML=render();
    });
    view.addEventListener("click",event=>{
      if(location.hash!=="#stats") return;
      if(event.target.closest("#tc-sequencer") || Object.keys(event.target.dataset||{}).some(key=>key.startsWith("ts"))) return;
      if(event.target.closest("[data-tc-build-reset]")){loadBuild();buildTotal=0;saveBuild();view.innerHTML=render();return;}
      const tab=event.target.closest("[data-tc-view]");
      if(tab){
        if(["gym","calc","compare"].includes(tab.dataset.tcView)){
          state.subpage=tab.dataset.tcView;
          view.innerHTML=render();
        }
        return;
      }
      const gymButton=event.target.closest("[data-tc-gym]");
      if(gymButton){const active=activeGym();state.selectedGym=active&&active.name===gymButton.dataset.tcGym?null:gymButton.dataset.tcGym;if(state.selectedGym!==null&&active)state.gymInfoOpen=true;view.innerHTML=render();return;}
      const reset=event.target.closest("[data-tc-reset]");
      if(reset){const stat=reset.dataset.tcReset,value=apiStatValue(stat);if(value!==null){state.statValues[stat]=value;view.innerHTML=render();}return;}
      const pick=event.target.closest("[data-tc-pick]");
      const action=event.target.closest("[data-tc-action]");
      if(pick){state.compareStat=pick.dataset.tcPick;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="auto-gym"){state.selectedGym=null;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="happy-mode"){state.calcHappyMode=({current:"hj",hj:"99k","99k":"current"})[state.calcHappyMode];view.innerHTML=render();return;}
      if(action&&action.dataset.tcAction==="candy-max"){if(calcCandyPlan().loaded&&calcCandyPlan().cooldown.allowed!==null){state.calcCandyMax=true;state.calcCandyQty=calcCandyPlan().capacity;view.innerHTML=render();}return;}
      if(action&&action.dataset.tcAction==="max"){state.trainMax=true;state.trainFull=false;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="full"){state.trainFull=true;state.trainMax=false;view.innerHTML=render();return;}
      if(action&&action.dataset.tcAction==="restore"){hydrateFromApi(true);view.innerHTML=render();}
    });
  }
  return {render,wire,syncLiveBars,homeTrainingAdvice,homeCandyAdvice,
    simulate:()=>({natural:tornTrainSequence.simulate(tornTrainSequence.steps.natural),jump:tornTrainSequence.simulate(tornTrainSequence.steps.jump)}),
    state,internal:{oneTrain,trainBlock,percentage,gainPerks}};
})();
