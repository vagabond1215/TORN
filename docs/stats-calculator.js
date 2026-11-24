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
    ["Woody's Workout",5,2.8,3.2,3.0,2.8],["Beach Bods",5,3.2,3.2,3.2,0],
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
    ["The Sports Science Lab",25,9,9,9,9],["Fight Club",10,10,10,10]
  ].map((g,i) => ({id:i+1,name:g[0],energy:g[1],strength:g[2],speed:g[3],defense:g[4],dexterity:g[5],offline:true}));
  const state = {
    selectedGym:null, currentPlayer:null, imported:false, apiStamp:null, subpage:"calc",
    statValues:{strength:1000,defense:1000,speed:1000,dexterity:1000},
    trainCount:1, trainMax:false,
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
  const rawBars=()=>{const p=api("bars");return p && p.bars?p.bars:null;};
  function hydrateFromApi(force=false) {
    const id=tornGuideApi.state.identity&&tornGuideApi.state.identity.id;
    if (!id) {
      if (state.currentPlayer!==null) { state.currentPlayer=null;state.imported=false;state.apiStamp=null;state.selectedGym=null; }
      return;
    }
    if (!force && state.currentPlayer===id && state.imported) return;
    if(state.currentPlayer!==id || force) state.selectedGym=null;
    state.currentPlayer=id;
    const bars=rawBars(),stats=rawStats();
    if (bars) {
      state.currentEnergy=clamp(bars.energy&&bars.energy.current,0,1000);
      state.maxEnergy=clamp(bars.energy&&bars.energy.maximum,1,1000);
      state.happy=clamp(bars.happy&&bars.happy.current,0,99999);
      state.maxHappy=clamp(bars.happy&&bars.happy.maximum,1,99999);

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
  function gyms() {
    const source=api("gymCatalog");
    const raw=source && source.gyms;
    if (!raw || typeof raw!=="object") return fallback;
    const pairs=Array.isArray(raw)?raw.map((item,index)=>[String(item.id??index+1),item]):Object.entries(raw);
    const pick=(...values)=>values.find(value=>value!==null && value!==undefined && Number.isFinite(Number(value)));
    const normalized=pairs.filter(([key,item])=>item && typeof item==="object" && item.name).map(([key,item])=>{
      const known=fallback.find(g=>g.name.toLowerCase()===String(item.name).toLowerCase());
      const result={id:item.id??Number(key),name:String(item.name),energy:5,offline:false};
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
    return normalized.length?normalized:fallback;
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
  function singleStatSession(stat,energy,gym) {
    const start=state.statValues[stat];
    return trainBlock(start,state.happy,energy,gym,stat,effectsFor(stat).multiplier);
  }
  const shorthand={strength:"STR",defense:"DEF",speed:"SPD",dexterity:"DEX"};
  const gymCategories=["Lightweight","Middleweight","Heavyweight","Specialty"];
  function gymCategory(g) {
    const index=fallback.findIndex(item=>item.name.toLowerCase()===g.name.toLowerCase());
    return index<0?3:Math.min(3,Math.floor(index/8));
  }
  function trainingCount(gym) {
    return state.trainMax?Math.floor(state.currentEnergy/gym.energy):Math.max(1,Math.min(10000,Math.floor(state.trainCount)));
  }
  function gymIcon(category) {
    const plates=[1,2,3,3][category];
    let shapes='<path d="M6 16h20" stroke-width="2.5"/>';
    for(let i=0;i<plates;i++){
      const h=10+i*3;
      shapes+='<rect x="'+(5+i*3)+'" y="'+(16-h/2)+'" width="2.5" height="'+h+'" rx="1"/><rect x="'+(24-i*3)+'" y="'+(16-h/2)+'" width="2.5" height="'+h+'" rx="1"/>';
    }
    if(category===3)shapes+='<path d="m16 1 1.5 3 3 .5-2.2 2 .5 3-2.8-1.5-2.8 1.5.5-3-2.2-2 3-.5Z"/>';
    return '<svg viewBox="0 0 32 32" width="34" height="34" fill="none" stroke="currentColor" stroke-linejoin="round" aria-hidden="true">'+shapes+'</svg>';
  }
  function statPanel(stat,gym) {
    const eff=effectsFor(stat);
    const battle=battleEffects(stat);
    const projected=singleStatSession(stat,trainingCount(gym)*gym.energy,gym);
    const disabled=!gym[stat];
    let bonuses='<div class="tc-mod-head">Gym gain effects (multiplied by source)</div>';
    for(const group of eff.groups) {
      const label=group.group==="job"?"Job / workplace":group.group[0].toUpperCase()+group.group.slice(1);
      bonuses+='<div class="tc-mod-row"><span>'+esc(label)+'</span><strong class="'+(group.total<0?"tc-neg":group.total>0?"tc-pos":"")+'">'+(group.total>=0?"+":"")+nice(group.total,2)+'%</strong></div>';
      for(const entry of group.items) bonuses+='<small class="tc-mod-detail" title="'+esc(entry.text)+'">'+esc(entry.text)+'</small>';
    }
    bonuses+='<label class="tc-manual"><span>Custom gym-gain %</span><input type="number" min="-95" max="300" step="0.1" data-tc-extra="'+stat+'" value="'+esc(state.extra[stat])+'"></label>';
    bonuses+='<p class="tc-multiplier">Training multiplier ×'+nice(eff.multiplier,3)+(eff.sourceAvailable?"":" · API perks unavailable")+'</p>';
    bonuses+='<div class="tc-mod-head">Effective combat modifiers (not gym gains)</div>';
    if(battle) {
      bonuses+='<p class="tc-combat-total">Total combat modifier: <strong class="'+(battle.total<0?"tc-neg":battle.total>0?"tc-pos":"")+'">'+(battle.total>=0?"+":"")+nice(battle.total,2)+'%</strong></p>';
      if(battle.lines.length) for(const line of battle.lines) bonuses+='<small class="tc-mod-detail">'+esc(line.text)+(line.value!==null?" ("+(line.value>0?"+":"")+nice(line.value,2)+"%)":"")+'</small>';
      else bonuses+='<small class="tc-mod-detail">No individual combat modifiers reported.</small>';
    } else bonuses+='<small class="tc-mod-detail">Requires a connected API key with battle-stat access.</small>';
    return '<div class="tc-stat-col '+(disabled?"tc-disabled":"")+'"><div class="tc-stat-title">'+readable[stat]+'</div>'+
      '<label class="tc-field"><span>Current stat</span><input data-tc-stat="'+stat+'" type="number" min="0" step="1" value="'+esc(state.statValues[stat])+'"></label>'+
      '<div class="tc-stat-meta"><span>Gym dots</span><strong>'+(disabled?"Unavailable":nice(gym[stat],1))+'</strong></div>'+
      '<div class="tc-stat-meta"><span>Est. gain</span><strong>+'+nice(projected.stat-state.statValues[stat],2)+'</strong></div>'+
      '<div class="tc-stat-meta"><span>Est. final</span><strong>'+nice(projected.stat,2)+'</strong></div>'+
      bonuses+'</div>';
  }
  function render() {
    hydrateFromApi();
    const gym=selectedGym();
    const active=activeGym();
    const available=tornGuideApi.isConnected();
    let markup='<h1 id="topic-title" tabindex="-1" class="sr-only">Battle stats</h1><div class="tc-subbar"><nav class="tc-subnav" aria-label="Stats sections">'+
      '<button type="button" data-tc-view="calc" class="tc-subtab '+(state.subpage==="calc"?"is-current":"")+'" aria-current="'+(state.subpage==="calc"?"page":"false")+'">Calc · Gym simulator</button>'+
      '<button type="button" data-tc-view="compare" class="tc-subtab '+(state.subpage==="compare"?"is-current":"")+'" aria-current="'+(state.subpage==="compare"?"page":"false")+'">Compare · Training strategies</button></nav>'+
      '<div class="tc-overview"><div class="tc-stat-overview">'+statNames.map(stat=>
      '<div class="tc-overview-item"><small title="'+readable[stat]+'">'+shorthand[stat]+'</small><strong>'+nice(state.statValues[stat])+'</strong></div>').join("")+'</div></div></div>';
    if(state.subpage==="calc"){
    const catalog=gyms();
    const ordered=[...catalog].sort((a,b)=>{
      const rank=g=>{const i=fallback.findIndex(x=>x.name.toLowerCase()===g.name.toLowerCase());return i<0?999:i;};
      return rank(a)-rank(b);
    });
    markup+='<section class="panel"><div class="panel-content tc-gym-picker"><div class="tc-gym-board" role="group" aria-label="Select simulation gym">'+gymCategories.map((label,i)=>{
      const list=ordered.filter(g=>gymCategory(g)===i);
      return '<div class="tc-gym-group"><span class="tc-gym-group-label">'+label+'</span><div class="tc-gym-tiles">'+list.map(g=>
        '<button type="button" class="tc-gym-tile '+(g.name===gym.name?"is-selected":"")+(active&&g.name===active.name?" is-active-gym":"")+'" data-tc-gym="'+esc(g.name)+'" title="'+esc(g.name)+' · '+g.energy+' E/train'+(active&&g.name===active.name?' · Current gym':'')+'" aria-label="'+esc(g.name)+'" aria-pressed="'+(g.name===gym.name)+'">'+gymIcon(i)+'<span>'+esc(g.name)+'</span></button>').join("")+
        Array.from({length:Math.max(0,10-list.length)},()=>'<span class="tc-gym-empty" aria-hidden="true"></span>').join("")+'</div></div>';
    }).join("")+'</div>'+
      '<div class="tc-gym-details"><strong>'+esc(gym.name)+'</strong><span class="fine-print">'+(state.selectedGym!==null?'Manual simulation override':active?'Current API gym':'Demo / gym not reported')+'</span>'+
      '<div class="tc-status"><span><strong>'+nice(state.currentEnergy)+' / '+nice(state.maxEnergy)+'</strong> Energy</span><span><strong>'+nice(state.happy)+' / '+nice(state.maxHappy)+'</strong> Happy</span><span>'+gym.energy+' E/train</span></div>'+
      '<button type="button" class="button secondary" data-tc-action="auto-gym" '+(state.selectedGym===null?'disabled':'')+'>Use current gym</button>'+
      '<button type="button" class="button secondary" data-tc-action="restore" '+(!available?"disabled":"")+'>Restore current API values</button></div></div></section>';
    if(!available) markup+='<div class="tc-notice">Connect your <a href="#profile">Torn account</a> to load real battle stats, live energy/happiness, gym membership and active perks. Sample values are displayed until then.</div>';
    else if(!api("battlestats")||!api("perks"))markup+='<div class="tc-notice">Some API selections are missing. Values and modifiers not provided by Torn will be marked as unavailable or treated as zero in estimates.</div>';
    markup+='<section class="panel"><div class="panel-heading"><h2>Gym training simulator</h2></div><div class="panel-content">'+
      '<div class="tc-train-control"><label for="tc-train-count">Train:</label><input id="tc-train-count" data-tc="trainCount" type="number" min="1" max="10000" step="1" value="'+trainingCount(gym)+'"><button type="button" class="button secondary '+(state.trainMax?"is-selected":"")+'" data-tc-action="max" aria-pressed="'+state.trainMax+'">MAX</button><small>'+nice(trainingCount(gym)*gym.energy)+' E per alternative'+(trainingCount(gym)*gym.energy>state.currentEnergy?' · exceeds current Energy (simulation only)':'')+'</small></div>'+
      '<div class="tc-stat-scroll"><div class="tc-four">'+statNames.map(stat=>statPanel(stat,gym)).join("")+'</div></div>'+
      '<p class="fine-print">Training gains use the current Happy level and average per-train Happy loss. Combat-only penalties (including some drug and merit effects) are listed separately and are not treated as gym-gain modifiers. Different stats have independent faction and education bonuses.</p></div></section>';
    }
    if(state.subpage==="compare"){
      markup+='<div class="tc-compare-conditions">Using <strong>'+esc(gym.name)+'</strong> ('+nice(gym.energy)+' E/train), <strong>'+
        nice(state.currentEnergy)+' / '+nice(state.maxEnergy)+' Energy</strong> and <strong>'+
        nice(state.happy)+' / '+nice(state.maxHappy)+' Happy</strong>. Change gym and editable stats on <button type="button" class="text-button" data-tc-view="calc">Calc</button>.</div>';
    markup+='<section class="panel"><div class="panel-heading"><h2>Natural Energy vs. Happy Jump · Execution Timeline</h2></div><div class="panel-content">'+
      '<div class="tc-stat-tabs" role="group" aria-label="Compare stat">'+statNames.map(stat=>'<button type="button" class="tc-stat-tab '+(state.compareStat===stat?"is-selected":"")+'" data-tc-pick="'+stat+'">'+readable[stat]+'</button>').join("")+'</div>'+
      '<div class="tc-compare-intro">Choose a stat and edit each plan as a sequence of actions. Both use the same starting stat of '+nice(state.statValues[state.compareStat])+' and the same time window.</div>'+
      '<div id="tc-sequencer">'+tornTrainSequence.render({state,gym,trainBlock,effectsFor})+'</div></div></section>';
    }
    return markup;
  }
  function wire(view) {
    if (view.dataset.tcPlannerBound === "1") return;
    view.dataset.tcPlannerBound = "1";
    tornTrainSequence.wire(view);
    view.addEventListener("change",event=>{
      if(event.target.closest("#tc-sequencer") || Object.keys(event.target.dataset||{}).some(key=>key.startsWith("ts"))) return;
      const el=event.target;
      if(el.dataset.tc) {
        const key=el.dataset.tc;
        if(key==="selectedGym") state.selectedGym=el.value;
        else if(key==="trainCount"){state.trainCount=Math.floor(clamp(el.value,1,10000));state.trainMax=false;}
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
      if(event.target.closest("#tc-sequencer") || Object.keys(event.target.dataset||{}).some(key=>key.startsWith("ts"))) return;
      const tab=event.target.closest("[data-tc-view]");
      if(tab){
        if(tab.dataset.tcView==="calc" || tab.dataset.tcView==="compare"){
          state.subpage=tab.dataset.tcView;
          view.innerHTML=render();
        }
        return;
      }
      const gymButton=event.target.closest("[data-tc-gym]");
      if(gymButton){state.selectedGym=gymButton.dataset.tcGym;view.innerHTML=render();return;}
      const pick=event.target.closest("[data-tc-pick]");
      const action=event.target.closest("[data-tc-action]");
      if(pick){state.compareStat=pick.dataset.tcPick;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="auto-gym"){state.selectedGym=null;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="max"){state.trainMax=true;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="restore"){hydrateFromApi(true);view.innerHTML=render();}
    });
  }
  return {render,wire,
    simulate:()=>({natural:tornTrainSequence.simulate(tornTrainSequence.steps.natural),jump:tornTrainSequence.simulate(tornTrainSequence.steps.jump)}),
    state,internal:{oneTrain,trainBlock,percentage,gainPerks}};
})();
