"use strict";
const tornCrimeGuide = (() => {
  const crimes = [
    ["Search for Cash","Starter","Start here; prioritize high-opportunity searches and find useful crime tools."],
    ["Bootlegging","Starter","Copy DVDs safely first; selling offers faster skill but more risk."],
    ["Graffiti","Low","Very reliable CE/NNB builder. Build reputation and use spray cans."],
    ["Shoplifting","Low–Medium","Choose stores and security windows; higher-risk targets can cause setbacks."],
    ["Card Skimming","Low–Medium","Passive side project. Install skimmers and collect after details accumulate."],
    ["Pickpocketing","Variable","Target choice matters enormously; begin with safer pedestrians."],
    ["Hustling","Low–Medium","Strong CE builder if you manage attention and suspicion."],
    ["Disposal","Medium","Daily jobs, with method-specific risks. Build skill on safer jobs."],
    ["Burglary","Medium–High","Scout and case carefully; weak confidence and repeated fails hurt chains."],
    ["Cracking","Medium–High","Needs equipment and preparation; later becomes an efficient CE builder."],
    ["Forgery","High","Multi-step projects with materials; best after a solid CE foundation."],
    ["Scamming","High","Many moving parts and mistakes; postpone until more experienced."],
    ["Arson","High","Advanced vandalism with dangerous targets; efficient CE at appropriate skill."]
  ];
  const esc = x => String(x == null ? "" : x).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const number = n => Number.isFinite(Number(n)) ? Number(n).toLocaleString() : "?";
  // In-game reference data; sources: official Crimes 2.0 wiki and Emforus's
  // Graffiti guide. Unknown outcome averages are deliberately not estimated.
  const reference=[
    ["Search for Cash","Glasses",34,["Trash","Subway","Junkyard","Beach — Metal Detector","Cemetery — Cemetery Key","Fountain — CS 75"],[["Metal Detector","Tool","Beach access"],["Cemetery Key","Tool","Cemetery access"]]],
    ["Bootlegging","High-Speed Drive",4,["Copy DVDs — 2 N; computer and blank DVDs","Sell DVDs — 5 N; copied stock","Online store — CS 50, Web Design and Development, computer"],[]],
    ["Graffiti","Paint Mask",41,["East Side","West Side","North Side","Residential District","Red-Light District","Financial District","City Centre"],[["Ladder","Tool","Extra outcomes; obtainable in West Side at CS 15",15],["Wire Cutters","Tool","Extra outcomes; obtainable in North Side at CS 25",25]]],
    ["Shoplifting","Mountain Bike",58,["Sally's Sweet Shop","Bits 'n' Bobs","TC Clothing","Super Store","Pharmacy","Cyber Force","Jewelry Store","Big Al's Gun Shop"],[["Torn City Times","Other","Additional outcomes"]]],
    ["Card Skimming","Duct Tape",0,["Install skimmer","Recover skimmer","Sell card details"],[["Card Skimmer","Tool","Required equipment"],["Spy Camera","Tool","Required equipment"]]],
    ["Pickpocketing","Cut-Throat Razor",22,["22 pedestrian types — all accessible from CS 1; difficulty varies"],[]],
    ["Hustling","Megaphone",0,["Gather audience","Demonstrate","Persuade","Play to lose","Play to win"],[]],
    ["Disposal","Latex Gloves",11,["12 daily job categories; method and nerve cost vary"],[]],
    ["Burglary","Flashlight",34,["Residential","Commercial","Industrial","Scout","Case","Burglarize"],[]],
    ["Cracking","Office Chair",0,["Computer / laptop","Rig chassis — first at CS 25","Brute force","Guess"],[]],
    ["Forgery","Magnifying Glass",0,["Driver's License","Parking Permit","Concert Ticket","Collection Bucket","Diploma","Birth Certificate","License Plate","Ordination Certificate","Court Order","Skeleton Key","Prescription","Travel Visa","ID Badge","Medical License","Bank Check","Police Badge","ATM Key","Passport","Government Contract"],[]],
    ["Scamming","Ergonomic Keyboard",0,["Collect addresses","Launch spam waves","Respond to marks"],[]],
    ["Arson","Windproof Lighter",16,["Job targets vary by size and job requirements"],[]]
  ];
  const paint=[
    ["East Side","Initial","Purple","Red"],["West Side","Initial","Green","Blue"],["North Side","Initial","Green","Orange"],
    ["Residential District","CS 50; East Side unique","White","Blue"],["Red-Light District","CS 50; West Side unique","Green","Pink"],
    ["Financial District","Crew membership","Black","Red"],["City Centre","Crew membership","Green","Blue"]
  ];
  const normalize=v=>String(v??"").toLowerCase().replace(/[^a-z0-9]/g,"");
  function skill(name){
    const raw=payload("skills","skills"),target=normalize(name);
    const list=Array.isArray(raw)?raw:Array.isArray(raw?.crimes)?raw.crimes:Array.isArray(raw?.crime)?raw.crime:[];
    const row=list.find(x=>normalize(x.name??x.crime??x.type)===target);
    const direct=Object.entries(raw?.crimes??raw?.crime??raw??{}).find(([k])=>normalize(k)===target)?.[1];
    const val=row?.skill??row?.level??row?.value??(typeof direct==="object"?direct?.skill??direct?.level:direct);
    return val!=null&&Number.isFinite(Number(val))?Number(val):null;
  }
  function inventoryStatus(name,cat){
    const inventory=tornGuideApi.state.inventory[cat];
    if(!Array.isArray(inventory)||tornGuideApi.state.inventoryErrors[cat])return null;
    return inventory.some(x=>normalize(x.name??x.item?.name)===normalize(name)&&Number(x.amount??x.quantity??1)>0);
  }
  function market(name){
    const raw=payload("itemCatalog","items");
    const item=(Array.isArray(raw)?raw:Object.values(raw||{})).find(x=>normalize(x.name)===normalize(name));
    const v=item?.market_value??item?.value?.market_price??item?.value?.market_value??item?.market_price;
    return v!=null&&Number.isFinite(Number(v))&&Number(v)>0?Number(v):null;
  }
  function equipment(ref){
    const [name,enhancer,,,tools]=ref;
    return [[enhancer,"Enhancer",name==="Arson"?"Crime-specific enhancer; check current effect":"5% crime experience and skill gains"],...tools];
  }
  function wiki(name){return "https://wiki.torn.com/wiki/"+encodeURIComponent(name==="Search for Cash"?"Search_For_Cash":name.replace(/ /g,"_"));}
  const index="https://www.torn.com/forums.php?p=threads&t=16414425";
  function detailSections(){
    return '<section class="panel"><div class="panel-heading"><h2>Crime reference</h2></div><div class="panel-content"><p class="fine-print">Expand a crime for activities, equipment, unique counts and source tables. Profit per nerve requires observed cash, loot, costs and failed attempts; no unsupported averages are substituted.</p>'+
      reference.map(ref=>{
        const [name,,uniques,activities]=ref,cs=skill(name);
        return '<details class="crime-reference"><summary><strong>'+esc(name)+'</strong><small>'+(cs===null?"CS unavailable":"CS "+number(cs))+' · '+uniques+' documented uniques</small></summary><div class="crime-reference-body"><h3>Tools &amp; enhancers</h3><ul class="crime-equipment">'+equipment(ref).map(([item,cat,reason,min])=>{
          const owned=inventoryStatus(item,cat),price=market(item);
          return '<li><strong>'+esc(item)+'</strong><span>'+esc(reason)+'</span><small>'+(owned===null?"Inventory unknown":owned?"Owned":"Not owned")+(price===null?"":" · $"+number(price))+'</small></li>';
        }).join("")+'</ul><h3>Activities &amp; unlocks</h3><div class="crime-table-scroll"><table class="crime-table"><thead><tr><th>Activity / requirement</th><th>Average net $/N</th></tr></thead><tbody>'+activities.map(x=>'<tr><td>'+esc(x)+'</td><td>—</td></tr>').join("")+'</tbody></table></div>'+
        (name==="Graffiti"?'<h3>Paint color preferences</h3><p class="fine-print">Any color works. Community observations suggest the following colors; not guaranteed bonuses. Each attempt costs 3 nerve.</p><div class="crime-table-scroll"><table class="crime-table"><thead><tr><th>Area</th><th>Unlock</th><th>Cash</th><th>Reputation</th></tr></thead><tbody>'+paint.map(row=>'<tr>'+row.map(x=>'<td>'+esc(x)+'</td>').join("")+'</tr>').join("")+'</tbody></table></div><p>Reputation thresholds: 25 / 50 / 100 / 250 / 500 tags. At CS 70 and 5 stars in an eligible area, find the crew invitation unique. Reputation decays.</p><p>Notable unique tools: Ladder (West Side CS 15), Wire Cutters (North Side CS 25), Paint Mask (East Side CS 35). <a href="https://www.torn.com/forums.php?p=threads&t=16344567" target="_blank" rel="noopener noreferrer">Color research and unique tables</a></p>':"")+
        '<p class="fine-print"><a href="'+wiki(name)+'" target="_blank" rel="noopener noreferrer">Full unique outcomes and requirements</a> · <a href="'+index+'" target="_blank" rel="noopener noreferrer">Community profitability index</a></p></div></details>';
      }).join("")+'</div></section>';
  }
  // OC scenario-level equipment checklist. Quantities here are personal reserves,
  // not the total required by all members of a team.
  const ocReference=[
    [1,"First Aid and Abet","Lockpicks","Shaving Foam"],
    [1,"Mob Mentality","Jemmy",""],
    [1,"Pet Project","Net|Lockpicks","Dog Treats"],
    [2,"Disorderly Conduct","Megaphone","Spray Paint : Pink|Molotov Cocktail|Brick"],
    [2,"Thou Shalt Not Steal","Lockpicks|Cassock","Cell Phone"],
    [2,"Cash Me If You Can","","ID Badge|ATM Key"],
    [2,"Best of the Lot","Lockpicks|Police Badge",""],
    [3,"Smoke and Wing Mirrors","DSLR Camera|RF Detector",""],
    [3,"Market Forces","","Gasoline"],
    [3,"Gaslight the Way","Construction Helmet","ID Badge"],
    [4,"Snow Blind","","PCP"],
    [4,"Plucking the Lotus Petal","","Blank Casino Chips"],
    [4,"Stage Fright","Binoculars",""],
    [5,"Guardian Angels","","Hand Drill"],
    [5,"Honey Trap","Billfold",""],
    [5,"Counter Offer","Wire Cutters|Lockpicks","Zip Ties|Polymorphic Virus"],
    [5,"No Reserve","Bolt Cutters","Spray Paint : Black|Chloroform"],
    [6,"Bidding War","Jemmy|Dental Mirror","C4 Explosive|Flash Grenade"],
    [6,"Leave No Trace","Police Badge",""],
    [6,"Dish It Out","Bolt Cutters|Wire Cutters","Thermite|Ipecac Syrup"],
    [6,"Sneaky Git Grab","Wireless Dongle","Tunneling Virus"],
    [7,"Blast from the Past","Core Drill","Zip Ties|Shaped Charge|Firewalk Virus"],
    [7,"Window of Opportunity","Wire Cutters|Ladder|Angle Grinder","Razor Wire|Floor Cleaner"],
    [7,"Cleared for Takeoff","Large Suitcase|Hand Drill|Tracking Device|Bone Saw",""],
    [8,"Break the Bank","Hand Drill","Zip Ties"],
    [8,"Ship Happens","Core Drill","Single Red Rose"],
    [8,"Clinical Precision","","Chloroform|Blood Bag : Irradiated|Syringe"],
    [8,"Stacking the Deck","Jemmy","Smoke Grenade|ID Badge|Stealth Virus"],
    [8,"Lock Stock","","Ecstasy|Lubricant|Armored Virus"],
    [8,"Manifest Cruelty","Cigar Cutter|Car Battery","Zip Ties|Stealth Virus"],
    [9,"Ace in the Hole","","ID Badge"],
    [9,"Gone Fission","DSLR Camera|Cut-Throat Razor","Zip Ties|Thermite|C4 Explosive"],
    [9,"Hostile Takeover","China Lake","Tunneling Virus|PSU|Hard Drive|Igniter Cord|Nail Bomb"],
    [10,"Crane Reaction","Binoculars|Remote Detonator","Shaped Charge|Tear Gas"]
  ];
  const extraCrimeItems=[
    ["Search for Cash","Lost and Found Office Key|Bucket",1],
    ["Bootlegging","Blank DVDs",10],
    ["Graffiti","Spray Paint : Black|Spray Paint : Blue|Spray Paint : Green|Spray Paint : Orange|Spray Paint : Pink|Spray Paint : Purple|Spray Paint : Red|Spray Paint : White",3],
    ["Card Skimming","Card Skimmer",5],
    ["Disposal","Double Cut File|Handkerchief|Wheelbarrow|Shovel",1],
    ["Disposal","Anchor|Bleach|Disposable Mask|Gasoline|Hydrochloric Acid|Lye|Paper Towels|Rope",2],
    ["Burglary","Lockpicks|Rope",1],
    ["Cracking","Computer Fan|CPU|ECPU|HPCPU|Heat Sink",1],
    ["Forgery","Card Programmer|Crucible|Embosser|Fountain Pen|Graver|Grinding Stone|Hand Drill|Hole Punch|Hot Foil Stamper|Lump of Coal|Perforator|Permanent Marker|Polishing Pad|Printer|Scissors|Sewing Kit|Thimble|Wax Seal Stamp",1],
    ["Forgery","Adhesive Plastic|Aluminum Plate|Bank Statement|Binder|Bond Paper|Bonded Latex|Brass Ingot|Candle|Cardstock|Certificate Seal|Crushed Enamel|Glow Stick|Glue|Inkwell|Lanyard|Medical Bill|PVC Cards|Picture Frame|Toner",3],
    ["Arson","Diesel|Fire Extinguisher|Gasoline|Hydrogen Tank|Kerosene|Magnesium Shavings|Methane Tank|Oxygen Tank|Potassium Nitrate|Sand|Thermite",3]
  ];
  const reserveDefaults=[
    ["Xanax","Drug",12],["Ecstasy","Drug",2],["Erotic DVD","Booster",5],
    ["Small First Aid Kit","Medical",20],["First Aid Kit","Medical",10],["Morphine","Medical",10]
  ];
  function recommendations(){
    const st=tornGuideApi.state,raw=payload("itemCatalog","items");
    const catalog=Array.isArray(raw)?raw:Object.values(raw||{});
    const itemsByName=new Map(catalog.map(x=>[normalize(x.name),x]));
    const itemsById=new Map(catalog.map(x=>[String(x.id),x]));
    const ready=cat=>Array.isArray(st.inventory[cat])&&!st.inventoryErrors[cat];
    const qty=x=>Math.max(0,Number(x.amount??x.quantity??0)||0);
    const category=x=>{const t=x?.type?.name??x?.type??x?.category?.name??x?.category;return typeof t==="string"?t:null;};
    const matches=(x,name)=>normalize(x.name??x.item?.name??itemsById.get(String(x.id??x.item_id))?.name)===normalize(name);
    function count(name,hint){
      const cat=category(itemsByName.get(normalize(name)))||hint;
      // Search all fetched categories for positive holdings first; missing stock
      // is only inferred when the matching catalog category was fully loaded.
      const all=Object.entries(st.inventory).filter(([k])=>ready(k)).flatMap(([,list])=>list);
      if(cat&&ready(cat))return st.inventory[cat].filter(x=>matches(x,name)).reduce((n,x)=>n+qty(x),0);
      const owned=all.filter(x=>matches(x,name)).reduce((n,x)=>n+qty(x),0);
      return owned||null;
    }
    const buckets={current:new Map(),stock:new Map(),crime:new Map(),oc:new Map()};
    function add(bucket,item,hint,target,reason,level){
      const n=count(item,hint);
      if(n===null||n>=target)return;
      const key=normalize(item),map=buckets[bucket],old=map.get(key);
      if(old){old.target=Math.max(old.target,target);if(!old.reasons.includes(reason))old.reasons.push(reason);old.level=Math.min(old.level,level??99);return;}
      map.set(key,{item,owned:n,target,reasons:[reason],price:market(item),level:level??99});
    }
    // Assigned OC items take precedence over elective stockpiling. API slot
    // formats vary; only recommend exact requirements explicitly attributed to us.
    const oc=payload("organizedcrime","organizedcrime");
    const slots=oc?.slots??oc?.crime?.slots??[];
    const self=String(st.identity?.id??"");
    for(const slot of Array.isArray(slots)?slots:Object.values(slots||{})){
      const member=slot.user??slot.member??slot.participant;
      if(!self||String(member?.id??member?.user_id??slot.user_id??slot.member_id??"")!==self)continue;
      const needs=slot.item_requirements??slot.required_items??slot.items??(slot.item_requirement?[slot.item_requirement]:[]);
      for(const req of Array.isArray(needs)?needs:Object.values(needs||{})){
        if(req?.is_available===true||req?.available===true||req?.fulfilled===true)continue;
        const item=itemsById.get(String(req?.id??req?.item_id??req?.item?.id));
        const name=req?.item?.name??req?.name??item?.name;
        if(name)add("current",name,category(item),Math.max(1,Number(req.quantity??req.amount??1)||1),oc?.name??oc?.crime?.name??"Assigned OC");
      }
    }
    for(const ref of reference){
      const cs=skill(ref[0]);
      if(cs===null||cs<=1)continue;
      for(const [item,cat,reason,min] of equipment(ref)){
        if(min&&cs<min)continue;
        if(cs>=100&&cat==="Enhancer")continue;
        add("crime",item,cat,1,ref[0]+" · "+reason);
      }
    }
    for(const [name,names,target] of extraCrimeItems){
      const cs=skill(name);if(cs===null||cs<=1)continue;
      for(const item of names.split("|"))add("crime",item,null,target,name+" · optional stock");
    }
    for(const [level,name,tools,materials] of ocReference){
      for(const item of tools.split("|").filter(Boolean))add("oc",item,null,1,"L"+level+" "+name+" · reusable",level);
      for(const item of materials.split("|").filter(Boolean))add("oc",item,null,1,"L"+level+" "+name+" · consumed",level);
    }
    for(const [name,cat,target] of reserveDefaults)add("stock",name,cat,target,"Suggested reserve");
    for(const [cat,target] of [["Candy",50],["Alcohol",25],["Energy Drink",5]]){
      if(!ready(cat))continue;
      const owned=st.inventory[cat].reduce((n,x)=>n+qty(x),0);
      if(owned<target)buckets.stock.set(cat,{item:cat+" (any type)",owned,target,reasons:["Suggested category reserve"],price:null,level:99});
    }
    // Avoid duplicate shopping rows while retaining every relevant use.
    const seen=new Map();
    for(const group of Object.values(buckets))for(const [key,x] of group){
      if(!seen.has(key)){seen.set(key,x);continue;}
      const first=seen.get(key);first.target=Math.max(first.target,x.target);first.reasons=[...new Set([...first.reasons,...x.reasons])];group.delete(key);
    }
    const rows=group=>[...group.values()].sort((a,b)=>a.level-b.level||a.item.localeCompare(b.item)).map(x=>{
      const missing=x.target-x.owned;
      return '<li><div><strong>'+esc(x.item)+'</strong><small>'+esc(x.reasons.join(" · "))+'</small></div><span title="Owned / suggested reserve">'+number(x.owned)+' / '+number(x.target)+'</span><span>+'+number(missing)+(x.price===null?"":" · $"+number(missing*x.price))+'</span></li>';
    }).join("");
    const section=(label,group,open=false)=>group.size?'<details class="rec-group" '+(open?"open":"")+'><summary>'+esc(label)+' ('+group.size+')</summary><ul class="crime-recommendations">'+rows(group)+'</ul></details>':"";
    const total=[...Object.values(buckets)].reduce((n,g)=>n+g.size,0);
    const pending=tornGuideApi.inventoryTypes.filter(c=>!ready(c));
    return '<details class="home-expand-panel" open><summary>Recommendations'+(total?" ("+total+")":"")+'</summary><div class="home-expand-body">'+
      section("Assigned OC requirements",buckets.current,true)+section("Low consumable reserves",buckets.stock,true)+section("Crime equipment & materials",buckets.crime,true)+section("Optional OC supplies by difficulty",buckets.oc)+
      (!total?'<p>No shortages identified in loaded inventory.</p>':"")+
      (pending.length?'<p class="fine-print">Inventory unavailable: '+esc(pending.join(", "))+'</p>':"")+
      '<p class="fine-print">Reserve targets are suggested defaults, not mandatory purchases. Check faction loans and your assigned role before buying OC supplies. <a href="#crime">Crimes</a> · <a href="https://wiki.torn.com/wiki/Organized_Crime_2.0" target="_blank" rel="noopener noreferrer">OC Wiki</a> · <a href="https://www.torn.com/page.php?sid=ItemMarket" target="_blank" rel="noopener noreferrer">Item Market</a></p></div></details>';
  }
  function render(){
    const bars=tornGuideApi.state.data.bars;
    const nerve=bars && bars.bars && bars.bars.nerve;
    let out='<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Crimes 2.0</h1><p>Build crime experience safely, raise your natural nerve bar, and unlock more reliable advanced crimes.</p></header>';
    out+='<section class="panel"><div class="panel-heading"><h2>How crimes and nerve work</h2></div><div class="panel-content">';
    if(nerve)out+='<p class="crime-nerve">Your nerve right now: <strong>'+esc(number(nerve.current))+' / '+esc(number(nerve.maximum))+'</strong> <small>(total bar, including bonuses, not necessarily your NNB)</small></p>';
    out+='<p><strong>Crimes 2.0 is the current system.</strong> It launched in June 2023 and became the default for new players in January 2024. Many older Crimes 1.0 guides are obsolete for Crimes 2.0; existing legacy accounts may be an exception.</p>'+
      '<div class="crime-definitions"><p><strong>CE = Crime Experience:</strong> hidden, account-wide experience gained through successful crimes. Higher CE helps your natural nerve bar grow and affects organized-crime success. <strong>NNB = Natural Nerve Bar:</strong> the base nerve capacity earned through CE; it grows in 5-nerve increments. Merits, factions and jobs can add nerve above NNB.</p>'+
      '<p><strong>CS = Crime Skill:</strong> your visible level <em>within each crime</em>, typically up to level 100. Skill makes that crime more effective and unlocks activities; increasing Search for Cash skill does not directly increase Burglary skill. The <em>CE you earned</em> doing safe early crimes is what prepares you for tougher crimes later.</p></div>'+
      '<p><strong>Why difficulty matters:</strong> success adds CE and CS. An ordinary (orange) fail gives no progress; a critical (red) fail can remove CE, CS and your crime-chain bonus. Safer crimes build a chain that increases later CE/CS rewards. Individual subcrimes also depend on opportunity, security, timing, equipment and your skill.</p>'+
      '<p class="fine-print">Nerve regenerates at 1 every 5 minutes below its cap. A larger displayed maximum is not itself proof that your hidden CE increased.</p></div></section>';
    out+='<section class="panel"><div class="panel-heading"><h2>Recommended completion order</h2></div><div class="panel-content">'+
      '<p><strong>Safe completionist route:</strong> Search for Cash → Bootlegging → Graffiti → Shoplifting / Card Skimming → Pickpocketing / Hustling → Disposal / Burglary → Cracking → Forgery / Scamming / Arson.</p>'+
      '<p>Aim to approach <strong>CS 100</strong> in early crimes before taking on difficult targets; you can work on skimmers and time-gated Disposal jobs in parallel once safe. This is a <em>suggested</em> path, not a hard unlock order. If your goal is CE/NNB rather than every honor, a faster alternative is <strong>Graffiti → Hustling → Disposal → Cracking</strong>, once you have enough CE to avoid critical failures.</p>'+
      '<p class="fine-print">Crimes are not uniformly harder just because they appear later: the subcrime, target and current opportunity can matter more than the category. If a harder option is failing repeatedly, return to a safer option to rebuild CE and your crime chain.</p></div></section>';
    out+='<section class="panel"><div class="panel-heading"><h2>Each crime at a glance</h2></div><div class="panel-content"><p class="fine-print">Difficulty labels are qualitative, not official success percentages; they assume a relatively new player and vary by subcrime.</p>'+
      '<div class="crime-table-scroll"><table class="crime-table"><thead><tr><th>Crime</th><th>Relative difficulty</th><th>When and how to approach it</th></tr></thead><tbody>'+
      crimes.map(([name,difficulty,tip])=>'<tr><th>'+esc(name)+'</th><td>'+esc(difficulty)+'</td><td>'+esc(tip)+'</td></tr>').join("")+
      '</tbody></table></div></div></section>';
    out+=detailSections();
    out+='<section class="panel"><div class="panel-heading"><h2>Progress efficiently</h2></div><div class="panel-content"><ul class="crime-tips">'+
      '<li>Favor consistent success over expensive, high-risk attempts. Build CE and your crime chain before chasing difficult subcrimes.</li>'+
      '<li>Consider Crime Progression merits, your faction Criminality perks, relevant education, the Law starter career benefit and matching enhancers. They can increase CE and CS gains.</li>'+
      '<li>Use appropriate equipment and crime-specific conditions; hitting CS 100 is a milestone, not a guarantee that every target will succeed.</li></ul>'+
      '<p class="fine-print">References: <a href="https://wiki.torn.com/wiki/Crimes_2.0" target="_blank" rel="noopener noreferrer">Official Crimes 2.0 wiki</a> · <a href="https://wiki.torn.com/wiki/Nerve" target="_blank" rel="noopener noreferrer">Nerve and NNB</a> · <a href="https://www.torn.com/forums.php?p=threads&t=16385729" target="_blank" rel="noopener noreferrer">Community progression guide</a>.</p></div></section>';
    const note=activeProfile ? '<form class="note-form" id="note-form"><label for="topic-note">Personal crime notes</label><textarea id="topic-note" maxlength="5000" rows="4"></textarea><button class="button primary" type="submit">Save notes</button><p class="feedback" id="note-feedback" role="status"></p></form>' : '<p><a href="#profile">Connect your account</a> to save notes locally.</p>';
    return out+'<section class="panel"><div class="panel-heading"><h2>Your notes</h2></div><div class="panel-content">'+note+'</div></section>';
  }
  function syncNerve(){
    const bars=tornGuideApi.state.data.bars;
    const nerve=bars&&bars.bars&&bars.bars.nerve;
    const value=document.querySelector(".crime-nerve strong");
    if(nerve&&value)value.textContent=number(nerve.current)+" / "+number(nerve.maximum);
  }
  return {render,crimes,syncNerve,recommendations};
})();
