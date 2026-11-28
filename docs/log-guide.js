"use strict";
// Unified chronological view; source stores, permissions and identities remain separate.
const tornLogGuide=(()=>{
 const cap=2000,pageSize=50,source="https://www.torn.com/page.php?sid=log";
 const esc=x=>String(x??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
 const owner=()=>tornGuideApi.isConnected()?Number(tornGuideApi.state.identity?.id)||null:null;
 let packet=null,query="",day="",page=0,priorOwner=null,requestedAt=null;
 let archive=null,enabled=false,workerBusy=false,generation=0,nextCheck=0,workerStatus="Paused";
 const newArchive=()=>({rows:[],older:null,headAt:0,catchup:null,initial:false,exhausted:false,warning:""});
 // Only the documented record ID, time, category/title and bounded selected
 // data are retained. Never retain params, response links or credentials.
 function decodeApiPage(payload,now=Date.now()){
   if(!Array.isArray(payload?.log)||payload.log.length>100)throw Error("Unexpected log response");
   const rows=payload.log.map(x=>{
     const at=x?.timestamp*1000,details=x?.details;
     if(typeof x?.id!=="string"||!x.id||x.id.length>200||!Number.isSafeInteger(at)||at<Date.UTC(2004,0,1)||at>now+300000||
       typeof details?.title!=="string"||!details.title.trim()||details.title.length>300||typeof details.category!=="string"||details.category.length>150)throw Error("Invalid log record");
     const fields=Object.entries(x.data??{}).filter(([k,v])=>/^(item|item_id|item_name|quantity|amount|cost|price|money|energy|nerve|happy|happiness|stat|gym|points|drug|booster|medical|duration)$/i.test(k)&&(typeof v==="number"&&Number.isFinite(v)||typeof v==="string"&&v.length<=120&&!/api.?key|password|token|secret|cookie|authorization/i.test(v))).map(([k,v])=>k+": "+v);
     return {id:x.id,at,text:(details.category+" · "+details.title+(fields.length?" · "+fields.join(", "):"")).slice(0,1200)};
   });
   const raw=payload?._metadata?.nanostamp;
   const cursor=typeof raw==="string"&&/^\d{1,30}$/.test(raw)?raw:null;
   return {rows,cursor};
 }
 function mergeApiRows(old,added){
   const map=new Map(old.map(x=>[x.id,x]));for(const row of added)map.set(row.id,row);
   return [...map.values()].sort((a,b)=>b.at-a.at||a.id.localeCompare(b.id)).slice(0,cap);
 }
 // Newest-page refresh takes priority every five minutes. If no overlap
 // is found, continue exact-cursor catchup before historical backfill.
 function nextApiTask(a,now){
   if(!a.initial||!a.catchup&&now-a.headAt>=300000)return {kind:"head",cursor:null};
   if(a.catchup)return {kind:"catchup",cursor:a.catchup};
   if(!a.exhausted&&a.older&&a.rows.length<cap)return {kind:"older",cursor:a.older};
   return null;
 }
 function applyApiPage(a,task,p,now){
   const oldIds=new Set(a.rows.map(x=>x.id)),overlap=p.rows.some(x=>oldIds.has(x.id));
   const cursor=p.cursor&&p.cursor!==task.cursor?p.cursor:null;
   const next={...a,rows:mergeApiRows(a.rows,p.rows)};
   if(task.kind==="head"){
     next.headAt=now;next.initial=true;
     if(!a.initial){next.older=cursor;next.exhausted=!cursor||!p.rows.length;}
     else next.catchup=!overlap&&p.rows.length?cursor:null;
   }else if(task.kind==="catchup")next.catchup=!overlap&&p.rows.length?cursor:null;
   else {next.older=cursor;next.exhausted=!cursor||!p.rows.length;}
   if(p.rows.length===100&&!cursor&&!overlap)next.warning="Pagination cursor unavailable; archive coverage may be incomplete.";
   return next;
 }
 function tick(now=Date.now()){
   const id=ensureOwner();
   if(!id||!enabled||workerBusy||now<nextCheck||document.visibilityState!=="visible")return;
   const task=nextApiTask(archive,now);if(!task)return;
   nextCheck=now+10000;workerBusy=true;
   const token=generation;
   Promise.resolve(tornGuideApi.idleLogPage(task.cursor)).then(result=>{
     if(token!==generation||id!==ensureOwner()||!enabled)return;
     if(result.status==="ok"){
       archive=applyApiPage(archive,task,decodeApiPage(result.payload),Date.now());
       workerStatus=archive.rows.length>=cap?"Archive cap reached; checking for new entries":archive.exhausted?"Available history reached; checking for new entries":"Collecting history during idle time";
     }else if(result.status==="stopped"||result.status==="changed"||result.status==="disconnected"){
       enabled=false;workerStatus=result.reason??"Account changed; enable again.";
     }else if(result.status==="backoff")workerStatus=result.reason;
     else if(result.status==="verified")workerStatus="Account verified; waiting for next idle request";
     else return;
     paint();
   }).catch(()=>{if(token===generation){enabled=false;workerStatus="Unexpected response; collection paused.";paint();}}).finally(()=>{workerBusy=false;});
 }
 function ensureOwner(){
   const id=owner();if(id!==priorOwner){priorOwner=id;packet=null;archive=newArchive();enabled=false;generation++;nextCheck=0;workerStatus="Paused";query="";day="";page=0;requestedAt=null;window.dispatchEvent(new Event("torn-guide-stop-log"));}return id;
 }
 function validate(p,id,now=Date.now()){
   if(!id||p?.version!==1||p.playerId!==id||!Array.isArray(p.rows)||p.rows.length>cap)return null;
   const rows=p.rows.filter(x=>Number.isSafeInteger(x?.at)&&x.at>=Date.UTC(2004,0,1)&&x.at<=now+300000&&typeof x.text==="string"&&x.text.trim()&&x.text.length<=1200).map(x=>({at:x.at,text:x.text})).sort((a,b)=>b.at-a.at);
   const stamp=Number.isSafeInteger(p.capturedAt)&&p.capturedAt<=now+5000&&p.capturedAt>0?p.capturedAt:null;
   const count=x=>Number.isInteger(x)&&x>=0&&x<=cap?x:0;
   return {playerId:id,rows,capturedAt:stamp,matched:count(p.matched),skipped:count(p.skipped)};
 }
 // Never infer cross-source identity from timestamp/text alone.
 function unifiedRows(companion=[],api=[]){
   const key=x=>JSON.stringify([x.at,x.text.replace(/\s+/g," ").trim()]);
   const companionKeys=new Set(companion.map(key)),apiKeys=new Set(api.map(key));
   return [
     ...api.map((x,i)=>({...x,source:"api",possibleOverlap:companionKeys.has(key(x)),order:i})),
     ...companion.map((x,i)=>({...x,source:"companion",possibleOverlap:apiKeys.has(key(x)),order:i}))
   ].sort((a,b)=>b.at-a.at||(a.source===b.source?0:a.source==="api"?-1:1)||a.order-b.order).map(({order,...row})=>row);
 }
 function filterRows(rows,q="",d=""){
   const search=q.trim().toLowerCase();return rows.filter(x=>(!search||x.text.toLowerCase().includes(search))&&(!d||new Date(x.at).toISOString().slice(0,10)===d));
 }
 const time=at=>new Date(at).toISOString().slice(0,19).replace("T"," ")+" TCT";
 function request(){
   const id=ensureOwner();if(!id||location.hash!=="#log")return;requestedAt=Date.now();
   window.dispatchEvent(new CustomEvent("torn-guide-request-log",{detail:{playerId:id}}));
 }
 function content(){
   const id=ensureOwner(),companion=packet?.rows??[],api=archive?.rows??[],rows=unifiedRows(companion,api),matches=filterRows(rows,query,day),pages=Math.max(1,Math.ceil(matches.length/pageSize));page=Math.min(page,pages-1);
   const companionStatus=!id?"Connect the Torn API to verify which player's local archive may be shown.":packet?packet.capturedAt?"Captured "+time(packet.capturedAt)+" · "+packet.matched+" rows recognized in last capture"+(packet.skipped?" · "+packet.skipped+" unreadable skipped":""):"Companion connected; no log entries captured yet.":"No log archive received. Update the companion script, open your Torn Log and capture loaded entries.";
   const status=workerStatus+(archive?.warning?" · "+archive.warning:"")+(archive?.headAt?" · Latest checked "+time(archive.headAt):"");
   const format=n=>n.toLocaleString("en-US"),overlaps=matches.filter(x=>x.possibleOverlap).length;
   return '<div class="log-actions" role="group" aria-label="API log collection"><button type="button" data-log-api-toggle '+(!id?"disabled":"")+'>'+(enabled?"Pause API idle sync":"Enable API idle sync")+'</button><button type="button" data-log-api-clear '+(!id||!api.length?"disabled":"")+'>Clear API records</button></div><small class="fine-print">API sync is opt-in, up to one request per idle minute in a visible Guide tab. Full-access or authorized custom log key required. Both sources appear in one activity history. Currently, API records are held only for this session and companion records persist in the userscript manager. Each retains up to 2,000 newest entries; older entries may be discarded. Durable storage and external Log backups are not yet enabled.</small><div class="log-source-status" data-log-sync-status role="status"><p><strong>API:</strong> '+esc(status)+'</p><p><strong>Companion:</strong> '+esc(companionStatus)+'</p></div><p class="log-count">'+format(matches.length)+' matching / '+format(rows.length)+' source records <span class="log-source-counts">· API '+format(api.length)+' · Companion '+format(companion.length)+'</span></p><p class="fine-print">Sources can contain the same activity; records are not verified unique.'+(overlaps?' '+format(overlaps)+' matching rows have identical time and description across sources.':'')+'</p>'+
     (matches.length?'<div class="log-table-scroll"><table class="log-table"><thead><tr><th scope="col">Date / time (TCT)</th><th scope="col">Activity</th><th scope="col">Source</th></tr></thead><tbody>'+matches.slice(page*pageSize,(page+1)*pageSize).map(x=>'<tr><td><time datetime="'+new Date(x.at).toISOString()+'">'+esc(time(x.at).replace(" TCT",""))+'</time></td><td class="log-description">'+esc(x.text)+'</td><td class="log-row-source">'+(x.source==="api"?"API":"Companion")+(x.possibleOverlap?'<small class="log-overlap">Possible overlap</small>':'')+'</td></tr>').join("")+'</tbody></table></div>':'<p class="fine-print">No matching entries in the combined archive.</p>')+
     '<div class="log-pagination"><button type="button" data-log-page="prev" '+(page===0?"disabled":"")+'>Previous</button><small>Page '+(page+1)+' / '+pages+'</small><button type="button" data-log-page="next" '+(page+1>=pages?"disabled":"")+'>Next</button></div>';
 }
 function render(){
   ensureOwner();
   return '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Log</h1><p>Your personal Torn activity history from the official Log page and authorized Torn API, in one chronological view.</p></header><section class="panel"><div class="panel-heading"><h2>Activity archive</h2></div><div class="panel-content log-guide"><div class="log-actions"><a href="'+source+'" target="_blank" rel="noopener noreferrer">Open Torn Log</a><button type="button" data-log-sync '+(!owner()?"disabled":"")+'>Sync companion archive</button><a href="./torn-companion.user.js" target="_blank" rel="noopener noreferrer">Install / update companion</a></div><small>On Torn, use Capture loaded entries or enable Auto-capture while focused. Scroll or change filters manually to load more. Companion captures are scoped to your player and retain up to 2,000 newest entries; older entries may be discarded. No server upload. Unrecognized timestamps are skipped; identical events at the same second are matched by observed multiplicity, so history may be incomplete. Clear the archive from the Torn Log capture panel.</small><div class="log-filters"><label>Search log <input type="search" data-log-query value="'+esc(query)+'" placeholder="Xanax, gym, item, cash…"></label><label>UTC date <input type="date" data-log-date value="'+esc(day)+'"></label><button type="button" data-log-reset>Clear filters</button></div><div data-log-results>'+content()+'</div></div></section>';
 }
 function paint(){
   if(location.hash!=="#log")return;
   const view=document.getElementById("topic-view"),results=view?.querySelector("[data-log-results]");if(!results)return;results.innerHTML=content();
   const button=view.querySelector("[data-log-sync]");if(button)button.disabled=!owner();
 }
 function wire(view){
   if(view.dataset.logBound==="1")return;view.dataset.logBound="1";
   view.addEventListener("input",e=>{if(location.hash!=="#log")return;const el=e.target;if(el.matches("[data-log-query]"))query=el.value;else if(el.matches("[data-log-date]"))day=el.value;else return;page=0;paint();});
   view.addEventListener("click",e=>{
     if(location.hash!=="#log")return;
     if(e.target.closest("[data-log-api-toggle]")){
       if(!ensureOwner())return;
       enabled=!enabled;generation++;if(!enabled)tornGuideApi.cancelIdleLog();page=0;nextCheck=0;workerStatus=enabled?"Waiting for an idle API slot":"Paused";paint();if(enabled)tick();return;
     }
     if(e.target.closest("[data-log-api-clear]")){
       if(!ensureOwner()||!archive?.rows.length)return;
       enabled=false;generation++;tornGuideApi.cancelIdleLog();archive=newArchive();page=0;workerStatus="API records cleared; companion records retained";paint();return;
     }
     if(e.target.closest("[data-log-sync]")){request();return;}
     if(e.target.closest("[data-log-reset]")){query="";day="";page=0;view.querySelector("[data-log-query]").value="";view.querySelector("[data-log-date]").value="";paint();return;}
     const button=e.target.closest("[data-log-page]");if(button&&!button.disabled){page=Math.max(0,page+(button.dataset.logPage==="next"?1:-1));paint();}
   });
 }
 window.addEventListener("torn-guide-log-snapshot",e=>{
   if(location.hash!=="#log")return;
   const id=ensureOwner();if(!id||requestedAt===null)return;
   let p;try{p=typeof e.detail==="string"?JSON.parse(e.detail):e.detail;}catch{return;}
   const next=validate(p,id);if(!next)return;packet=next;paint();
 });
 window.addEventListener("torn-guide-sync",()=>{const before=priorOwner;ensureOwner();if(location.hash==="#log"&&before!==priorOwner){paint();request();}});
 window.addEventListener("focus",request);
 document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")request();});
 window.addEventListener("load",()=>{if(location.hash==="#log")setTimeout(request,1500);},{once:true});
 return {render,wire,request,validate,unifiedRows,filterRows,tick,decodeApiPage,mergeApiRows,newArchive,nextApiTask,applyApiPage};
})();
