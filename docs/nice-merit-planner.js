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
  return Object.freeze({order,limit,count,inspect,solve});
})();
