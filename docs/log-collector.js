"use strict";
/* Isolated L2.2 adapter. Not loaded by the live Guide. No timer, DOM
 * listeners, new endpoint, persisted consent, or automatic fallback.
 * Future UI must select exactly one worker and wire lifecycle events.
 */
const tornLogCollector=(()=>{
  function create({api,openArchive,visible,clock=Date.now,onStatus=()=>{},requireConsent=false}){
    let session=null,running=null,maintenance=false,sequence=0,nextCheck=0;
    const visibleNow=()=>visible()===true;
    const owns=s=>session===s&&s.lease.isCurrent()===true;
    const notify=(s,status,detail={})=>{
      if(owns(s))onStatus({status,playerId:s.lease.playerId,...detail});
      return {status,...detail};
    };
    function cancel(s){
      sequence++;
      if(running?.session===s&&running.network)api.cancelIdleLog();
      s?.store?.abortPending();
    }
    function stop(s=session){
      if(!s||session!==s)return;
      session=null;cancel(s);s.store?.close();
    }
    // A cached identity may initiate verification only. Even if another
    // request verifies it before the next tick, require a new explicit start.
    function start({generation=null}={}){
      if(session||running||maintenance)return {status:"busy"};
      const lease=api.idleLogSession();
      if(!lease?.isCurrent())return {status:"disconnected"};
      if(requireConsent&&lease.isVerified()&&(!Number.isSafeInteger(generation)||generation<1))return {status:"consent-required"};
      session={lease,verificationOnly:!lease.isVerified(),store:null,generation:requireConsent?generation:null};nextCheck=0;
      return notify(session,session.verificationOnly?"verification-required":"ready");
    }
    function lifecycle(){
      if(!session)return;
      if(!owns(session)){stop();return;}
      if(!visibleNow())cancel(session);
    }
    function finish(s,status,detail={}){
      const result=notify(s,status,detail);stop(s);return result;
    }
    async function tick(){
      lifecycle();
      const s=session,at=clock();
      if(!s||running||maintenance||!visibleNow()||at<nextCheck)return {status:"idle"};
      const token=sequence,work={session:s,network:false};
      const current=()=>owns(s)&&token===sequence&&visibleNow();
      const guard=()=>current()&&s.lease.isVerified()===true;
      running=work;nextCheck=at+10000;
      try{
        if(s.verificationOnly){
          if(s.lease.isVerified())return finish(s,"verified-start-required");
          work.network=true;
          const response=await api.idleLogPage(null,{isCurrent:current,verifyOnly:true});
          work.network=false;
          if(!current())return {status:"cancelled"};
          if(response.status==="verified"&&s.lease.isVerified())return finish(s,"verified-start-required");
          if(response.status==="busy"||response.status==="backoff")return notify(s,response.status);
          return finish(s,"verification-stopped");
        }
        if(!guard())return finish(s,"verification-required");
        if(!s.store){
          const store=await openArchive();
          if(!guard()){store.close();return {status:"cancelled"};}
          s.store=store;
        }
        const state=await s.store.state(s.lease.playerId,guard);
        if(!guard())return {status:"cancelled"};
        if(s.generation===null)s.generation=state.generation;
        if(state.generation!==s.generation)return finish(s,"archive-changed");
        if(requireConsent&&state.consent!==true)return finish(s,"consent-required");
        if(state.blocked||state.checkpoint.gap)return finish(s,"review-required");
        const ticket=await s.store.begin(s.lease.playerId,guard,at);
        if(!guard())return {status:"cancelled"};
        if(!ticket)return notify(s,"waiting");
        if(ticket.generation!==s.generation)return finish(s,"archive-changed");
        work.network=true;
        const response=await api.idleLogPage(ticket.task.cursor,{isCurrent:guard,verifyOnly:false});
        work.network=false;
        if(!guard())return {status:"cancelled"};
        if(response.status==="busy"||response.status==="backoff")return notify(s,response.status);
        if(response.status!=="ok")return finish(s,"collection-stopped");
        const result=await s.store.commit(ticket,response.payload,guard,clock());
        if(!guard())return {status:"cancelled"};
        if(result.status==="committed"){
          if(result.state.generation!==s.generation)return finish(s,"archive-changed");
          const detail={count:result.state.count,inserted:result.inserted,duplicates:result.duplicates};
          if(result.state.checkpoint.gap)return finish(s,"review-required",detail);
          return notify(s,"saved",detail);
        }
        if(result.status==="stale"){
          const latest=await s.store.state(s.lease.playerId,guard);
          if(!guard())return {status:"cancelled"};
          if(latest.generation!==s.generation)return finish(s,"archive-changed");
          if(latest.blocked||latest.checkpoint.gap)return finish(s,"review-required");
          return notify(s,"competing-commit");
        }
        return finish(s,["conflict","limit","blocked","invalid"].includes(result.status)?result.status:"storage-error");
      }catch{
        if(!current())return {status:"cancelled"};
        return finish(s,"storage-or-protocol-error");
      }finally{if(running===work)running=null;}
    }
    // Explicit account-wide pause/purge invalidates tickets across tabs.
    // An unverified cached identity cannot read or mutate the archive.
    async function maintenanceAction(purge,confirmed=false){
      if(maintenance||purge&&confirmed!==true)return {status:"not-authorized"};
      const lease=session?.lease??api.idleLogSession();
      stop();
      if(!lease?.isVerified())return {status:"verification-required"};
      maintenance=true;let store;
      const guard=()=>lease.isCurrent()===true&&lease.isVerified()===true;
      try{
        store=await openArchive();
        if(!guard())return {status:"cancelled"};
        const state=await (purge?store.purge(lease.playerId,guard):store.invalidate(lease.playerId,guard));
        if(!guard())return {status:"cancelled"};
        return {status:purge?"purged":"paused",generation:state.generation};
      }catch{return {status:"maintenance-error"};}
      finally{store?.close();maintenance=false;}
    }
    return Object.freeze({start,tick,lifecycle,stop:()=>stop(),pause:()=>maintenanceAction(false),purge:confirmed=>maintenanceAction(true,confirmed),active:()=>!!session});
  }
  return Object.freeze({create});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogCollector;
