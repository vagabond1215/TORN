"use strict";
// Real IndexedDB and same-origin Web Locks; mock own-account API, clock
// and visibility. Two independent connections, not two actual browser tabs.
// Unique synthetic database and lock names; never use the production archive.
(async()=>{
  const output=document.getElementById("result"),name="torn-log-collector-fixture:"+crypto.randomUUID();
  const now=Date.UTC(2026,10,27),yes=()=>true;
  const assert=(v,m)=>{if(!v)throw Error(m);};
  const wait=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
  const reached=signal=>Promise.race([signal.promise,new Promise((_,reject)=>setTimeout(()=>reject(Error("Expected request did not reach fixture boundary")),5000))]);
  const row=(id,at=now,q=1)=>({id,timestamp:at/1000,details:{id:123,category:"Fixture",title:"Event"},data:{quantity:q},params:{}});
  const page=(rows,cursor=null)=>({log:rows,_metadata:{links:{prev:cursor===null?null:"not-followed",next:null},...(cursor===null?{}:{nanostamp:cursor})}});
  let epoch=1,verified=false,visible=true,time=now,requests=0,lastAttempt=null,next=page([row("a"),row("b")],"100"),hold=null,entered=null,cancels=0;
  const opened=()=>tornLogArchive.open({name});
  const api={
    idleLogSession:()=>{const old=epoch,valid=()=>old===epoch;return {playerId:"1",isCurrent:valid,isVerified:()=>valid()&&verified};},
    cancelIdleLog:()=>{cancels++;},
    idleLogPage:async(cursor,options)=>navigator.locks.request(name+":idle",{ifAvailable:true},async lock=>{
      if(!lock||!options.isCurrent()||lastAttempt!==null&&time-lastAttempt<60000)return {status:"busy"};
      lastAttempt=time;requests++;
      if(options.verifyOnly){verified=true;return {status:"verified"};}
      if(hold){entered.resolve();await hold.promise;}
      return {status:"ok",payload:next};
    })
  };
  const messages=[],make=()=>tornLogCollector.create({api,openArchive:opened,visible:()=>visible,clock:()=>time,onStatus:m=>messages.push(m)});
  const a=make(),b=make();let inspector;
  try{
    assert(!!navigator.locks?.request,"Web Locks unavailable");
    assert(a.start().status==="verification-required","cached identity requires verification");
    assert((await a.tick()).status==="verified-start-required"&&!a.active(),"explicit start after verification");
    time+=60000;a.start();b.start();
    const results=await Promise.all([a.tick(),b.tick()]);
    assert(results.some(x=>x.status==="saved")&&results.some(x=>x.status==="busy"),"one shared idle slot");
    inspector=await opened();
    assert((await inspector.state(1,yes)).count===2,"committed record count");
    assert(requests===2,"only verification and one page");
    time+=60000;next=page([row("c",now-1000)],"99");
    hold=wait();entered=wait();const pending=a.tick();await reached(entered);
    assert((await b.purge(true)).status==="purged","explicit purge");
    hold.resolve();hold=null;
    assert((await pending).status==="archive-changed"&&!a.active(),"purge invalidates other collector");
    assert((await inspector.state(1,yes)).count===0,"late response cannot resurrect");
    time+=60000;next=page([row("d")],"98");a.start();
    hold=wait();entered=wait();const hidden=a.tick();await reached(entered);
    visible=false;a.lifecycle();visible=true;hold.resolve();hold=null;
    assert((await hidden).status==="cancelled"&&cancels>0,"visibility lifecycle cancellation");
    assert((await inspector.state(1,yes)).count===0,"hidden page not committed");
    time+=60000;next=page([row("e")],"97");
    assert((await a.tick()).status==="saved","resume visible");
    epoch++;a.lifecycle();
    assert(!a.active(),"same-player epoch change stops collector");
    a.start();time+=60000;next=page([row("newer",now+1000)],"96");
    assert((await a.tick()).status==="invalid","out-of-order older page stops");
    const invalid=await inspector.state(1,yes);
    assert(invalid.count===1&&invalid.checkpoint.older==="97"&&!!invalid.blocked,"invalid continuation never advances");
    assert(!a.active()&&messages.every(x=>!Object.hasOwn(x,"payload")),"fixed status and no raw data");
    const data=await inspector.readPage(1,yes);
    assert(data.records.length===1&&data.records[0].sourceId==="e","bounded archive read");
    output.textContent="PASS: synthetic API + real IndexedDB/Web Locks, competing collectors, purge, visibility, connection epoch and invalid continuation.";
    output.dataset.result="pass";
  }catch(error){output.textContent="FAIL: "+error.message;output.dataset.result="fail";console.error(error);}
  finally{hold?.resolve();a.stop();b.stop();inspector?.close();indexedDB.deleteDatabase(name);}
})();
