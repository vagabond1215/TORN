"use strict";
/* Isolated, version-aware recovery dispatch. NOT loaded in index.html.
 * No create/merge/restore authority, no implicit rollback, no fallback
 * to a different journal parser. Caller verifies owner/epoch and gets
 * explicit user approval; raw journal remains in memory, never DOM.
 */
const tornRecoveryDispatch=(()=>{
  const MAX=10100000;
  function create({storage=tornAccountStorage,calendar,rehab,bootstrap}={}){
    const legacy={read:storage.readJournal,recover:async(store,id,raw,mode,isCurrent,locks)=>{
      // Legacy helpers do not lock internally. New handlers do, so do not
      // acquire the same non-reentrant Web Lock twice.
      return storage.withRecoveryLock(id,locks,()=>{
        if(!isCurrent()||store.getItem(storage.journalKey(id))!==raw)throw Error("Account or recovery journal changed");
        if(mode==="finish")storage.finishJournal(store,id,raw,isCurrent);
        else storage.rollbackJournal(store,id,raw,isCurrent);
        return {status:mode==="finish"?"finalized":"rolled-back"};
      });
    }};
    function select(raw,id){
      if(typeof raw!=="string"||raw.length>MAX)throw Error("Invalid recovery journal size");
      let j;try{j=JSON.parse(raw);}catch{throw Error("Malformed recovery journal; preserve for review");}
      if(!j||typeof j!=="object"||Array.isArray(j)||j.playerId!==id)throw Error("Invalid recovery journal owner");
      const version=j.version;
      let handler;
      if(version===1||version===2)handler=legacy;
      else if([3,4,5,7].includes(version))handler=calendar;
      else if(version===6)handler=rehab;
      else if(version===8)handler=bootstrap;
      else throw Error("Unsupported recovery journal version; preserve for review");
      if(typeof handler?.read!=="function"||typeof handler?.recover!=="function")throw Error("Recovery handler unavailable; preserve journal");
      return {handler,version};
    }
    function inspect(store,playerId){
      const id=storage.owner(playerId),key=storage.journalKey(id),raw=store.getItem(key);
      if(raw===null)return null;
      const {handler,version}=select(raw,id);
      const info=handler.read(store,id);
      if(info?.raw!==raw||info.version!==version||store.getItem(key)!==raw)throw Error("Recovery journal changed; review again");
      if(!Array.isArray(info.rows)||!info.rows.length||info.rows.some(x=>typeof x.section!=="string"||!["matched","previous","missing","conflict"].includes(x.state))||info.complete!==info.rows.every(x=>x.state==="matched")||info.conflict!==info.rows.some(x=>x.state==="conflict"))throw Error("Invalid recovery status; preserve journal");
      // Explicit projection: the UI displays status/sections only, retains
      // exact raw value privately for a subsequent approval.
      return {raw,version,rows:info.rows.map(x=>({section:x.section,state:x.state})),complete:info.complete,conflict:info.conflict};
    }
    async function recover(store,playerId,raw,mode,approved,isCurrent,locks,options={}){
      const id=storage.owner(playerId);
      if(approved!==true||!["finish","rollback"].includes(mode))throw Error("Explicit recovery approval and action required");
      if(typeof isCurrent!=="function"||!isCurrent())throw Error("Verified account required for recovery");
      if(!locks?.request)throw Error("Web Locks required for version-aware recovery");
      const info=inspect(store,id);
      if(!info||info.raw!==raw||!isCurrent())throw Error("Recovery journal changed; review again");
      if(info.conflict||mode==="finish"&&!info.complete)throw Error("Conflicting or incomplete recovery journal; preserve for review");
      const {handler}=select(info.raw,id);
      // Handler verifies exact bytes, current owner, domain-specific
      // evidence and final/previous values again under its own lock.
      return handler.recover(store,id,raw,mode,isCurrent,locks,options);
    }
    return Object.freeze({inspect,recover});
  }
  return Object.freeze({create});
})();
