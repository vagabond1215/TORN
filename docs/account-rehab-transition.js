"use strict";
/* Read-only candidate for a future evidence-bound rehab transaction.
 * No API calls, writes, automatic reconciliation or cost deduction.
 * The caller must supply current, verified own-account observations.
 */
const tornRehabTransition=(()=>{
  const calendar="calendar-events",ledger="activity-spend",minute=60000;
  const exact=(v,ks)=>v!==null&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===ks.length&&ks.every(k=>Object.hasOwn(v,k));
  const integer=v=>Number.isSafeInteger(v)&&v>=0;
  const money=v=>v===null||integer(v);
  const copy=v=>JSON.parse(JSON.stringify(v));
  const fresh=(at,now,max)=>integer(at)&&at>0&&at<=now&&now-at<=max;
  const review=reason=>({status:"review",reason});
  async function prepare(local,playerId,observation,{now=Date.now(),digest}={}){
    const id=tornAccountStorage.owner(playerId);
    local=copy(local);observation=copy(observation);
    if(!Array.isArray(local.omitted)||local.omitted.length)throw Error("Incomplete account snapshot");
    await tornAccountRevisions.verify(local.manifest,local.records,id,digest?{digest}:{});
    if(!integer(now)||now>Date.now()+1000||!exact(observation,["playerId","count","cost","statsAt","profileAt","profileStatus"])||observation.playerId!==id||!integer(observation.count)||!money(observation.cost)||!fresh(observation.statsAt,now,30*minute)||!fresh(observation.profileAt,now,15*minute)||!["okay","ok"].includes(observation.profileStatus))return review("Fresh verified own-account counters and available profile required");
    const value=key=>local.records.find(x=>x.section===key)?.value??null;
    const beforeCalendar=value(calendar),beforeLedger=value(ledger);
    const rows=JSON.parse(beforeCalendar??"[]"),spend=JSON.parse(beforeLedger??"[]");
    const pending=rows.filter(x=>x.kind==="rehab"&&!Object.hasOwn(x,"completedAt")&&!x.recoveryReview&&x.rehabBaseline&&x.start<=now&&observation.statsAt>=x.start&&observation.profileAt>=x.start&&observation.statsAt>x.rehabBaseline.at&&observation.count>x.rehabBaseline.count);
    if(pending.length!==1)return review(pending.length?"Multiple reservations match the observed counter increase":"No uniquely supported pending reservation");
    const event=pending[0],base=event.rehabBaseline,delta=observation.count-base.count;
    // Cumulative totals cannot allocate several sessions to one booking.
    if(delta!==1)return review("Multiple rehabilitation sessions observed; manual allocation required");
    if(!money(base.cost)||!integer(base.count)||base.cost!==null&&observation.cost!==null&&observation.cost<base.cost)return review("Counter rollback or unsupported cost evidence");
    if(rows.some(x=>x!==event&&x.kind==="rehab"&&x.rehabBaseline&&Object.hasOwn(x,"completedAt")&&x.completedAt>=base.at&&x.rehabBaseline.count>=base.count))return review("Counter interval overlaps previously completed rehabilitation evidence");
    // Other held reservations are not eligible for automatic confirmation,
    // but overlapping evidence still makes attribution uncertain.
    if(rows.some(x=>x!==event&&x.kind==="rehab"&&!Object.hasOwn(x,"completedAt")&&x.rehabBaseline&&x.start<=observation.statsAt&&x.rehabBaseline.count<observation.count&&x.rehabBaseline.at<observation.statsAt))return review("Another reservation may share this counter evidence");
    const evidenceId="rehab-"+event.id;
    if(spend.some(x=>x.id===evidenceId))return review("Existing expenditure evidence requires reconciliation; never overwrite or charge again");
    const cost=base.cost===null||observation.cost===null?null:observation.cost-base.cost;
    if(cost!==null&&spend.length>=500)return review("Expenditure capacity reached; preserve existing records");
    const completed={...event,completedAt:now,blocking:false,end:Math.max(event.start+1,now),rehabCost:cost};
    const afterCalendar=JSON.stringify(rows.map(x=>x.id===event.id?completed:x));
    const entry=cost===null?null:{id:evidenceId,kind:"rehab",at:observation.statsAt,cost,source:"API counter delta"};
    const afterLedger=entry?JSON.stringify([...spend,entry]):beforeLedger;
    const changes=[{section:calendar,before:beforeCalendar,value:afterCalendar}];
    if(entry)changes.push({section:ledger,before:beforeLedger,value:afterLedger});
    const changedSections=new Set(changes.map(x=>x.section));
    const records=local.records.filter(x=>!changedSections.has(x.section)).concat(changes.map(({section,value})=>({section,value}))).sort((a,b)=>a.section.localeCompare(b.section));
    tornAccountStorage.validRecords(records,id);
    return {status:"candidate",playerId:id,eventId:event.id,count:delta,cost,changes,records,evidence:{...observation},requiresJournal:true,attribution:"inferred from cumulative counters; not a verified individual API log"};
  }
  return Object.freeze({prepare});
})();
