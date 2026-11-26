"use strict";
// Torn game reference: https://wiki.torn.com/wiki/Search_For_Cash
// https://wiki.torn.com/wiki/Shoplifting . Reference keys are NOT API unique IDs.
// Each reward row = [skill, reward bundle, conditions, optional required item].
// Item quantities use ×; "$" / points-only entries are intentionally unmatched.
const tornCrimeStates=(()=>{
 const range=(min,max)=>[["meter","range",[min,max]]],phase=value=>[["phase","in",value]],guard=value=>[["guard","eq",value]],cam=value=>[["camera","eq",value]],check=value=>[["checkpoint","eq",value]],notoriety=value=>[["meter","range",[value,value]]];
 const search=[
  ["trash","Trash","Trash collection",[],null,1,[
   [1,"Bag of Candy Kisses ×4"],[25,"Morphine ×10"]]],
  ["subway","Subway","Ridership",["phase"],null,1,[
   [1,"Glasses",phase(["rush"])],[1,"Empty Box; Card Skimmer ×10",[],"Lost and Found Office Key"],[1,"Torn City Times; Zip Wallet",range(0,23)],[30,"Ecstasy ×3; LSD ×2",phase(["rush"])],[50,"Laptop",phase(["on","rush"])],[60,"Vicodin ×3; Xanax",range(0,23)],[85,"Lost and Found Office Key"]]],
  ["junkyard","Junkyard","Crushing rating",[],null,1,[
   [5,"Mountain Bike",range(0,49)],[30,"Metal Detector"],[30,"Spray Can: Black ×4; Spray Can: Red ×3; Spray Can: White ×3",range(0,75)],[40,"Kevlar Gloves",range(50,100)],[40,"Stash Box",range(75,100)],[60,"High-Speed Drive",range(0,23)],[80,"$50,620–79,820",range(50,75)]]],
  ["beach","Beach","Tide rating (higher = lower tide)",[],"Metal Detector",1,[
   [10,"Fishing Rod; Trout",range(60,100)],[10,"Bottle of Beer ×6; Sports Shades ×5; Proda Sunglasses ×4; Blanket",range(60,100)],[20,"First Aid Kit ×2",range(60,100)],[50,"Cemetery Key"],[50,"Coconut Bra",range(0,40)],[50,"Cork Hat"],[66,"Snorkel; Flippers; Wetsuit; Diving Gloves",range(0,40)],[90,"Sextant",range(40,100)],[95,"Silver Bead",range(0,40)]]],
  ["cemetery","Cemetery","Groundskeeping",["grounds"],"Cemetery Key",1,[
   [80,"Speed ×3",[["grounds","eq","inactive"]]],[80,"Golden Wreath",[["grounds","eq","active"]]],[90,"WWII Helmet",[["grounds","eq","inactive"]]],[100,"$100,884–197,978"]]],
  ["fountain","Fountain","Collections rating",[],null,75,[
   [75,"Cannabis ×4"],[80,"Lucky Quarter"],[85,"PCP",range(25,100)],[90,"Spray Can: Pink ×4; Spray Can: Purple ×3; Spray Can: Blue ×3; Spray Can: Orange ×3"],[100,"Ecstasy ×2",range(50,100)]]]
 ];
 const shops=[
  ["sally","Sally's Sweet Shop","Notoriety",["camera"],null,1,[
   [20,"Jawbreaker",cam("disabled")],[40,"Empty Box; Bag of Chocolate Truffles ×2; Jawbreaker ×2",cam("enabled")],[60,"Pixie Sticks ×2",cam("disabled")],[70,"Bag of Sherbet ×4",cam("enabled")],[80,"Tin of Treats",cam("disabled")]]],
  ["bits","Bits 'n' Bobs","Notoriety",["camera"],null,1,[
   [1,"Bottle of Champagne ×8",cam("disabled")],[1,"Cut-Throat Razor; Shaving Foam"],[20,"Flashlight"],[30,"Duct Tape",cam("disabled")],[60,"Bottle of Beer ×24"],[80,"$12,890–57,340",cam("disabled")],[90,"Mountain Bike"]]],
  ["clothing","TC Clothing","Notoriety",["camera","checkpoint"],null,1,[
   [20,"Raincoat",check("disabled")],[30,"Fisherman Hat; Fishing Rod"],[40,"Tailor's Dummy; Scissors",cam("disabled")],[50,"Trench Coat"],[60,"Mackintosh"],[70,"Coat Hanger",notoriety(100)],[80,"Bush Hat",[...cam("disabled"),...check("enabled")]],[90,"Crop Top; Coin Purse; Lipstick"],[100,"Poncho",check("disabled")]]],
  ["super","Super Store","Notoriety",["camera","checkpoint"],null,1,[
   [1,"DSLR Camera",check("disabled")],[1,"DVD Player; Erotic DVD",[...cam("disabled"),...check("disabled")]],[20,"Tracking Device"],[40,"Wireless Dongle",cam("disabled")],[60,"Ergonomic Keyboard",check("disabled")],[80,"High-Speed Drive"],[100,"Laptop"],[null,"Voice Recorder"]]],
  ["pharmacy","Pharmacy","Notoriety",["camera","checkpoint"],null,1,[
   [5,"Melatonin",cam("enabled")],[100,"Box of Medical Supplies",check("enabled")],[10,"Tyrosine",[...cam("disabled"),...check("enabled")]],[100,"Epinephrine",[...cam("enabled"),...check("disabled")]],[1,"Serotonin; Syringe ×4",[...cam("disabled"),...check("disabled")]]]],
  ["cyber","Cyber Force","Notoriety",["camera","guard"],null,1,[
   [1,"3–9 points",guard("off")],[1,"$220,000–299,000",[...cam("enabled"),...guard("on")]],[1,"RF Detector",cam("disabled")],[5,"HPCPU ×3",cam("disabled")],[15,"CPU ×5; HPCPU; Computer Fan ×2; Water Block",[...cam("disabled"),...guard("off")]],[60,"Office Chair",guard("off")]]],
  ["jewelry","Jewelry Store","Notoriety",["camera","guard"],null,1,[
   [20,"Gold Tooth ×12",guard("on")],[40,"Diamond Ring; Latex Gloves",guard("on")],[40,"Raw Ivory",[...cam("enabled"),...guard("on")]],[60,"Diamond Bladed Knife",guard("off")],[10,"Vanity Hand Mirror",[...cam("disabled"),...guard("off")]],[1,"Magnifying Glass"],[1,"Gold Ring; Graver"],[1,"Diamond Ring; Grinding Stone",cam("disabled")],[1,"Gold Ring ×2; Drill; Polishing Pad",cam("disabled")],[100,"Cluster Ring",[...notoriety(0),...cam("disabled"),...guard("off")]]]],
  ["gun","Big Al's Gun Shop","Notoriety",["camera","guard"],null,1,[
   [1,"2,500 special ammo",[...cam("disabled"),...guard("off")]],[1,"Full Body Armor",[...cam("disabled"),...guard("off")]],[30,"Ninja Stars ×9",cam("disabled")],[40,"Desert Eagle",[...cam("enabled"),...guard("on")]],[50,"Stick Grenade ×6",guard("off")],[60,"Steyr AUG",guard("off")],[70,"Throwing Knife ×4",cam("disabled")],[80,"HEG ×8",[...cam("enabled"),...guard("on")]],[100,"Box of Grenades"]]]
 ];
 const data={"Search for Cash":search,"Shoplifting":shops};
 const esc=x=>String(x??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
 const norm=x=>String(x??"").toLowerCase().replace(/spray\s+(?:can|paint)/g,"spray").replace(/[^a-z0-9]/g,"");
 const fields={phase:["off","on","rush"],grounds:["inactive","active"],camera:["enabled","disabled"],checkpoint:["enabled","disabled"],guard:["on","off"]};
 const names={phase:"Ridership phase",grounds:"Groundskeeping",camera:"Cameras",checkpoint:"Checkpoint",guard:"Guard"};
 const labels={phase:{off:"Off-peak",on:"On-peak",rush:"Rush hour"},grounds:{inactive:"Inactive",active:"Active"},camera:{enabled:"Enabled",disabled:"Disabled"},checkpoint:{enabled:"Enabled",disabled:"Disabled"},guard:{on:"On duty",off:"Off duty / break"}};
 const ttl=(crime,field)=>crime==="Shoplifting"&&field==="meter"?300000:900000;
 const key=owner=>"torn-city-guide:crime-observations:v1:"+String(owner);
 function load(owner,store){try{const v=JSON.parse(store.getItem(key(owner))||"{}");return v&&typeof v==="object"&&!Array.isArray(v)?v:{};}catch{return {};}}
 function valid(crime,id,field,value){
  const t=data[crime]?.find(x=>x[0]===id);if(!t)return false;
  if(field==="meter")return id!=="cemetery"&&typeof value==="number"&&Number.isInteger(value)&&value>=0&&value<=100;
  return t[3].includes(field)&&fields[field]?.includes(value);
 }
 function save(owner,store,crime,id,field,raw,now=Date.now()){
  if(typeof tornTrainingRecovery!=="undefined"&&tornTrainingRecovery.journalHeld(store,owner))return false;
  const t=data[crime]?.find(x=>x[0]===id);
  if(!t||!(field==="meter"&&id!=="cemetery"||t[3].includes(field)))return false;
  const val=field==="meter"&&raw!==""?Number(raw):raw;
  if(raw!==""&&!valid(crime,id,field,val))return false;
  const all=load(owner,store),k=crime+"|"+id+"|"+field;
  if(raw==="")delete all[k];else all[k]={value:val,at:now};
  try{if(typeof tornAccountStorage!=="undefined")tornAccountStorage.trackedWrite(store,owner,key(owner),JSON.stringify(all));else store.setItem(key(owner),JSON.stringify(all));return true;}catch{return false;}
 }
 function observed(all,crime,id,field,now){
  const x=all[crime+"|"+id+"|"+field];
  if(!x||!valid(crime,id,field,x.value)||!Number.isFinite(x.at)||x.at>now)return {value:null,expired:false};
  const expires=x.at+ttl(crime,field);
  return {value:expires>now?x.value:null,expired:expires<=now,at:x.at,expires};
 }
 function conditionMatch(conditions,read){
  let unknown=false;
  for(const [field,op,wanted] of conditions??[]){
   const v=read(field);
   if(v==null){unknown=true;continue;}
   const pass=op==="range"?v>=wanted[0]&&v<=wanted[1]:op==="in"?wanted.includes(v):v===wanted;
   if(!pass)return "mismatch";
  }
  return unknown?"unknown":"match";
 }
 function conditionLabel(conditions,meter,crime){
  if(!conditions?.length)return "";
  return conditions.map(([field,op,v])=>{
   if(field==="meter"){
    const label=crime==="Shoplifting"?"Notoriety":meter.split(" (")[0];
    return label+" "+(v[0]===v[1]?v[0]+"%":v[0]===0?"≤"+v[1]+"%":v[1]===100?"≥"+v[0]+"%":v[0]+"–"+v[1]+"%");
   }
   return (field==="phase"?"":names[field]+" ")+(op==="in"?v.map(x=>labels[field][x]).join(" / "):labels[field][v]);
  }).join(" + ");
 }
 function bundleSignature(bundle){
  if(!bundle||/^\$|points$|special ammo$/i.test(bundle))return null;
  return bundle.split(";").map(x=>{const m=x.trim().match(/^(.*?)(?:\s*×(\d+))?$/);return norm(m[1])+":"+(m[2]??1);}).sort().join("|");
 }
 function collected(crime,uniques,catalog){
  const out=new Set(),map=new Map();
  for(const [id,,,,,,rows] of data[crime]??[])for(const [i,row] of rows.entries()){
   const sig=bundleSignature(row[1]);if(sig)map.set(sig,[...(map.get(sig)??[]),id+":"+i]);
  }
  const items=Array.isArray(catalog)?catalog:Object.entries(catalog??{}).map(([id,x])=>({...x,id:x.id??id}));
  for(const unique of Array.isArray(uniques)?uniques:[]){
   const rewards=unique?.rewards?.items;
   if(!Array.isArray(rewards)||!rewards.length)continue;
   const parts=rewards.map(x=>{
    const name=x.name??items.find(i=>String(i.id)===String(x.id??x.item_id))?.name;
    const count=x.quantity??x.amount;
    return name&&count!=null&&Number.isInteger(Number(count))&&Number(count)>0?norm(name)+":"+Number(count):null;
   });
   if(parts.includes(null))continue;
   const matches=map.get(parts.sort().join("|"));if(matches?.length===1)out.add(matches[0]);
  }
  return out;
 }
 function render(crime,{cs=null,only=true,allCollected=false,uniques=[],catalog=[],itemStatus=()=> "unknown",owner="guest",store=localStorage,now=Date.now()}={}){
  if(!data[crime])return "";
  const all=load(owner,store),known=collected(crime,uniques,catalog),shop=crime==="Shoplifting";
  let soon=Infinity,shown=0;
  const body=data[crime].map(([id,title,meter,extra,item,min,rows])=>{
   const read=field=>observed(all,crime,id,field,now);
   const controls=(id==="cemetery"?extra:["meter",...extra]).map(field=>{
    const obs=read(field);if(obs.value!==null)soon=Math.min(soon,obs.expires);
    const attr=' data-crime-observation data-crime-name="'+esc(crime)+'" data-crime-target="'+id+'" data-crime-field="'+field+'"';
    const age=obs.value!==null?"Observed "+Math.floor((now-obs.at)/60000)+"m ago":obs.expired?"Expired · enter new reading":"Unknown";
    if(field==="meter")return '<div class="crime-meter-row"><label>'+esc(meter)+' <input type="number" min="0" max="100" step="1" placeholder="?" value="'+esc(obs.value??"")+'"'+attr+' aria-label="'+esc(title+" "+meter+" percent")+'">%</label><div class="crime-meter-track'+(obs.value===null?" is-unknown":"")+(shop?" is-notoriety":"")+'" role="meter" aria-label="'+esc(title+" "+meter)+'"'+(obs.value===null?' aria-valuetext="Unknown"':' aria-valuemin="0" aria-valuemax="100" aria-valuenow="'+obs.value+'"')+'><span style="width:'+Number(obs.value??0)+'%"></span></div><small>'+esc(age)+'</small></div>';
    return '<label class="crime-condition-control">'+esc(names[field])+'<select'+attr+' aria-label="'+esc(title+" "+names[field])+'"><option value="">Unknown</option>'+fields[field].map(v=>'<option value="'+v+'" '+(v===obs.value?"selected":"")+'>'+esc(labels[field][v])+'</option>').join("")+'</select><small>'+esc(age)+'</small></label>';
   }).join("");
   const groups=new Map();
   for(const [i,[skill,reward,conditions,required]] of rows.entries()){
    const done=allCollected||known.has(id+":"+i);if(only&&done)continue;shown++;
    const condition=conditionLabel(conditions,meter,crime),match=conditionMatch(conditions,f=>read(f).value),gear=required?itemStatus(required):"owned",targetGear=item?itemStatus(item):"owned";
    const locked=cs!=null&&(cs<min||skill!=null&&cs<skill)||gear==="missing"||targetGear==="missing";
    const status=done?"Collected":locked?"Requirement unmet":skill==null||cs==null||gear==="unknown"||targetGear==="unknown"?"Verify requirements":condition?match==="match"?"Observed match":match==="mismatch"?"Condition differs":"Condition unknown":"No extra state requirement";
    const cls=done?"collected":locked||match==="mismatch"?"unmet":condition&&match==="match"&&skill!=null&&cs!=null&&gear==="owned"&&targetGear==="owned"?"matched":"unknown";
    const html='<div class="crime-state-reward"><span>'+esc(reward)+'</span><small>CS '+esc(skill??"?")+(required?" · "+esc(required)+" ("+esc(gear)+")":"")+' · <span class="crime-state-'+cls+'">'+esc(status)+'</span></small></div>';
    groups.set(condition,[...(groups.get(condition)??[]),html]);
   }
   const unrestricted=groups.get("")??[];groups.delete("");
   return '<li class="crime-state-target"><div class="rec-crime-option-head"><strong>'+esc(title)+'</strong><small>'+(shop?4:2)+' N'+(min>1?' · CS '+min:"")+'</small></div>'+
    (item?'<small>'+esc(item)+' · '+esc(itemStatus(item))+'</small>':"")+unrestricted.join("")+
    '<div class="crime-state-controls">'+controls+'</div>'+
    [...groups].map(([condition,rows])=>'<div class="crime-state-group"><strong class="crime-condition-label">'+esc(condition)+'</strong><div>'+rows.join("")+'</div></div>').join("")+
    (!unrestricted.length&&!groups.size?'<small>No uncollected reference rewards shown.</small>':"")+'</li>';
  }).join("");
  return '<li class="rec-crime-options crime-state-board"'+(Number.isFinite(soon)?' data-crime-state-expires="'+soon+'"':"")+'><div><strong>'+(shop?"Stores &amp; vulnerabilities":"Search meters &amp; unique outcomes")+'</strong><small>Manual observations only. Read values in Torn; blank = unknown. '+(shop?"Notoriety is per store and changes with attempts; readings expire in 5 min. Security expires in 15 min.":"Readings expire in 15 min.")+' An observed match is not a success guarantee. Unverified rewards remain visible.</small><small>'+shown+' reference outcomes shown · '+known.size+' exact item-bundle matches</small><ul class="crime-state-list">'+body+'</ul></div></li>';
 }
 return {data,valid,save,load,observed,conditionMatch,conditionLabel,bundleSignature,collected,render};
})();
