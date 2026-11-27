"use strict";
/* L2.1 isolated local store. No network, UI, consent, or ledger integration.
 * Callers must supply a synchronous verified-account/epoch/consent guard
 * and abortPending() on lifecycle changes. Browser storage is not encrypted.
 */
const tornLogArchive=(()=>{
  const records=typeof module!=="undefined"&&module.exports?require("./log-records.js"):tornLogRecords;
  const coverage=typeof module!=="undefined"&&module.exports?require("./log-coverage.js"):tornLogCoverage;
  const DB_NAME="torn-city-guide:personal-api-log",VERSION=1,SOURCE="api-log";
  const MAX_RECORDS=20000,MAX_BYTES=32*1024*1024,MAX_READ=100;
  const MIN_AT=Date.UTC(2004,0,1),MAX_AT=8640000000000000;
  const object=v=>v!==null&&typeof v==="object"&&!Array.isArray(v);
  const exact=(v,keys)=>object(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
  const int=(n,min=0,max=Number.MAX_SAFE_INTEGER)=>Number.isSafeInteger(n)&&n>=min&&n<=max;
  const time=v=>int(v,MIN_AT,MAX_AT),nullableTime=v=>v===null||time(v);
  const id=v=>typeof v==="string"&&/^[\x21-\x7e]{1,200}$/.test(v)&&!v.includes("://");
  const anchor=v=>v===null||exact(v,["id","at"])&&id(v.id)&&time(v.at);
  const cursorList=v=>Array.isArray(v)&&v.length<=coverage.MAX_CHAIN&&v.every(records.cursor)&&new Set(v).size===v.length;
  const gap=v=>v===null||typeof v==="string"&&v.length>0&&v.length<=160;
  const cpKeys=["version","playerId","revision","head","older","olderState","olderTail","olderRecent","headCheckedAt","lastPageAt","pending","gap"];
  function validCheckpoint(c,player){
    if(!exact(c,cpKeys)||c.version!==1||c.playerId!==player||!int(c.revision)||!anchor(c.head)||!anchor(c.olderTail)||!nullableTime(c.headCheckedAt)||!nullableTime(c.lastPageAt)||!cursorList(c.olderRecent)||!gap(c.gap)||!["unstarted","more","terminal","unknown"].includes(c.olderState))return false;
    if(c.olderState==="more"?(!records.cursor(c.older)||c.olderRecent.at(-1)!==c.older):c.older!==null)return false;
    if(c.revision===0)return c.head===null&&c.olderState==="unstarted"&&c.olderTail===null&&c.olderRecent.length===0&&c.headCheckedAt===null&&c.lastPageAt===null&&c.pending===null&&c.gap===null;
    if(c.olderState==="unstarted"||c.headCheckedAt===null||c.lastPageAt===null||c.headCheckedAt>c.lastPageAt)return false;
    if(c.olderState==="more"&&(!c.head||!c.olderTail))return false;
    if(c.olderTail&&(!c.head||c.olderTail.at>c.head.at))return false;
    if(c.pending===null)return true;
    const p=c.pending;
    return exact(p,["target","candidate","tail","cursor","recent","headAt"])&&[p.target,p.candidate,p.tail].every(a=>a!==null&&anchor(a))&&c.head!==null&&p.target.id===c.head.id&&p.target.at===c.head.at&&p.candidate.at>=p.tail.at&&p.tail.at>=p.target.at&&records.cursor(p.cursor)&&cursorList(p.recent)&&p.recent.at(-1)===p.cursor&&time(p.headAt)&&p.headAt>=c.headCheckedAt&&p.headAt<=c.lastPageAt;
  }
  const fresh=(player,generation=0)=>({playerId:player,source:SOURCE,version:VERSION,generation,count:0,bytes:0,checkpoint:coverage.create(player),blocked:null});
  function checked(value,player){
    if(value===undefined)return fresh(player);
    if(!exact(value,["playerId","source","version","generation","count","bytes","checkpoint","blocked"])||value.playerId!==player||value.source!==SOURCE||value.version!==VERSION||!int(value.generation)||!int(value.count,0,MAX_RECORDS)||!int(value.bytes,0,MAX_BYTES)||!validCheckpoint(value.checkpoint,player)||!gap(value.blocked))throw Error("Invalid stored archive checkpoint; review required");
    return value;
  }
  const authorized=guard=>typeof guard==="function"&&guard()===true;
  const cost=row=>2*JSON.stringify(row).length; // bounded estimate, not actual browser quota
  function open({indexedDB=globalThis.indexedDB,IDBKeyRange=globalThis.IDBKeyRange,name=DB_NAME}={}){
    if(!indexedDB||!IDBKeyRange)return Promise.reject(Error("IndexedDB unavailable"));
    return new Promise((resolve,reject)=>{
      let rejected=false;
      const req=indexedDB.open(name,VERSION);
      req.onupgradeneeded=event=>{
        const db=req.result;
        if(event.oldVersion!==0){req.transaction.abort();return;}
        const store=db.createObjectStore("records",{keyPath:["playerId","source","sourceId"]});
        store.createIndex("byTime",["playerId","source","occurredAt","sourceId"],{unique:true});
        db.createObjectStore("sync",{keyPath:["playerId","source"]});
      };
      req.onblocked=()=>{rejected=true;reject(Error("Archive upgrade blocked by another tab"));};
      req.onerror=()=>reject(req.error??Error("Archive open failed"));
      req.onsuccess=()=>{if(rejected){req.result.close();return;}resolve(connection(req.result,IDBKeyRange));};
    });
  }
  function connection(db,range){
    const pending=new Set();let closed=false;
    const abortPending=()=>{for(const tx of pending){try{tx.abort();}catch{}}};
    const close=()=>{closed=true;abortPending();db.close();};
    db.onversionchange=close;
    function run(names,mode,guard,work){
      return new Promise((resolve,reject)=>{
        if(closed||!authorized(guard)){reject(Error("Archive closed or account not authorized"));return;}
        const tx=db.transaction(names,mode);pending.add(tx);
        let result,failure;
        function check(){if(closed||!authorized(guard))throw Error("Archive authorization changed");}
        function abort(error){failure=error;try{tx.abort();}catch{}}
        const on=(request,fn=()=>{})=>{request.onsuccess=()=>{try{check();fn(request.result);}catch(error){abort(error);}};return request;};
        const done=value=>{check();result=value;};
        tx.oncomplete=()=>{pending.delete(tx);try{check();resolve(result);}catch(error){reject(error);}};
        tx.onabort=()=>{pending.delete(tx);reject(failure??tx.error??Error("Archive transaction aborted"));};
        try{check();work(tx,on,done);}catch(error){abort(error);}
      });
    }
    const key=player=>[player,SOURCE];
    const state=(playerId,guard)=>{
      const player=records.owner(playerId);
      return run(["sync"],"readonly",guard,(tx,on,done)=>on(tx.objectStore("sync").get(key(player)),v=>done(checked(v,player))));
    };
    async function begin(playerId,guard,now=Date.now()){
      if(!time(now))throw Error("Invalid archive request time");
      const s=await state(playerId,guard);
      if(!authorized(guard))throw Error("Archive authorization changed");
      const task=s.blocked?null:coverage.task(s.checkpoint,now);
      return task?{playerId:s.playerId,generation:s.generation,task}:null;
    }
    function commit(ticket,payload,guard,now=Date.now()){
      if(!exact(ticket,["playerId","generation","task"])||!int(ticket.generation)||!exact(ticket.task,["kind","cursor","revision","requestedAt"])||!["head","older","catchup"].includes(ticket.task.kind)||!int(ticket.task.revision)||!time(ticket.task.requestedAt)||(ticket.task.kind==="head"?ticket.task.cursor!==null:!records.cursor(ticket.task.cursor)))return Promise.reject(Error("Invalid archive ticket"));
      const player=records.owner(ticket.playerId),generation=ticket.generation,task={...ticket.task};
      if(!authorized(guard))return Promise.reject(Error("Archive account not authorized"));
      const page=records.decodePage(payload,player,now);
      return run(["records","sync"],"readwrite",guard,(tx,on,done)=>{
        const sync=tx.objectStore("sync"),rows=tx.objectStore("records");
        on(sync.get(key(player)),v=>{
          const s=checked(v,player);
          if(s.generation!==generation||s.blocked){done({status:"stale"});return;}
          const proposed=coverage.apply(s.checkpoint,task,page);
          if(!proposed.ok){done({status:"stale",reason:proposed.reason});return;}
          const added=[];let duplicates=0,conflict=false,remaining=page.records.length;
          const finish=()=>{
            if(conflict){
              // Preserve all original records and the unadvanced checkpoint.
              // Persist a bounded blocking status, not the conflicting payload.
              on(sync.put({...s,blocked:"Conflicting API log identity; review required"}),()=>done({status:"conflict"}));return;
            }
            const bytes=added.reduce((n,row)=>n+cost(row),0);
            if(s.count+added.length>MAX_RECORDS||s.bytes+bytes>MAX_BYTES){
              on(sync.put({...s,blocked:"Archive retention limit reached; review required"}),()=>done({status:"limit"}));return;
            }
            const next={...s,count:s.count+added.length,bytes:s.bytes+bytes,checkpoint:proposed.checkpoint};
            for(const row of added)on(rows.add(row));
            on(sync.put(next),()=>done({status:"committed",inserted:added.length,duplicates,state:next}));
          };
          if(!remaining){finish();return;}
          for(const row of page.records)on(rows.get([player,SOURCE,row.sourceId]),existing=>{
            if(existing!==undefined&&!records.validRecord(existing,player))throw Error("Invalid stored archive record; review required");
            const kind=records.classify(existing,row);
            if(kind==="insert")added.push(row);else if(kind==="duplicate")duplicates++;else conflict=true;
            if(--remaining===0)finish();
          });
        });
      });
    }
    // Invalidate outstanding tickets even without deleting history (pause).
    function invalidate(playerId,guard,purge=false){
      const player=records.owner(playerId);
      return run(purge?["records","sync"]:["sync"],"readwrite",guard,(tx,on,done)=>{
        const sync=tx.objectStore("sync");
        on(sync.get(key(player)),v=>{
          const s=checked(v,player);
          if(s.generation===Number.MAX_SAFE_INTEGER)throw Error("Archive generation exhausted");
          const next=purge?fresh(player,s.generation+1):{...s,generation:s.generation+1};
          if(purge)on(tx.objectStore("records").delete(range.bound([player,SOURCE,""],[player,SOURCE,"\uffff"])));
          on(sync.put(next),()=>done(next));
        });
      });
    }
    function readPage(playerId,guard,{limit=50,after=null}={}){
      const player=records.owner(playerId);
      if(!int(limit,1,MAX_READ)||after!==null&&(!exact(after,["at","id"])||!time(after.at)||!id(after.id)))return Promise.reject(Error("Invalid archive page request"));
      return run(["records"],"readonly",guard,(tx,on,done)=>{
        const min=[player,SOURCE,MIN_AT,""],max=after?[player,SOURCE,after.at,after.id]:[player,SOURCE,MAX_AT,"\uffff"];
        const out=[],req=tx.objectStore("records").index("byTime").openCursor(range.bound(min,max,false,after!==null),"prev");
        on(req,c=>{
          if(!c){done({records:out,after:null});return;}
          if(out.length===limit){const last=out.at(-1);done({records:out,after:{at:last.occurredAt,id:last.sourceId}});return;}
          if(!records.validRecord(c.value,player))throw Error("Invalid stored archive record; review required");
          out.push(c.value);c.continue();
        });
      });
    }
    return Object.freeze({state,begin,commit,readPage,invalidate:(p,g)=>invalidate(p,g),purge:(p,g)=>invalidate(p,g,true),abortPending,close});
  }
  return Object.freeze({open,DB_NAME,VERSION,MAX_RECORDS,MAX_BYTES,MAX_READ,validCheckpoint});
})();
if(typeof module!=="undefined"&&module.exports)module.exports=tornLogArchive;
