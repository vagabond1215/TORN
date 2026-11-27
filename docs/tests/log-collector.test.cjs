"use strict";
const assert=require("node:assert/strict"),collector=require("../log-collector.js");
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
async function regression(){
  let now=Date.UTC(2026,10,27),epoch=1,id="1",verified=false,visible=true,opens=0,commits=0,cancels=0,requests=[],status=[],nextResponse={status:"ok",payload:{fixture:true}},generation=0,revision=0,count=0,gap=null,blocked=null,commitStatus=null;
  let holdOpen=null,holdNetwork=null,holdCommit=null;
  const lease=()=>{const oldEpoch=epoch,oldId=id;const isCurrent=()=>epoch===oldEpoch&&id===oldId;return {playerId:oldId,isCurrent,isVerified:()=>isCurrent()&&verified};};
  const api={idleLogSession:lease,cancelIdleLog:()=>{cancels++;},idleLogPage:async(cursor,options)=>{
    requests.push({cursor,verifyOnly:options.verifyOnly});
    if(!options.isCurrent())return {status:"changed"};
    if(options.verifyOnly){verified=true;return {status:"verified"};}
    if(holdNetwork)await holdNetwork.promise;
    return nextResponse;
  }};
  const getState=()=>({generation,count,blocked,checkpoint:{revision,gap}});
  const openArchive=async()=>{opens++;if(holdOpen)await holdOpen.promise;let closed=false;
    const check=g=>{if(closed||!g())throw Error("denied");};
    return {
      state:async(p,g)=>{check(g);assert.equal(p,id);return getState();},
      begin:async(p,g,at)=>{check(g);return {generation,playerId:p,task:{cursor:revision?"123":null,requestedAt:at,revision}};},
      commit:async(t,p,g)=>{check(g);commits++;if(holdCommit)await holdCommit.promise;check(g);if(commitStatus)return {status:commitStatus};
        if(t.generation!==generation||t.task.revision!==revision)return {status:"stale"};
        revision++;count++;return {status:"committed",inserted:1,duplicates:0,state:getState()};},
      invalidate:async(p,g)=>{check(g);generation++;return getState();},
      purge:async(p,g)=>{check(g);generation++;revision=0;count=0;return getState();},
      abortPending:()=>{},close:()=>{closed=true;}
    };
  };
  const c=collector.create({api,openArchive,visible:()=>visible,clock:()=>now,onStatus:s=>status.push(s)});
  assert.equal(c.start().status,"verification-required");
  assert.equal((await c.tick()).status,"verified-start-required");
  assert.equal(opens,0);assert.equal(commits,0);assert.equal(c.active(),false);
  assert.equal(requests[0].verifyOnly,true);
  verified=false;c.start();verified=true;
  assert.equal((await c.tick()).status,"verified-start-required");assert.equal(opens,0);
  assert.equal(c.start().status,"ready");
  assert.equal((await c.tick()).status,"saved");assert.equal(count,1);assert.equal(requests.at(-1).cursor,null);
  assert.equal((await c.tick()).status,"idle");
  now+=10000;nextResponse={status:"busy"};
  assert.equal((await c.tick()).status,"busy");assert.equal(commits,1);
  now+=10000;nextResponse={status:"ok",payload:{}};
  holdNetwork=deferred();const pending=c.tick();for(let i=0;i<4;i++)await Promise.resolve();
  visible=false;c.lifecycle();visible=true;holdNetwork.resolve();holdNetwork=null;
  assert.equal((await pending).status,"cancelled");assert.equal(commits,1);assert.ok(cancels>0);
  now+=10000;generation++;
  assert.equal((await c.tick()).status,"archive-changed");assert.equal(c.active(),false);
  c.start();now+=10000;commitStatus="invalid";
  assert.equal((await c.tick()).status,"invalid");assert.equal(c.active(),false);
  commitStatus=null;c.start();holdOpen=deferred();const opening=c.tick();
  epoch++;holdOpen.resolve();holdOpen=null;
  assert.equal((await opening).status,"cancelled");c.lifecycle();assert.equal(c.active(),false);
  c.start();now+=10000;holdCommit=deferred();const saving=c.tick();
  for(let i=0;i<8;i++)await Promise.resolve();
  const before=count;const paused=c.pause();holdCommit.resolve();holdCommit=null;
  assert.equal((await saving).status,"cancelled");assert.equal((await paused).status,"paused");assert.equal(count,before);
  assert.equal(c.active(),false);
  assert.equal((await c.purge(false)).status,"not-authorized");
  assert.equal((await c.purge(true)).status,"purged");assert.equal(count,0);
  verified=false;
  const oldOpens=opens;assert.equal((await c.purge(true)).status,"verification-required");assert.equal(opens,oldOpens);
  verified=true;c.start();now+=10000;blocked="test";
  assert.equal((await c.tick()).status,"review-required");assert.equal(c.active(),false);blocked=null;
  c.start();now+=10000;commitStatus="stale";
  assert.equal((await c.tick()).status,"competing-commit");assert.equal(c.active(),true);c.stop();
  assert.ok(status.every(x=>!Object.hasOwn(x,"payload")));
  console.log("Isolated collector verification-only, explicit start, visibility cancellation, epoch/generation changes, pause/purge and competing commits passed.");
}
module.exports=regression;
if(require.main===module)regression().catch(error=>{console.error(error);process.exitCode=1;});
