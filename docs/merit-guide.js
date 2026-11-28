"use strict";
// Award catalog and completion come from Torn; the curated easy shortlist uses
// the Award wiki and community guide (not a claim of guaranteed completion).
const tornMeritGuide=(()=>{
 const easy=[
 ["Historian","Read a city chronicle","Quick","https://www.torn.com/newspaper.php"],
 ["Pocket Money","Open a city bank investment","Quick","https://www.torn.com/bank.php"],
 ["Protege","Finish Duke's introductory mission","Quick","https://www.torn.com/loader.php?sid=missions"],
 ["Worker Bee","Reach 10,000 in a working stat","Progress","#jobs"],
 ["Homing","Use focused scouting in Burglary","Quick","#crime"],
 ["Zero Liability","Recover a skimmer containing at least 250 details","Progress","#crime"],
 ["Landlord","Lease a property to another player","Coordination","https://www.torn.com/properties.php"],
 ["Energetic","Reach 1,000 energy","Cost","#stats"],
 ["10-stack","Max out one merit upgrade","Progress","https://www.torn.com/page.php?sid=honors"],
 ["Decorated","Earn 100 awards","Progress","#merits"],
 ["Seeker","Earn 250 awards","Progress","#merits"],
 ["Buffed","Acquire 50 personal perks","Progress","#education"],
 ["Web of Perks","Acquire 100 personal perks","Progress","#education"],
 ["Christmas in Torn","Log in on December 25","Seasonal","https://www.torn.com/"],
 ["Resolution","Log in on January 1","Seasonal","https://www.torn.com/"],
 ["Tornication","Log in on February 14","Seasonal","https://www.torn.com/"],
 ["Trick or Treat","Log in on October 31","Seasonal","https://www.torn.com/"],
 ["Torniversary","Log in on November 15","Seasonal","https://www.torn.com/"],
 ["The Affronted","Irritate every city job interviewer.","Coordination","#jobs"]
 ];
 const key=x=>String(x??"").toLowerCase().replace(/[^a-z0-9]/g,"");
 const arr=x=>Array.isArray(x)?x:x&&typeof x==="object"?Object.entries(x).map(([id,v])=>typeof v==="object"&&v?{id,...v}:id):[];
 function model(){
   const result=[];
   for(const [type,cat] of [["honors","honorCatalog"],["medals","medalCatalog"]]){
     const user=payload(type,type),catalog=payload(cat,type);
     const raw=Array.isArray(user)?user:user?.[type]??user?.awarded??user?.ids;
     const known=Array.isArray(raw);
     const ids=new Set((known?raw:[]).map(x=>String(typeof x==="object"?x.id??x.honor_id??x.medal_id:x)));
     for(const x of arr(catalog?.[type]??catalog)){
       if(!x?.name||x.id==null)continue;
       const category=typeof x.type==="object"?x.type?.name:x.type??x.category??type;
       if(type==="honors"&&(/^(default|defaults|default honors?)$/i.test(String(category).trim())||/\bdefault honor bar\b/i.test(String(x.description??x.requirement??""))))continue;
       const version=x.crimes_version;if(version===1||String(version)==="1")continue;
       result.push({type,id:String(x.id),name:x.name,description:x.description??x.requirement??"",category,done:known?ids.has(String(x.id)):null});
     }
   }
   return result;
 }
 function candidates(){
   const awards=model(),byName=new Map(awards.filter(x=>x.type==="honors").map(x=>[key(x.name),x]));
   return easy.map(([name,detail,effort,link])=>({name,detail,effort,link,done:byName.get(key(name))?.done??null})).filter(x=>x.done!==true);
 }
 // The rail is for actions, not a list of every unfinished checkpoint.
 // Count only independently available easy honors; do not recursively use
 // one milestone to justify another. Missing award data cannot establish
 // proximity. Counting catalog-matched earned IDs excludes default honors
 // and yields a conservative lower bound if legacy entries are missing.
 function railRecommendations(awards,shortlist,awardCount,now=Date.now()){
   const dates={"christmasintorn":"12-25",resolution:"01-01",tornication:"02-14",trickortreat:"10-31",torniversary:"11-15"};
   const today=new Date(now).toISOString().slice(5,10);
   const unearned=shortlist.filter(x=>x.done===false);
   const direct=unearned.filter(x=>["Quick","Coordination"].includes(x.effort)||x.effort==="Seasonal"&&dates[key(x.name)]===today)
     .sort((a,b)=>["Quick","Coordination","Seasonal"].indexOf(a.effort)-["Quick","Coordination","Seasonal"].indexOf(b.effort)).slice(0,8);
   const unique=new Set(direct.map(x=>key(x.name))).size;
   const checkpoints={decorated:100,seeker:250};
   const close=Number.isSafeInteger(awardCount)&&awardCount>=0?unearned.flatMap(x=>{
     const target=checkpoints[key(x.name)],gap=target-awardCount;
     return Number.isSafeInteger(target)&&gap>0&&gap<=unique?[{...x,remaining:gap}]:[];
   }):[];
   return [...direct,...close];
 }
 function recommendations(){
   const awards=model(),shortlist=candidates();
   let count=null;
   // Both user selections must be present; the complete catalog is used
   // only to establish known earned non-default awards, never to estimate.
   const idsFor=type=>{const u=payload(type,type);return Array.isArray(u)?u:u?.[type]??u?.awarded??u?.ids;};
   const verified=type=>{
     if(!Array.isArray(idsFor(type)))return false;
     if(typeof tornGuideApi==="undefined")return true;
     const s=tornGuideApi.state,at=Number(s.fetchedAt?.[type]);
     return !s.errors?.[type]&&Number.isFinite(at)&&at>0&&at<=Date.now()&&Date.now()-at<=86400000;
   };
   if(verified("honors")&&verified("medals")&&awards.some(x=>x.type==="honors")&&awards.some(x=>x.type==="medals")){
     count=new Set(awards.filter(x=>x.done===true).map(x=>x.type+":"+x.id)).size;
   }
   return railRecommendations(awards,shortlist,count);
 }
 // In-game dialogue cues, paraphrased from community walkthroughs:
 // https://www.torn.com/forums.php?f=61&p=threads&t=15925001
 // https://www.torn.com/forums.php?f=61&p=threads&t=15928011
 const affronted=[
  ["army","Army","Get hired, spend the initial job points on a promotion, leave, then reapply. If the special response is absent, check your rank first.",["Request a job.","Say you like frequently switching jobs.","Claim not to understand.","Give the vague stuff/thing reply.","Agree impatiently until dismissed."],"Interviewer rejects your lack of commitment."],
  ["grocer","Grocer","Usually accessible through the introductory conversation without taking the job. If the dialogue is absent, verify promotion requirements.",["Ask about working in the grocery job.","Ask what else you should know.","Ask about hobbies, then clarify you mean the interviewer personally.","Ask about LARP and ask for its meaning.","Mock the hobby as lame.","Ask about dressing up and the character played.","Choose both laughing responses."],"Interviewer refuses further conversation."],
  ["casino","Casino","Get hired and promoted using job points, leave, then reapply. The insulting interview option may otherwise be absent.",["Express interest in working at the casino.","Ask for further information, then request an interview.","Pick the insulting response instead of continuing the quiz.","Say goodbye; keep dismissing the interviewer until the dialogue ends."],"Interviewer tells you to leave the office."],
  ["law","Law","Use the introductory dialogue about the bar exam, career progression and pay. If the special branch is unavailable, check whether a promotion is needed.",["Ask about qualifying for the bar.","Ask how long advancement takes, then about pay.","Admit to taking the interviewer's car.","Say you sold it at the docks.","Apologize; repeat the sale admission if offered.","Choose OBJECTION, the confused reply, then OVERRULED."],"Interviewer threatens legal action and refuses to see you."],
  ["medical","Medical","Random interview prompt required. Start the interview and correctly answer the opening question. Look for the question about a patient with a knife embedded in an arm. If it never appears, finish the ordinary interview, leave and retry; promote first if needed.",["Request the job and start the quiz.","Answer the opening knowledge question correctly.","For the arm-injury scenario, select the deliberately absurd matching-other-arm answer.","Refuse to reconsider.","Claim responsibility for many hospital patients.","Choose the postcard reply, then the final agreement."],"Interviewer refuses to see you again."],
  ["education","Education","Random interview prompt required. Correctly answer the opening question, then look for the bullying scenario. Finish the ordinary interview, leave and retry if necessary; promote first if the branch is missing.",["Request a job and agree to the interview.","Answer the opening knowledge question correctly.","For the bullying scenario, select the deliberately absurd baseball-bat response.","Question why it is wrong.","Agree impatiently, then protest the dismissal."],"Interviewer warns the pupils away from you."]
 ];
 const affrontedOpen=new Map();
 function affrontedDetails(name,scope="catalog"){
   if(key(name)!=="theaffronted")return "";
   const selected=typeof tornDisclosureState!=="undefined"?tornDisclosureState.get("affronted:"+scope,affrontedOpen.get(scope)??""):affrontedOpen.get(scope)??"";
   return '<div class="affronted-details" data-affronted-scope="'+safe(scope)+'"><div class="affronted-chips" role="group" aria-label="City job interview answers">'+affronted.map(([id,label])=>'<button type="button" data-affronted-job="'+id+'" aria-expanded="'+(id===selected)+'">'+safe(label)+'</button>').join("")+'</div><div class="affronted-answer" '+(selected?"":"hidden")+'>'+affrontedAnswer(selected)+'</div></div>';
 }
 function affrontedAnswer(id){
   const row=affronted.find(x=>x[0]===id);if(!row)return "";
   const [,label,requirement,steps,success]=row;
   return '<strong>'+safe(label)+' · interview route</strong><small>'+safe(requirement)+'</small><ol>'+steps.map(step=>'<li>'+safe(step)+'</li>').join("")+'</ol><small>Confirmation: '+safe(success)+'</small><small>Complete all six while their refusal periods overlap (community reports roughly 3–4 days). Plan around your current employment. These are in-game dialogue cues, not real-world advice or automatic completion.</small><div class="affronted-links"><a href="https://www.torn.com/job.php" target="_blank" rel="noopener noreferrer">Open City jobs</a><a href="https://www.torn.com/forums.php?f=61&amp;p=threads&amp;t=15928011" target="_blank" rel="noopener noreferrer">Exact dialogue &amp; quiz answers</a><a href="https://www.torn.com/forums.php?f=61&amp;p=threads&amp;t=15925001" target="_blank" rel="noopener noreferrer">Prerequisite guide</a></div>';
 }
 function wireAffronted(view){
   if(view.dataset.affrontedBound==="1")return;view.dataset.affrontedBound="1";
   view.addEventListener("click",e=>{
     const button=e.target.closest("[data-affronted-job]"),root=button?.closest("[data-affronted-scope]");if(!root)return;
     const id=button.dataset.affrontedJob;if(!affronted.some(x=>x[0]===id))return;
     const scope=root.dataset.affrontedScope,next=button.getAttribute("aria-expanded")==="true"?"":id;
     if(typeof tornDisclosureState!=="undefined")tornDisclosureState.set("affronted:"+scope,next);
     affrontedOpen.set(scope,next);
     for(const b of root.querySelectorAll("[data-affronted-job]"))b.setAttribute("aria-expanded",String(b.dataset.affrontedJob===next));
     const panel=root.querySelector(".affronted-answer");panel.hidden=!next;panel.innerHTML=affrontedAnswer(next);
   });
 }
 let filter="all",query="",niceManual=null,niceCache=null,opportunityCache=null;
 const niceLabel={strength:"Strength",defense:"Defense",speed:"Speed",dexterity:"Dexterity"};
 const niceNum=v=>Number.isFinite(v)?Math.floor(v).toLocaleString("en-US"):"Unavailable";
 const niceExact=v=>Number.isFinite(v)?String(v):"";
 const niceKey=live=>JSON.stringify([live.owner,live.stamp,live.stats]);
 // Shared by the main pane and rail; cheap cached scan, no API calls.
 function niceOpportunities(awards=model(),live=tornStatPlanner.niceLiveInputs()){
   const honor=awards.find(x=>x.type==="honors"&&key(x.name)==="nice"),done=honor?.done??null,scope=niceKey(live);
   if(done===true){opportunityCache=null;return {done,status:"earned",rows:[]};}
   if(niceManual?.scope!==scope)niceManual=null;
   const stats=niceManual?.stats??live.stats,current=tornNiceMerit.inspect(stats);
   if(!current||live.reason){opportunityCache=null;return {done,status:"unavailable",rows:[],reason:live.reason??"Battle stats unavailable."};}
   const gyms=live.gyms??(live.gym?[live.gym]:[]);
   const fingerprint=JSON.stringify([scope,stats,live.happy,live.energy,gyms,live.multipliers]);
   if(opportunityCache?.fingerprint!==fingerprint)opportunityCache={fingerprint,result:tornNiceMerit.opportunities({stats,happy:live.happy,gyms,multipliers:live.multipliers,energy:live.energy},tornStatPlanner.internal.oneTrain)};
   return {...opportunityCache.result,done,unlockListKnown:live.unlockListKnown===true,unavailable:live.unavailable??0,unresolved:live.unresolved??0,energy:live.energy,manual:!!niceManual,cached:!!live.cached};
 }
 const patternText=row=>[row.matches.n69?"69 × "+row.matches.n69:"",row.matches.n420?"420 × "+row.matches.n420:""].filter(Boolean).join(" · ");
 // Shared route cache: current Energy affects affordability, not the
 // minimum-energy route or preservation decision.
 function nicePlan(awards,live,stats,current){
   if(current.met)return {status:"met",rows:current.rows.map(r=>({...r,after:r.value,trains:0,energy:0})),result:current,trains:0,energy:0};
   if(live.reason){niceCache=null;return null;}
   const gyms=live.gyms??(live.gym?[live.gym]:[]);
   const fingerprint=JSON.stringify([niceKey(live),stats,live.happy,gyms,live.multipliers]);
   if(niceCache?.fingerprint!==fingerprint){
     const plan=tornNiceMerit.solveAcrossGyms({stats,happy:live.happy,gyms,multipliers:live.multipliers},tornStatPlanner.internal.oneTrain);
     niceCache={fingerprint,plan:tornNiceMerit.preferRoute(plan,niceOpportunities(awards,live),live.happy)};
   }
   return niceCache.plan;
 }
 function niceNotice(){
   const awards=model(),honor=awards.find(x=>x.type==="honors"&&key(x.name)==="nice");
   if(honor?.done===true){niceCache=null;opportunityCache=null;return null;}
   const live=tornStatPlanner.niceLiveInputs(),scope=niceKey(live);
   if(niceManual?.scope!==scope)niceManual=null;
   const stats=niceManual?.stats??live.stats,current=tornNiceMerit.inspect(stats);
   if(!current||live.reason)return null;
   const plan=nicePlan(awards,live,stats,current);
   if(!plan?.rows)return null;
   const abbreviations={strength:"STR",defense:"DEF",speed:"SPD",dexterity:"DEX"};
   let spent=0;
   const rows=plan.rows.flatMap(r=>{
     const before=current.rows.find(x=>x.stat===r.stat),stat=abbreviations[r.stat];
     if(!r.trains){
       if(!before?.matches.total)return [];
       return [{stat,hold:true,trains:0,detail:niceLabel[r.stat]+" · HOLD "+niceNum(before.value)+" · "+patternText(before)+" · Preserve existing matches; no beneficial upgrade selected in the recommended route."}];
     }
     spent+=r.energy;
     const affordable=Number.isFinite(live.energy)?spent<=live.energy:null;
     const detail=niceLabel[r.stat]+" · "+r.gymName+" · "+r.trains+" train"+(r.trains===1?"":"s")+" · "+r.energy+" E · "+patternText(r)+" at "+niceNum(r.after)+(before?.matches.total>0?" · Upgrade: "+patternText(before)+" → "+patternText(r)+"; selected for the lower-Energy or higher-coverage route":"")+" · "+(affordable===true?"Within current Energy":affordable===false?"More Energy needed":"Energy unverified")+(spent>r.energy?" · Train earlier listed rows first":"")+(honor?.done===false?"":" · Honor status unverified")+(r.reference?" · Reference gym values":"")+" · Estimate; recheck each train.";
     return [{stat,gym:r.gymName,trains:r.trains,detail,hold:false}];
   });
   if(!rows.length)return null;
   const tag="NICE "+current.total+"/5",detail=(plan.status==="met"?"Digit requirement met; hold matched stats.":(plan.status==="plan"?"Predicted completion":plan.status==="partial"?"Partial route":"Preserve existing matches")+" · "+plan.trains+" trains · "+plan.energy+" E · "+plan.result.total+" matches predicted.")+" Train in listed order and refresh after training.";
   return {tag,detail,rows,ready:Number.isFinite(live.energy)&&plan.energy<=live.energy,met:plan.result.met,improved:plan.status==="plan"||plan.status==="partial",verified:honor?.done===false};
 }
 let niceRefreshing=false,niceRefreshMessage="",niceRefreshOwner=null;
 // Read-only live header. Keep this separate from the expensive route
 // solver, and from the calculator's theoretical settings.
 function niceHeaderModel(now=Date.now()){
   if(typeof tornGuideApi==="undefined"||!tornGuideApi.isConnected()||tornGuideApi.state.identity?.id==null)return {energy:"—",happy:"—",label:"Happiness tick",countdown:"—",connected:false,busy:false};
   const state=tornGuideApi.state,owner=String(state.identity.id);
   const inputs=tornTrainSequence.liveInputs(state,now,tornBarProjection),book=tornHappinessBook();
   const energy=inputs.energy,happy=inputs.happy;
   const amount=(bar,cap)=>bar?niceNum(bar.current)+" / "+niceNum(cap??bar.maximum):"—";
   let label="Happiness tick",countdown="—",tip="Fresh Happiness data required.";
   let happyText=amount(happy,book.active?99999:undefined);
   if(happy){
     const cap=book.active?99999:happy.maximum;
     const quarter=900000,resetAt=(Math.floor(now/quarter)+1)*quarter;
     const lastReset=Math.floor(now/quarter)*quarter;
     const over=happy.current>happy.maximum;
     // Shared bar projection intentionally retains the observed over-cap
     // value until verified; do not display it as confirmed after a reset.
     if(over&&!book.active&&!book.known){
       label="Possible reset";countdown=homeCountdown((resetAt-now)/1000);tip="Book status unavailable; over-cap Happiness may reset at the next quarter-hour.";
       if(happy.observedAt<lastReset)happyText="Refresh needed";
     }else if(over&&!book.active){
       label="Happiness reset";countdown=homeCountdown((resetAt-now)/1000);tip="Over-cap Happiness resets at the next Torn quarter-hour.";
       if(happy.observedAt<lastReset){happyText="Refresh needed";label="Reset passed";countdown="Refresh";tip="The quarter-hour reset has passed; refresh to verify current Happiness.";}
     }else if(happy.current>=cap){
       label="Happiness";countdown="FULL";tip="Happiness is at its current cap.";
     }else{
       label="Next +"+niceNum(Math.min(happy.step,cap-happy.current))+" Happy";
       countdown=Number.isFinite(happy.nextTick)?homeCountdown(happy.nextTick):"—";
       tip=(book.active?"Ignorance Is Bliss: Happiness regenerates up to 99,999 without quarter-hour resets. ":"")+(happy.estimated?"Estimated regeneration phase.":"API regeneration phase.");
     }
   }
   return {energy:amount(energy),happy:happyText,label,countdown,tip,connected:true,busy:niceRefreshing||!!state.loading,owner};
 }
 function niceHeader(done,model=niceHeaderModel()){
   const message=niceRefreshOwner===model.owner?niceRefreshMessage:"";
   return '<div class="panel-heading nice-merit-heading"><h2>Nice honor planner</h2><small class="nice-honor-status">'+(done===true?"Earned":done===false?"Not earned":"Award status unverified")+'</small><div class="nice-header-bars"><span class="nice-header-energy">Energy <strong data-nice-energy>'+safe(model.energy)+'</strong></span><span class="nice-header-happy">Happiness <strong data-nice-happy>'+safe(model.happy)+'</strong></span><span class="nice-header-timer" data-nice-timer title="'+safe(model.tip??"")+'"><span data-nice-timer-label>'+safe(model.label)+'</span> <strong data-nice-countdown>'+safe(model.countdown)+'</strong></span></div><button type="button" class="nice-refresh-button" data-nice-refresh aria-label="Refresh and recalculate Nice honor planner" title="Refresh and recalculate Nice honor planner" aria-busy="'+model.busy+'" '+(!model.connected||model.busy?"disabled":"")+'><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 7v5h-5M20 12a8 8 0 1 0-2 6"/></svg></button></div><p class="nice-refresh-status fine-print" data-nice-refresh-status role="status" '+(message?"":"hidden")+'>'+safe(message)+'</p>';
 }
 function tick(now=Date.now()){
   if(typeof document==="undefined")return;
   const head=document.querySelector(".nice-merit-heading");
   if(!head||location.hash!=="#merits")return;
   const model=niceHeaderModel(now);
   for(const [selector,value] of [["[data-nice-energy]",model.energy],["[data-nice-happy]",model.happy],["[data-nice-timer-label]",model.label],["[data-nice-countdown]",model.countdown]]){
     const el=head.querySelector(selector);if(el&&el.textContent!==value)el.textContent=value;
   }
   const timer=head.querySelector("[data-nice-timer]");if(timer)timer.title=model.tip??"";
   const button=head.querySelector("[data-nice-refresh]");if(button){button.disabled=!model.connected||model.busy;button.setAttribute("aria-busy",String(model.busy));}
   const status=head.parentElement?.querySelector("[data-nice-refresh-status]");
   if(status){const message=niceRefreshOwner===model.owner?niceRefreshMessage:"";if(status.textContent!==message)status.textContent=message;status.hidden=!message;}
 }
 async function refreshNice(view){
   if(niceRefreshing||!tornGuideApi.isConnected()||tornGuideApi.state.loading||tornGuideApi.state.identity?.id==null)return;
   const owner=String(tornGuideApi.state.identity.id);
   niceRefreshing=true;niceRefreshOwner=owner;niceRefreshMessage="Refreshing Nice planner…";tick();
   niceCache=null;opportunityCache=null;
   try{
     const result=await tornGuideApi.refresh({route:"niceRefresh",force:true});
     if(!tornGuideApi.isConnected()||String(tornGuideApi.state.identity?.id)!==owner||result?.discarded)return;
     niceRefreshMessage=result?.failures?"Some Nice inputs could not refresh. Check API diagnostics.":"Nice planner recalculated.";
   }catch(error){
     if(tornGuideApi.isConnected()&&String(tornGuideApi.state.identity?.id)===owner)niceRefreshMessage="Refresh failed: "+String(error.message??error);
   }finally{
     niceRefreshing=false;
     if(tornGuideApi.isConnected()&&String(tornGuideApi.state.identity?.id)===owner&&location.hash==="#merits"){
       // The coordinator normally redraws the route itself; update status
       // after its redraw and ensure errors also recalculate from valid inputs.
       view.innerHTML=render();if(typeof tornRightRail!=="undefined")tornRightRail.render();
       view.querySelector("[data-nice-refresh]")?.focus({preventScroll:true});
     }
     tick();
   }
 }
 function nicePanel(awards){
   const honor=awards.find(x=>x.type==="honors"&&key(x.name)==="nice"),done=honor?.done??null;
   const head='<section class="panel">'+niceHeader(done)+'<div class="panel-content nice-merit">';
   const tail='<p class="fine-print"><a href="https://www.torn.com/forums.php?p=threads&amp;t=16195359" target="_blank" rel="noopener noreferrer">Nice honor training guide</a> · <a href="https://www.torn.com/gym.php" target="_blank" rel="noopener noreferrer">Open Torn gym</a></p></div></section>';
   if(done===true){niceManual=null;niceCache=null;return head+'<p>Nice is already earned. No special training is needed.</p>'+tail;}
   const live=tornStatPlanner.niceLiveInputs(),scope=niceKey(live);
   if(niceManual?.scope!==scope)niceManual=null;
   const stats=niceManual?.stats??live.stats,current=tornNiceMerit.inspect(stats);
   const rule='<p>Collect <strong>5 digit matches</strong> across your four whole-number battle stats, including both <strong>69</strong> and <strong>420</strong>.</p>';
   if(!current){niceCache=null;return head+rule+'<p class="fine-print">'+safe(live.reason??"Battle stats unavailable.")+'</p>'+tail;}
   const plan=nicePlan(awards,live,stats,current);
   const results=plan?.rows??null;
   const table='<div class="crime-table-scroll"><table class="crime-table nice-merit-table"><thead><tr><th scope="col">Stat</th><th scope="col">Current</th><th scope="col">69 / 420 now</th><th scope="col">Gym</th><th scope="col">Trains</th><th scope="col">Energy</th><th scope="col">Predicted stop</th><th scope="col">69 / 420 at stop</th></tr></thead><tbody>'+current.rows.map((r,i)=>{
     const next=results?.[i],m=next?.matches??r.matches;
     return '<tr><th scope="row">'+niceLabel[r.stat]+'</th><td>'+niceNum(r.value)+'</td><td>'+r.matches.n69+' / '+r.matches.n420+'</td><td>'+(next?.trains?safe(next.gymName)+(next.reference?' <small>(reference)</small>':""):next||current.met?r.matches.total?"HOLD":"No training":"–")+'</td><td>'+ (next?next.trains:current.met?0:"–")+'</td><td>'+(next?next.energy:current.met?0:"–")+'</td><td>'+(next?niceNum(next.after):current.met?niceNum(r.value):"–")+'</td><td>'+(next||current.met?m.n69+" / "+m.n420:"–")+'</td></tr>';
   }).join("")+'</tbody></table></div>';
   let summary='<p><strong>Current: '+current.total+' / 5 occurrences</strong> · 69: '+current.n69+' · 420: '+current.n420+'</p>';
   if(current.met)summary+='<p><strong>Digit requirement met.</strong> Check Torn for the honor; the Guide cannot confirm the award without award data.</p>';
   else if(live.reason)summary+='<p class="fine-print">'+safe(live.reason)+'</p>';
   else if(plan?.status==="plan"||plan?.status==="partial"){
     const remaining=Number.isFinite(live.energy)?Math.max(0,plan.energy-live.energy):null;
     summary+='<p><strong>'+(plan.status==="partial"?"Suggested partial route: ":"Suggested route: ")+plan.trains+' trains · '+plan.energy.toLocaleString("en-US")+' Energy</strong> · Predicted '+plan.result.total+' / 5 (69: '+plan.result.n69+', 420: '+plan.result.n420+')'+(plan.status==="partial"?" · More matches needed": " · Requirement met")+(plan.independent?" · Single-stat alternative":"")+'</p><p class="fine-print">'+(remaining===null?"Current Energy unknown.":remaining>0?"Needs "+remaining.toLocaleString("en-US")+" more Energy. Recalculate after each training session.":"Within current Energy.")+'</p>';
   }else if(plan?.status==="not-found")summary+='<p>No progress-making combined route found within '+plan.maxTrains+' total trains across the searched gyms. Existing stat matches are preserved. Refresh after training or when Happiness changes.</p>';
   else if(plan?.reason)summary+='<p class="fine-print">'+safe(plan.reason)+'</p>';
   const assumptions=plan?.gyms&&!live.reason?'<p class="fine-print">'+plan.gyms+' gym'+(plan.gyms===1?"":"s")+' checked · Happiness '+niceNum(live.happy)+(live.unlockListKnown===true?"":" · Unlocked list unavailable; active gym only")+(live.cached?" · Cached inputs":"")+(niceManual?" · Precise stat overrides":"")+'. Train in table order; estimates include Happiness loss. Search limited to '+plan.maxTrains+' trains, not exhaustive. Check actual gains and refresh after each train.</p>':"";
   const exact='<details class="nice-merit-exact" data-collapse-key="nice-exact-values"><summary>Use precise values from your training log</summary><p class="fine-print">Optional: enter the exact decimals for all four current stats. Overrides are temporary and reset when the API stat snapshot changes.</p><form data-nice-exact class="stock-controls">'+tornNiceMerit.order.map(stat=>'<label>'+niceLabel[stat]+'<input name="'+stat+'" type="number" min="0" max="9007199254740990" step="any" required value="'+safe(niceExact(stats[stat]))+'"></label>').join("")+'<button type="submit" class="button secondary">Recalculate</button><button type="button" class="button secondary" data-nice-reset>Use API values</button></form></details>';
   return head+rule+summary+table+assumptions+exact+tail;
 }

 function render(){
   const awards=model(),shortlist=candidates(),earned=awards.filter(x=>x.done===true).length;
   const visible=awards.filter(x=>(filter==="all"||filter==="remaining"&&x.done===false||filter==="earned"&&x.done===true||filter===x.type)&&key(x.name+" "+x.description+" "+x.category).includes(key(query)));
   const list=(rows,scope)=>'<ul class="crime-recommendations rec-advice">'+rows.map(x=>'<li><div><strong>'+safe(x.name)+'</strong><small>'+safe(x.detail??x.description)+' · '+safe(x.effort??x.category)+'</small></div><small>'+ (x.done===true?"Earned":x.done===false?"Not earned":"Unverified")+'</small>'+(x.link?'<a href="'+safe(x.link)+'">View</a>':"")+affrontedDetails(x.name,scope)+'</li>').join("")+'</ul>';
   const m=payload("merits","merits");
   return '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Merits &amp; awards</h1></header>'+
    nicePanel(awards)+
    '<section class="panel"><div class="panel-heading"><h2>Easy honors</h2><a href="https://wiki.torn.com/wiki/Award" target="_blank" rel="noopener">Wiki</a></div><div class="panel-content">'+list(shortlist,"shortlist")+'<p class="fine-print">Unverified entries are not confirmed missing. <a href="https://www.torn.com/forums.php?p=threads&t=16394278" target="_blank" rel="noopener">Community easy honor guide</a></p></div></section>'+
    '<section class="panel"><div class="panel-heading"><h2>Honors &amp; medals</h2><small>'+earned+' confirmed earned / '+awards.length+' catalog entries</small></div><div class="panel-content"><div class="stock-controls"><label>Search <input data-award-search value="'+safe(query)+'"></label><label>Show <select data-award-filter>'+[["all","All"],["remaining","Not earned"],["earned","Earned"],["honors","Honors"],["medals","Medals"]].map(([id,label])=>'<option value="'+id+'" '+(filter===id?"selected":"")+'>'+label+'</option>').join("")+'</select></label></div>'+(visible.length?list(visible,"catalog"):'<p class="fine-print">No matching award data loaded.</p>')+'</div></section>'+
    '<section class="panel"><div class="panel-heading"><h2>Merit spending</h2></div><div class="panel-content"><p>Honors and medals generally each award one merit. Upgrades have ten levels; each successive level costs one more merit (55 total for a full upgrade).</p><p>Available merits: '+safe(m?.available??m?.unspent??m?.merits_available??"Unavailable")+'</p><p><a href="https://wiki.torn.com/wiki/Merit" target="_blank" rel="noopener">Merit upgrade reference</a></p></div></section>';
 }
 function wire(view){wireAffronted(view);if(view.dataset.awardsBound)return;view.dataset.awardsBound="1";
   view.addEventListener("submit",e=>{
     if(location.hash!=="#merits"||!e.target.matches("[data-nice-exact]"))return;
     e.preventDefault();const live=tornStatPlanner.niceLiveInputs();if(!live.stats)return;
     const data=new FormData(e.target),values=tornNiceMerit.order.map(s=>[s,data.get(s)]);
     if(values.some(([,v])=>typeof v!=="string"||!v.trim()))return;
     const stats=Object.fromEntries(values.map(([s,v])=>[s,Number(v)]));
     if(!tornNiceMerit.inspect(stats))return;
     niceManual={scope:niceKey(live),stats};niceCache=null;view.innerHTML=render();if(typeof tornRightRail!=="undefined")tornRightRail.render();
   });
   view.addEventListener("click",e=>{if(location.hash==="#merits"&&e.target.closest("[data-nice-refresh]")){void refreshNice(view);return;}if(location.hash==="#merits"&&e.target.closest("[data-nice-reset]")){niceManual=null;niceCache=null;view.innerHTML=render();if(typeof tornRightRail!=="undefined")tornRightRail.render();}});
   view.addEventListener("change",e=>{if(location.hash!=="#merits")return;if(e.target.matches("[data-award-filter]"))filter=e.target.value;else if(e.target.matches("[data-award-search]"))query=e.target.value;else return;view.innerHTML=render();});}
 return {render,wire,tick,recommendations,model,affrontedDetails,wireAffronted,niceOpportunities,niceNotice,niceHeaderModel,railRecommendations};
})();
