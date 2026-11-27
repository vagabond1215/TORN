"use strict";
// Synthetic isolated database; never open or delete the actual user's archive.
(async()=>{
  const status=document.getElementById("result"),name="torn-log-archive-fixture:"+crypto.randomUUID();
  const now=Date.UTC(2026,10,27),yes=()=>true,no=()=>false;
  const row=(id,at=now,quantity=1)=>({id,timestamp:at/1000,details:{id:123,category:"Fixture",title:"Event"},data:{quantity},params:{}});
  const page=(rows,cursor=null)=>({log:rows,_metadata:{links:{prev:cursor===null?null:"not-followed",next:null},...(cursor===null?{}:{nanostamp:cursor})}});
  const assert=(condition,message)=>{if(!condition)throw Error(message);};
  const rejects=async(fn,message)=>{let rejected=false;try{await fn();}catch{rejected=true;}assert(rejected,message);};
  const open=()=>tornLogArchive.open({name});
  let a,b;
  try{
    a=await open();b=await open();
    const first=await a.begin(1,yes,now);
    assert((await a.state(1,yes)).count===0,"initial count");
    const initial=await a.commit(first,page([row("a"),row("b")],"100"),yes,now);
    assert(initial.status==="committed"&&initial.inserted===2,"initial commit");
    assert((await b.commit(first,page([row("a")],"100"),yes,now)).status==="stale","competing ticket");
    let p=await b.readPage(1,yes,{limit:1});
    assert(p.records[0].sourceId==="b"&&p.after.id==="b","same-second ordering");
    p=await b.readPage(1,yes,{after:p.after,limit:1});
    assert(p.records[0].sourceId==="a"&&p.after===null,"exclusive page");
    assert((await b.readPage(2,yes)).records.length===0,"owner isolation");
    const foreign=await b.begin(2,yes,now);
    await b.commit(foreign,page([row("a")]),yes,now);
    const next=await a.begin(1,yes,now+60000);
    a.close();a=await open();
    assert((await a.state(1,yes)).checkpoint.older==="100","reload checkpoint");
    const result=await a.commit(next,page([row("b"),row("c",now-1000)],"99"),yes,now+60000);
    assert(result.inserted===1&&result.duplicates===1&&result.state.count===3,"deduplication");
    const old=await a.begin(1,yes,now+120000);
    await b.invalidate(1,yes);
    assert((await a.commit(old,page([row("d",now-2000)],"98"),yes,now+120000)).status==="stale","pause generation");
    const conflictTicket=await a.begin(1,yes,now+120000);
    const conflict=await b.commit(conflictTicket,page([row("c",now-1000,2),row("d",now-2000)],"98"),yes,now+120000);
    assert(conflict.status==="conflict","conflict status");
    assert((await a.state(1,yes)).count===3&&(await a.state(1,yes)).checkpoint.older==="99","conflict atomicity");
    assert(await a.begin(1,yes,now+180000)===null,"conflict hold");
    const stale=conflictTicket;
    await a.purge(1,yes);
    assert((await b.state(1,yes)).count===0&&(await b.state(2,yes)).count===1,"partition purge");
    assert((await b.commit(stale,page([row("d")]),yes,now+180000)).status==="stale","purge resurrection prevention");
    await rejects(()=>a.state(1,no),"denied read");
    const ticket=await a.begin(1,yes,now+180000);
    let checks=0;
    await rejects(()=>a.commit(ticket,page([row("e"),row("f")],"90"),()=>++checks<5,now+180000),"authorization interruption");
    assert((await a.state(1,yes)).count===0,"interrupted write rollback");
    const pending=a.commit(ticket,page([row("e")],"90"),yes,now+180000);
    a.abortPending();
    await rejects(()=>pending,"explicit abort");
    assert((await a.state(1,yes)).count===0,"explicit abort rollback");
    assert((await a.commit(ticket,page([row("e")],"90"),yes,now+180000)).status==="committed","retry after abort");
    // Simulate a reached bound with a synthetic checkpoint, not 20k real records.
    a.close();b.close();a=b=null;
    await new Promise((resolve,reject)=>{
      const q=indexedDB.open(name,1);q.onerror=()=>reject(q.error);
      q.onsuccess=()=>{const db=q.result,tx=db.transaction("sync","readwrite"),store=tx.objectStore("sync"),get=store.get(["1","api-log"]);
        get.onsuccess=()=>store.put({...get.result,count:tornLogArchive.MAX_RECORDS});
        tx.oncomplete=()=>{db.close();resolve();};tx.onabort=()=>{db.close();reject(tx.error);};};
    });
    a=await open();const capped=await a.begin(1,yes,now+240000);
    assert((await a.commit(capped,page([row("g",now-1000)],"89"),yes,now+240000)).status==="limit","retention hold");
    assert((await a.state(1,yes)).checkpoint.older==="90","limit does not advance");
    a.close();a=null;
    status.textContent="PASS: native IndexedDB page/checkpoint transactions, competing connections, reload, account isolation, deduplication, conflict, purge, abort and retention.";
    status.dataset.result="pass";
  }catch(error){status.textContent="FAIL: "+error.message;status.dataset.result="fail";console.error(error);}
  finally{a?.close();b?.close();indexedDB.deleteDatabase(name);}
})();
