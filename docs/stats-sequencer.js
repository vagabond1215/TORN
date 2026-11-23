"use strict";
const tornTrainSequence=(()=>{
  const names={xanax:"Xanax (+250 E)",ecstasy:"Ecstasy (double Happy)",candy:"Candy (+Happy)",dvd:"Erotic DVD (+2,500 Happy)",train:"Train available Energy",refill:"Points energy refill",wait:"Wait minutes",waitDrug:"Wait for drug cooldown",waitBooster:"Wait for booster space",autoOn:"Train regenerated energy ON",autoOff:"Train regenerated energy OFF"};
  const make=(type,qty=1,minutes=0)=>({type,qty,minutes});
  const defaults={
    natural:()=>[make("xanax"),make("candy",2),make("train"),make("refill"),make("train"),make("autoOn"),make("waitDrug"),make("xanax")],
    jump:()=>[make("train"),make("xanax",4),make("waitDrug"),make("dvd",5),make("ecstasy"),make("train"),make("refill"),make("train"),make("autoOn")]
  };
  const steps={natural:defaults.natural(),jump:defaults.jump()};
  const p={hours:32,regenMin:10,boosterCapH:24,startDrugMin:0,startBoosterMin:0,xanaxCDMin:420,ecstasyCDMin:215,resetAfterSec:600,tornClockMin:720,candyCDMultiplier:1,dvdCDMultiplier:1,candyHappy:25,dvdHappy:2500,autoWait:true,
    xanaxPrice:850000,ecstasyPrice:40000,candyPrice:850,dvdPrice:4300000,pointPrice:30000};
  const $=v=>String(v==null?"":v).replace(/[&<>"']/g,x=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]));
  const n=(v,f=0)=>v===null||v===undefined||v===""||!Number.isFinite(Number(v))?f:Number(v);
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,n(v,a)));
  const fmt=(v,d=0)=>Number(v).toLocaleString(undefined,{maximumFractionDigits:d});
  const clock=v=>{const s=Math.max(0,Math.round(v));return Math.floor(s/3600)+":"+String(Math.floor(s/60)%60).padStart(2,"0")+":"+String(s%60).padStart(2,"0");};
  let ctx=null,loadedPlayer=null;
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
  function simulate(list,overrides={}){
    const cfg={...p,...overrides},base=ctx.state.statValues[ctx.state.compareStat];
    const gym=ctx.gym,stat=ctx.state.compareStat,limit=Math.floor(cfg.hours*3600);
    const eCap=ctx.state.maxEnergy;
    const boosterLimit=cfg.boosterCapH*3600;
    const regenTime=cfg.regenMin*60;
    const gymCost=Math.max(1,Math.floor(gym.energy));
    const mult=ctx.effectsFor(stat).multiplier;
    const v={time:0,stat:base,energy:ctx.state.currentEnergy,happy:ctx.state.happy,drug:Math.round(cfg.startDrugMin*60),booster:Math.round(cfg.startBoosterMin*60),auto:false,
      costs:{xanax:0,ecstasy:0,dvd:0,candy:0,refill:0},used:0,log:[],errors:[],series:[{h:0,s:base}],days:new Set(),lostRegen:0};
    const snap=()=>({time:v.time,energy:v.energy,happy:v.happy,drug:v.drug,booster:v.booster,stat:v.stat});
    const point=()=>{const last=v.series[v.series.length-1],h=v.time/3600;if(Math.abs(last.h-h)<1e-8)last.s=v.stat;else v.series.push({h,s:v.stat});};
    function train(){
      if(v.energy<gymCost || n(gym[stat])<=0)return;
      const out=ctx.trainBlock(v.stat,v.happy,v.energy,gym,stat,mult);
      v.energy-=out.used;v.happy=out.happy;v.stat=out.stat;v.used+=out.used;
    }
    function advance(duration){
      const until=Math.min(limit,v.time+Math.max(0,Math.ceil(duration)));
      while(v.time<until){
        const eTick=(Math.floor(v.time/regenTime)+1)*regenTime;
        const first=Math.max(1,Math.round(cfg.resetAfterSec));
        const hTick=first+Math.max(0,Math.floor((v.time-first)/900)+1)*900;
        const next=Math.min(until,eTick,hTick),passed=next-v.time;
        v.time=next;v.drug=Math.max(0,v.drug-passed);v.booster=Math.max(0,v.booster-passed);
        if(next===eTick){if(v.energy<eCap)v.energy=Math.min(eCap,v.energy+5);else v.lostRegen+=5;}
        if(next===hTick){v.happy=v.happy>ctx.state.maxHappy?ctx.state.maxHappy:Math.min(ctx.state.maxHappy,v.happy+5);}
        if(v.auto)train();
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
        if(v.auto)train();
      }else{
        // The threshold is evaluated BEFORE each consumption. A final item
        // can push the cooldown over the cap; after 4 DVDs, wait one second.
        if(!waitFor(Math.max(0,v.booster-boosterLimit+1),"Booster cooldown"))return false;
        const secs=type==="dvd"?21600*cfg.dvdCDMultiplier:1800*cfg.candyCDMultiplier;
        v.booster+=Math.round(secs);
        v.happy=Math.min(99999,v.happy+(type==="dvd"?cfg.dvdHappy:cfg.candyHappy));
        v.costs[type]++;
      }
      return true;
    }
    for(let i=0;i<list.length;i++){
      if(v.errors.length)break;
      const a=list[i],start=snap(),qty=Math.floor(clamp(a.qty,1,40)),type=a.type;
      if(["xanax","ecstasy","dvd","candy"].includes(type)){
        for(let k=0;k<(type==="ecstasy"?1:qty);k++){
          if(!useItem(type))break;
        }
      }else if(type==="train")train();
      else if(type==="wait")advance(n(a.minutes)*60);
      else if(type==="waitDrug")advance(v.drug);
      else if(type==="waitBooster")advance(Math.max(0,v.booster-boosterLimit+1));
      else if(type==="autoOn"){v.auto=true;train();}
      else if(type==="autoOff")v.auto=false;
      else if(type==="refill"){
        let day=Math.floor((cfg.tornClockMin*60+v.time)/86400);
        if(v.days.has(day)){
          if(!waitFor((day+1)*86400-cfg.tornClockMin*60-v.time,"Daily points refill"))break;
          day=Math.floor((cfg.tornClockMin*60+v.time)/86400);
        }
        if(!v.days.has(day)){v.days.add(day);v.energy=eCap;v.costs.refill++;if(v.auto)train();}
      }else{v.errors.push("Unrecognized action: "+type);}
      point();
      v.log.push({i:i+1,type,start,end:snap()});
      if(v.time>=limit && i<list.length-1){v.errors.push("The "+cfg.hours+"-hour window ended before all steps.");break;}
    }
    if(v.time<limit)advance(limit-v.time);
    point();
    return {...v,final:v.stat,gain:v.stat-base,complete:v.errors.length===0,
      money:v.costs.xanax*cfg.xanaxPrice+v.costs.ecstasy*cfg.ecstasyPrice+
        v.costs.candy*cfg.candyPrice+v.costs.dvd*cfg.dvdPrice+v.costs.refill*30*cfg.pointPrice};
  }
  function controls(){
    const fields=[
      ["hours","Time window (hours)",1,168,1],["regenMin","Energy +5 every (min)",10,15,5],
      ["boosterCapH","Booster use threshold (hours)",1,72,1],
      ["startDrugMin","Starting drug CD (min)",0,20000,1],["startBoosterMin","Starting booster CD (min)",0,20000,1],
      ["xanaxCDMin","Xanax CD (360–480 min)",360,480,1],["ecstasyCDMin","Ecstasy CD (200–230 min)",200,230,1],
      ["resetAfterSec","Next Happy reset in (seconds)",1,900,1],
      ["tornClockMin","Torn minutes since midnight",0,1439,1],
      ["candyCDMultiplier","Candy CD multiplier",0.1,3,0.05],
      ["dvdCDMultiplier","eDVD CD multiplier",0.1,3,0.05],
      ["candyHappy","Happy per candy",0,10000,1],["dvdHappy","Happy per eDVD",0,10000,1],
      ["xanaxPrice","Xanax price",0,1e8,1000],["ecstasyPrice","Ecstasy price",0,1e8,1000],
      ["candyPrice","Candy price",0,1e8,100],["dvdPrice","eDVD price",0,1e8,1000],["pointPrice","Point price",0,1e8,1000]
    ];
    return '<details class="ts-settings" open><summary>Time, cooldowns, effects, prices</summary><div class="ts-settings-grid">'+fields.map(([key,label,min,max,step])=>
      '<label><span>'+$(label)+'</span><input type="number" data-ts-param="'+key+'" value="'+$(p[key])+'" min="'+min+'" max="'+max+'" step="'+step+'"></label>').join("")+
      '</div><label class="ts-switch"><input type="checkbox" data-ts-auto '+(p.autoWait?"checked":"")+'>Automatically wait when a cooldown blocks an action</label>'+
      '<button type="button" class="button secondary" data-ts-sync>Re-import live cooldowns</button>'+
      '<p class="fine-print">Candy cooldown can be shortened by Grocery Store/Restaurant company perks and some books. The consumable-cooldown book does not shorten eDVD cooldown; keep its multiplier at 1 unless you have a specific applicable perk. Starting cooldowns come from the Torn API when present.</p></details>';
  }
  function row(side,a,index){
    const types=Object.entries(names).map(([id,label])=>'<option value="'+id+'" '+(a.type===id?"selected":"")+'>'+$(label)+'</option>').join("");
    const qty=["xanax","candy","dvd"].includes(a.type);
    const wait=a.type==="wait";
    return '<div class="ts-step"><span>'+(index+1)+'</span><select data-ts-side="'+side+'" data-ts-index="'+index+'" data-ts-edit="type">'+types+'</select>'+
      (qty||wait?'<input type="number" min="'+(qty?1:0)+'" max="'+(qty?40:10080)+'" step="'+(qty?1:.01)+'" value="'+(qty?a.qty:a.minutes)+'" data-ts-side="'+side+'" data-ts-index="'+index+'" data-ts-edit="'+(qty?"qty":"minutes")+'" aria-label="'+(qty?"Quantity":"Minutes")+'">':'<span></span>')+
      '<div class="ts-arrows"><button type="button" title="Move up" data-ts-op="up" data-ts-side="'+side+'" data-ts-index="'+index+'">↑</button>'+
      '<button type="button" title="Move down" data-ts-op="down" data-ts-side="'+side+'" data-ts-index="'+index+'">↓</button>'+
      '<button type="button" title="Remove" data-ts-op="remove" data-ts-side="'+side+'" data-ts-index="'+index+'">×</button></div></div>';
  }
  function log(data){
    return '<details class="ts-log"><summary>Execution timeline ('+data.log.length+' steps)</summary><div class="ts-log-scroller"><table><thead><tr><th>Step</th><th>Time</th><th>Energy</th><th>Happy</th><th>Drug CD</th><th>Booster CD</th></tr></thead><tbody>'+
      data.log.map(a=>'<tr><td>'+$(names[a.type])+'</td><td>'+clock(a.end.time)+'</td><td>'+fmt(a.end.energy)+'</td><td>'+fmt(a.end.happy)+'</td><td>'+clock(a.end.drug)+'</td><td>'+clock(a.end.booster)+'</td></tr>').join("")+
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
      '<p class="ts-stat">Final: '+(data.complete?fmt(data.final,2):"Blocked")+' <small>+'+fmt(data.gain,2)+' gain, '+fmt(data.used)+' E, $'+fmt(data.money)+'</small></p>'+
      log(data)+'</section>';
  }
  function chart(natural,jump){
    const xval=hour=>80+hour/p.hours*800;
    const bottom=Math.min(natural.stat,natural.final,jump.final);
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
    const a=simulate(steps.natural),b=simulate(steps.jump);
    const diff=b.gain-a.gain;
    const perks=activePerks();
    return '<p class="ts-intro">Build both strategies as an ordered timeline. Drug cooldown must reach zero before the next drug. Boosters can exceed their use threshold on the last item: a fifth eDVD becomes legal after one second below 24 hours. Wait steps move the clock forward; automatic training spends regenerated energy after each tick.</p>'+
      controls()+
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
      const param=el.dataset.tsParam;
      if(param && Object.hasOwn(p,param)){p[param]=clamp(el.value,Number(el.min),Number(el.max));rebuild();return;}
      if(el.hasAttribute("data-ts-auto")){p.autoWait=el.checked;rebuild();return;}
      const edit=el.dataset.tsEdit,side=el.dataset.tsSide,index=Number(el.dataset.tsIndex);
      if(edit&&steps[side]&&steps[side][index]){
        const a=steps[side][index];
        if(edit==="type"){a.type=el.value;a.qty=1;a.minutes=0;}
        if(edit==="qty")a.qty=clamp(Math.floor(n(el.value,1)),1,40);
        if(edit==="minutes")a.minutes=clamp(el.value,0,10080);
        rebuild();
      }
    });
    view.addEventListener("click",event=>{
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
