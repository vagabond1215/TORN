"use strict";
/* Nice honor: >=5 integer-digit occurrences across the four base stats,
 * with at least one of each. Community-confirmed rule, not an award API.
 * Bounded deterministic single- and multi-gym search in fixed stat order.
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
  // Combined search: each stat gets one uninterrupted block in any reported
  // available gym, or zero trains. Earlier blocks reduce later Happiness.
  // Retain up to eight distinct cumulative Energy states per count/mask
  // bucket, favoring lower Energy and fewer trains. This is a bounded
  // heuristic, not exhaustive optimization over gym changes or stat orders.
  function solveAcrossGyms({stats,happy,gyms,multipliers,maxTrains=limit},gain){
    const current=inspect(stats);
    if(!current)return {status:"unavailable",reason:"All four base stats are required at reliable numeric precision."};
    const zero=current.rows.map(r=>({...r,after:r.value,trains:0,energy:0,gymId:null,gymName:null}));
    if(current.met)return {status:"met",rows:zero,trains:0,energy:0,result:current};
    if(!valid(happy)||happy>99999||!Array.isArray(gyms)||typeof gain!=="function"||!Number.isSafeInteger(maxTrains)||maxTrains<1||maxTrains>limit||order.some(s=>!valid(multipliers?.[s])))return {status:"unavailable",reason:"Unlocked gym data, Happiness and gain modifiers are required."};
    const seen=new Set(),available=[];
    for(const gym of gyms){
      const id=String(gym?.id??gym?.name??""),cost=gym?.energy;
      if(!id||seen.has(id)||!Number.isSafeInteger(cost)||cost<1||cost>1000||!order.some(stat=>valid(gym[stat])&&gym[stat]>0))continue;
      seen.add(id);available.push({...gym,gymId:id});
    }
    if(!available.length)return {status:"unavailable",reason:"No available unlocked gym has usable training data."};
    const width=8,cheaper=(a,b)=>a.energy-b.energy||a.trains-b.trains;
    let states=[{energy:0,trains:0,n69:0,n420:0,rows:[]}];
    for(let i=0;i<order.length;i++){
      const stat=order[i],buckets=new Map();
      // Equivalent processed pattern coverage and same cumulative Energy
      // give identical later Happiness. Fewer trains dominates at that
      // Energy. Do not spend trains solely to burn Happiness on this stat.
      const put=(prev,row)=>{
        const n69=prev.n69+row.matches.n69,n420=prev.n420+row.matches.n420,total=Math.min(5,n69+n420),mask=(n69?1:0)|(n420?2:0);
        const key=total*4+mask,energy=prev.energy+row.energy,trains=prev.trains+row.trains;
        let bucket=buckets.get(key);if(!bucket){bucket=[];buckets.set(key,bucket);}
        const same=bucket.findIndex(x=>x.energy===energy);
        if(same>=0&&bucket[same].trains<=trains)return;
        if(same<0&&bucket.length>=width&&cheaper({energy,trains},bucket[bucket.length-1])>=0)return;
        if(same>=0)bucket.splice(same,1);
        bucket.push({energy,trains,n69,n420,rows:[...prev.rows,row]});
        bucket.sort(cheaper);if(bucket.length>width)bucket.pop();
      };
      // Each offset is replayed from original stat, with no intervening
      // time, resets or artificial boosts. Cache within this stage by
      // cumulative Energy; candidates depend only on starting Happiness.
      const cache=new Map();
      for(const prev of states){
        put(prev,zero[i]);
        if(prev.trains>=maxTrains)continue;
        let endpoints=cache.get(prev.energy);
        if(!endpoints){
          endpoints=[];
          for(const gym of available){
            if(!valid(gym[stat])||gym[stat]<=0||multipliers[stat]<=0)continue;
            const cost=gym.energy;
            let value=stats[stat],h=Math.max(0,happy-prev.energy*.5);
            for(let n=1;n<=maxTrains;n++){
              const delta=gain(value,h,gym[stat],cost,multipliers[stat],stat),after=value+delta;
              if(!valid(delta)||delta<=0||!valid(after)||after<=value)break;
              value=after;h=Math.max(0,h-cost*.5);
              const matches=count(value);
              if(matches.total)endpoints.push({stat,value:stats[stat],after:value,trains:n,energy:n*cost,matches,gymId:gym.gymId,gymName:String(gym.name??gym.gymId),reference:!!gym.offline,active:!!gym.active});
            }
          }
          cache.set(prev.energy,endpoints);
        }
        for(const row of endpoints)if(prev.trains+row.trains<=maxTrains)put(prev,row);
      }
      states=[...buckets.values()].flat();
    }
    const complete=s=>s.n69+s.n420>=5&&s.n69>0&&s.n420>0;
    const quality=s=>Math.min(5,s.n69+s.n420),types=s=>Number(s.n69>0)+Number(s.n420>0);
    states.sort((a,b)=>Number(complete(b))-Number(complete(a))||(complete(a)&&complete(b)?0:quality(b)-quality(a)||types(b)-types(a))||cheaper(a,b));
    const best=states[0],result=inspect(Object.fromEntries(best.rows.map(r=>[r.stat,r.after])));
    const progress=quality(best)>Math.min(5,current.total)||types(best)>Number(current.n69>0)+Number(current.n420>0);
    // Unchanged baseline remains a valid candidate, even when the beam
    // prunes other paths. Do not offer a non-improving training expense.
    const chosen=result.met||progress?best:{energy:0,trains:0,rows:zero};
    const finalResult=chosen===best?result:current;
    return {status:finalResult.met?"plan":chosen.trains?"partial":"not-found",rows:chosen.rows,trains:chosen.trains,energy:chosen.energy,result:finalResult,maxTrains,gyms:available.length,beamWidth:width,finalHappy:Math.max(0,happy-chosen.energy*.5)};
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
  // Keep one coherent displayed route. If the bounded combined search
  // misses a better single-stat endpoint, compare independently replayed
  // opportunities against it. Never combine independently projected hits.
  function preferRoute(plan,report,happy){
    if(plan?.status==="plan"||plan?.status==="met"||report?.status!=="ready"||!report.current||!valid(happy))return plan;
    const current=report.current,zero=current.rows.map(r=>({...r,after:r.value,trains:0,energy:0,gymId:null,gymName:null}));
    const coverage=r=>Math.min(5,r.total);
    const types=r=>Number(r.n69>0)+Number(r.n420>0);
    const better=(a,b)=>Number(b.result.met)-Number(a.result.met)||coverage(b.result)-coverage(a.result)||types(b.result)-types(a.result)||a.energy-b.energy||a.trains-b.trains;
    const unchanged={status:"not-found",rows:zero,result:current,energy:0,trains:0};
    let best=plan?.result&&better(plan,unchanged)<0?plan:unchanged;
    for(const hit of report.rows){
      const i=order.indexOf(hit.stat);
      if(i<0||!Number.isSafeInteger(hit.trains)||hit.trains<1||hit.trains>(plan?.maxTrains??report.maxTrains)||!valid(hit.after)||hit.after<=zero[i].value||!Number.isSafeInteger(hit.energy)||hit.energy<1)continue;
      const rows=zero.map((row,j)=>j===i?{...hit,value:row.value,matches:count(hit.after)}:row);
      const result=inspect(Object.fromEntries(rows.map(r=>[r.stat,r.after])));
      const candidate={status:result.met?"plan":"partial",rows,result,trains:hit.trains,energy:hit.energy,gyms:report.gyms,maxTrains:plan?.maxTrains??report.maxTrains,finalHappy:Math.max(0,happy-hit.energy*.5),independent:true};
      if(better(candidate,best)<0)best=candidate;
    }
    return best===unchanged?plan:best;
  }
  return Object.freeze({order,limit,count,inspect,solve,solveAcrossGyms,opportunities,preferRoute});
})();
