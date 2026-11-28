"use strict";
/* Nice honor: >=5 integer-digit occurrences across the four base stats,
 * with at least one of each. Community-confirmed rule, not an award API.
 * Bounded deterministic search in one gym and fixed displayed stat order.
 * Model uses the shared per-train gain and shared Happiness depletion.
 * No requests, writes, automation or changes to the player's build.
 */
const tornNiceMerit=(()=>{
  const order=["strength","defense","speed","dexterity"],limit=200;
  const valid=v=>typeof v==="number"&&Number.isFinite(v)&&v>=0&&v<Number.MAX_SAFE_INTEGER;
  function count(value){
    if(!valid(value))return null;
    const digits=String(Math.floor(value));
    const n69=(digits.match(/69/g)||[]).length,n420=(digits.match(/420/g)||[]).length;
    return {n69,n420,total:n69+n420,mask:(n69?1:0)|(n420?2:0)};
  }
  function inspect(stats){
    const rows=order.map(stat=>({stat,value:stats?.[stat],matches:count(stats?.[stat])}));
    if(rows.some(r=>!r.matches))return null;
    const n69=rows.reduce((a,r)=>a+r.matches.n69,0),n420=rows.reduce((a,r)=>a+r.matches.n420,0);
    return {rows,n69,n420,total:n69+n420,met:n69+n420>=5&&n69>0&&n420>0};
  }
  function solve({stats,happy,gym,multipliers,maxTrains=limit},gain){
    const current=inspect(stats);
    if(!current)return {status:"unavailable",reason:"All four base stats are required at reliable numeric precision."};
    const zero=current.rows.map(r=>({...r,after:r.value,trains:0,energy:0}));
    if(current.met)return {status:"met",rows:zero,trains:0,energy:0,result:current};
    const cost=gym?.energy;
    if(!Number.isSafeInteger(cost)||cost<1||cost>1000||!valid(happy)||happy>99999||typeof gain!=="function"||!Number.isInteger(maxTrains)||maxTrains<0||maxTrains>limit||order.some(s=>!valid(gym[s])||!valid(multipliers?.[s])))return {status:"unavailable",reason:"Active gym, Happiness and gain modifiers are required."};
    // DP state = total previous trains + count capped at five + presence
    // of each pattern. Past Happiness depends only on total Energy used.
    // For each stat and starting offset, simulate every reachable endpoint
    // once; combine only exact simulated endpoints, including zero trains.
    let states=new Map([[0,{used:0,total:0,mask:0,rows:[]}]]);
    for(const stat of order){
      const next=new Map(),ends=new Map();
      for(const prev of states.values()){
        let candidates=ends.get(prev.used);
        if(!candidates){
          candidates=[];let value=stats[stat],h=Math.max(0,happy-prev.used*cost*0.5);
          for(let n=0;n<=maxTrains-prev.used;n++){
            const matches=count(value);if(!matches)break;
            candidates.push({stat,value:stats[stat],after:value,trains:n,energy:n*cost,matches});
            if(n===maxTrains-prev.used||gym[stat]<=0||multipliers[stat]<=0)break;
            const delta=gain(value,h,gym[stat],cost,multipliers[stat],stat),after=value+delta;
            if(!valid(delta)||delta<=0||!valid(after)||after<=value)break;
            value=after;h=Math.max(0,h-cost*0.5);
          }
          ends.set(prev.used,candidates);
        }
        for(const row of candidates){
          const used=prev.used+row.trains,total=Math.min(5,prev.total+row.matches.total),mask=prev.mask|row.matches.mask;
          const key=used*24+total*4+mask;
          if(!next.has(key))next.set(key,{used,total,mask,rows:[...prev.rows,row]});
        }
      }
      states=next;
    }
    let best=null;
    for(const s of states.values())if(s.total===5&&s.mask===3&&(!best||s.used<best.used))best=s;
    if(!best)return {status:"not-found",maxTrains,energyLimit:maxTrains*cost,current};
    const result=inspect(Object.fromEntries(best.rows.map(r=>[r.stat,r.after])));
    return {status:"plan",rows:best.rows,trains:best.used,energy:best.used*cost,result,maxTrains,finalHappy:Math.max(0,happy-best.used*cost*0.5)};
  }
  // Each route starts independently from the same live stat and Happiness.
  // Retain the nearest hit for each pattern and the nearest net improvement
  // separately; a preserved existing match is not new merit progress.
  function opportunities({stats,happy,gyms,multipliers,maxTrains=limit,energy=null},gain){
    const current=inspect(stats);
    if(!current||!valid(happy)||happy>99999||!Array.isArray(gyms)||typeof gain!=="function"||!Number.isSafeInteger(maxTrains)||maxTrains<1||maxTrains>limit||order.some(s=>!valid(multipliers?.[s])))return {status:"unavailable",rows:[],checked:0};
    const rows=[],seen=new Set(),next=new Map();let checked=0;
    // The display is a separate projection, not the alert's priority list.
    // "Next" means the nearest strictly higher whole-number stat with
    // either pattern, regardless of which gym, pattern or merit progress.
    const compareNext=(a,b)=>Math.floor(a.after)-Math.floor(b.after)||a.energy-b.energy||a.trains-b.trains||Number(b.active)-Number(a.active)||a.gymName.localeCompare(b.gymName)||a.gymId.localeCompare(b.gymId);
    for(const gym of gyms){
      const id=String(gym?.id??gym?.name??""),cost=gym?.energy;
      if(!id||seen.has(id)||!Number.isSafeInteger(cost)||cost<1||cost>1000)continue;
      seen.add(id);
      for(const stat of order){
        if(!valid(gym[stat])||gym[stat]<=0||multipliers[stat]<=0)continue;
        checked++;
        const before=count(stats[stat]),hits=new Map(),improvements=new Map();
        let value=stats[stat],h=happy;
        for(let n=1;n<=maxTrains;n++){
          const delta=gain(value,h,gym[stat],cost,multipliers[stat],stat),after=value+delta;
          if(!valid(delta)||delta<=0||!valid(after)||after<=value)break;
          value=after;h=Math.max(0,h-cost*.5);
          const matches=count(value);
          const n69=current.n69-before.n69+matches.n69,n420=current.n420-before.n420+matches.n420,total=n69+n420;
          const met=total>=5&&n69>0&&n420>0;
          const improved=total>current.total||(current.n69===0&&n69>0)||(current.n420===0&&n420>0);
          const row={stat,gymId:id,gymName:String(gym.name??id),reference:!!gym.offline,trains:n,energy:n*cost,after:value,matches,n69,n420,total,met,improved,affordable:valid(energy)?n*cost<=energy:null,active:!!gym.active};
          if(matches.total&&Math.floor(after)>Math.floor(stats[stat])){
            const prior=next.get(stat);
            if(!prior||compareNext(row,prior)<0)next.set(stat,row);
          }
          for(const [pattern,field] of [["69","n69"],["420","n420"]]){
            if(!matches[field])continue;
            if(!hits.has(pattern))hits.set(pattern,{...row,pattern});
            if(improved&&!improvements.has(pattern))improvements.set(pattern,{...row,pattern});
          }
          if(hits.size===2&&improvements.size===2)break;
        }
        for(const [pattern,hit] of hits){
          rows.push(hit);
          const improved=improvements.get(pattern);
          if(improved&&improved.trains!==hit.trains)rows.push(improved);
        }
      }
    }
    rows.sort((a,b)=>Number(b.met)-Number(a.met)||Number(b.improved)-Number(a.improved)||a.energy-b.energy||a.trains-b.trains||order.indexOf(a.stat)-order.indexOf(b.stat)||a.gymName.localeCompare(b.gymName)||a.pattern.localeCompare(b.pattern));
    return {status:"ready",rows,nextByStat:order.map(stat=>({stat,hit:next.get(stat)??null})),checked,gyms:seen.size,maxTrains,current};
  }
  return Object.freeze({order,limit,count,inspect,solve,opportunities});
})();
