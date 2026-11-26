"use strict";
// Personal activity history from the optional companion. No API requests.
const tornLogGuide=(()=>{
 const cap=2000,pageSize=50,source="https://www.torn.com/page.php?sid=log";
 const esc=x=>String(x??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
 const owner=()=>tornGuideApi.isConnected()?Number(tornGuideApi.state.identity?.id)||null:null;
 let packet=null,query="",day="",page=0,priorOwner=null,requestedAt=null;
 function ensureOwner(){
   const id=owner();if(id!==priorOwner){priorOwner=id;packet=null;query="";day="";page=0;requestedAt=null;window.dispatchEvent(new Event("torn-guide-stop-log"));}return id;
 }
 function validate(p,id,now=Date.now()){
   if(!id||p?.version!==1||p.playerId!==id||!Array.isArray(p.rows)||p.rows.length>cap)return null;
   const rows=p.rows.filter(x=>Number.isSafeInteger(x?.at)&&x.at>=Date.UTC(2004,0,1)&&x.at<=now+300000&&typeof x.text==="string"&&x.text.trim()&&x.text.length<=1200).map(x=>({at:x.at,text:x.text})).sort((a,b)=>b.at-a.at);
   const stamp=Number.isSafeInteger(p.capturedAt)&&p.capturedAt<=now+5000&&p.capturedAt>0?p.capturedAt:null;
   const count=x=>Number.isInteger(x)&&x>=0&&x<=cap?x:0;
   return {playerId:id,rows,capturedAt:stamp,matched:count(p.matched),skipped:count(p.skipped)};
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
   const id=ensureOwner(),rows=packet?.rows??[],matches=filterRows(rows,query,day),pages=Math.max(1,Math.ceil(matches.length/pageSize));page=Math.min(page,pages-1);
   const status=!id?"Connect the Torn API to verify which player's local archive may be shown.":packet?packet.capturedAt?"Captured "+time(packet.capturedAt)+" · "+packet.matched+" rows recognized in last capture"+(packet.skipped?" · "+packet.skipped+" unreadable skipped":""):"Companion connected; no log entries captured yet.":"No log archive received. Update the companion script, open your Torn Log and capture loaded entries.";
   return '<p class="fine-print" data-log-sync-status role="status">'+esc(status)+'</p><p class="log-count">'+matches.length.toLocaleString("en-US")+' matching / '+rows.length.toLocaleString("en-US")+' archived entries</p>'+
     (matches.length?'<div class="log-table-scroll"><table class="log-table"><thead><tr><th scope="col">Date / time (TCT)</th><th scope="col">Activity</th></tr></thead><tbody>'+matches.slice(page*pageSize,(page+1)*pageSize).map(x=>'<tr><td><time datetime="'+new Date(x.at).toISOString()+'">'+esc(time(x.at).replace(" TCT",""))+'</time></td><td>'+esc(x.text)+'</td></tr>').join("")+'</tbody></table></div>':'<p class="fine-print">No matching entries in this local archive.</p>')+
     '<div class="log-pagination"><button type="button" data-log-page="prev" '+(page===0?"disabled":"")+'>Previous</button><small>Page '+(page+1)+' / '+pages+'</small><button type="button" data-log-page="next" '+(page+1>=pages?"disabled":"")+'>Next</button></div>';
 }
 function render(){
   ensureOwner();
   return '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Log</h1><p>Your personal Torn activity history, captured from the official Log page.</p></header><section class="panel"><div class="panel-heading"><h2>Activity archive</h2></div><div class="panel-content log-guide"><div class="log-actions"><a href="'+source+'" target="_blank" rel="noopener noreferrer">Open Torn Log</a><button type="button" data-log-sync '+(!owner()?"disabled":"")+'>Sync companion archive</button><a href="./torn-companion.user.js" target="_blank" rel="noopener noreferrer">Install / update companion</a></div><small>On Torn, use Capture loaded entries or enable Auto-capture while focused. Scroll or change filters manually to load more. Up to 2,000 newest entries stay in the userscript archive, separated by player. No server upload. Unrecognized timestamps are skipped; identical events at the same second are matched by observed multiplicity, so history may be incomplete. Clear the archive from the Torn Log capture panel.</small><div class="log-filters"><label>Search log <input type="search" data-log-query value="'+esc(query)+'" placeholder="Xanax, gym, item, cash…"></label><label>UTC date <input type="date" data-log-date value="'+esc(day)+'"></label><button type="button" data-log-reset>Clear filters</button></div><div data-log-results>'+content()+'</div></div></section>';
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
 return {render,wire,request,validate,filterRows};
})();
