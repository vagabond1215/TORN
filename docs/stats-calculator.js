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
    selectedGym:null, currentPlayer:null, imported:false, apiStamp:null,
    statValues:{strength:1000,defense:1000,speed:1000,dexterity:1000},
    energy:{strength:150,defense:0,speed:0,dexterity:0},
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
    state.currentPlayer=id;
    const bars=rawBars(),stats=rawStats();
    if (bars) {
      state.currentEnergy=clamp(bars.energy&&bars.energy.current,0,1000);
      state.maxEnergy=clamp(bars.energy&&bars.energy.maximum,1,1000);
      state.happy=clamp(bars.happy&&bars.happy.current,0,99999);
      state.maxHappy=clamp(bars.happy&&bars.happy.maximum,1,99999);
      const maxE=state.currentEnergy;
      state.energy={strength:maxE,defense:0,speed:0,dexterity:0};
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
    state.selectedGym=null; // Choose actual active gym from catalog after import.
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
  function selectedGym() {
    const all=gyms();
    const g=api("gym");
    const info=g&&(g.gym||g);
    const current=info&&(info.active_gym!==undefined?info.active_gym:info.id!==undefined?info.id:null);
    if(state.selectedGym===null && current!==null && current!==undefined) {
      const id=typeof current==="object"?current.id:current;
      const match=all.find(item=>String(item.id)===String(id)||String(item.name).toLowerCase()===String(id).toLowerCase());
      if(match) state.selectedGym=String(match.id);
    }
    if(state.selectedGym===null) state.selectedGym=String(all[0].id);
    return all.find(item=>String(item.id)===String(state.selectedGym))||all[0];
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
  function naturalEvents(opts,kind) {
    const horizon=Math.floor(state.hours*60),reg=state.regenMinutes;
    const cap=state.maxEnergy,gym=selectedGym(),stat=state.compareStat;
    const cost=Math.max(1,Math.floor(gym.energy));
    const totalX=kind==="natural"?state.naturalXan:state.jumpXan;
    const ecst=kind==="natural"?state.naturalEcstasy:state.jumpEcstasy;
    const candy=kind==="natural"?state.naturalCandy:state.jumpCandy;
    const refills=kind==="natural"?state.naturalRefill:state.jumpRefill;
    const jump=kind==="jump";
    const stackDelay=totalX*480;
    const feasible=jump ? (horizon>=stackDelay && state.jumpDvd*6+state.jumpCandy*0.5<=state.boosterCap) : (state.naturalCandy*0.5<=state.boosterCap);
    const multiplier=effectsFor(stat).multiplier;
    let current=state.statValues[stat],E=state.currentEnergy,H=state.happy;
    const initialH=state.happy;
    let used=0,missedRegen=0,spentX=0,spentEc=0,spentCandy=0,spentDvd=0,spentPoints=0;
    let nextX=ecst&& !jump?240:0;
    let boosterApplied=false,stacked=false;
    const series=[{hour:0,value:current}];
    function train() {
      const result=trainBlock(current,H,E,gym,stat,multiplier);
      current=result.stat;H=result.happy;E-=result.used;used+=result.used;
    }
    function boost(countCandy,countDvd,ecstasy) {
      H=Math.min(99999,H+countCandy*state.candyHappy+countDvd*state.dvdHappy);
      spentCandy+=countCandy;spentDvd+=countDvd;
      if(ecstasy) {H=Math.min(99999,H*2);spentEc+=1;}
      boosterApplied=true;
    }
    function addEnergy(amount) {
      const newE=Math.min(1000,E+amount);
      E=newE;
    }
    function refill() {
      E=cap;spentPoints+=1;
    }
    if(jump && totalX>0) {
      // A 4-Xanax stack starts with an empty bar, so train starting Energy before banking.
      train();
      if(feasible) {addEnergy(250);spentX++;stacked=true;}
    } else {
      if(feasible) boost(candy,jump?state.jumpDvd:0,ecst);
      train();
      if(!jump && totalX>0 && !ecst) {addEnergy(250);spentX++;train();nextX=480;}
      if(!jump && refills>0) {refill();train();}
      if(jump && feasible && refills>0) {refill();train();}
    }
    for(let minute=5;minute<=horizon;minute+=5) {
      if(minute%reg===0) {
        if(E<cap && !(jump&&stacked)) E=Math.min(cap,E+5);
        else missedRegen+=5;
      }
      if(minute%15===0) {
        H=Math.min(state.maxHappy,H+5);
        if(H>state.maxHappy) H=state.maxHappy;
      }
      if(jump && totalX>0 && feasible && minute%480===0 && minute<stackDelay && spentX<totalX) {
        addEnergy(250);spentX++;
      }
      if(jump && totalX>0 && feasible && minute===stackDelay) {
        boost(candy,state.jumpDvd,ecst);train();
        if(refills>0) {refill();train();}
        stacked=false;
      }
      if(!jump && spentX<totalX && minute>=nextX) {
        addEnergy(250);spentX++;train();nextX=minute+480;
      }
      if(!jump && spentPoints<refills && minute>=spentPoints*1440 && minute>0) {
        refill();train();
      }
      if(!stacked && minute!==stackDelay) train();
      if(minute%60===0 || minute===horizon) series.push({hour:minute/60,value:current});
    }
    const costMoney=spentX*state.priceXan+spentEc*state.priceEcstasy+spentCandy*state.priceCandy+
      spentDvd*state.priceDvd+spentPoints*30*state.pricePoint;
    return {start:state.statValues[stat],final:current,gain:current-state.statValues[stat],energyUsed:used,
      happyAtBoost:boosterApplied?Math.min(99999,(initialH+candy*state.candyHappy+(jump?state.jumpDvd:0)*state.dvdHappy)*(ecst?2:1)):null,
      missedRegen,spentX,spentEc,spentCandy,spentDvd,spentPoints,cost:costMoney,complete:feasible,
      series};
  }
  function fields() {
    const a=state;
    const number=(key,label,step,min,max,tip)=>{
      return '<label class="tc-field"><span>'+esc(label)+'</span><input type="number" data-tc="'+esc(key)+'" value="'+esc(a[key])+'" step="'+step+'" min="'+min+'" max="'+max+'">'+(tip?'<small>'+esc(tip)+'</small>':"")+'</label>';
    };
    return '<div class="tc-settings-grid">'+
      number("hours","Same time window (hours)",1,1,168,"Both strategies run for this entire period")+
      number("regenMinutes","Energy +5 every (minutes)",5,10,15,"10 = donor/subscriber; 15 = standard")+
      number("naturalXan","Natural: Xanax doses",1,0,16,"250 Energy each, spaced at least 8 hours")+
      number("naturalRefill","Natural: points refills",1,0,7,"30 points each; one per ~24 hours")+
      number("naturalCandy","Natural: candy units",1,0,60,"Consumed just before starting training")+
      number("naturalEcstasy","Natural: Ecstasy (0 or 1)",1,0,1,"Doubles happiness before first train")+
      number("jumpXan","Jump: stacked Xanax",1,0,4,"Up to 1,000 Energy; allow 8 hours per dose")+
      number("jumpRefill","Jump: points refill (0 or 1)",1,0,1,"Used immediately during the jump")+
      number("jumpDvd","Jump: eDVD count",1,0,9,"+2,500 Happy each before Ecstasy")+
      number("jumpCandy","Jump: candy count",1,0,60,"Combined with eDVDs; booster cap applies")+
      number("jumpEcstasy","Jump: Ecstasy (0 or 1)",1,0,1,"Doubles happiness immediately before training")+
      number("candyHappy","Happy per candy",1,0,5000,"Lollipop: 25; Big Box of Chocolate: 35")+
      number("dvdHappy","Happy per eDVD",1,0,10000,"Usually 2,500; job perks may raise this")+
      number("boosterCap","Available booster cooldown hours",1,0,96,"Typical cap is 24 hours, faction perks can change it")+
      '</div><details class="tc-advanced"><summary>Editable estimated item prices (Torn dollars)</summary><div class="tc-settings-grid">'+
      number("priceXan","Xanax each",1,0,100000000)+number("priceEcstasy","Ecstasy each",1,0,100000000)+
      number("priceCandy","Candy each",1,0,100000000)+number("priceDvd","eDVD each",1,0,100000000)+
      number("pricePoint","Price per point",1,0,100000000)+'</div></details>';
  }
  function statPanel(stat,gym) {
    const eff=effectsFor(stat);
    const battle=battleEffects(stat);
    const projected=singleStatSession(stat,state.energy[stat],gym);
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
      '<label class="tc-field"><span>Energy to spend</span><input data-tc-energy="'+stat+'" type="number" min="0" max="1000" step="'+gym.energy+'" value="'+esc(state.energy[stat])+'"></label>'+
      '<div class="tc-stat-meta"><span>Gym dots</span><strong>'+(disabled?"Unavailable":nice(gym[stat],1))+'</strong></div>'+
      '<div class="tc-stat-meta"><span>Est. gain</span><strong>+'+nice(projected.stat-state.statValues[stat],2)+'</strong></div>'+
      '<div class="tc-stat-meta"><span>Est. final</span><strong>'+nice(projected.stat,2)+'</strong></div>'+
      bonuses+'</div>';
  }
  function chart(natural,jump) {
    const width=840,height=260,left=70,right=20,top=20,bottom=40;
    const base=state.statValues[state.compareStat];
    const higher=Math.max(natural.final,jump.final,base+1);
    const range=higher-base;
    const x=t=>left+(t/state.hours)*(width-left-right);
    const y=v=>top+(1-(v-base)/range)*(height-top-bottom);
    const line=(list)=>list.map((p,i)=>(i?"L":"M")+x(p.hour).toFixed(1)+" "+y(p.value).toFixed(1)).join(" ");
    let markup='<svg class="tc-chart-svg" viewBox="0 0 '+width+' '+height+'" role="img" aria-label="Projected '+esc(readable[state.compareStat])+' over '+state.hours+' hours: natural final '+nice(natural.final)+' versus jump final '+nice(jump.final)+'">';
    for(let i=0;i<5;i++){
      const v=base+range*i/4,py=y(v);
      markup+='<line x1="'+left+'" x2="'+(width-right)+'" y1="'+py+'" y2="'+py+'" stroke="#42463d" stroke-width="1"/>';
      markup+='<text x="'+(left-8)+'" y="'+(py+4)+'" text-anchor="end" fill="#b6baad" font-size="11">'+esc(nice(v))+'</text>';
    }
    for(let i=0;i<=4;i++)markup+='<text x="'+x(state.hours*i/4)+'" y="'+(height-10)+'" fill="#b6baad" font-size="12" text-anchor="middle">'+nice(state.hours*i/4,1)+'h</text>';
    markup+='<path d="'+line(natural.series)+'" stroke="#8dbde0" fill="none" stroke-width="3" stroke-linejoin="round"/>';
    if(jump.complete)markup+='<path d="'+line(jump.series)+'" stroke="#e4c673" fill="none" stroke-width="3" stroke-linejoin="round"/>';
    markup+='</svg><div class="tc-chart-legend"><span><i style="background:#8dbde0"></i>Natural / regular</span><span><i style="background:#e4c673"></i>Happy jump</span></div>';
    return markup;
  }
  function comparison() {
    const n=naturalEvents({}, "natural"),j=naturalEvents({}, "jump"),delta=j.gain-n.gain;
    const warnings=[];
    if(state.jumpXan*8>state.hours) warnings.push("The stacked-Xanax jump needs "+state.jumpXan*8+" hours (including the final drug cooldown). It cannot finish inside the selected window.");
    if(state.jumpDvd*6+state.jumpCandy*0.5>state.boosterCap) warnings.push("Jump boosters require "+nice(state.jumpDvd*6+state.jumpCandy*0.5,1)+" hours of booster capacity. Your selected cap is only "+state.boosterCap+" hours.");
    if(state.naturalCandy*0.5>state.boosterCap) warnings.push("Natural candy consumption exceeds your selected booster cooldown capacity.");
    if(state.naturalXan>Math.floor((state.hours*60-(state.naturalEcstasy?240:0))/480)+1)warnings.push("Not all requested natural Xanax doses fit the time window; only the scheduled ones were used.");
    if(state.naturalRefill>Math.ceil(state.hours/24))warnings.push("Natural points refills are limited to roughly one per 24 hours; not all requested refills fit.");
    let verdict="The happy jump is not feasible with the chosen timing or cooldown limits.";
    if(n.complete && j.complete)verdict=delta>0?"Happy jump gains ~"+nice(delta)+" more "+readable[state.compareStat]+" in this window.":delta<0?"Natural training gains ~"+nice(-delta)+" more "+readable[state.compareStat]+" in this window.":"Both approaches produce similar projected gains.";
    const summary='<div class="tc-compare-summary">'+
      '<div class="tc-result"><span>Natural: final stat</span><strong>'+(n.complete?nice(n.final,2):"Not feasible")+'</strong><small>+'+nice(n.gain,2)+' gained · '+nice(n.energyUsed)+' Energy</small><small>Est. cost $'+nice(n.cost)+'</small></div>'+
      '<div class="tc-result"><span>Happy jump: final stat</span><strong>'+ (j.complete?nice(j.final,2):"Not feasible")+'</strong><small>+'+nice(j.gain,2)+' gained · '+nice(j.energyUsed)+' Energy</small><small>Est. cost $'+nice(j.cost)+'</small></div>'+
      '<div class="tc-result"><span>Difference in gain</span><strong>'+(n.complete&&j.complete?(delta>0?"+":"")+nice(delta,2):"—")+'</strong><small>Jump minus natural</small><small>Same '+nice(state.hours)+'-hour period</small></div></div>';
    return (warnings.length?'<div class="tc-warnings" role="status">'+warnings.map(s=>'<p>'+esc(s)+'</p>').join("")+'</div>':"")+
      summary+'<p class="tc-verdict">'+esc(verdict)+'</p>'+
      (n.complete&&j.complete?chart(n,j):'<p class="fine-print">The comparison graph is hidden because one or more recipes cannot complete under the current settings.</p>')+
      '<div class="tc-footnotes"><p>Natural: immediate training, continuous energy regeneration when below the cap, scheduled Xanax, optional candy/Ecstasy and point refills. Jump: train your starting energy before stacking Xanax, wait for each drug cooldown, apply happy boosters and Ecstasy once, then train the banked energy and optional refill. Other time is spent regenerating or waiting.</p>'+
      '<p>Average estimates, not exact predictions. No overdose probability, drug addiction progression, combat injury, shop-job train conversion, calendar happy-reset alignment, faction perks altering item effectiveness, or fluctuating item prices are simulated. Drug cooldown is modeled as 8 hours for Xanax and 4 hours for Ecstasy; actual cooldowns vary. Points refills cost 30 points and are limited to one per day.</p>'+
      '<p><a href="https://wiki.torn.com/wiki/Gym#Training_Formulas" target="_blank" rel="noopener noreferrer">Torn Gym formula</a> · <a href="https://wiki.torn.com/wiki/Happy" target="_blank" rel="noopener noreferrer">Happy mechanics</a> · <a href="https://aidapaul.github.io/torn-happy-jumps/" target="_blank" rel="noopener noreferrer">Jump timing guide</a></p></div>';
  }
  function render() {
    hydrateFromApi();
    const gym=selectedGym();
    const totalEnergy=statNames.reduce((v,s)=>v+numeric(state.energy[s]),0);
    const remaining=state.currentEnergy-totalEnergy;
    const available=tornGuideApi.isConnected();
    const gymOptions=gyms().map(g=>'<option value="'+esc(g.id)+'" '+(String(g.id)===String(gym.id)?"selected":"")+'>'+esc(g.name)+(g.offline?" (wiki dots)":"")+'</option>').join("");
    let markup='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Stats & training calculator</h1><p>Four battle stats in parallel, source-by-source perks and combat modifiers, and an equal-time happy-jump comparison.</p></header>';
    markup+='<section class="panel"><div class="panel-heading"><h2>Current training conditions</h2></div><div class="panel-content">'+
      '<div class="tc-status"><span><strong>'+nice(state.currentEnergy)+' / '+nice(state.maxEnergy)+'</strong> Energy</span><span><strong>'+nice(state.happy)+' / '+nice(state.maxHappy)+'</strong> Happy</span><span><strong>'+ (available?"Torn API connected":"Demo / manual mode")+'</strong></span></div>'+
      '<div class="tc-controls"><label class="tc-field"><span>Gym used for the calculation</span><select data-tc="selectedGym">'+gymOptions+'</select></label>'+
      '<button type="button" class="button secondary" data-tc-action="restore" '+(!available?"disabled":"")+'>Restore current API values</button></div>'+
      '<p class="fine-print">The selected gym uses '+gym.energy+' Energy per train. Missing gym dots indicate a stat that cannot be trained there. The '+(gym.offline?"API + offline fallback":"Torn API")+' gym catalog is in use. Editable values can be used for planning; they do not alter your Torn account.</p></div></section>';
    if(!available) markup+='<div class="tc-notice">Connect your <a href="#profile">Torn account</a> to load real battle stats, live energy/happiness, gym membership and active perks. Sample values are displayed until then.</div>';
    else if(!api("battlestats")||!api("perks"))markup+='<div class="tc-notice">Some API selections are missing. Values and modifiers not provided by Torn will be marked as unavailable or treated as zero in estimates.</div>';
    markup+='<section class="panel"><div class="panel-heading"><h2>Four-stat energy allocation</h2></div><div class="panel-content">'+
      '<p class="tc-budget '+(remaining<0?"tc-neg":"")+'">Allocated '+nice(totalEnergy)+' E of '+nice(state.currentEnergy)+' currently available · '+(remaining>=0?nice(remaining)+' unallocated':nice(-remaining)+' over budget')+'</p>'+
      '<div class="tc-stat-scroll"><div class="tc-four">'+statNames.map(stat=>statPanel(stat,gym)).join("")+'</div></div>'+
      '<p class="fine-print">Training gains use the current Happy level and average per-train Happy loss. Combat-only penalties (including some drug and merit effects) are listed separately and are not treated as gym-gain modifiers. Different stats have independent faction and education bonuses.</p></div></section>';
    markup+='<section class="panel"><div class="panel-heading"><h2>Natural energy vs. happy jump</h2></div><div class="panel-content">'+
      '<div class="tc-stat-tabs" role="group" aria-label="Compare stat">'+statNames.map(stat=>'<button type="button" class="tc-stat-tab '+(state.compareStat===stat?"is-selected":"")+'" data-tc-pick="'+stat+'">'+readable[stat]+'</button>').join("")+'</div>'+
      '<div class="tc-compare-intro">Choose the same time window and edit both strategies. Natural uses regeneration continuously; the jump banks energy with Xanax, losing natural regeneration while above the cap. Both start from '+nice(state.statValues[state.compareStat])+' '+readable[state.compareStat]+'.</div>'+
      fields()+'<div id="tc-comparison">'+comparison()+'</div></div></section>';
    return markup;
  }
  function wire(view) {
    if (view.dataset.tcPlannerBound === "1") return;
    view.dataset.tcPlannerBound = "1";
    view.addEventListener("change",event=>{
      const el=event.target;
      if(el.dataset.tc) {
        const key=el.dataset.tc;
        if(key==="selectedGym") state.selectedGym=el.value;
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
      if(el.dataset.tcEnergy)state.energy[el.dataset.tcEnergy]=clamp(el.value,0,1000);
      if(el.dataset.tcExtra)state.extra[el.dataset.tcExtra]=clamp(el.value,-95,300);
      // Refresh calculated results without losing the browser route or API key.
      view.innerHTML=render();
    });
    view.addEventListener("click",event=>{
      const pick=event.target.closest("[data-tc-pick]");
      const action=event.target.closest("[data-tc-action]");
      if(pick){state.compareStat=pick.dataset.tcPick;view.innerHTML=render();}
      if(action&&action.dataset.tcAction==="restore"){hydrateFromApi(true);view.innerHTML=render();}
    });
  }
  return {render,wire,simulate:()=>({natural:naturalEvents({},"natural"),jump:naturalEvents({},"jump")}),
    state,internal:{oneTrain,trainBlock,percentage,gainPerks}};
})();
