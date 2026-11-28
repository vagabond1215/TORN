"use strict";
/* Synthetic fixture only. Real Web Crypto, localStorage and Web Locks.
 * Two independent storage handles, not two actual browser tabs.
 * Unique storage/lock namespace; no production account data or API keys.
 * Fault injection simulates interruption, not actual browser quota.
 */
(async()=>{
  const output=document.getElementById("result");
  const assert=(value,message)=>{if(!value)throw Error(message);};
  const equal=(a,b,message)=>assert(JSON.stringify(a)===JSON.stringify(b),message);
  const rejects=async(fn,re)=>{let err;try{await fn();}catch(e){err=e;}assert(err&&re.test(err.message),"Expected "+re+"; got "+err);};
  let namespace=null;
  try{
    assert(!!globalThis.crypto?.subtle&&!!crypto.randomUUID,"Native Web Crypto unavailable");
    assert(!!navigator.locks?.request,"Native Web Locks unavailable");
    namespace="torn-rehab-fixture:"+crypto.randomUUID()+":";
    const id="999999991",prefix="torn-city-guide:",a=tornAccountStorage,r=tornAccountRevisions,l=tornCalendarLineage,j=tornRehabJournal;
    const cal=prefix+"activity-events:"+id,ledger=prefix+"activity-spend-ledger:"+id,lineage=prefix+"calendar-lineage:v1:"+id,manifest=r.key(id),journal=a.journalKey(id),note=prefix+"v1:profile:"+id+":notes:gym";
    const names=()=>Array.from({length:localStorage.length},(_,i)=>localStorage.key(i)).filter(k=>k?.startsWith(namespace));
    const storage=()=>({get length(){return names().length;},key:i=>names()[i]?.slice(namespace.length)??null,getItem:k=>localStorage.getItem(namespace+k),setItem:(k,v)=>localStorage.setItem(namespace+k,v),removeItem:k=>localStorage.removeItem(namespace+k)});
    const locks={request:(name,opt,fn)=>navigator.locks.request(namespace+name,opt,fn)},yes=()=>true;
    const now=Date.now(),event={id:"fixture-rehab",kind:"rehab",title:"Synthetic reservation",start:now-120000,end:now+60000,blocking:true,source:"manual",rehabBaseline:{count:5,cost:100000,at:now-180000}};
    const old={id:"manual-fixture",kind:"war",at:now-100*86400000,cost:1,source:"Manual confirmation"};
    const evidence={playerId:id,count:6,cost:350000,statsAt:now-1000,profileAt:now-1000,profileStatus:"okay"};
    const review={eventId:event.id,cost:250000,evidence};
    const records=[{section:"activity-spend",value:JSON.stringify([old])},{section:"calendar-events",value:JSON.stringify([event])},{section:"notes:gym",value:"fixture"}],omitted=[];
    const local={records,omitted,manifest:await r.observe(r.empty(id),{records,omitted},id)};
    const initial=await l.initialize(local,id);
    const original={[cal]:records[1].value,[ledger]:records[0].value,[note]:"fixture",[manifest]:JSON.stringify(local.manifest),[lineage]:JSON.stringify(initial)};
    const reset=()=>{for(const k of names())localStorage.removeItem(k);const s=storage();for(const [k,v] of Object.entries(original))s.setItem(k,v);return s;};
    const apply=(s,rv=review,current=yes)=>j.apply(s,id,local,rv,()=>rv.evidence,current,locks);
    const verify=async s=>{const snap={...a.snapshot(s,id),manifest:r.read(s,id)};await r.verify(snap.manifest,snap.records,id);await l.verify(JSON.parse(s.getItem(lineage)),snap,id);};
    const s=reset(),second=storage();
    // True native lock contention in one browser context, independent
    // storage handles. Both writers start from the same reviewed bytes.
    const outcomes=await Promise.allSettled([apply(s),apply(second)]);
    assert(outcomes.filter(x=>x.status==="fulfilled"&&x.value.status==="applied").length===1,"Only one writer may apply");
    assert(outcomes.some(x=>x.status==="rejected"&&/changed/.test(x.reason.message)),"Second stale writer rejected");
    equal(JSON.parse(s.getItem(ledger)),[old,{id:"rehab-"+event.id,kind:"rehab",at:evidence.statsAt,cost:250000,source:"API counter delta"}],"Exactly one expense");
    assert(s.getItem(journal)===null,"Completed journal cleared");await verify(s);
    for(const dest of [cal,ledger,lineage,manifest]){
      const store=reset(),w=store.setItem;
      store.setItem=(k,v)=>{if(k===dest)throw Error("Injected write interruption");w(k,v);};
      await rejects(()=>apply(store),/journal retained/);
      // Reopen via independent handle; hold and rollback survive handle loss.
      const reopened=storage(),info=j.read(reopened,id);
      assert(info.version===6&&!info.complete&&!info.conflict,"Recoverable partial journal");
      await rejects(()=>j.recover(reopened,id,info.raw,"finish",yes,locks),/incomplete/);
      assert((await j.recover(reopened,id,info.raw,"rollback",yes,locks)).status==="rolled-back","Explicit rollback");
      for(const [k,v] of Object.entries(original))equal(reopened.getItem(k),v,"Exact prior bytes restored: "+k);
      assert(reopened.getItem(journal)===null,"Rollback hold cleared");await verify(reopened);
    }
    const interrupted=reset(),remove=interrupted.removeItem;
    interrupted.removeItem=k=>{if(k===journal)throw Error("Injected finalization interruption");remove(k);};
    await rejects(()=>apply(interrupted),/journal retained/);
    const reopened=storage(),done=j.read(reopened,id);
    assert(done.complete&&!done.conflict,"All destination writes verified");
    assert((await j.recover(reopened,id,done.raw,"finish",yes,locks)).status==="finalized","Explicit finish");await verify(reopened);
    const unknown=reset(),u={...review,cost:null,evidence:{...evidence,cost:null}};
    assert((await apply(unknown,u)).status==="applied","Unknown cost completion");
    equal(unknown.getItem(ledger),original[ledger],"Unknown cost must not modify expense ledger");await verify(unknown);
    output.textContent="PASS: real localStorage, Web Crypto and Web Locks; competing handles, injected write failures, rollback, finalization, and unknown cost. Not independent-tab or real quota validation.";
    output.dataset.result="pass";
  }catch(error){output.textContent="FAIL: "+error.message;output.dataset.result="fail";console.error(error);}
  finally{if(namespace!==null){for(let i=localStorage.length-1;i>=0;i--){const k=localStorage.key(i);if(k?.startsWith(namespace))localStorage.removeItem(k);}}}
})();
