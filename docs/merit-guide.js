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
 ["The Affronted","Irritate every city job interviewer; avoid disrupting a current career","Coordination","#jobs"]
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
       const version=x.crimes_version;if(version===1||String(version)==="1")continue;
       result.push({type,id:String(x.id),name:x.name,description:x.description??x.requirement??"",category:typeof x.type==="object"?x.type?.name:x.type??x.category??type,done:known?ids.has(String(x.id)):null});
     }
   }
   return result;
 }
 function candidates(){
   const awards=model(),byName=new Map(awards.filter(x=>x.type==="honors").map(x=>[key(x.name),x]));
   return easy.map(([name,detail,effort,link])=>({name,detail,effort,link,done:byName.get(key(name))?.done??null})).filter(x=>x.done!==true);
 }
 function recommendations(){return candidates().filter(x=>x.done===false&&["Quick","Coordination","Progress"].includes(x.effort)).sort((a,b)=>["Quick","Coordination","Progress"].indexOf(a.effort)-["Quick","Coordination","Progress"].indexOf(b.effort)).slice(0,8);}
 let filter="all",query="";
 function render(){
   const awards=model(),shortlist=candidates(),earned=awards.filter(x=>x.done===true).length;
   const visible=awards.filter(x=>(filter==="all"||filter==="remaining"&&x.done===false||filter==="earned"&&x.done===true||filter===x.type)&&key(x.name+" "+x.description+" "+x.category).includes(key(query)));
   const list=rows=>'<ul class="crime-recommendations rec-advice">'+rows.map(x=>'<li><div><strong>'+safe(x.name)+'</strong><small>'+safe(x.detail??x.description)+' · '+safe(x.effort??x.category)+'</small></div><small>'+ (x.done===true?"Earned":x.done===false?"Not earned":"Unverified")+'</small>'+(x.link?'<a href="'+safe(x.link)+'">View</a>':"")+'</li>').join("")+'</ul>';
   const m=payload("merits","merits");
   return '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Merits &amp; awards</h1></header>'+
    '<section class="panel"><div class="panel-heading"><h2>Easy honors</h2><a href="https://wiki.torn.com/wiki/Award" target="_blank" rel="noopener">Wiki</a></div><div class="panel-content">'+list(shortlist)+'<p class="fine-print">Unverified entries are not confirmed missing. <a href="https://www.torn.com/forums.php?p=threads&t=16394278" target="_blank" rel="noopener">Community easy honor guide</a></p></div></section>'+
    '<section class="panel"><div class="panel-heading"><h2>Honors &amp; medals</h2><small>'+earned+' confirmed earned / '+awards.length+' catalog entries</small></div><div class="panel-content"><div class="stock-controls"><label>Search <input data-award-search value="'+safe(query)+'"></label><label>Show <select data-award-filter>'+[["all","All"],["remaining","Not earned"],["earned","Earned"],["honors","Honors"],["medals","Medals"]].map(([id,label])=>'<option value="'+id+'" '+(filter===id?"selected":"")+'>'+label+'</option>').join("")+'</select></label></div>'+(visible.length?list(visible):'<p class="fine-print">No matching award data loaded.</p>')+'</div></section>'+
    '<section class="panel"><div class="panel-heading"><h2>Merit spending</h2></div><div class="panel-content"><p>Honors and medals generally each award one merit. Upgrades have ten levels; each successive level costs one more merit (55 total for a full upgrade).</p><p>Available merits: '+safe(m?.available??m?.unspent??m?.merits_available??"Unavailable")+'</p><p><a href="https://wiki.torn.com/wiki/Merit" target="_blank" rel="noopener">Merit upgrade reference</a></p></div></section>';
 }
 function wire(view){if(view.dataset.awardsBound)return;view.dataset.awardsBound="1";view.addEventListener("change",e=>{if(location.hash!=="#merits")return;if(e.target.matches("[data-award-filter]"))filter=e.target.value;else if(e.target.matches("[data-award-search]"))query=e.target.value;else return;view.innerHTML=render();});}
 return {render,wire,recommendations,model};
})();
