"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const session=new Function(read("log-collector.js")+"\n"+read("log-session.js")+"\nreturn tornLogSession;")();
async function run(){
 const copy=x=>JSON.parse(JSON.stringify(x)),deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
 let state={playerId:"1",generation:0,count:0,checkpoint:{revision:0,gap:null},blocked:null},epoch=1,verified=false,visible=true,now=Date.UTC(2026,10,28),opens=0,requests=0,commits=0,hold=null,entered=null;
 const api={idleLogSession:()=>{const old=epoch;const isCurrent=()=>old===epoch;return {playerId:"1",isCurrent,isVerified:()=>isCurrent()&&verified};},cancelIdleLog:()=>{},idleLogPage:async(cursor,options)=>{requests++;if(options.verifyOnly){verified=true;return {status:"verified"};}return {status:"ok",payload:{}};}};
 const open=async()=>{opens++;if(hold){entered.resolve();await hold.promise;}let closed=false;
  const check=g=>{if(closed||!g())throw Error("denied");};
  return {state:async(p,g)=>{check(g);return copy(state);},setConsent:async(p,reviewed,enabled,g)=>{check(g);if(JSON.stringify(state)!==JSON.stringify(reviewed))return {status:"stale"};state={...state,generation:state.generation+1,consent:enabled};return {status:"committed",state:copy(state)};},
   begin:async(p,g)=>{check(g);return {playerId:p,generation:state.generation,task:{cursor:null}};},
   commit:async(ticket,p,g)=>{check(g);commits++;if(ticket.generation!==state.generation)return {status:"stale"};state={...state,count:state.count+1};return {status:"committed",state:copy(state)};},
   invalidate:async(p,g)=>{check(g);state={...state,generation:state.generation+1,consent:false};return copy(state);},
   purge:async(p,g)=>{check(g);state={...state,generation:state.generation+1,consent:false,count:0};return copy(state);},
   close:()=>{closed=true;},abortPending:()=>{}};
 };
 const make=()=>session.create({api,openArchive:open,visible:()=>visible,clock:()=>now}),a=make(),b=make();
 assert.equal((await a.inspect()).status,"verification-required");assert.equal(opens,0);
 assert.equal((await a.start(null,false)).status,"not-authorized");
 assert.equal((await a.start(null,true)).status,"verification-required");
 assert.equal((await a.tick()).status,"verified-start-required");assert.equal(opens,0);
 assert.equal((await a.start(null,true)).status,"review-required");
 const review=(await a.inspect()).state;
 assert.equal((await a.start(review,true)).status,"ready");
 assert.equal(state.consent,true);
 assert.equal((await b.start(review,true)).status,"stale");
 assert.equal((await b.pause()).status,"paused");
 assert.equal((await a.tick()).status,"archive-changed");assert.equal(commits,0);
 const next=(await a.inspect()).state;assert.equal((await a.start(next,true)).status,"ready");
 assert.equal((await a.tick()).status,"saved");assert.equal(commits,1);
 a.stop();const reloaded=make();assert.equal((await reloaded.tick()).status,"idle");assert.equal(commits,1);
 const pendingReview=(await a.inspect()).state;hold=deferred();entered=deferred();
 const pending=a.start(pendingReview,true);await entered.promise;epoch++;a.lifecycle();hold.resolve();hold=null;
 assert.equal((await pending).status,"cancelled");assert.equal(state.generation,pendingReview.generation);
 assert.equal((await b.purge(false)).status,"not-authorized");assert.equal((await b.purge(true)).status,"purged");assert.equal(state.count,0);
 visible=false;assert.equal((await a.inspect()).status,"hidden");
 console.log("Durable Log session: explicit review and opt-in, verified owner, stale starts, cross-tab pause before open, reload no auto-start, epoch cancellation and confirmed purge passed.");
}
module.exports=run;
if(require.main===module)run().catch(e=>{console.error(e);process.exitCode=1});
