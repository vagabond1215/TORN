"use strict";
/* L3 isolated consent/lifecycle controller. No timers or live wiring.
 * UI must supply reviewed state from inspect(), then explicit start.
 * Persisted consent is not authority to restart after reload.
 */
const tornLogSession=(()=>{
  function create({api,openArchive,visible,clock=Date.now,onStatus=()=>{}}){
    const worker=tornLogCollector.create({api,openArchive,visible,clock,onStatus,requireConsent:true});
    let operation=null,serial=0;
    const lease=()=>api.idleLogSession();
    const verified=l=>!!l&&l.isCurrent()===true&&l.isVerified()===true;
    function lifecycle(){
      worker.lifecycle();
      if(operation&&(!verified(operation.lease)||visible()!==true)){
        serial++;operation.store?.abortPending();
      }
    }
    function stop(){
      serial++;worker.stop();operation?.store?.abortPending();
    }
    async function withStore(l,fn){
      if(operation)return {status:"busy"};
      if(!verified(l))return {status:"verification-required"};
      if(visible()!==true)return {status:"hidden"};
      const token=++serial,op={lease:l,store:null};operation=op;
      const guard=()=>token===serial&&verified(l)&&visible()===true;
      try{
        op.store=await openArchive();
        if(!guard())return {status:"cancelled"};
        const result=await fn(op.store,guard);
        if(!guard())return {status:"cancelled"};
        return result;
      }catch{return {status:guard()?"storage-error":"cancelled"};}
      finally{op.store?.close();if(operation===op)operation=null;}
    }
    async function inspect(){
      const l=lease();
      return withStore(l,async(store,guard)=>({status:"ready",state:await store.state(l.playerId,guard)}));
    }
    async function start(reviewed,approved){
      if(approved!==true)return {status:"not-authorized"};
      if(operation||worker.active())return {status:"busy"};
      const l=lease();
      if(!verified(l)){
        // Only identity verification; no DB access or persistent consent.
        return worker.start();
      }
      if(!reviewed||reviewed.playerId!==l.playerId)return {status:"review-required"};
      return withStore(l,async(store,guard)=>{
        const result=await store.setConsent(l.playerId,reviewed,true,guard);
        if(!guard())return {status:"cancelled"};
        if(result.status!=="committed")return result;
        // A fresh lease is checked by the collector. The persisted generation
        // is the reviewed start fence; pause before first tick invalidates it.
        return worker.start({generation:result.state.generation});
      });
    }
    async function pause(){
      stop();
      return worker.pause();
    }
    async function purge(approved){
      if(approved!==true)return {status:"not-authorized"};
      stop();return worker.purge(true);
    }
    return Object.freeze({inspect,start,pause,purge,stop,lifecycle,tick:()=>worker.tick(),active:()=>worker.active()});
  }
  return Object.freeze({create});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogSession;
