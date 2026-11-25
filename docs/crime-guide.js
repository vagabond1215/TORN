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
  const ocLevelBands=[[1,2],[3,4],[5,6],[7,8],[9,10]];
  let ocEnabled=new Set(ocLevelBands.map(([lo])=>lo));
  let ocOwner=null,ocOpen=false;
  function loadOcFilters(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(owner===ocOwner)return;
    ocOwner=owner;ocOpen=false;ocEnabled=new Set(ocLevelBands.map(([lo])=>lo));
    try{
      const stored=JSON.parse(localStorage.getItem("torn-city-guide:oc-bands:"+owner));
      if(Array.isArray(stored))ocEnabled=new Set(stored.filter(v=>ocLevelBands.some(([lo])=>lo===v)));
    }catch{}
  }
  const recommendationTypes=[["restock","Restock"],["merit","Merits"],["growth","Stat growth"],["consume","Use consumables"],["crime","Crimes"],["education","Education"],["money","Money"]];
  let recIncomplete=true;
  let recOwner=null,recEnabled=new Set(recommendationTypes.map(([id])=>id));
  function loadRecFilters(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(recOwner===owner)return;
    recOwner=owner;recIncomplete=true;try{recIncomplete=localStorage.getItem("torn-city-guide:crime-incomplete:"+owner)!=="false";}catch{}recEnabled=new Set(recommendationTypes.map(([id])=>id));
    try{const v=JSON.parse(localStorage.getItem("torn-city-guide:rec-types:"+owner));if(Array.isArray(v))recEnabled=new Set(v.filter(id=>recommendationTypes.some(([key])=>key===id)));}catch{}
  }
  const recItem=(title,detail,link)=>'<li><div><strong>'+esc(title)+'</strong><small>'+esc(detail)+'</small></div>'+(link?'<a href="'+esc(link)+'">View</a>':"")+'</li>';
  // Wiki target groups and unique conditions; recommended skill bands are
  // conservative editorial estimates, not a measured success probability.
  const pickTargets=[
    ["Drunk Man",0,"Stumbling / distracted","Any",true,1],
    ["Drunk Woman",0,"Stumbling / distracted","Any",true,1],
    ["Elderly Man",0,"Walking","Any",true,1],
    ["Elderly Woman",0,"Walking","Any",false,1],
    ["Homeless Person",0,"Begging / loitering","Any",false,1],
    ["Junkie",0,"Stumbling","Stumbling",false,1],
    ["Young Man",0,"Distracted / on phone / music","Any",false,1],
    ["Young Woman",0,"Distracted / on phone / music","Any",false,1],
    ["Businessman",1,"Distracted / on phone","Any",false,1],
    ["Businesswoman",1,"Distracted / on phone","Any",false,1],
    ["Jogger",1,"Walking","Walking",true,1],
    ["Laborer",1,"Walking","Walking",false,1],
    ["Postal Worker",1,"Distracted","Distracted",false,1],
    ["Student",1,"Distracted / music","Any",true,1],
    ["Thug",1,"Loitering","Male, loitering",false,1],
    ["Classy Lady",2,"On phone","On phone",false,1],
    ["Cyclist",2,"Cycling","Cycling",true,100],
    ["Gang Member",2,"Loitering","Loitering",true,1],
    ["Rich Kid",2,"Listening to music","Listening to music",true,1],
    ["Sex Worker",2,"Soliciting","Soliciting",false,1],
    ["Mobster",3,"Walking","Walking",true,100],
    ["Police Officer",3,"Running","Running",false,1]
  ];
  const crimeIds={"Search for Cash":1,"Bootlegging":2,"Graffiti":3,"Shoplifting":4,"Pickpocketing":5,"Card Skimming":6,"Burglary":7,"Hustling":8,"Disposal":9,"Cracking":10,"Forgery":11,"Scamming":12,"Arson":13};
  const crimeAdvice={
    "Search for Cash":"Choose Trash, Subway or Junkyard with favorable opportunity. Beach and Cemetery require tools; Fountain requires CS 75.",
    "Bootlegging":"Copy DVDs to build stock; sell when stock and skill support it. Online store requires CS 50, education and a computer.",
    "Graffiti":"Start in initial districts and build reputation. Check paint, tools and unlocks before attempting later districts.",
    "Shoplifting":"Start with Sally's Sweet Shop or Bits 'n' Bobs; check security and avoid unfavorable windows.",
    "Card Skimming":"Install skimmers at accessible low-risk locations. Collect details when live risk is acceptable; keep spare skimmers.",
    "Hustling":"Start with manageable crowds and low suspicion. Demonstrate and persuade before riskier plays.",
    "Disposal":"Choose simpler available jobs and favorable methods; skip dangerous jobs until skill and tools support them.",
    "Burglary":"Scout residential locations first; build confidence by casing. Avoid commercial or industrial locations at low skill.",
    "Cracking":"Start with shorter accessible passwords and adequate rig capacity; use guesses and brute force according to clues.",
    "Forgery":"Start with earliest unlocked documents and required materials; complete preparation before more complex projects.",
    "Scamming":"Use early unlocked campaigns and follow the in-game mark position and available persuasion actions.",
    "Arson":"Choose small accessible jobs, inspect the target and required materials, and avoid difficult jobs until conditions improve."
  };
  function crimeProgress(name){return tornGuideApi.readCrimeProgress?.(crimeIds[name])?.crimes??null;}
  function pickUniqueState(name){
    if(name==="Police Officer"&&tornMeritGuide.model().some(x=>normalize(x.name)==="pigrustler"&&x.done===true))return true;
    const uniques=crimeProgress("Pickpocketing")?.uniques;
    if(!Array.isArray(uniques))return null;
    const raw=payload("itemCatalog","items"),catalog=Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
    const rewardNames=u=>(u.rewards?.items??[]).map(x=>normalize(x.name??catalog.find(i=>String(i.id)===String(x.id??x.item_id))?.name));
    if(name==="Police Officer")return uniques.some(u=>rewardNames(u).includes("policebadge"))?true:null;
    if(name==="Thug")return uniques.some(u=>{const r=rewardNames(u);return ["pcp","cutthroatrazor","billfold"].every(x=>r.includes(x));})?true:null;
    return null;
  }
  function crimeRecommendation(risk,completion){
    const riskRank={"Starter":0,"Low":0,"Low–Medium":1,"Medium":1,"Variable":1,"Medium–High":2,"High":2};
    const maxRisk={low:0,medium:1,high:2}[risk]??0;
    const all=crimes.map(([name,r,detail],i)=>{const progress=crimeProgress(name),cs=skill(name)??(Number.isFinite(progress?.skill)?progress.skill:null),total=reference.find(x=>x[0]===name)?.[2]??0;return {name,r,detail,i,cs,rank:riskRank[r]??2,total,progress,uniqueCount:Array.isArray(progress?.uniques)?new Set(progress.uniques.map(u=>u.id)).size:null};});
    const incomplete=all.filter(x=>x.cs!==null&&x.cs<100);
    const eligible=recIncomplete?incomplete:all.filter(x=>x.cs!==null);
    const pool=eligible.length?eligible:all.filter(x=>x.cs!==null&&completion&&x.total>0&&(x.uniqueCount===null||x.uniqueCount<x.total));
    const rank=(a,b)=>Number(a.rank>maxRisk)-Number(b.rank>maxRisk)||a.rank-b.rank||a.i-b.i;
    const chosen=[...pool].sort((a,b)=>completion&&!recIncomplete?Number(a.cs>=100)-Number(b.cs>=100)||rank(a,b):rank(a,b))[0]??[...all].filter(x=>x.cs!==null).sort(rank)[0]??all[0];
    const fallback=!eligible.length||chosen.rank>maxRisk;
    const detail=(chosen.cs===null?"Skill unavailable":chosen.cs<100?number(100-chosen.cs)+" skill levels to 100":"CS 100 · practice / unique review")+(fallback?" · No eligible safer unfinished crime; verify conditions and choose the easiest available action.":"");
    const ref=reference.find(x=>x[0]===chosen.name);
    const equipmentText=ref?equipment(ref).filter(x=>!x[3]||chosen.cs!=null&&chosen.cs>=x[3]).map(([name,cat])=>name+": "+({true:"owned",false:"missing",null:"unknown"}[inventoryStatus(name,cat)])).join(" · "):"";
    const uniqueText=chosen.total?chosen.uniqueCount==null?"Unique collection not loaded":chosen.uniqueCount+" / "+chosen.total+" documented unique outcomes collected":"No documented unique outcomes";
    return '<li><div><strong>Recommended: '+esc(chosen.name)+(chosen.cs===null?"":" · CS "+number(chosen.cs))+'</strong><small>'+esc(detail)+'</small><p>'+esc(crimeAdvice[chosen.name]??chosen.detail)+'</p><small>'+esc(uniqueText)+'</small>'+(equipmentText?'<small>'+esc(equipmentText)+'</small>':"")+'<div class="rec-crime-actions"><button type="button" class="rec-oc-toggle" data-rec-crime-load="'+crimeIds[chosen.name]+'">'+(chosen.progress?"Refresh crime progress":"Load crime progress")+'</button><a href="'+wiki(chosen.name)+'" target="_blank" rel="noopener noreferrer">Unique requirements</a><a href="https://torn.report/uniques" target="_blank" rel="noopener noreferrer">Unique tracker</a></div></div><a href="#crime">View</a></li>'+(chosen.name==="Pickpocketing"?pickpocketRows(chosen.cs,risk):"");
  }
  function pickpocketRows(cs,risk){
    const maxTier=Math.min(risk==="low"?1:risk==="medium"?2:3,cs==null||cs<35?0:cs<70?1:cs<100?2:3);
    const razor=inventoryStatus("Cut-Throat Razor","Enhancer");
    const avoided=pickTargets.filter(x=>x[1]>=1&&pickUniqueState(x[0])===true).map(x=>x[0]);
    const rows=pickTargets.filter(x=>x[1]<=maxTier&&!avoided.includes(x[0])).map(([name,tier,state,condition,needRazor,min])=>{
      const done=pickUniqueState(name);
      const note=done===true?"Unique collected; ordinary skill growth only":cs!=null&&cs<min?"Unique requires CS "+min:needRazor&&razor!==true?"Unique requires Razor (ownership "+(razor===false?"missing":"unknown")+")":"Unique: "+condition+" · check star";
      return '<tr><td>'+esc(name)+'</td><td>'+esc(state)+'</td><td>'+esc(note)+'</td></tr>';
    });
    return '<li class="rec-pickpocket"><div><strong>Recommended targets</strong><small>'+ (maxTier===0?"Easy targets only":maxTier===1?"Easy and moderate targets":maxTier===2?"Up to difficult targets":"All difficulty bands")+'</small><div class="crime-table-scroll"><table class="crime-table"><thead><tr><th>Target</th><th>Preferred state</th><th>Unique condition</th></tr></thead><tbody>'+rows.join("")+'</tbody></table></div><small>'+(avoided.length?"Avoid for unique hunting: "+esc(avoided.join(", "))+". ":"")+'Unmapped unique rewards remain unverified. Check the star and live success conditions in Torn. <a href="https://wiki.torn.com/wiki/Pickpocketing" target="_blank" rel="noopener">Wiki</a></small></div></li>';
  }
  function adviceSections(count){
    const prefs=tornRoadmap.preferences(),activities=tornRoadmap.selectedStyles(),growth=prefs.priority==="growth",completion=prefs.priority==="completion",risk=prefs.risk;
    const rows={merit:[],growth:[],consume:[],crime:[],education:[],money:[]};
    const add=(key,title,detail,link)=>rows[key].push(recItem(title,detail,link));
    const n=v=>v!=null&&v!==""&&Number.isFinite(Number(v))?Number(v):null;
    for(const x of tornMeritGuide.recommendations())add("merit",x.name,x.detail+" · "+x.effort,x.link);
    if(!rows.merit.length)add("merit","Award shortlist unavailable","Open Merits to load the award catalog and compare unearned honors.","#merits");
    const iconData=payload("icons","icons");
    const iconFresh=iconData&&!tornGuideApi.state.errors?.icons&&Date.now()-Number(tornGuideApi.state.fetchedAt?.icons||0)<15*60000;
    const iconTexts=iconFresh?Object.values(iconData).map(x=>typeof x==="string"?x:[x?.title,x?.name,x?.description,x?.text].filter(Boolean).join(" ")):[];
    const addictionDebuff=iconTexts.filter(x=>/addict/i.test(x)).map(x=>{const m=x.match(/(?:reduced by|reduction of|[-−])\s*(\d+(?:\.\d+)?)\s*%/i);return m?Number(m[1]):null;}).filter(x=>x!==null);
    const highAddiction=addictionDebuff.some(x=>x>=5);
    const edu=educationModel(),enrolled=Boolean((edu.id!=null&&edu.id!==0&&edu.id!=="0"&&edu.id!=="")||(Number(edu.deadline)>Date.now()));
    const perks=payload("perks","perks"),jobPerks=Object.entries(perks||{}).filter(([key])=>/job|company/i.test(key)).flatMap(([,v])=>Array.isArray(v)?v:[]).map(x=>typeof x==="string"?x:[x?.name,x?.description,x?.effect].filter(Boolean).join(" "));
    const protectedEducation=jobPerks.some(x=>/\bRestraint\b|education is unaffected by drug addiction|education.*immune.*addiction/i.test(x));
    const educationRisk=enrolled&&highAddiction&&!protectedEducation;
    const blockDrugs=highAddiction&&(!enrolled||!protectedEducation);
    if(educationRisk){
      const detail="Active education course · addiction-related battle-stat penalty "+Math.max(...addictionDebuff)+"%. Avoid all drugs until addiction is reduced. Course dismissal can occur at 5%; restarting loses progress.";
      add("consume","Protect education · avoid all drugs",detail,"#education");
      add("education","Education dismissal risk",detail,"#education");
    }else if(enrolled&&highAddiction&&protectedEducation)add("consume","Education protected by Restraint","The active job perk protects enrollment, but addiction still affects other gameplay; consider rehabilitation.","#education");
    const plan=tornStatPlanner.homeTrainingAdvice(prefs.weeklyBudget,risk,{blockDrugs});
    if(plan){
      add("growth","Train "+plan.stat,plan.detail,"#stats");
      const p=plan.program;
      if(p)add("growth","Recommended program: "+p.label,"7-day estimated gain: +"+number(Math.round(p.gain))+" · "+number(p.used)+" E · $"+number(Math.round(p.money))+" / week · "+Object.entries(p.costs).filter(([,qty])=>qty>0).map(([type,qty])=>qty+" "+type).join(", ")+(prefs.weeklyBudget===null?" · Set a weekly budget to compare paid programs.":" · Budget $"+number(prefs.weeklyBudget))+(p.cycles>0?" · "+p.cycles+" plan cycle"+(p.cycles===1?"":"s")+" × "+number(p.blockHours)+"h; natural training between/after cycles":"")+" · Highest estimated gain among affordable Stats → Plan templates; prices and cooldowns may change.","#stats");
      else add("growth","Training program unavailable","Load current gym, bars and battle stats to compare weekly training programs.","#stats");
    }else add("growth","Review your build targets","Load current battle stats and select a build on Stats.","#stats");
    const bars=payload("bars","bars"),cd=payload("cooldowns","cooldowns");
    const energy=n(bars?.energy?.current),cap=n(bars?.energy?.maximum),happy=n(bars?.happy?.current),happyCap=n(bars?.happy?.maximum),nerve=n(bars?.nerve?.current);
    const drug=n(cd?.drug),booster=n(cd?.booster);
    const program=plan?.program, costs=program?.costs??{};
    if(highAddiction&&!educationRisk&&!protectedEducation)add("consume","High addiction · consider rehabilitation","Addiction-related battle-stat penalty "+Math.max(...addictionDebuff)+"%. Pause drug use until addiction is reduced; review your training schedule.","#stats");
    if(growth){
      if(program){
        const items=[["Xanax","xanax","Drug"],["Ecstasy","ecstasy","Drug"],["Erotic DVD","dvd","Booster"],["Candy","candy","Candy"],["Points refill","refill",null]];
        for(const [name,key,cat] of items){
          if(!(costs[key]>0)||blockDrugs&&cat==="Drug")continue;
          const held=cat&&key!=="candy"?count(name,cat):null;
          const status=cat==="Drug"?(drug===0?"Drug cooldown clear; follow the plan sequence, not simply the cooldown.":drug==null?"Check drug cooldown.":"Wait for drug cooldown and the planned action."):cat==="Booster"||key==="candy"?"Reserve booster allowance for the planned training action.":"Use only at the scheduled refill step.";
          add("consume",name+" · "+number(costs[key])+" / week"+(held!=null?" · "+number(held)+" held":""),program.label+" · "+status,"#stats");
        }
        if(!Object.values(costs).some(x=>x>0))add("consume","Natural training","No paid consumables required by the recommended plan.","#stats");
      }else add("consume","Training plan required","Load the Stats plan comparison before choosing training consumables.","#stats");
    }else{
      const nerveRoom=nerve!=null&&n(bars?.nerve?.maximum)!=null&&nerve<n(bars.nerve.maximum);
      const crimeActivity=completion||activities.some(x=>["Crime","OC"].includes(x));
      const marijuana=count("Cannabis","Drug");
      if(!blockDrugs&&drug===0&&marijuana>0&&(crimeActivity||completion)&&nerveRoom)add("consume","Cannabis · "+number(marijuana)+" held","Consider the in-game Nerve effect for crime activity when there is room; check the drug cooldown and any scheduled training or war.","#crime");
      const alcohol=tornGuideApi.state.inventory.Alcohol;
      if(crimeActivity&&nerveRoom&&booster!==null&&booster<86400&&Array.isArray(alcohol)&&!tornGuideApi.state.inventoryErrors?.Alcohol&&alcohol.some(x=>n(x.amount??x.quantity)>0))add("consume","Alcohol","Consider a Nerve boost for crime activity; reserve booster allowance for scheduled training if needed.","#crime");
    }
    if(!iconFresh)add("consume","Addiction status unavailable","Current addiction icon data is unavailable; no high-addiction warning has been inferred.","#stats");
    if(!rows.consume.length)add("consume","No immediate consumable suggestion","Check current bars, cooldowns, inventory and planned training before consuming items.","#stats");
    rows.crime.push(crimeRecommendation("low",completion));
    loadEducationPreference();
    const m=educationModel();
    if(m.known&&m.courses.length){
      const groups=educationPaths.filter(([name])=>name!=="Other Perks");
      const preferred=educationView.groupBy==="effect"&&educationView.effect!=="all"?educationView.effect:null;
      const weights={"Gym Perks":growth?5:1,"Passive Battle Stats":activities.some(x=>["War","Mug"].includes(x))?4:1,"Company Perks":prefs.priority==="company"||activities.includes("Business")?5:0,"Crime Perks":activities.some(x=>["Crime","OC"].includes(x))?5:1,"Jail Perks":activities.includes("Jail")?5:0,"Medical Perks":activities.includes("Revive")?5:0,"Attacking Perks":activities.some(x=>["War","Mug"].includes(x))?4:0};
      const ranked=m.courses.filter(c=>!m.ids.has(String(c.id))&&String(c.id)!==String(m.id)).map(c=>{
        const effect=educationEffectText(c),code=educationCode(c);
        const req=c.prerequisites??c.requirements;
        const ids=Array.isArray(req)?req.map(x=>String(typeof x==="object"?x.id??x.course_id:x)):null;
        const unmet=ids&&ids.some(id=>!m.ids.has(id));
        const matches=([name,codes,pattern])=>codes.split(" ").includes(code)||pattern?.test(effect);
        const score=preferred?(preferred==="Other Perks"?Number(!groups.some(matches)):Number(groups.some(g=>g[0]===preferred&&matches(g)))*100):groups.reduce((sum,g)=>sum+(matches(g)?(weights[g[0]]||0):0),0);
        return {c,effect,score,unmet};
      }).filter(x=>!x.unmet&&x.score>0).sort((a,b)=>b.score-a.score);
      for(const x of ranked.slice(0,3))add("education",x.c.name??x.c.title??"Course",x.effect+" · Verify enrollment prerequisites in Torn","#education");
    }
    if(!rows.education.length)add("education",growth?"Prioritize Sports Science / education reductions":"Prioritize Business or useful income-related courses","Course completion or prerequisites may be unavailable. Open Education to compare available courses.","#education");
    const money=payload("money","money"),wallet=n(money?.wallet??money?.cash),bank=n(money?.city_bank?.amount??money?.city_bank),cayman=n(money?.cayman_bank?.amount??money?.cayman_bank);
    const stocks=stockRows(),company=prefs.priority==="company"||activities.includes("Business"),education=prefs.priority==="education";
    const financialRisk={
      low:{travel:"Prefer short trips, carry only the purchase amount, and keep spare cash protected.",trade:"Prefer small transactions and trusted counterparties; avoid holding large sale proceeds in your wallet.",mug:"Prefer targets with well-understood combat and retaliation risk; account for Energy opportunity cost.",gamble:"Avoid gambling as an income strategy; preserve training and investment funds."},
      medium:{travel:"Compare profit per hour on short and longer routes; limit carried cash to planned purchases.",trade:"Consider moderately sized trades with verified prices, safe settlement and a predefined exposure limit.",mug:"Compare likely net proceeds with Energy, medical costs and retaliation risk; avoid uncertain targets.",gamble:"Treat gambling only as entertainment with a separate fixed loss limit; never use essential funds."},
      high:{travel:"Consider longer routes or higher-value cargo only when net profit justifies time and exposure; protect reserves.",trade:"Consider larger trades and price volatility within a predefined loss limit; verify settlement and liquidity.",mug:"Consider higher-variance opportunities only after checking combat odds, protection and retaliation; preserve reserves.",gamble:"High financial risk tolerance does not improve gambling odds. Use a separate entertainment limit and never chase losses."}
    }[risk]??{};
    if(activities.includes("Travel"))add("money","Travel · financial exposure",financialRisk.travel,"#money");
    if(activities.includes("Trade"))add("money","Trading · settlement and cash",financialRisk.trade,"#money");
    if(activities.includes("Mug"))add("money","Mugging · expected net return",financialRisk.mug,"#attacking");
    if(activities.includes("Gambling"))add("money","Gambling · loss limit",financialRisk.gamble,"#money");
    const options=stocks.filter(x=>x.shares!==null&&x.nextCost>0&&(x.nextRoi!=null||["TCP","TGP","TCI","WSU"].includes(x.ticker))).map(x=>{
      const strategic=(company&&["TCP","TGP"].includes(x.ticker)?100:0)+(education&&x.ticker==="WSU"?100:0)+(x.ticker==="TCI"?35:0)+(growth&&x.ticker==="WSU"?50:0);
      const history=tornInvestmentHistory.get(x.ticker,x.price);
      const timing=history?(history.year<=.15?45:history.month<=.15?25:history.month>=.85?-30:0):0;
      return {...x,strategic,history,score:strategic+timing+Math.min(50,x.nextRoi??0)};
    }).sort((a,b)=>b.score-a.score);
    for(const stock of options.slice(0,5)){
      const timing=stock.history?" · 30d "+Math.round(stock.history.month*100)+"% of range · 1y "+Math.round(stock.history.year*100)+"% of range":" · Historical price unavailable";
      const action=stock.history?.month>=.85&&stock.strategic>=100?"Watch / wait for entry: ":"";
      add("money",action+stock.ticker+" · "+stock.description,"$"+number(Math.round(stock.nextCost))+" to next block"+(stock.nextRoi==null?"":" · "+stock.nextRoi.toFixed(1)+"% annual marginal dividend ROI")+timing+(wallet!==null&&wallet<stock.nextCost?" · Not affordable from wallet alone":""),"#stocks");
    }
    if(bank!==null&&bank<2000000000)add("money","City bank · "+number(2000000000-bank)+" capacity remaining","Compare the available investment term and current rate before depositing.","#money");
    if(cayman>0)add("money","Cayman bank · $"+number(cayman),"Existing deposit; compare withdrawal availability with investment requirements.","#money");
    if(!options.length)add("money","Investment data unavailable","Open Stocks to load prices and holdings.","#stocks");
    return recommendationTypes.filter(([id])=>id!=="restock"&&recEnabled.has(id)).map(([id,label])=>'<section class="rec-tile" data-rec-group="'+id+'"><h3>'+esc(label)+'</h3>'+(id==="crime"?'<div class="rec-oc-filters"><button class="rec-oc-toggle" data-rec-incomplete type="button" aria-pressed="'+recIncomplete+'">&lt;100 only</button></div>':id==="money"?'<div class="rec-oc-filters"><button class="rec-oc-toggle" type="button" data-rec-history>Refresh price history</button><small>Public Tornsy data, no Torn key</small></div>':"")+'<ul class="crime-recommendations rec-advice">'+rows[id].join("")+'</ul></section>').join("");
  }

  function recommendations(){
    loadOcFilters();loadRecFilters();
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
      if(!ocEnabled.has(level%2?level:level-1))continue;
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
    const ocControls='<div class="rec-oc-filters" role="group" aria-label="Optional OC difficulty">'+ocLevelBands.map(([lo,hi])=>'<button type="button" class="rec-oc-toggle" data-oc-band="'+lo+'" aria-pressed="'+ocEnabled.has(lo)+'">'+lo+'–'+hi+'</button>').join("")+'</div>';
    const optional='<details class="rec-group" data-oc-optional '+(ocOpen?"open":"")+'><summary>Optional OC supplies by difficulty ('+buckets.oc.size+')</summary>'+ocControls+(buckets.oc.size?'<ul class="crime-recommendations">'+rows(buckets.oc)+'</ul>':'<p class="fine-print">'+(ocEnabled.size?"No additional shortages identified for selected levels.":"Select a difficulty range.")+'</p>')+'</details>';
    const total=[...Object.values(buckets)].reduce((n,g)=>n+g.size,0);
    const pending=tornGuideApi.inventoryTypes.filter(c=>!ready(c));
    const controls='<div class="rec-type-toggles" role="group" aria-label="Recommendation types">'+recommendationTypes.map(([id,label])=>'<button type="button" class="rec-oc-toggle" data-rec-type="'+id+'" aria-pressed="'+recEnabled.has(id)+'">'+esc(label)+'</button>').join("")+'</div>';
    const restock=recEnabled.has("restock")?'<section class="rec-tile" data-rec-group="restock"><h3>Restock</h3>'+section("Assigned OC requirements",buckets.current,true)+section("Low consumable reserves",buckets.stock,true)+section("Crime equipment & materials",buckets.crime,true)+optional+(!total?'<p>No shortages identified in loaded inventory.</p>':"")+(pending.length?'<p class="fine-print">Inventory unavailable: '+esc(pending.join(", "))+'</p>':"")+'</section>':"";
    const priority=tornRoadmap.preferences().priority,first={growth:["growth","consume"],completion:["crime","merit"],networth:["money"],company:["money","education"],education:["education"]}[priority]??[];
    return '<section class="home-recommendations" data-home-recommendations><nav class="rec-titlebar" aria-label="Recommendation filters">'+controls+'</nav><div class="rec-tile-grid" data-rec-priority="'+esc(first.join(","))+'">'+restock+adviceSections(count)+(!recEnabled.size?'<p class="fine-print">Select recommendation types above.</p>':"")+'</div></section>';
  }

  // Keep independent tile heights while retaining the existing priority order.
  let recMasonryObserver=null,recMasonryGrid=null,recMasonryFrame=0;
  function layoutRecommendations(view){
    const grid=view.querySelector(".rec-tile-grid");
    if(grid===recMasonryGrid&&grid?.isConnected)return;
    recMasonryObserver?.disconnect();
    if(recMasonryFrame)cancelAnimationFrame(recMasonryFrame);
    recMasonryFrame=0;recMasonryGrid=grid;
    if(!grid||typeof ResizeObserver==="undefined")return;
    const tiles=[...grid.querySelectorAll(":scope > .rec-tile")];
    if(!tiles.length)return;
    const pack=()=>{
      if(!grid.isConnected)return;
      const gap=parseFloat(getComputedStyle(grid).columnGap)||10;
      const heights=tiles.map(tile=>Math.ceil(tile.getBoundingClientRect().height+gap));
      if(heights.some(h=>h<=gap))return;
      for(let i=0;i<tiles.length;i++){
        const span="span "+heights[i];
        if(tiles[i].style.gridRowEnd!==span)tiles[i].style.gridRowEnd=span;
      }
      grid.classList.add("rec-masonry");
    };
    const schedule=()=>{if(!recMasonryFrame)recMasonryFrame=requestAnimationFrame(()=>{recMasonryFrame=0;pack();});};
    recMasonryObserver=new ResizeObserver(schedule);
    for(const tile of tiles)recMasonryObserver.observe(tile);
    pack();
  }
  function refreshRecommendations(view){
    const panel=view.querySelector("[data-home-recommendations]");if(!panel)return;
    const opened=[...panel.querySelectorAll(".rec-group")].map(el=>[el.querySelector("summary")?.textContent?.replace(/ \(\d+\)$/,""),el.open]);
    panel.outerHTML=recommendations();
    const fresh=view.querySelector("[data-home-recommendations]");
    for(const el of fresh?.querySelectorAll(".rec-group")||[]){
      const name=el.querySelector("summary")?.textContent?.replace(/ \(\d+\)$/,"");
      const prior=opened.find(([key])=>key===name);if(prior)el.open=prior[1];
    }
    layoutRecommendations(view);
  }
  function wireRecommendations(view){
    layoutRecommendations(view);
    if(view.dataset.ocRecommendationsBound==="1")return;
    view.dataset.ocRecommendationsBound="1";
    view.addEventListener("toggle",e=>{
      if(e.target.matches?.("[data-oc-optional]")&&e.target.isConnected)ocOpen=e.target.open;
    },true);
    view.addEventListener("click",e=>{
      const btn=e.target.closest("[data-oc-band],[data-rec-type],[data-rec-incomplete],[data-rec-history],[data-rec-crime-load]");
      if(!btn||!btn.closest("[data-home-recommendations]"))return;
      if(btn.hasAttribute("data-rec-crime-load")){
        btn.disabled=true;btn.textContent="Loading…";
        tornGuideApi.loadCrimeProgress(Number(btn.dataset.recCrimeLoad)).then(()=>refreshRecommendations(view)).catch(error=>{if(btn.isConnected){btn.disabled=false;btn.textContent="Retry crime progress";btn.title=error.message;}});return;
      }
      if(btn.hasAttribute("data-rec-incomplete")){recIncomplete=!recIncomplete;try{localStorage.setItem("torn-city-guide:crime-incomplete:"+recOwner,String(recIncomplete));}catch{}refreshRecommendations(view);return;}
      if(btn.hasAttribute("data-rec-history")){btn.disabled=true;tornInvestmentHistory.refresh().finally(()=>{if(location.hash==="#home")refreshRecommendations(view);});return;}
      if(btn.dataset.recType){
        const id=btn.dataset.recType;
        if(recEnabled.has(id))recEnabled.delete(id);else recEnabled.add(id);
        try{localStorage.setItem("torn-city-guide:rec-types:"+recOwner,JSON.stringify([...recEnabled]));}catch{}
        refreshRecommendations(view);
        view.querySelector('[data-rec-type="'+id+'"]')?.focus();return;
      }
      const band=Number(btn.dataset.ocBand);
      if(ocEnabled.has(band))ocEnabled.delete(band);else ocEnabled.add(band);
      ocOpen=true;
      try{localStorage.setItem("torn-city-guide:oc-bands:"+ocOwner,JSON.stringify([...ocEnabled]));}catch{}
      refreshRecommendations(view);
      view.querySelector('[data-oc-band="'+band+'"]')?.focus();
    });
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
  return {render,crimes,syncNerve,recommendations,wireRecommendations,refreshRecommendations};
})();
