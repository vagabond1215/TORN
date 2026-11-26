"use strict";
const tornCrimeGuide = (() => {
  const crimes = [
    ["Search for Cash","Starter","Start here; prioritize high-opportunity searches and find useful crime tools."],
    ["Bootlegging","Starter","Copy DVDs safely first; selling offers faster skill but more risk."],
    ["Graffiti","Low","Very reliable CE/NNB builder. Build reputation and use spray cans."],
    ["Shoplifting","Low–Medium","Choose stores and security windows; higher-risk targets can cause setbacks."],
    ["Card Skimming","Low–Medium","Passive side project. Install skimmers and collect after details accumulate."],
    ["Pickpocketing","Variable",""],
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
  function reservePurchase(item,marketPrice){
    if(!item||["blankdvds50","blankdvds100"].includes(normalize(item.name)))return null;
    if(marketPrice!==null&&item.is_tradable!==false)return {price:marketPrice,source:"Market value"};
    const shops=item.value?.shops;
    const prices=[item.buy_price,item.value?.buy_price,...(Array.isArray(shops)?shops.map(shop=>shop?.buy_price):[])]
      .map(Number).filter(price=>Number.isFinite(price)&&price>0);
    return prices.length?{price:Math.min(...prices),source:"Shop buy price"}:null;
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
    ["Search for Cash","Lost and Found Office Key|Bucket",1,"Equipment"],
    ["Bootlegging","Blank DVDs",1,"Consumable"],
    ["Graffiti","Spray Paint : Black|Spray Paint : Blue|Spray Paint : Green|Spray Paint : Orange|Spray Paint : Pink|Spray Paint : Purple|Spray Paint : Red|Spray Paint : White",3,"Consumable"],
    ["Card Skimming","Card Skimmer",5,"Equipment"],
    ["Disposal","Double Cut File|Handkerchief|Wheelbarrow|Shovel",1,"Equipment"],
    ["Disposal","Anchor|Bleach|Disposable Mask|Gasoline|Hydrochloric Acid|Lye|Paper Towels|Rope",2,"Consumable"],
    ["Burglary","Lockpicks|Rope",1,"Tool"],
    ["Cracking","Computer Fan|CPU|ECPU|HPCPU|Heat Sink",1,"Equipment"],
    ["Forgery","Card Programmer|Crucible|Embosser|Fountain Pen|Graver|Grinding Stone|Hand Drill|Hole Punch|Hot Foil Stamper|Lump of Coal|Perforator|Permanent Marker|Polishing Pad|Printer|Scissors|Sewing Kit|Thimble|Wax Seal Stamp",1,"Equipment"],
    ["Forgery","Adhesive Plastic|Aluminum Plate|Bank Statement|Binder|Bond Paper|Bonded Latex|Brass Ingot|Candle|Cardstock|Certificate Seal|Crushed Enamel|Glow Stick|Glue|Inkwell|Lanyard|Medical Bill|PVC Cards|Picture Frame|Toner",3,"Consumable"],
    ["Arson","Diesel|Fire Extinguisher|Gasoline|Hydrogen Tank|Kerosene|Magnesium Shavings|Methane Tank|Oxygen Tank|Potassium Nitrate|Sand|Thermite",3,"Consumable"]
  ];
  const reusableCrimeItems=new Set(ocReference.flatMap(([, , tools])=>tools.split("|").filter(Boolean).map(normalize)));
  const consumedCrimeItems=new Set(ocReference.flatMap(([, , , materials])=>materials.split("|").filter(Boolean).map(normalize)));
  function categoryStockDefault(name,category){
    if(!["Tool","Enhancer","Material"].includes(category))return 0;
    const key=normalize(name);
    if(key==="blankdvds")return 1;
    if(consumedCrimeItems.has(key))return 3;
    return category==="Material"&&!reusableCrimeItems.has(key)?3:1;
  }
  const reserveDefaults=[
    ["Xanax","Drug",12],["Ecstasy","Drug",2],["Erotic DVD","Booster",5],
    ["Small First Aid Kit","Medical",20],["First Aid Kit","Medical",10],["Morphine","Medical",10]
  ];
  const ocLevelBands=[[1,2],[3,4],[5,6],[7,8],[9,10]];
  let ocEnabled=new Set(ocLevelBands.map(([lo])=>lo));
  let ocOwner=null,restockTab="urgent",restockForecastDays=7,restockRules=new Map();
  const restockSettingsKey=owner=>"torn-city-guide:restock-settings:"+owner;
  function loadOcFilters(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(owner===ocOwner)return;
    ocOwner=owner;restockTab="urgent";restockForecastDays=7;restockRules=new Map();ocEnabled=new Set(ocLevelBands.map(([lo])=>lo));
    try{
      const settings=JSON.parse(localStorage.getItem(restockSettingsKey(owner)));
      if(Number.isInteger(settings?.forecastDays)&&settings.forecastDays>=1&&settings.forecastDays<=28)restockForecastDays=settings.forecastDays;
      if(Array.isArray(settings?.items)){
        for(const rule of settings.items){
          if(typeof rule?.key==="string"&&typeof rule.monitored==="boolean"&&
            (rule.minimum===null||(Number.isSafeInteger(rule.minimum)&&rule.minimum>=0)))restockRules.set(rule.key,rule);
        }
      }
      const stored=settings?.ocBands??JSON.parse(localStorage.getItem("torn-city-guide:oc-bands:"+owner));
      if(Array.isArray(stored))ocEnabled=new Set(stored.filter(v=>ocLevelBands.some(([lo])=>lo===v)));
    }catch{}
  }
  function restockSettings(categories){
    const groups=[...categories].sort(([a],[b])=>a.localeCompare(b)).map(([category,items])=>{
      const rows=[...items.values()].sort((a,b)=>a.name.localeCompare(b.name)).map(item=>{
        const rule=restockRules.get(item.key),monitored=rule?.monitored??item.target>0;
        return '<div class="restock-setting-row" data-restock-item="'+esc(item.key)+'" data-initial-monitor="'+monitored+'" data-default-monitor="'+(item.target>0)+'">'+
          '<label><input type="checkbox" data-restock-monitor '+(monitored?"checked":"")+'> '+esc(item.name)+'</label>'+
          '<input type="number" data-restock-minimum min="0" max="'+Number.MAX_SAFE_INTEGER+'" step="1" value="'+(rule?.minimum??"")+
          '" placeholder="'+(item.target||1)+'" aria-label="'+esc("Minimum stock for "+item.name)+'"></div>';
      }).join("");
      return '<details class="restock-settings-category"><summary>'+esc(category)+' ('+items.size+')</summary>'+
        '<div class="restock-settings-actions"><button type="button" data-restock-all="true">Select all</button><button type="button" data-restock-all="false">Deselect all</button></div>'+rows+'</details>';
    }).join("");
    return '<template data-restock-dialog><dialog class="restock-settings-dialog" aria-labelledby="restock-settings-title"><form>'+
      '<header><h2 id="restock-settings-title">Restock settings</h2><button type="button" data-restock-close aria-label="Close">×</button></header>'+
       '<div class="restock-settings-content"><label class="restock-forecast">Urgent forecast (days) <input name="forecastDays" type="number" min="1" max="28" step="1" required value="'+restockForecastDays+'"></label><fieldset><legend>Optional OC difficulty</legend><div class="rec-oc-filters">'+
      ocLevelBands.map(([lo,hi])=>'<label><input type="checkbox" name="ocBand" value="'+lo+'" '+(ocEnabled.has(lo)?"checked":"")+'> '+lo+'–'+hi+'</label>').join("")+
      '</div></fieldset><p class="fine-print">Leave a minimum blank to use the suggested quantity. Training and assigned OC requirements are always checked.</p>'+groups+
      '</div><footer><span role="status" data-restock-status></span><button type="submit">Save settings</button></footer></form></dialog></template>';
  }
  function openRestockSettings(view,button){
    if(document.querySelector(".restock-settings-dialog[open]"))return;
    const template=view.querySelector("[data-restock-dialog]");
    const dialog=template?.content.firstElementChild.cloneNode(true);
    if(!dialog)return;
    const owner=ocOwner;
    document.body.append(dialog);
    dialog.addEventListener("click",event=>{
      if(event.target.closest("[data-restock-close]"))dialog.close();
      const bulk=event.target.closest("[data-restock-all]");
      if(bulk)for(const control of bulk.closest("details").querySelectorAll("[data-restock-monitor]"))control.checked=bulk.dataset.restockAll==="true";
    });
    dialog.addEventListener("close",()=>{
      dialog.remove();
      (button.isConnected?button:view.querySelector("[data-restock-settings]"))?.focus();
    },{once:true});
    dialog.querySelector("form").addEventListener("submit",event=>{
      event.preventDefault();
      if(owner!==String(tornGuideApi.state.identity?.id??"guest")){dialog.close();return;}
      const items=new Map(restockRules);
      for(const row of dialog.querySelectorAll("[data-restock-item]")){
        const key=row.dataset.restockItem,monitored=row.querySelector("[data-restock-monitor]").checked;
        const value=row.querySelector("[data-restock-minimum]").value;
        const minimum=value===""?null:Number(value);
        if(monitored===(row.dataset.initialMonitor==="true")&&minimum===(items.get(key)?.minimum??null))continue;
        if(minimum===null&&monitored===(row.dataset.defaultMonitor==="true"))items.delete(key);
        else items.set(key,{key,monitored,minimum});
      }
      const values=new FormData(event.currentTarget);
      const bands=new Set(values.getAll("ocBand").map(Number)),forecastDays=Number(values.get("forecastDays"));
      try{writeAccountValue(restockSettingsKey(owner),JSON.stringify({items:[...items.values()],ocBands:[...bands],forecastDays}));}
      catch{dialog.querySelector("[data-restock-status]").textContent="Settings could not be saved.";return;}
      restockRules=items;ocEnabled=bands;restockForecastDays=forecastDays;
      dialog.close();
      refreshRecommendations(view);
    });
    dialog.showModal();
  }
  const recommendationTypes=[["restock","Restock"],["growth","Energy"],["calendar","Calendar"],["consume","Use & Collect"],["crime","Crime"],["education","Education"],["money","Money"]];
  let recIncomplete=true,recUniques=false,incompleteUniquesOnly=true,crimeOverride="auto";
  let recOwner=null,recEnabled=new Set(recommendationTypes.map(([id])=>id)),recExpanded=new Set();
  function loadRecFilters(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(recOwner===owner)return;
    recOwner=owner;incompleteUniquesOnly=true;try{incompleteUniquesOnly=localStorage.getItem("torn-city-guide:crime-incomplete-uniques:"+owner)!=="false";}catch{}crimeOverride="auto";try{const saved=localStorage.getItem("torn-city-guide:crime-override:"+owner);if(crimes.some(([name])=>name===saved))crimeOverride=saved;}catch{}growthTab="summary";try{const saved=localStorage.getItem("torn-city-guide:growth-tab:"+owner);if(["summary","steps","build","collapsed"].includes(saved))growthTab=saved;}catch{}recExpanded=new Set();try{const saved=JSON.parse(localStorage.getItem("torn-city-guide:rec-expanded:"+owner));if(Array.isArray(saved))recExpanded=new Set(saved.filter(id=>recommendationTypes.some(([key])=>key===id)));}catch{}recIncomplete=true;recUniques=false;try{recIncomplete=localStorage.getItem("torn-city-guide:crime-incomplete:"+owner)!=="false";recUniques=localStorage.getItem("torn-city-guide:crime-uniques:"+owner)==="true";}catch{}recEnabled=new Set(recommendationTypes.map(([id])=>id));
    try{const v=JSON.parse(localStorage.getItem("torn-city-guide:rec-types:"+owner));if(Array.isArray(v)){recEnabled=new Set(v.filter(id=>recommendationTypes.some(([key])=>key===id)));if(!v.includes("calendar")&&localStorage.getItem("torn-city-guide:calendar-introduced:"+owner)!=="true"){recEnabled.add("calendar");writeAccountValue("torn-city-guide:rec-types:"+owner,JSON.stringify([...recEnabled]));writeAccountValue("torn-city-guide:calendar-introduced:"+owner,"true");}}}catch{}
  }
  let growthSettingsOpen=false;
  function excludeOwned(){try{return localStorage.getItem("torn-city-guide:growth-exclude-owned:"+String(tornGuideApi.state.identity?.id??"guest"))!=="false";}catch{return true;}}
  const recGearIcon='<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.09a2 2 0 0 1 1 1.73v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.38a2 2 0 0 0-.73-2.73l-.15-.09a2 2 0 0 1-1-1.74v-.51a2 2 0 0 1 1-1.73l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>';
  const recRefreshIcon='<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 7v5h-5M4 17v-5h5M5.5 8a7 7 0 0 1 11.6-2L20 12M4 12l2.9 6A7 7 0 0 0 18.5 16"/></svg>';
  const recRoutes={restock:"#inventory",growth:"#stats",calendar:"#calendar",consume:"#inventory",crime:"#crime",education:"#education",money:"#stocks"};
  const recIconButton=(label,icon,attributes="",available=true)=>'<button type="button" class="rec-header-button" aria-label="'+esc(label)+'" title="'+esc(label+(available?"":" (not configured)"))+'" '+attributes+(available?"":" disabled")+'>'+icon+'</button>';
  function energyWarSettings(){
    const defaults={mode:"scheduled",adjustment:60,lead:120};
    try{
      const data=JSON.parse(localStorage.getItem("torn-city-guide:energy-war:"+recOwner));
      if(!data)return defaults;
      const bounded=(value,min,max,fallback)=>Number.isInteger(value)?Math.max(min,Math.min(max,value)):fallback;
      return {mode:["off","scheduled","faction"].includes(data.mode)?data.mode:defaults.mode,
        adjustment:bounded(data.adjustment,-120,120,60),lead:bounded(data.lead===2&&!data.version?120:data.lead,0,120,120)};
    }catch{return defaults;}
  }
  function autoTrainingWatch(){
    try{return localStorage.getItem("torn-city-guide:growth-watch:"+String(tornGuideApi.state.identity?.id??"guest"))!=="false";}catch{return true;}
  }
  function growthSettings(){
    if(!growthSettingsOpen)return "";
    const war=energyWarSettings();
    return '<div class="growth-settings-panel"><label><input type="checkbox" data-growth-watch '+(autoTrainingWatch()?"checked":"")+'> Automatically detect completed training actions</label><small>Read-only Torn API checks while an active Energy plan is open. No game actions are performed.</small><label><input type="checkbox" data-growth-exclude-owned '+(excludeOwned()?"checked":"")+'> Inventory value not counted toward budget</label>'+
      '<small>Only additional purchases count when enabled. Points refills remain priced; unverified inventory is not credited.</small>'+
      '<label>War mode <select data-energy-war="mode">'+[["scheduled","Scheduled ranked wars"],["faction","Only wars with a published mode"],["off","Off"]]
        .map(([id,label])=>'<option value="'+id+'" '+(war.mode===id?"selected":"")+'>'+label+'</option>').join("")+'</select></label>'+
      '<label>Xanax cooldown adjustment (minutes) <input type="number" min="-120" max="120" step="1" value="'+war.adjustment+'" data-energy-war="adjustment"></label>'+
      '<label>Clear cooldown before war (minutes) <input type="number" min="0" max="120" step="1" value="'+war.lead+'" data-energy-war="lead"></label>'+
      '<small>Adjustment applies to a 7-hour Xanax estimate. Default +60 allows 8 hours per dose. Training ends before four cooldowns plus the clearance buffer.</small><button type="button" data-activity-settings>Rehab &amp; activity budget settings</button></div>';
  }

  function recTileStart(id,label,crimeRefreshIds=[]){
    const settings=id==="growth"?recIconButton("Energy settings",recGearIcon,"data-growth-settings"):
      id==="restock"?recIconButton("Restock settings (minimums)",recGearIcon,'data-restock-settings aria-haspopup="dialog"'):
      id==="crime"?recIconButton("Crime settings",recGearIcon,'data-rec-crime-settings aria-haspopup="dialog"'):
      id==="calendar"?recIconButton("Calendar settings",recGearIcon,'data-activity-settings aria-haspopup="dialog"'):
      recIconButton(label+" settings",recGearIcon,"",false);
    const refresh=id==="crime"?recIconButton("Refresh crime progress",recRefreshIcon,'data-rec-crime-load="'+crimeRefreshIds.join(",")+'"',crimeRefreshIds.length>0):
      id==="growth"?recIconButton("Refresh Energy",recRefreshIcon,'data-growth-session="'+(loadTrainingSession()?"refresh":"war-refresh")+'"',!recoveryBusy):
      id==="money"?recIconButton("Refresh price history",recRefreshIcon,"data-rec-history"):
      id==="calendar"?recIconButton("Refresh Calendar",recRefreshIcon,"data-activity-refresh",!recoveryBusy):
      recIconButton("Refresh "+label,recRefreshIcon,"",false);
    const refill=id==="crime"?refillIndicator("nerve"):id==="growth"?refillIndicator("energy"):"";
    return '<details class="rec-tile" data-rec-group="'+esc(id)+'" '+(recExpanded.has(id)?"open":"")+'><summary class="rec-tile-heading"><a class="rec-tile-link" href="'+recRoutes[id]+'" title="Open '+esc(label)+' guide">'+esc(label)+'</a>'+refill+'<span class="rec-header-actions">'+settings+refresh+'</span></summary><div class="rec-tile-body">';
  }
  const recTileEnd='</div></details>';
  const recItem=(title,detail,link)=>'<li><div><strong>'+esc(title)+'</strong><small>'+esc(detail)+'</small></div>'+(link?'<a href="'+esc(link)+'">View</a>':"")+'</li>';
  // Wiki target groups and unique conditions; recommended skill bands are
  // conservative editorial estimates, not a measured success probability.
  const pickTargets=[
    ["Drunk Man",0,"Stumbling|Distracted","Any","Bottle of Beer × 6",true],
    ["Drunk Woman",0,"Stumbling|Distracted","Any","Bottle of Pumpkin Brew × 2",true],
    ["Elderly Man",0,"Walking","Any","Bag of Tootsie Rolls",true],
    ["Elderly Woman",0,"Walking","Any","Opium"],
    ["Homeless Person",0,"Begging|Loitering","Any","Morphine × 4, Soap on a Rope, Brick × 3, Toothbrush"],
    ["Junkie",0,"Stumbling|Loitering","Stumbling","Ecstasy, LSD, PCP, Speed"],
    ["Young Man",0,"Listening to music|On the phone|Walking","Any","Ketamine"],
    ["Young Woman",0,"Distracted|Listening to music|On the phone|Walking","Any","Ecstasy"],
    ["Businessman",1,"Walking|On the phone","Any","Speed × 2"],
    ["Businesswoman",1,"Walking|On the phone","Any","Glasses"],
    ["Jogger",1,"Walking|Jogging","Walking","Can of Crocozade",true],
    ["Laborer",1,"Walking|Distracted|On the phone","Walking","Megaphone"],
    ["Postal Worker",1,"Distracted|Walking","Distracted","Lottery Voucher"],
    ["Student",1,"Listening to music|On the phone|Running|Walking","Any","Laptop, Cannabis, Coin Purse, Cell Phone",true],
    ["Thug",1,"Loitering|Running|Walking","Loitering","PCP, Cut-Throat Razor, Billfold (male target)"],
    ["Classy Lady",2,"On the phone|Walking","On the phone","Pair of High Heels"],
    ["Cyclist",2,"Cycling","Cycling","Mountain Bike",true,100],
    ["Gang Member",2,"Loitering","Loitering","Red, Purple and Blue Spray Cans, Wire Cutters",true],
    ["Rich Kid",2,"Listening to music|On the phone|Walking","Listening to music","Six Pack of Alcohol",true],
    ["Sex Worker",2,"Soliciting|Distracted|On the phone","Soliciting","Thong"],
    ["Mobster",3,"Walking","Walking","Cash reward",true,100],
    ["Police Officer",3,"Running|Walking","Running","Billfold, Police Badge"]
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
  // Game reference data: https://wiki.torn.com/wiki/Burglary and the
  // corresponding crime pages linked in the tile footer. Approximate CS
  // thresholds retain the wiki's question mark. Other unique examples are selective.
  const burglaryTargets=[["Residential",0,[["Beach Hut",1,"Jemmy","Cash"],["Bungalow",1,"Window Breaker","Soap on a Rope, Xanax, Vitamins, Toothbrush",["Soap on a Rope","Xanax","Vitamins","Toothbrush"]],["Mobile Home",1,"Rope","Claymore Mine, Luger, WWII Helmet",["Claymore Mine","Luger","WWII Helmet"]],["Tool Shed",1,"Lockpicks","Flashlight",["Flashlight"]],["Cottage","3?","Window Breaker","Jacket, Lawyer Business Card",["Jacket","Lawyer Business Card"]],["Apartment",14,"Credit Card","Personal Computer, High-Speed Drive, Blank DVDs",["Personal Computer","High-Speed Drive","Blank DVDs"]],["Suburban Home",22,"Window Breaker","Lottery Voucher",["Lottery Voucher"]],["Secluded Cabin",30,"Jemmy","Pack of Cuban Cigars, Windproof Lighter, Cigar Cutter",["Pack of Cuban Cigars","Windproof Lighter","Cigar Cutter"]],["Farmhouse",38,"Window Breaker","Turkey Baster, Bull Semen",["Turkey Baster","Bull Semen"]],["Lake House",46,"Jemmy","Box of Medical Supplies ×2",["Box of Medical Supplies"]],["Luxury Villa","69?","Window Breaker","Persian Rug",["Persian Rug"]],["Manor House",100,"Lockpicks","Chandelier",["Chandelier"]]]],["Commercial",1,[["Funeral Parlor",25,"Lockpicks","Empty Blood Bag, Bone Saw, Bone, Cassock",["Empty Blood Bag","Bone Saw","Bone","Cassock"]],["Market",25,"Jemmy","Fanny Pack",["Fanny Pack"]],["Postal Office",25,"Credit Card","Stamp Collection",["Stamp Collection"]],["Self-Storage Facility",25,"Skeleton Key","Opium ×4",["Opium"]],["Cleaning Agency","29?","Jemmy","Tumble Dryer",["Tumble Dryer"]],["Barbershop","35?","Lockpicks","Cut-Throat Razor",["Cut-Throat Razor"]],["Liquor Store","43?","Skeleton Key","Six Pack of Alcohol",["Six Pack of Alcohol"]],["Dentists Office","47?","Credit Card","Latex Gloves, Gold Tooth ×6",["Latex Gloves","Gold Tooth"]],["Chiropractors","56?","Window Breaker","Xanax ×3",["Xanax"]],["Recruitment Agency","77?","Window Breaker","Jade Buddha, Bowling Trophy",["Jade Buddha","Bowling Trophy"]],["Advertising Agency","100?","Skeleton Key","Can of Damp Valley ×2",["Can of Damp Valley"]]]],["Industrial",2,[["Dockside Warehouse",50,"Lockpicks","Erotic DVD",["Erotic DVD"]],["Farm Storage Unit",50,"Jemmy","Cattle Prod",["Cattle Prod"]],["Shipyard",50,"Jemmy","Anchor",["Anchor"]],["Printing Works","54?","Window Breaker","Hot Foil Stamper",["Hot Foil Stamper"]],["Brewery","60?","Rope","Empty Box, Bottle of Stinky Swamp Punch ×6",["Empty Box","Bottle of Stinky Swamp Punch"]],["Truckyard","68?","Skeleton Key","Can of Munster",["Can of Munster"]],["Old Factory","77?","Window Breaker","Empty Box, Small Explosive Device",["Empty Box","Small Explosive Device"]],["Slaughterhouse","84?","Skeleton Key","Bloody Apron",["Bloody Apron"]],["Paper Mill","91?","Skeleton Key","Cash"],["Foundry","96?","Jemmy","Yasukuni Sword",["Yasukuni Sword"]],["Fertilizer Plant","100?","Lockpicks","Truck Nuts",["Truck Nuts"]]]]];
  const crimeOptions={"Search for Cash":[["Search locations",[["Trash","2 N","Trash collection meter; unique examples: candy (CS 1), Morphine (CS 25)."],["Subway","2 N","Ridership meter; Glasses at rush hour; Card Skimmers with Lost and Found Office Key."],["Junkyard","2 N","Crushing meter; Mountain Bike at CS 5 with rating ≤49%."],["Beach","2 N · Metal Detector","Tide meter; Cemetery Key at CS 50; other unique rewards have tide requirements."],["Cemetery","2 N · Cemetery Key","Groundskeeping status; unique examples at CS 80."],["Fountain","2 N · CS 75","Coin collection meter; Lucky Quarter at CS 80."]]]],"Bootlegging":[["Activities",[["Copy DVDs","2 N","Blank DVDs and computer; build inventory across genres."],["Sell counterfeit DVDs","5 N","Copied stock; unique rewards at CS 55 (ammo), 70 (Lottery Voucher), 85 (Rosary Beads), 100 (eDVD)."],["Online store","10 N · CS 50","Computer and Web Design and Development education."],["Collect funds","1 N","Available once online store is established."]]]],"Graffiti":[["Districts · 3 N per attempt",[["East Side","Initial","Paint Mask CS 35; Residential unlock CS 50; crew at CS 70 / reputation 5."],["West Side","Initial","Ladder CS 15; Red-Light District unlock CS 50."],["North Side","Initial","Wire Cutters CS 25; crew at CS 70 / reputation 5; points CS 95."],["Residential District","East Side unique","Reputation-tier cash uniques; additional cash unique at CS 100."],["Red-Light District","West Side unique","Reputation-tier rewards; crew access at CS 70 / reputation 5."],["Financial District","Crew access","Reputation 2: Card Skimmers ×25; reputation 5: Neumune Tablet."],["City Centre","Crew access","Reputation 1: High-Speed Drive and DVDs; reputation 5: $500,000."]]]],"Shoplifting":[["Stores · selected unique examples",[["Sally's Sweet Shop","Security meter","Jawbreaker: CS 20, camera disabled."],["Bits 'n' Bobs","Security meter","Cut-Throat Razor + Shaving Foam: CS 1; Flashlight: CS 20; Duct Tape: CS 30, camera disabled; Mountain Bike: CS 90."],["TC Clothing","Cameras / checkpoints","Raincoat: CS 20, checkpoint disabled; Scissors + Tailor's Dummy: CS 40, camera disabled."],["Super Store","Security meter","DSLR Camera: CS 1, checkpoint disabled."],["Pharmacy","Cameras / checkpoints","Melatonin CS 5, cameras active; Tyrosine CS 10, cameras off / checkpoint active."],["Cyber Force","Cameras / guard","RF Detector CS 1, cameras disabled; Office Chair CS 60 (reported), guard off duty."],["Jewelry Store","Cameras / guard","Gold Teeth CS 20, guard active; Diamond Ring + Latex Gloves CS 40, guard active."],["Big Al's Gun Shop","Cameras / guards","Full Body Armor CS 1, cameras off / guards on break."]]]],"Card Skimming":[["Locations · install 6 N",[["Bus Station","CS 1",""],["Subway Station","CS 1",""],["College Campus","CS 1",""],["Post Office","CS 1",""],["Gas Station","CS 25",""],["Airport Terminal","CS 50",""],["Casino Lobby","CS 75",""],["Bank Branch","CS 100",""]]],["Actions",[["Install","Card Skimmer + Spy Camera","One pair per location."],["Recover","Live risk / collected details","Equipment returns after successful recovery."],["Sell details","Collected records","No documented unique rewards."]]]],"Hustling":[["Games",[["Cornhole","2 N","Technique progression"],["Snail Racing","2 N","Technique progression"],["Find The Lady","2 N","Technique progression"],["Shell Game","2 N","Technique progression"]]],["Audience actions",[["Gather / demonstrate / persuade","Audience interest","Review current audience and interest."],["Play to win / lose","Game technique","Review in-game suspicion and interest."],["Shill","CS 60","Optional assistant."],["Pickpocket","CS 80","Optional assistant."]]]],"Disposal":[["Daily jobs",[["Building Debris","Unique available","LSD, Vicodin, Xanax, Permanent Markers"],["Old Furniture","Unique available","Hard Drive, eCPU, CPU, HPCPU"],["Documents","Unique available","Box of Medical Supplies ×2"],["Broken Appliance","Unique available","Stash Box"],["Firearm","Unique available","M249 SAW"],["Murder Weapon","Unique available","Diamond Bladed Knife"],["Industrial Waste","Unique available","Special ammo"],["General Waste","Unique available","Assorted candy"],["Body Part","Unique available","Combat Gloves"],["Dead Body","Unique available","Epinephrine, Melatonin, Serotonin, Tyrosine"],["Vehicle","Unique available","Cash"],["Biological Waste","Job-specific requirements","No unique listed in the current reference."]]],["In-game overview",[["Daily reset","00:00 TCT","Review available jobs, in-game methods and equipment; one attempt per job."]]]],"Cracking":[["In-game jobs",[["Password targets","4–10 characters","Review target complexity, encryption and progress."],["Rig","CS 1","Computer or laptop."],["Additional chassis","CS 25 / 50 / 75","Review the rig's displayed capacity."],["Brute force","7 N","Use the in-game action; no documented uniques."]]]],"Forgery":[["Project unlocks",[["CS 1","Starter projects","Driver's License, Parking Permit, Concert Ticket, Collection Bucket"],["CS 25","Intermediate projects","Diploma, Birth Certificate, License Plate, Ordination Certificate, Court Order"],["CS 50","Advanced projects","Skeleton Key, Prescription, Travel Visa, ID Badge, Medical License"],["CS 75","Advanced projects","Bank Check, Police Badge, ATM Key, Passport, Government Contract"]]],["Preparation",[["Project requirements","Varies by project","Review the in-game material list, timers and risk before starting."]]]],"Scamming":[["In-game campaign unlocks",[["Delivery / Family / Prize","CS 1",""],["Charity / Tech support","CS 20",""],["Vacation / Tax","CS 40",""],["Advance-fee / Job","CS 60",""],["Romance / Investment","CS 80",""]]],["Activities",[["Addresses / campaigns / responses","In-game progress","Review current campaign and target indicators; no documented uniques."]]]],"Arson":[["In-game job types",[["Small targets","Job-specific","Review target size and job objectives."],["Larger targets","Job-specific","Review difficulty and requirements."],["Unique contracts","16 documented","Unique jobs have a special marker; review the job's listed reward and unlock."],["Collect","2 N","Collect completed contract payment."]]]]};
  function crimeItemStatus(name){
    const st=tornGuideApi.state,raw=payload("itemCatalog","items");
    const catalog=Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
    const item=catalog.find(x=>normalize(x.name)===normalize(name));
    const match=x=>normalize(x.name??x.item?.name)===normalize(name)||item&&String(x.id??x.item_id??x.item?.id)===String(item.id);
    for(const [category,items] of Object.entries(st.inventory??{}))
      if(Array.isArray(items)&&!st.inventoryErrors?.[category]&&items.some(x=>match(x)&&Number(x.amount??x.quantity??1)>0))return "owned";
    const cat=item?.type??item?.category;
    return typeof cat==="string"&&Array.isArray(st.inventory?.[cat])&&!st.inventoryErrors?.[cat]?"missing":"unknown";
  }
  function burglaryCollected(){
    const uniques=crimeProgress("Burglary")?.uniques;
    if(!Array.isArray(uniques))return new Set();
    const raw=payload("itemCatalog","items"),catalog=Array.isArray(raw)?raw:Object.entries(raw||{}).map(([id,x])=>({...x,id:x.id??id}));
    const signature=names=>[...new Set(names.map(normalize))].sort().join("|");
    const targets=burglaryTargets.flatMap(([, ,rows])=>rows).filter(row=>row[4]);
    const matches=new Map();
    for(const row of targets){const key=signature(row[4]);matches.set(key,[...(matches.get(key)??[]),row[0]]);}
    const collected=new Set();
    for(const u of uniques){
      const items=u.rewards?.items;
      if(!Array.isArray(items)||!items.length)continue;
      const names=items.map(x=>x.name??catalog.find(i=>String(i.id)===String(x.id??x.item_id))?.name);
      if(names.some(x=>!x))continue;
      const candidates=matches.get(signature(names));
      if(candidates?.length===1)collected.add(candidates[0]);
    }
    return collected;
  }
  function burglaryRows(cs,risk,only,allCollected){
    const maxTier={low:0,medium:1,high:2}[risk]??0,known=burglaryCollected();
    const groups=burglaryTargets.filter(([,tier])=>tier<=maxTier).map(([group,tier,targets])=>{
      const rows=targets.filter(([name])=>!only||!allCollected&&!known.has(name)).map(([name,min,item,reward])=>{
        const done=allCollected||known.has(name),approx=typeof min==="string",level=Number(String(min).replace("?",""));
        const lock=!approx&&cs!=null&&cs<level,owned=crimeItemStatus(item);
        return '<li class="rec-crime-option'+(lock?" is-locked":"")+'"><div class="rec-crime-option-head"><strong class="rec-pick-risk-'+tier+'">'+esc(name)+'</strong><small>'+esc("CS "+min+(lock?" · Locked":""))+'</small></div><div class="rec-crime-option-reward">'+esc(reward)+(done?' <small>Collected</small>':"")+'</div><small>Unique requires '+esc(item)+' · <span data-item-status="'+owned+'">'+esc(owned)+'</span></small></li>';
      });
      return rows.length?'<details class="rec-crime-option-group" open><summary><strong>'+esc(group)+'</strong><small>'+rows.length+' targets</small></summary><ul>'+rows.join("")+'</ul></details>':"";
    }).join("");
    return '<li class="rec-crime-options"><div><strong>Burglary targets</strong><small>District difficulty is an estimate. CS? indicates an unconfirmed unlock. Cash-only and unverified unique matches remain visible.</small>'+(groups||'<small>No incomplete targets at this risk level.</small>')+'</div></li>';
  }
  function crimeOptionRows(name,cs,risk,only,allCollected){
    if(name==="Burglary")return burglaryRows(cs,risk,only,allCollected);
    if(tornCrimeStates.data[name])return tornCrimeStates.render(name,{cs,only,allCollected,uniques:crimeProgress(name)?.uniques,catalog:payload("itemCatalog","items"),itemStatus:crimeItemStatus,owner:String(tornGuideApi.state.identity?.id??"guest")});
    const groups=crimeOptions[name];
    if(!groups)return "";
    return '<li class="rec-crime-options"><div><strong>Available activities &amp; reference options</strong><small>Static in-game reference; check live availability and requirements. Unique examples are not a complete collected-reward list.</small>'+groups.map(([heading,rows])=>'<details class="rec-crime-option-group" open><summary><strong>'+esc(heading)+'</strong></summary><ul>'+rows.map(([label,meta,detail])=>'<li class="rec-crime-option"><div class="rec-crime-option-head"><strong>'+esc(label)+'</strong><small>'+esc(meta)+'</small></div>'+(detail?'<div class="rec-crime-option-reward">'+esc(detail)+'</div>':"")+'</li>').join("")+'</ul></details>').join("")+'</div></li>';
  }
  function crimeRecommendation(risk,completion,refreshIds){
    if(tornGuideApi.crimeVersion?.()===1)return '<li><div><strong>Crimes 1.0 detected</strong><small>Use the legacy crime report; Crimes 2.0 skill and unique recommendations do not apply.</small><a href="https://torn.report/crimes" target="_blank" rel="noopener noreferrer">Old Crimes report</a></div></li>';
    const riskRank={"Starter":0,"Low":0,"Low–Medium":1,"Medium":1,"Variable":1,"Medium–High":2,"High":2};
    const maxRisk={low:0,medium:1,high:2}[risk]??0;
    const all=crimes.map(([name,r,detail],i)=>{const progress=crimeProgress(name),cs=skill(name)??(Number.isFinite(progress?.skill)?progress.skill:null),total=reference.find(x=>x[0]===name)?.[2]??0;return {name,r,detail,i,cs,rank:riskRank[r]??2,total,uniqueCount:Array.isArray(progress?.uniques)?new Set(progress.uniques.map(u=>u.id)).size:null};});
    const allowed=all.filter(x=>x.rank<=maxRisk);
    const manual=all.find(x=>x.name===crimeOverride);
    const card=x=>{
      const ref=reference.find(y=>y[0]===x.name);
      const equipmentText=ref?equipment(ref).filter(y=>!y[3]||x.cs!=null&&x.cs>=y[3]).map(([name,cat])=>name+": "+({true:"owned",false:"missing",null:"unknown"}[inventoryStatus(name,cat)])).join(" · "):"";
      const uniqueText=x.total?x.uniqueCount==null?"Unique collection not loaded":x.uniqueCount+" / "+x.total+" Uniques Collected":"No documented unique outcomes";
      return '<li><div><strong>'+esc(x.name)+(x.cs===null?"":" "+number(x.cs))+'</strong>'+(x.cs===null?'<small>Skill unavailable</small>':"")+(x.name==="Pickpocketing"?"":'<p>'+esc(crimeAdvice[x.name]??x.detail)+'</p>')+'<small>'+esc(uniqueText)+'</small>'+(equipmentText?'<small>'+esc(equipmentText)+'</small>':"")+'</div></li>'+(x.name==="Pickpocketing"?pickpocketRows(x.cs,risk,incompleteUniquesOnly,x.uniqueCount!==null&&x.total>0&&x.uniqueCount>=x.total):crimeOptionRows(x.name,x.cs,risk,incompleteUniquesOnly,x.uniqueCount!==null&&x.total>0&&x.uniqueCount>=x.total));
    };
    if(manual){refreshIds.push(crimeIds[manual.name]);return card(manual);}
    if(recUniques){
      const scope=allowed.filter(x=>!recIncomplete||x.cs!==null&&x.cs<100);
      const unknownSkill=recIncomplete?allowed.filter(x=>x.total>0&&x.cs===null):[];
      const missing=scope.filter(x=>x.total>0&&x.uniqueCount!==null&&x.uniqueCount<x.total).sort((a,b)=>a.rank-b.rank||b.cs-a.cs||a.i-b.i);
      const unknown=scope.filter(x=>x.total>0&&x.uniqueCount===null);
      const shown=incompleteUniquesOnly?missing:scope.filter(x=>x.total>0&&x.uniqueCount!==null).sort((a,b)=>a.rank-b.rank||b.cs-a.cs||a.i-b.i);
      refreshIds.push(...new Set([...shown,...unknown,...unknownSkill].map(x=>crimeIds[x.name])));
      const summary='<li><div><strong>Unique hunt</strong><small>'+missing.length+' crimes with remaining documented uniques · '+unknown.length+' awaiting collection data. '+(recIncomplete?"Only crimes below 100 CS are included.":"CS 100 crimes are included.")+' Check in-game stars and requirements; counts are not a mapping of individual missing rewards.</small></div></li>';
      return summary+shown.map(card).join("")+(unknown.length?'<li><div><strong>Awaiting unique data</strong><small>'+esc(unknown.map(x=>x.name).join(", "))+'</small></div></li>':"")+(unknownSkill.length?'<li><div><strong>Awaiting crime skill data</strong><small>'+esc(unknownSkill.map(x=>x.name).join(", "))+'</small></div></li>':"")+(!missing.length&&!unknown.length&&!unknownSkill.length?'<li><div><strong>No remaining documented uniques in the selected filters.</strong></div></li>':"");
    }
    const eligible=allowed.filter(x=>x.cs!==null&&(!recIncomplete||x.cs<100));
    const rank=(a,b)=>(risk==="low"?a.rank-b.rank:b.cs-a.cs)||a.rank-b.rank||a.i-b.i;
    const chosen=[...eligible].sort((a,b)=>completion&&!recIncomplete?Number(a.cs>=100)-Number(b.cs>=100)||rank(a,b):rank(a,b))[0];
    if(!chosen){
      const unknown=allowed.filter(x=>x.cs===null);
      refreshIds.push(...unknown.map(x=>crimeIds[x.name]));
      return '<li><div><small>'+(unknown.length?"Crime skill data unavailable.":recIncomplete?"No unfinished crimes at this risk level.":"No crimes at this risk level.")+'</small></div></li>';
    }
    refreshIds.push(crimeIds[chosen.name]);return card(chosen);
  }
  function crimeFooter(refreshIds){
    const names=Object.keys(crimeIds).filter(name=>refreshIds.includes(crimeIds[name]));
    const requirements=names.length===1?'<a href="'+wiki(names[0])+'" target="_blank" rel="noopener noreferrer">Unique requirements</a>':
      names.length?'<details class="rec-unique-links"><summary>Unique requirements</summary>'+names.map(name=>'<a href="'+wiki(name)+'" target="_blank" rel="noopener noreferrer">'+esc(name)+'</a>').join("")+'</details>':
      '<a href="https://wiki.torn.com/wiki/Crimes_2.0" target="_blank" rel="noopener noreferrer">Unique requirements</a>';
    return '<footer class="rec-crime-actions rec-crime-footer">'+requirements+'<a href="https://torn.report/uniques" target="_blank" rel="noopener noreferrer">Unique tracker</a></footer>';
  }
  function openCrimeSettings(view,button){
    if(document.querySelector(".crime-settings-dialog[open]"))return;
    const owner=recOwner;
    const dialog=document.createElement("dialog");
    dialog.className="restock-settings-dialog crime-settings-dialog";
    dialog.setAttribute("aria-labelledby","crime-settings-title");
    dialog.innerHTML='<form><header><h2 id="crime-settings-title">Crime settings</h2><button type="button" data-crime-settings-close aria-label="Close settings">×</button></header>'+
      '<div class="crime-settings-content"><label><input type="checkbox" name="incompleteUniques" '+(incompleteUniquesOnly?"checked":"")+'> Incomplete uniques only</label>'+
      '<small>Hide confirmed collected unique rewards. Unverified rewards remain visible. In Uniques mode, completed crimes are also hidden.</small></div>'+
      '<footer><small role="status" data-crime-settings-status></small><button type="submit">Save</button></footer></form>';
    document.body.append(dialog);
    dialog.addEventListener("click",e=>{if(e.target.closest("[data-crime-settings-close]"))dialog.close();});
    dialog.addEventListener("close",()=>{
      dialog.remove();
      (button.isConnected?button:view.querySelector("[data-rec-crime-settings]"))?.focus();
    },{once:true});
    dialog.querySelector("form").addEventListener("submit",e=>{
      e.preventDefault();
      if(owner!==String(tornGuideApi.state.identity?.id??"guest")){dialog.close();return;}
      const value=dialog.querySelector('[name="incompleteUniques"]').checked;
      try{writeAccountValue("torn-city-guide:crime-incomplete-uniques:"+owner,String(value));}
      catch{dialog.querySelector("[data-crime-settings-status]").textContent="Settings could not be saved.";return;}
      incompleteUniquesOnly=value;
      dialog.close();
      refreshRecommendations(view);
      view.querySelector("[data-rec-crime-settings]")?.focus();
    });
    dialog.showModal();
  }
  function crimeFilters(){
    return '<div class="rec-oc-filters"><div class="rec-crime-settings"><button class="rec-oc-toggle" data-rec-incomplete type="button" aria-pressed="'+recIncomplete+'">&lt;100 only</button><button class="rec-oc-toggle" data-rec-uniques type="button" aria-pressed="'+recUniques+'">Uniques</button><select data-rec-crime-override aria-label="Manual crime override" title="Manual crime override"><option value="auto" '+(crimeOverride==="auto"?"selected":"")+'>Auto</option>'+crimes.map(([name])=>'<option value="'+esc(name)+'" '+(crimeOverride===name?"selected":"")+'>'+esc(name)+'</option>').join("")+'</select></div></div>';
  }
  function pickpocketRows(cs,risk,uniqueOnly=false,allCollected=false){
    const maxTier={low:0,medium:1,high:3}[risk]??0;
    const razor=inventoryStatus("Cut-Throat Razor","Enhancer");
    const avoided=uniqueOnly?pickTargets.filter(x=>pickUniqueState(x[0])===true).map(x=>x[0]):[];
    const riskLabels=["Easy","Moderate","Difficult","Very difficult"];
    const rows=pickTargets.filter(x=>x[1]<=maxTier&&!(uniqueOnly&&allCollected)&&!avoided.includes(x[0])).map(([name,tier,states,condition,reward,needRazor,min=1])=>{
      const done=allCollected||pickUniqueState(name)===true;
      const qualifier=done===true?"Collected":[min>1&&(cs==null||cs<min)?"CS "+min+" required":"",needRazor&&razor!==true?"Cut-Throat Razor required":""].filter(Boolean).join(" · ");
      const unique='<span class="rec-pick-reward">'+esc(reward)+(qualifier?' <small>'+esc(qualifier)+'</small>':"")+'</span>';
      const target='<strong class="rec-pick-risk-'+tier+'">'+esc(name)+' <span class="sr-only">('+riskLabels[tier]+' risk)</span></strong>';
      return '<li><div class="rec-pick-target-heading">'+target+(condition==="Any"?unique:"")+'</div>'+
        (condition==="Any"?"":'<dl>'+condition.split("|").map(state=>'<div><dt>'+esc(state)+'</dt><dd>'+unique+'</dd></div>').join("")+'</dl>')+'</li>';
    });
    return '<li class="rec-pickpocket"><div><strong>Recommended targets</strong>'+(rows.length?'<ul class="rec-pick-targets">'+rows.join("")+'</ul>':'<small>No incomplete unique targets at this risk level.</small>')+'</div></li>';
  }
  function currentActivityWar(now=Date.now()){
    const settings=energyWarSettings(),manual=tornActivityScheduler.events().filter(e=>e.kind==="war"&&e.end>now).sort((a,b)=>a.start-b.start)[0],war=rankedWar(now)??(manual?{start:manual.start,end:manual.end,mode:"manual",source:"Manual Calendar war"}:null);
    if(settings.mode==="off"||settings.mode==="faction"&&!war?.mode)return null;
    return tornActivityScheduler.warWindow(war,settings,now);
  }
  function activityLimits(now=Date.now()){
    const war=currentActivityWar(now),limit=tornActivityScheduler.limits({war,now});
    const account=tornTrainSequence.liveAccountStatus(tornGuideApi.state,now);
    return {...limit,war,away:account.away,statusBlocked:account.blocked,blocked:limit.blocked||account.blocked,reason:account.reason??limit.reason};
  }
  function liveOptimizationContext(prefs=tornRoadmap.preferences(),now=Date.now(),{reviewOnly=false}={}){
    loadOcFilters();loadRecFilters();
    const settings=tornActivityScheduler.settings();
    if(!reviewOnly)tornActivityScheduler.reconcileRehab(now);
    const activity=activityLimits(now);
    const health=tornActivityScheduler.addictionSnapshot(now,settings,activity.war),iconFresh=health.fresh;
    const addictionDebuff=health.penalty==null?[]:[health.penalty],highAddiction=health.blockDrugs;
    const edu=educationModel(),enrolled=Boolean((edu.id!=null&&edu.id!==0&&edu.id!=="0"&&edu.id!=="")||(Number(edu.deadline)>now));
    const inputs=tornTrainSequence.liveInputs(tornGuideApi.state,now,tornBarProjection);
    const perks=inputs.sources.perks.ready?payload("perks","perks"):null,jobPerks=Object.entries(perks||{}).filter(([key])=>/job|company/i.test(key)).flatMap(([,v])=>Array.isArray(v)?v:[]).map(x=>typeof x==="string"?x:[x?.name,x?.description,x?.effect].filter(Boolean).join(" "));
    const protectedEducation=jobPerks.some(x=>/\bRestraint\b|education is unaffected by drug addiction|education.*immune.*addiction/i.test(x));
    const educationRisk=enrolled&&!protectedEducation&&health.penalty!=null&&health.penalty>=5;
    const blockDrugs=highAddiction||educationRisk||health.penalty===null;
    const session=loadTrainingSession();
    const remaining=prefs.weeklyBudget==null?null:Math.max(0,prefs.weeklyBudget-trainingSpend(now).reduce((sum,entry)=>sum+entry.cost,0)-(settings.sharedBudget?tornActivityScheduler.weeklySpend(now):0));
    const reserves=tornActivityScheduler.budget(remaining,settings,activity.war,health),budget=reserves.training;
    const warDeadline=activity.war?.cutoff??null;
    const profile=payload("profile","profile"),factionId=Number(profile?.faction_id??profile?.faction?.id);
    if(energyWarSettings().mode!=="off"&&factionId>0&&!inputs.sources.factionWars.ready)
      inputs.criticalIssues.push("Faction war schedule "+inputs.sources.factionWars.status+"; refresh before planning");
    const recoveryHeld=trainingRecoveryHeld();
    if(recoveryHeld)inputs.criticalIssues.push("Restored training session held for manual review");
    const options={blockDrugs:blockDrugs||prefs.odRisk==="low",excludeOwned:excludeOwned(),skipPrograms:recoveryHeld||!!session||activity.blocked||inputs.criticalIssues.length>0,restockForecastDays:recEnabled.has("restock")?restockForecastDays:undefined,naturalOnly:prefs.priority!=="growth",
      deadline:activity.deadline,requireDrugClear:warDeadline!==null&&activity.deadline===warDeadline,warXanaxSeconds:activity.war?Math.max(28800,activity.war.cd/1000):28800,reserveXanax:activity.war&&activity.war.cutoff<now+604800000?4:0,liveInputs:inputs};
    return {now,prefs,settings,session,recoveryHeld,activity,health,iconFresh,addictionDebuff,highAddiction,enrolled,protectedEducation,educationRisk,blockDrugs,budget,reserves,options,inputs};
  }
  function recoveryPreview(stage,reviewed,attested,report,requested){
    if(!trainingRecoveryHeld()||String(tornGuideApi.state.identity?.id)!==stage.playerId||tornTrainingRecovery.readStage(localStorage,stage.playerId)?.raw!==stage.raw)throw Error("Account or recovery record changed");
    const review=tornTrainingRecovery.reviewPrefix(stage,reviewed,attested);
    const now=Date.now(),state=tornGuideApi.state,context=liveOptimizationContext(tornRoadmap.preferences(),now,{reviewOnly:true});
    const {activity,options,inputs}=context;
    const fresh=k=>Number(state.fetchedAt?.[k]||0)>=requested&&!state.cachedSources?.[k]&&!state.errors?.[k]&&now-Number(state.fetchedAt[k])<=300000;
    if(activity.blocked||activity.war?.stale||report.warVerified===false||!fresh("travel")||!fresh("education")||!fresh("gymCatalog"))throw Error("Current activity, travel, education, gym or war evidence is unavailable or blocks training");
    if(inputs.criticalIssues.some(x=>x!=="Restored training session held for manual review"))throw Error(inputs.criticalIssues.filter(x=>x!=="Restored training session held for manual review").join(" · "));
    if(review.remaining.some(a=>["xanax","ecstasy"].includes(a.type))&&options.blockDrugs)throw Error("Drug restriction active");
    const categories=new Set(review.remaining.flatMap(a=>["xanax","ecstasy"].includes(a.type)?["Drug"]:a.type==="dvd"?["Booster"]:a.type==="candy"?["Candy"]:[]));
    for(const cat of categories)if(!inputs.sources["inventory:"+cat]?.ready||!fresh("inventory:"+cat)||state.inventoryErrors?.[cat])throw Error("Refresh "+cat+" inventory before previewing");
    if(review.remaining.some(a=>a.type==="refill")&&(!fresh("money")||inputs.points===null))throw Error("Refresh points before previewing");
    // No historical cooldown or watch state is used as fresh evidence.
    const result=tornStatPlanner.replayTrainingSession(review.session,{...options,recoveryPreview:true});
    const preview=tornTrainingRecovery.validatePreview(review,result,{now:Date.now(),deadline:options.deadline,requireDrugClear:options.requireDrugClear,warXanaxSeconds:options.warXanaxSeconds});
    return {...preview,inventoryChecked:[...categories],note:"Read-only timing and Energy preview. Supply affordability and actual expenditures are not verified; no actions are activated."};
  }
  function trainingRecommendationContext(prefs=tornRoadmap.preferences(),now=Date.now()){
    const context=liveOptimizationContext(prefs,now);
    const {settings,session,activity,health,iconFresh,addictionDebuff,highAddiction,enrolled,protectedEducation,educationRisk,blockDrugs,budget,reserves,options}=context;
    const plan=tornStatPlanner.homeTrainingAdvice(budget,prefs.risk,options);
    const scheduled=context.recoveryHeld||activity.statusBlocked?[]:activityEventsForTraining(session,plan?.program,now,context.inputs);
    const live=recoverySnapshot(now),profile=payload("profile","profile"),st=tornGuideApi.state;
    const status=String(profile?.status?.state??"").toLowerCase();
    const travelAvailable=Number(st.identity?.level??profile?.level)>=15&&["okay","ok"].includes(status)&&!st.errors?.profile&&now-Number(st.fetchedAt?.profile||0)<15*60000&&!activity.blocked;
    const rehab=tornActivityScheduler.events().some(e=>e.kind==="rehab"&&e.end>now)?null:tornActivityScheduler.rehabWindow({now,health,war:activity.war,actions:scheduled.map(e=>e.start),drugReady:live?.drug>0?now+live.drug*1000:null,s:settings,travelAvailable});
    return {...context,plan,avoidWarDrugs:blockDrugs||prefs.odRisk==="low",rehab,scheduled};
  }
  function activityEventsForTraining(session,program,now=Date.now(),inputs=null){
    const valueItems=tornTrainSequence.calendarValuation(inputs);
    const labels={xanax:"Xanax",ecstasy:"Ecstasy",train:"Gym training",candy:"Candy",dvd:"Erotic DVD",refill:"Energy refill",externalHappy:"Coordinated happiness boost"};
    const rows=session?sessionSchedule(session,now).filter(x=>!x.done).map(x=>({step:x.step,at:x.due,source:"Active training cycle"})):
      (program?.execution??[]).map((step,i)=>({step,at:program.generatedAt+step.at*1000,source:"Optimal Budget forecast",candy:program.calendarCandy?.[i]})).filter(x=>actionable(x.step));
    return rows.filter(x=>Number.isFinite(x.at)&&labels[x.step.type]).map(({step,at,source,candy},i)=>{
      // Match sessionSchedule for locked sessions; the simulator's post-action
      // drug balance is the duration for a new forecast. No extra gameplay logic.
      const drugCooldownSeconds=step.type==="xanax"||step.type==="ecstasy"?
        session?(step.type==="xanax"?session.timing?.xanaxCD??25200:session.timing?.ecstasyCD??12900):step.after?.drug:null;
      return {id:"training-"+i,kind:"training",title:labels[step.type]+(step.type==="train"?" · "+number(step.energy)+" E":["candy","dvd"].includes(step.type)?" × "+number(step.quantity):""),start:at,end:at,source,drugCooldownSeconds,items:valueItems(step,candy)};
    });
  }
  function calendarEvents(training,now=Date.now()){
    const valueItems=tornTrainSequence.calendarValuation(training.inputs);
    return tornActivityScheduler.schedule({now,war:training.activity.war,preparation:energyWarAdvice(training,now),health:training.health,rehab:training.rehab,training:training.scheduled,limit:training.activity.blocked?now:training.activity.deadline}).map(e=>/^war-dose-\d+$/.test(e.id)?{...e,items:valueItems({type:"xanax",quantity:1})}:e);
  }
  function rehabPanel(training){
    const {health,rehab,reserves}=training,fmt=tornActivityScheduler.time;
    const warning=health.level==="restricted"?"Drug recommendations restricted until refreshed addiction data clears the threshold.":health.level==="unknown"?"Addiction status unavailable; drug recommendations paused until icons refresh.":health.level==="recommended"?"Rehabilitation recommended.":health.level==="preferred"?"Rehabilitation preferred when a suitable gap exists.":"";
    const active=tornActivityScheduler.events().find(e=>e.kind==="rehab"&&!e.completedAt&&e.end>Date.now());
    const confirmed=tornActivityScheduler.events().filter(e=>e.kind==="rehab"&&e.completedAt).sort((a,b)=>b.completedAt-a.completedAt)[0];
    if(!active&&!rehab&&!confirmed&&!reserves.warReserve&&!reserves.rehabReserve&&!["preferred","recommended","restricted"].includes(health.level))return "";
    return '<div class="activity-rehab-details"><strong>Rehabilitation &amp; activity reserves</strong>'+(warning&&health.level!=="unknown"?'<small>'+esc(warning)+'</small>':"")+
      (active?'<small>Rehab reserved: '+esc(fmt(active.start))+' to '+esc(fmt(active.end))+'</small>':rehab?'<small>Suggested rehab: '+esc(fmt(rehab.start))+' to '+esc(fmt(rehab.end))+' · estimate $'+number(rehab.cost)+(rehab.overlapsCooldown?" · fits cooldown":"")+(rehab.requiresPause?" · pause training":"")+'</small><button type="button" data-activity-rehab>Reserve rehab window</button>':["preferred","recommended","restricted"].includes(health.level)?'<small>No verified travel window yet; check travel eligibility, live status and upcoming commitments.</small>':"")+
      (confirmed?'<small>Last rehab confirmed '+esc(fmt(confirmed.completedAt))+(confirmed.rehabCost==null?" · cost unknown":" · $"+number(confirmed.rehabCost))+'</small>':"")+
      (reserves.warReserve||reserves.rehabReserve?'<small>Reserved cash: war $'+number(reserves.warReserve)+' · rehab $'+number(reserves.rehabReserve)+(reserves.shortfall?" · exceeds available budget":"")+'</small>':"")+'</div>';
  }
  function calendarRenderOptions(training){return {now:training.now,war:training.activity.war,liveDrugSeconds:training.inputs?.owner!=null?training.inputs.drug:null};}
  function homeTimeline(training,events){
    return '<section class="home-activity-timeline" aria-label="Activity timeline"><div class="home-activity-timeline-header"><h3>Activity Timeline</h3><a href="#calendar">Full Calendar</a></div>'+tornActivityScheduler.renderModeTimeline(events,training.now,training.activity.war,calendarRenderOptions(training).liveDrugSeconds,"home")+'</section>';
  }
  function calendarCard(training,full=false,events=null){
    return '<small class="fine-print">Recorded activity spending (7 days): $'+number(tornActivityScheduler.weeklySpend())+'</small>'+tornActivityScheduler.render(events??calendarEvents(training,training.now),{full,homeTile:!full,timelineScope:full?"calendar":null,...calendarRenderOptions(training)})+rehabPanel(training)+(full?tornActivityScheduler.manualForm()+tornActivityScheduler.expenseForm():'<a class="fine-print" href="#calendar">Open full Calendar / add commitments</a>');
  }
  function renderCalendar(){
    loadOcFilters();loadRecFilters();
    const training=trainingRecommendationContext(tornRoadmap.preferences());
    activityContext=training;
    return '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Calendar</h1><p>Shared TCT agenda for training, rehabilitation, faction commitments and account timers.</p></header><section class="panel"><div class="panel-heading"><h2>Activity schedule</h2><div class="activity-page-actions"><button type="button" data-activity-settings>Settings</button><button type="button" data-activity-refresh>Refresh</button></div></div><div class="panel-content">'+calendarCard(training,true)+'<p class="fine-print"><a href="https://github.com/vagabond1215/TORN/blob/main/docs/activity-scheduler-plan.md" target="_blank" rel="noopener noreferrer">Scheduling design and limitations</a></p></div></section>';
  }
  let activityContext=null;
  function refreshActivityView(view){
    if(!view?.isConnected)return;
    if(tornGuideApi.routeName()==="calendar"){view.innerHTML=renderCalendar();wireActivity(view);}
    else if(tornGuideApi.routeName()==="home")refreshRecommendations(view);
  }
  function wireActivity(view){
    tornActivityScheduler.wire(view,()=>refreshActivityView(view));
    if(view.dataset.activityActionsBound==="1")return;view.dataset.activityActionsBound="1";
    view.addEventListener("click",async e=>{
      const gear=e.target.closest("[data-activity-settings]"),refresh=e.target.closest("[data-activity-refresh],[data-activity-war-refresh]"),rehab=e.target.closest("[data-activity-rehab]");
      if(gear){e.preventDefault();tornActivityScheduler.settingsDialog(()=>refreshActivityView(view),gear);return;}
      if(refresh&&!recoveryBusy){e.preventDefault();recoveryBusy=true;refresh.disabled=true;
        Promise.resolve(tornGuideApi.loadPage(refresh.hasAttribute("data-activity-war-refresh")?"warProgress":"calendar",true)).catch(()=>{}).finally(()=>{recoveryBusy=false;refreshActivityView(view);});return;}
      if(rehab&&activityContext?.rehab&&!recoveryBusy){
        const r=activityContext.rehab,owner=recOwner;
        if(!tornActivityScheduler.rehabSnapshot()){
          recoveryBusy=true;rehab.disabled=true;
          try{await tornGuideApi.loadPage("rehabProgress",true);}catch{}finally{recoveryBusy=false;}
          if(owner!==String(tornGuideApi.state.identity?.id??"guest"))return;
        }
        const now=Date.now(),start=Math.max(now,r.start),end=start+r.duration;
        const limit=activityLimits(now),busy=tornActivityScheduler.events().some(x=>x.blocking&&start<x.end&&end>x.start);
        if(limit.blocked||busy||limit.war&&end>limit.war.cutoff){refreshActivityView(view);return;}
        const baseline=tornActivityScheduler.rehabSnapshot(now);
        if(tornActivityScheduler.saveEvent({id:"rehab-"+now,kind:"rehab",title:"Switzerland rehabilitation (reserved)",start,end,blocking:true,rehabBaseline:baseline}))refreshActivityView(view);
      }
    });
  }
  let growthTab="summary";
  const growthTabIds=["summary","steps","build"];
  function nextGrowthTab(current,id,toggle=false){
    return growthTabIds.includes(id)?toggle&&current===id?"collapsed":id:current;
  }
  function growthDetails(tabs){
    const focusTab=growthTab==="collapsed"?"summary":growthTab;
    const tabbar='<div class="growth-tabs" role="tablist" aria-label="Energy details">'+tabs.map(([id,label])=>'<button type="button" role="tab" id="growth-tab-'+id+'" aria-controls="growth-panel-'+id+'" aria-selected="'+(growthTab===id)+'" aria-expanded="'+(growthTab===id)+'" tabindex="'+(focusTab===id?"0":"-1")+'" data-growth-tab="'+id+'">'+label+'</button>').join("")+'</div>';
    const panels=tabs.map(([id,,body])=>'<div class="growth-tab-panel" role="tabpanel" id="growth-panel-'+id+'" aria-labelledby="growth-tab-'+id+'" '+(growthTab===id?"":"hidden")+'>'+body+'</div>').join("");
    return tabbar+panels;
  }
  let sessionOwner=null,trainingSession=null,trainingDraft=null;
  const trainingSpendKey=()=> "torn-city-guide:training-spend:"+String(tornGuideApi.state.identity?.id??"guest");
  function trainingSpend(now=Date.now()){
    try{
      const saved=JSON.parse(localStorage.getItem(trainingSpendKey()));
      return Array.isArray(saved)?saved.filter(entry=>Number.isFinite(entry?.at)&&entry.at>now-7*86400000&&Number.isFinite(entry.cost)&&entry.cost>=0):[];
    }catch{return [];}
  }
  function accountForCycle(session){
    if(trainingRecoveryHeld()||sessionOwner!==String(tornGuideApi.state.identity?.id??"guest")||!(session.cycleSpend>0))return;
    const entries=trainingSpend();
    if(entries.some(entry=>entry.started===session.started))return;
    entries.push({started:session.started,at:Date.now(),cost:session.cycleSpend});
    writeAccountValue(trainingSpendKey(),JSON.stringify(entries));
  }
  async function reviewNextCycle(view,session){
    if(trainingRecoveryHeld()||recoveryBusy)return;
    const owner=sessionOwner,requested=Date.now();
    recoveryBusy=true;recoveryMessage="Cycle complete · updating the next recommendation…";
    refreshRecommendations(view);
    try{
      await tornGuideApi.loadPage("energy",true);
      if(loadTrainingSession()!==session||sessionOwner!==owner)return;
      const state=tornGuideApi.state,stamps=state.fetchedAt;
      if(["bars","cooldowns","battlestats"].some(key=>(stamps?.[key]??0)<requested||state.errors?.[key])){
        recoveryMessage="Fresh training data unavailable. Refresh to plan the next cycle.";return;
      }
      accountForCycle(session);
      trainingSession=null;saveTrainingSession();
      recoveryMessage="Readiness updated.";readinessExpires=Date.now()+3500;
    }catch(error){recoveryMessage="Could not review the next cycle: "+String(error.message??error);}
    finally{recoveryBusy=false;if(view.isConnected)refreshRecommendations(view);}
  }
  function writeAccountValue(key,value){
    const owner=String(key).split(":").at(-1);
    if(typeof tornTrainingRecovery!=="undefined"&&tornTrainingRecovery.journalHeld(localStorage,owner))throw Error("Account restore is pending");
    if(typeof tornAccountStorage!=="undefined")tornAccountStorage.trackedWrite(localStorage,owner,key,value);
    else if(value===null)localStorage.removeItem(key);
    else localStorage.setItem(key,value);
  }
  function trainingRecoveryHeld(){
    const id=tornGuideApi.state.identity?.id;
    if(typeof tornTrainingRecovery!=="undefined")return tornTrainingRecovery.held(localStorage,id);
    // Mixed cached assets must not silently release a stored hold.
    if(!/^[1-9][0-9]{0,14}$/.test(String(id??"")))return false;
    try{return localStorage.getItem("torn-city-guide:training-session-review:v1:"+id)!==null||localStorage.getItem("torn-city-guide:restore-journal:v1:"+id)!==null;}catch{return true;}
  }
  function loadTrainingSession(){
    const owner=String(tornGuideApi.state.identity?.id??"guest");
    if(trainingRecoveryHeld()){sessionOwner=null;trainingSession=null;trainingDraft=null;return null;}
    if(sessionOwner!==owner){sessionOwner=owner;trainingSession=null;try{const x=JSON.parse(localStorage.getItem("torn-city-guide:training-session:"+owner));if(x?.version===1&&Array.isArray(x.actions)&&x.actions.length<=2000&&Number.isFinite(x.started)&&Number.isInteger(x.index)&&x.index>=0&&x.index<=x.actions.length)trainingSession=x;}catch{}}
    return trainingSession;
  }
  function saveTrainingSession(){if(trainingRecoveryHeld()||sessionOwner!==String(tornGuideApi.state.identity?.id??"guest"))return;try{const key="torn-city-guide:training-session:"+sessionOwner;if(trainingSession)writeAccountValue(key,JSON.stringify(trainingSession));else writeAccountValue(key,null);}catch{}}
  const actionable=x=>Number.isFinite(x.at)&&x.at>=0&&!["wait","autoWait","happyReset"].includes(x.type)&&(x.type!=="train"||x.energy>0)&&(!["candy","dvd"].includes(x.type)||x.quantity>0);
  // Reconcile only future actions. Confirmed steps are immutable; missing live
  // snapshots never imply that an action happened.
  function sessionSchedule(session,now=Date.now()){
    const actions=session.actions,done=session.completed??{},timing=session.timing??{},st=tornGuideApi.state;
    const last=Number(session.lastConfirmed)||session.started;
    const raw=payload("bars","bars"),bridge=st.bridge;
    const barAt=bridge?.fields?.includes("energy")&&bridge.timestamp>Number(st.fetchedAt?.bars||0)?bridge.timestamp:Number(st.fetchedAt?.bars||0);
    const e=barAt>=last?tornBarProjection("energy",raw?.energy,barAt,now):null;
    const cd=payload("cooldowns","cooldowns"),cdAt=Number(st.fetchedAt?.cooldowns||0);
    const cdEnd=key=>{const v=cd?.[key],n=Number(typeof v==="object"?v?.remaining??v?.time_left:v);return cdAt>=last&&v!=null&&Number.isFinite(n)&&n>=0?cdAt+n*1000:0;};
    let drugEnd=Math.max(cdEnd("drug"),session.drugUntil||0),boosterEnd=Math.max(cdEnd("booster"),session.boosterUntil||0),energy=e?.current??null,energyAt=now;
    const cap=e?.maximum??session.maxEnergy??150,cost=session.gym?.energy??10;
    let refillDay=tornTrainSequence.energyRefillUsedToday(now)?Math.floor(now/86400000):session.refillDay??null,previousAt=session.index>0?actions[session.index-1].at:0,previousDue=last;
    const rows=[];
    for(let i=0;i<actions.length;i++){
      const x=actions[i];if(i<session.index){rows.push({step:x,done:true,due:done[i]??null});continue;}
      let due=Math.max(now,previousDue+(x.midnightRefill?0:Math.max(0,x.at-previousAt)*1000),i===session.index?session.notBefore||0:0);
      let drugWait=["xanax","ecstasy"].includes(x.type)&&drugEnd>now,energyWait=false,refillWait=false;
      if(["xanax","ecstasy"].includes(x.type))due=Math.max(due,drugEnd);
      const isBooster=["candy","dvd"].includes(x.type),unit=x.type==="candy"?timing.candyCD??1800:timing.dvdCD??21600,qty=x.quantity??1;
      let happyWait=false,boosterWait=false,boosterPending=false;
      if(isBooster){
        const boosterReady=boosterEnd-(timing.boosterCap??86400)*1000+Math.max(0,qty-1)*unit*1000;
        boosterWait=boosterReady>due;boosterPending=boosterReady>now;
        due=Math.max(due,boosterReady);
        const next=actions.slice(i+1).find(step=>["xanax","ecstasy","train","refill"].includes(step.type));
        if(next?.type==="ecstasy"){drugWait=drugEnd>now;due=Math.max(due,drugEnd);}
        const delay=tornHappinessBook().active?0:tornTrainSequence.happyResetWait(due/1000);
        happyWait=delay>0;
        due+=delay*1000;
      }
      if(x.midnightRefill&&refillDay===null){const reset=(Math.floor(previousDue/86400000)+1)*86400000;refillWait=reset>now;due=Math.max(due,reset);}
      if(x.type==="refill"&&refillDay!==null){const reset=(refillDay+1)*86400000;refillWait=reset>now;due=Math.max(due,reset);}
      if(energy!==null){
        const regen=t=>{if(energy<cap){const first=energyAt===now?Math.max(0,e.until)*1000:e.interval*1000;const elapsed=t-energyAt;if(elapsed>=first)energy=Math.min(cap,energy+(1+Math.floor((elapsed-first)/(e.interval*1000)))*e.step);}energyAt=t;};
        regen(due);
        if(x.type==="train"){
          const wanted=Math.max(cost,Math.floor((Number(x.energy)||cost)/cost)*cost);
          if(energy<wanted&&wanted<=cap){energyWait=true;const wait=Math.ceil((wanted-energy)/e.step)*e.interval*1000;due+=wait;regen(due);}else if(i===session.index&&due>now&&e.current<wanted&&wanted<=cap)energyWait=true;
          energy=Math.max(0,energy-Math.min(wanted,Math.floor(energy/cost)*cost));
        }
        if(x.type==="xanax")energy=Math.min(1000,energy+250);
        if(x.type==="refill")energy=Math.max(energy,cap);
      }
      rows.push({step:x,done:false,due,happyWait,boosterWait,boosterPending,drugWait,energyWait,refillWait});
      if(x.type==="xanax"||x.type==="ecstasy")drugEnd=due+(x.type==="xanax"?timing.xanaxCD??25200:timing.ecstasyCD??12900)*1000;
      if(isBooster)boosterEnd=Math.max(due,boosterEnd)+qty*unit*1000;
      if(x.type==="refill")refillDay=Math.floor(due/86400000);
      previousAt=x.at;previousDue=due;
    }
    return rows;
  }
  const sessionTime=at=>at==null?"Confirmed":new Date(at).toLocaleString(undefined,{month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"});
  function sessionActions(execution){
    const actions=[];
    let waits=[];
    for(const step of execution){
      if(["wait","autoWait"].includes(step.type)&&Number.isFinite(step.end)&&step.end>step.at){
        waits.push({reason:step.reason,duration:step.end-step.at,end:step.end});
      }else if(actionable(step)){
        actions.push(waits.length?{...step,waitsBefore:waits}:step);
        waits=[];
      }
    }
    return actions;
  }
  function sessionWaitText(wait,due,actionAt,live){
    const remaining=live?Math.min(wait.duration,Math.max(0,(due-Date.now())/1000-(actionAt-wait.end))):wait.duration;
    return tornTrainSequence.waitTitle(wait.reason??"")+" "+tornTctClock.formatDuration(remaining);
  }
  function sessionSteps(session,names,fmt){
    return sessionSchedule(session).map(({step:x,done,due},i)=>{
      const waits=(x.waitsBefore??[]).map((wait,j)=>'<li class="growth-session-wait"><time></time><span data-session-wait="'+i+'" data-wait-index="'+j+'">'+
        esc(sessionWaitText(wait,due,x.at,i===session.index))+'</span></li>').join("");
      return waits+'<li data-session-row="'+i+'" class="'+(done?"growth-step-done":i===session.index?"growth-step-next":"")+'"><time data-session-time>'+esc(sessionTime(due))+'</time><span>'+(done?"✓ ":"")+esc(x.type==="train"?"Train "+session.stat:names[x.type]??x.type)+(["candy","dvd"].includes(x.type)?" × "+fmt(x.quantity):"")+(i===session.index?" · Next":"")+'</span></li>';
    }).join("");
  }
  function prepState(plan,blockDrugs){
    if(trainingRecoveryHeld())return {ready:false,label:"Restored training session held for review",due:null};
    const program=plan?.program,raw=payload("bars","bars"),st=tornGuideApi.state;
    const inputs=tornTrainSequence.liveInputs(st,Date.now(),tornBarProjection),projected=inputs.energy;
    const cd=payload("cooldowns","cooldowns"),drug=cd?.drug;
    const remaining=drug==null?null:Math.max(0,Number(typeof drug==="object"?drug.remaining??drug.time_left:drug)-(Date.now()-Number(st.fetchedAt?.cooldowns||Date.now()))/1000);
    if(!program||!projected||!inputs.happy)return {ready:false,label:"Load current Energy and Happiness",due:null};
    const generated=Number(program.generatedAt),activity=activityLimits(inputs.now);
    if(inputs.criticalIssues.length||!Number.isFinite(generated)||inputs.now-generated>300000||
      program.source==="optimal-budget"&&(inputs.drug===null||inputs.booster===null))
      return {ready:false,label:"Refresh live training data before starting",due:null};
    const profile=payload("profile","profile"),factionId=Number(profile?.faction_id??profile?.faction?.id);
    if(energyWarSettings().mode!=="off"&&factionId>0&&!inputs.sources.factionWars.ready)
      return {ready:false,label:"Refresh faction war schedule before starting",due:null};
    if(activity.blocked||program.deadline&&inputs.now>=program.deadline-60000)return {ready:false,label:"Scheduled activity prevents training",due:null};
    if(activity.deadline!=null&&activity.deadline<generated+program.horizonSeconds*1000+60000&&activity.deadline!==program.deadline)
      return {ready:false,label:"Activity deadline changed; refresh training plan",due:null};
    const e=projected.current,cap=projected.maximum,cost=Number(plan.gym?.energy)||10;
    const first=(program.cycleExecution??program.execution).find(actionable),startsZero=program.startEnergy==="zero"&&program.id!=="natural";
    if(program.source==="optimal-budget"||program.source==="natural"){
      if(blockDrugs&&program.drugRisk)return {ready:false,label:"Drug restriction active",due:null};
      if(!first)return {ready:false,label:"No trainable cycle available",due:null};
      return {ready:true,label:"Ready to follow "+program.label,due:null};
    }
    if(blockDrugs&&program.drugRisk)return {ready:false,label:"Drug restriction active",due:null};
    if(startsZero){
      if(remaining===null)return {ready:false,label:"Check drug cooldown",due:null};
      const alreadyStacked=e>=cap+250;
      if(alreadyStacked)return {ready:false,label:"Existing Energy stack detected · review before starting",due:null};
      // For a zero-E jump, spend natural energy as close to the first Xanax as possible.
      let wait=remaining;
      if(e>0&&e%cost!==0&&e<cap){let n=1;while(n<=cost&&Math.min(cap,e+n*projected.step)%cost!==0)n++;if(n<=cost)wait=Math.max(wait,projected.until+(n-1)*projected.interval);}
      if(wait>0)return {ready:false,label:e>0?"Wait, then train to 0 E and take Xanax":"Wait for first Xanax",waitKind:wait>remaining?"energy":"drug",nextAction:e>0?"Train to 0 E, then take Xanax":"Take Xanax",due:Date.now()+wait*1000};
      if(e>0)return {ready:false,label:"Train "+plan.stat+" · "+Math.floor(e/cost)*cost+" E, then start at 0 E and take Xanax",due:null};
      return {ready:true,label:"Ready to begin Xanax stack",due:null};
    }
    if(program.id!=="natural"&&e<cap){const wait=projected.until+Math.max(0,Math.ceil((cap-e)/projected.step)-1)*projected.interval;return {ready:false,label:"Regenerate to "+cap+" E ("+e+" / "+cap+")",waitKind:"energy",nextAction:"Start "+program.label,due:Date.now()+wait*1000};}
    if(first?.type==="xanax"&&remaining>0)return {ready:false,label:"Wait for Xanax cooldown",waitKind:"drug",nextAction:"Take Xanax",due:Date.now()+remaining*1000};
    return {ready:true,label:"Ready to start "+program.label,due:null};
  }
  let recoveryBusy=false,recoveryMessage="",readinessExpires=0;
  function recoverySnapshot(now=Date.now()){
    const input=tornTrainSequence.liveInputs(tornGuideApi.state,now,tornBarProjection),E=input.energy,H=input.happy;
    if(!E||!H||input.drug===null||input.booster===null)return null;
    return {energy:E.current,cap:E.maximum,happy:H.current,maxHappy:H.maximum,drug:input.drug,booster:input.booster,at:now};
  }
  // Compare actual API snapshots, not extrapolated bars or the planned
  // starting state. A newly observed cooldown alone is not proof of a dose.
  function trainingWatchSnapshot(session,now=Date.now()){
    if(!session)return null;
    const st=tornGuideApi.state,stamps=st.fetchedAt??{},bars=payload("bars","bars"),cd=payload("cooldowns","cooldowns"),refills=payload("refills","refills");
    const barAt=Number(stamps.bars)||0,cdAt=Number(stamps.cooldowns)||0,statAt=Number(stamps.battlestats)||0,refillAt=Number(stamps.refills)||0;
    if(!barAt||!cdAt||Math.abs(barAt-cdAt)>60000||now-Math.min(barAt,cdAt)>120000||st.errors?.bars||st.errors?.cooldowns||
      Number(st.bridge?.timestamp||0)>barAt)return null;
    const val=x=>x==null?null:Number.isFinite(Number(x))?Number(x):null;
    const seconds=x=>val(typeof x==="object"?x?.remaining??x?.time_left:x);
    const entry=payload("battlestats","battlestats")?.[session.statKey];
    const stat=!st.errors?.battlestats&&statAt&&Math.abs(statAt-cdAt)<=60000?val(typeof entry==="object"?entry?.value:entry):null;
    const energy=val(bars?.energy?.current),cap=val(bars?.energy?.maximum),happy=val(bars?.happy?.current),maxHappy=val(bars?.happy?.maximum),drug=seconds(cd?.drug),booster=seconds(cd?.booster);
    const rawUsed=refills?.energy_refill_used??refills?.energy?.used;
    const refillUsed=!st.errors?.refills&&refillAt&&Math.floor(refillAt/86400000)===Math.floor(now/86400000)&&typeof rawUsed==="boolean"?rawUsed:null;
    if([energy,cap,happy,maxHappy,drug,booster].some(x=>x===null||x<0)||cap<=0)return null;
    return {at:Math.min(barAt,cdAt),barAt,cdAt,statAt,refillAt,energy,cap,happy,maxHappy,drug,booster,stat,refillUsed};
  }
  function detectWatchedAction(step,before,after,timing={},gymCost=10){
    if(!step||!before||!after||after.barAt<=before.barAt||after.cdAt<=before.cdAt)return false;
    const elapsed=Math.max(0,(after.at-before.at)/1000);
    if(elapsed>180||elapsed<0)return false; // avoid inferring individual actions over long gaps
    const regen=Math.ceil(elapsed/300)*5+5;
    const drugJump=after.drug-Math.max(0,before.drug-elapsed);
    const boostJump=after.booster-Math.max(0,before.booster-elapsed);
    const energyGain=after.energy-before.energy,happyGain=after.happy-before.happy;
    const drugMatch=(target,tolerance)=>drugJump>1800&&Math.abs(drugJump-target)<=tolerance+elapsed;
    if(step.type==="xanax"){
      const expected=Math.min(250,Math.max(0,1000-before.energy));
      return expected>0&&energyGain>=expected-5&&energyGain<=expected+regen&&drugMatch(timing.xanaxCD??25200,5400);
    }
    if(step.type==="ecstasy"){
      const expected=Math.min(99999,before.happy*2)-before.happy;
      return expected>0&&happyGain>=Math.max(1,expected-25)&&happyGain<=expected+25&&Math.abs(energyGain)<=regen&&drugMatch(timing.ecstasyCD??12900,3600);
    }
    if(step.type==="candy"||step.type==="dvd"){
      const qty=Number(step.quantity??1),unit=step.type==="candy"?timing.candyCD??1800:timing.dvdCD??21600;
      const predicted=Math.max(0,(step.after?.happy??0)-(step.before?.happy??0));
      return qty>0&&predicted>0&&Math.abs(boostJump-qty*unit)<=60+elapsed&&happyGain>=Math.max(1,predicted-25)&&happyGain<=predicted+25;
    }
    if(step.type==="refill"){
      return before.refillUsed===false&&after.refillUsed===true&&after.refillAt>before.refillAt&&Math.floor(before.at/86400000)===Math.floor(after.at/86400000)&&energyGain>0&&after.energy>=after.cap;
    }
    if(step.type==="train"){
      const expected=Math.max(0,Number(step.energy)||0),gain=after.stat-before.stat;
      return before.stat!=null&&after.stat!=null&&after.statAt>before.statAt&&gain>0&&expected>=gymCost&&
        before.energy-after.energy>=Math.max(gymCost,expected-regen)&&before.energy-after.energy<=expected+regen;
    }
    return false;
  }
  function observeTrainingStep(session,sample=trainingWatchSnapshot(session)){
    if(trainingRecoveryHeld()||!session||!sample||session.index>=session.actions.length)return false;
    const step=session.actions[session.index],after=Math.max(session.started,session.lastConfirmed??0);
    const watch=session.watch;
    if(!watch||watch.index!==session.index||!watch.sample){session.watch={index:session.index,sample};saveTrainingSession();return false;}
    const before=watch.sample;
    if(sample.at<=before.at||sample.barAt<=after||sample.cdAt<=after)return false;
    if(!detectWatchedAction(step,before,sample,session.timing,session.gym?.energy??10)){
      // Don't overwrite a promising pre-action baseline with a split/cached
      // update. Retry on the next fresh snapshot, then fall back to manual.
      const elapsed=(sample.at-before.at)/1000;
      const suspect=["xanax","ecstasy"].includes(step.type)?sample.drug>Math.max(0,before.drug-elapsed)+1800||
        (step.type==="xanax"?sample.energy-before.energy>=100:sample.happy-before.happy>=100):
        ["candy","dvd"].includes(step.type)?sample.booster>Math.max(0,before.booster-elapsed)+60:
        step.type==="refill"?before.refillUsed===false&&sample.refillUsed===true:
        step.type==="train"?sample.stat!=null&&before.stat!=null&&sample.stat>before.stat:false;
      if(!suspect||elapsed>180){
        session.watch={index:session.index,sample,...(watch.issue?{issue:watch.issue}:{})};saveTrainingSession();
      }else if(!watch.issue){
        watch.issue="Observed changes do not yet confirm this step. Refresh or verify in Torn, then use Mark done if appropriate.";saveTrainingSession();
      }
      return false;
    }
    const i=session.index;
    session.completed??={};session.recovered??={};
    session.completed[i]=sample.at;session.recovered[i]=true;
    session.index++;session.lastConfirmed=sample.at;
    const next=session.actions[session.index];
    session.notBefore=next&&!next.midnightRefill?sample.at+Math.max(0,next.at-step.at)*1000:0;
    session.drugUntil=sample.cdAt+sample.drug*1000;session.boosterUntil=sample.cdAt+sample.booster*1000;
    if(step.type==="refill")session.refillDay=Math.floor(sample.at/86400000);
    if(sample.stat!=null&&Number.isFinite(step.after?.stat))session.statCheckpoint={actual:sample.stat,projected:step.after.stat};
    session.watch={index:session.index,sample};saveTrainingSession();
    recoveryMessage="Training progress detected.";readinessExpires=Date.now()+3500;
    return true;
  }
  let watchRequestAt=0,watchRetryAt=0,watchPending=false;
  function watchTraining(view,{resume=false}={}){
    if(!view||view.hidden||!view.isConnected||tornGuideApi.routeName()!=="home"||!autoTrainingWatch()||recoveryBusy)return;
    const session=loadTrainingSession();
    if(!session||session.index>=session.actions.length||activityLimits().blocked||sessionDeadlineConflict(session,activityLimits())||warTraining&&(energyWarAdvice(warTraining)?.active||warTraining.blockDrugs&&session.drugRisk))return;
    const st=tornGuideApi.state;
    if(!st.identity)return;
    if(observeTrainingStep(session)){
      if(session.index>=session.actions.length)void reviewNextCycle(view,session);
      else refreshRecommendations(view);
      return;
    }
    const now=Date.now(),next=sessionSchedule(session)[session.index];
    const due=next?.due??now,interval=due>now+60000?120000:30000;
    if(watchPending||st.loading||now<watchRetryAt||now-watchRequestAt<(resume?30000:interval))return;
    watchRequestAt=now;watchPending=true;
    const owner=sessionOwner,started=session.started;
    void tornGuideApi.loadPage("trainingProgress",true).then(result=>{
      if(result?.failures||result?.discarded)watchRetryAt=Date.now()+120000;
      if(owner!==sessionOwner||loadTrainingSession()?.started!==started||!view.isConnected||!autoTrainingWatch()||tornGuideApi.routeName()!=="home"||recoveryBusy)return;
      const active=loadTrainingSession();
      if(active.index<active.actions.length&&observeTrainingStep(active)){
        if(active.index>=active.actions.length)void reviewNextCycle(view,active);
        else refreshRecommendations(view);
      }
    }).catch(()=>{watchRetryAt=Date.now()+120000;}).finally(()=>{watchPending=false;});
  }
  function matchTrainingCheckpoint(session,live,stat,statsAt,cooldownsAt,refillUsed){
    const from=session.index,actions=session.actions;
    const after=Math.max(session.started,session.lastConfirmed??0);
    const first=actions[from]?.before?.stat;
    if(!Number.isFinite(stat)||!Number.isFinite(first)||statsAt<=after||
      cooldownsAt<=after||Math.abs(statsAt-cooldownsAt)>120000)return null;
    const anchor=session.statCheckpoint;
    const offset=anchor?anchor.actual-anchor.projected:0;
    const actual=stat-(first+offset);
    if(actual<=0)return null;
    let usedDrug=false,usedBooster=false,crossedRefill=false,best=null;
    for(let i=from;i<Math.min(actions.length,from+20);i++){
      const step=actions[i],end=step.after;
      usedDrug||=["xanax","ecstasy"].includes(step.type);
      usedBooster||=["candy","dvd"].includes(step.type);
      crossedRefill||=step.type==="refill";
      if(crossedRefill&&!refillUsed)break;
      if(step.type!=="train"||!Number.isFinite(end?.stat))continue;
      const expected=end.stat-first,statError=Math.abs(actual-expected);
      if(expected<=0||statError>Math.max(1,expected*.2))continue;
      const elapsed=Math.max(0,(cooldownsAt-after)/1000);
      const comparisons=[];
      if(usedDrug)comparisons.push([end.drug,live.drug,2700]);
      if(usedBooster)comparisons.push([end.booster,live.booster,Math.max(1800,end.booster*.08)]);
      let lower=0,upper=elapsed;
      for(const [planned,observed,tolerance] of comparisons){
        if(!Number.isFinite(planned)||!Number.isFinite(observed)){upper=-1;break;}
        lower=Math.max(lower,planned-observed-tolerance);
        // A cleared cooldown may have reached zero at any point since the checkpoint.
        if(observed>0)upper=Math.min(upper,planned-observed+tolerance);
      }
      if(lower>upper)continue;
      const score=statError/expected;
      if(!best||score<best.score)best={index:i+1,projected:end.stat,score};
    }
    return best;
  }
  function reconcileTrainingProgress(session,live=recoverySnapshot()){
    if(trainingRecoveryHeld()||!session||session.index>=session.actions.length||!live||!session.statKey)return false;
    const state=tornGuideApi.state;
    if(state.errors?.battlestats)return false;
    const entry=payload("battlestats","battlestats")?.[session.statKey],raw=typeof entry==="object"?entry?.value:entry;
    const stat=raw==null?NaN:Number(raw);
    const refill=tornTrainSequence.energyRefillUsedToday();
    const match=matchTrainingCheckpoint(session,live,stat,Number(state.fetchedAt?.battlestats||0),Number(state.fetchedAt?.cooldowns||0),refill);
    if(!match)return false;
    session.completed??={};session.recovered??={};
    for(let i=session.index;i<match.index;i++){
      session.completed[i]=null;session.recovered[i]=true;
      if(session.actions[i].type==="refill")session.refillDay=Math.floor(live.at/86400000);
    }
    session.index=match.index;session.lastConfirmed=live.at;session.notBefore=0;
    session.statCheckpoint={actual:stat,projected:match.projected};
    session.watch={index:session.index,sample:trainingWatchSnapshot(session)};
    if(live.drug!=null)session.drugUntil=live.at+live.drug*1000;
    if(live.booster!=null)session.boosterUntil=live.at+live.booster*1000;
    saveTrainingSession();
    recoveryMessage="Training progress detected.";
    readinessExpires=Date.now()+3500;
    return true;
  }
  function recoveryPanel(){
    return recoveryMessage?'<small role="status" '+(["Readiness updated.","Training progress detected."].includes(recoveryMessage)?'data-readiness-status':"")+'>'+esc(recoveryMessage)+'</small>':"";
  }
  // The status reports detector readiness, not a guarantee that a game
  // action has occurred. Disabled/idle and needs-action share the red cross;
  // the accessible tooltip distinguishes the reason.
  function classifyWatch({enabled=true,connected=true,session=null,war=null,blocked=false,restricted=false,busy=false,retry=false,sample=null,now=Date.now()}={}){
    const result=(state,detail)=>({state,label:"API auto-detection: "+(state==="active"?"Active":state==="inactive"?"Inactive":"Requires action")+" · "+detail});
    if(!enabled)return result("inactive","Disabled in Energy settings.");
    if(!connected)return result("action","Connect the Torn API.");
    if(war?.stale)return result("action","Last known war schedule; refresh to verify.");
    if(war?.phase==="active")return result("inactive","Active war; training detection paused.");
    if(war?.phase==="stacking"){
      if(busy)return result("active","Refreshing war preparation.");
      if(war.energy==null||war.due==null)return result("action","Refresh Energy, cooldowns or Xanax inventory.");
      return result("active","Watching war preparation; projections update from account data.");
    }
    const step=session?.actions?.[session.index];
    if(!step)return result("inactive",session?"Cycle complete. Start or review the next cycle.":"Start a training plan to enable monitoring.");
    if(blocked||restricted)return result("action","Training paused by an activity deadline or drug restriction.");
    if(busy)return result("active","Refreshing or reconciling account data.");
    if(retry)return result("action","API check failed. Waiting to retry; use Refresh if needed.");
    if(!["xanax","ecstasy","candy","dvd","refill","train"].includes(step.type))return result("action","This step requires manual confirmation.");
    if(!sample)return result("action","Fresh Energy, Happiness and cooldown data needed. Refresh if this persists.");
    if(step.type==="train"&&sample.stat==null)return result("action","Fresh battle-stat data required to confirm training.");
    if(step.type==="refill"&&sample.refillUsed==null)return result("action","Current daily refill status required.");
    if(session.watch?.index!==session.index||!session.watch?.sample)return result("action","Waiting for a fresh pre-action baseline. Refresh before acting.");
    if(session.watch.issue)return result("action",session.watch.issue);
    if(now-session.watch.sample.at>180000)return result("action","Observation baseline expired. Refresh before acting.");
    return result("active","Watching the current step; read-only API checks every 30 seconds when ready, or two minutes while waiting.");
  }
  function growthWatchStatus(session,training,war=null,now=Date.now()){
    return classifyWatch({enabled:autoTrainingWatch(),connected:!!tornGuideApi.state.identity&&tornGuideApi.isConnected(),session,war,
      blocked:!!training?.activity?.blocked||!!(session&&training?.activity&&sessionDeadlineConflict(session,training.activity,now)),
      restricted:!!(session?.drugRisk&&training?.blockDrugs),busy:recoveryBusy||watchPending,retry:now<watchRetryAt,sample:war?null:trainingWatchSnapshot(session,now),now});
  }
  function growthWatchIndicator(status){
    return '<span class="growth-watch-status" data-growth-watch-status="'+status.state+'" role="img" tabindex="0" aria-label="'+esc(status.label)+'" data-tooltip="'+esc(status.label)+'"><span aria-hidden="true">'+(status.state==="active"?"✓":"×")+'</span></span>';
  }
  function updateGrowthWatchIndicator(view,now=Date.now()){
    const el=view?.querySelector("[data-growth-watch-status]");
    if(!el)return;
    const war=el.closest("[data-war-counter]")&&warTraining?energyWarAdvice(warTraining,now):null;
    const status=growthWatchStatus(loadTrainingSession(),warTraining,war,now);
    if(el.dataset.growthWatchStatus!==status.state){el.dataset.growthWatchStatus=status.state;el.firstElementChild.textContent=status.state==="active"?"✓":"×";}
    if(el.getAttribute("aria-label")!==status.label){el.setAttribute("aria-label",status.label);el.dataset.tooltip=status.label;}
  }
  // Presentation only: the scheduler owns due times and action selection.
  function energyAction(step,stat,fmt){
    if(!step)return "Review the training plan";
    if(step.type==="train")return "Train "+(stat||"selected stat")+(step.energy>0?" · "+fmt(step.energy)+" E":"");
    if(step.type==="xanax")return "Take Xanax";
    if(step.type==="ecstasy")return "Take Ecstasy";
    if(step.type==="refill")return "Use points Energy refill";
    if(step.type==="candy")return "Use candy × "+fmt(step.quantity??1);
    if(step.type==="dvd")return "Use Erotic DVD × "+fmt(step.quantity??1);
    if(step.type==="externalHappy")return "Arrange external Happiness boost";
    return "Review "+step.type;
  }
  function energySessionStatus(session,row,now=Date.now()){
    if(!row?.step)return "Training Cycle Complete";
    const {step,due}=row;
    if(due>now){
      if(row.drugWait)return "Waiting for Drug Cooldown";
      if(row.boosterPending||row.boosterWait)return "Waiting for Booster Cooldown";
      if(row.refillWait)return "Waiting for Daily Refill";
      if(row.energyWait)return "Waiting for Energy";
      if(row.happyWait)return "Waiting for Happiness Reset";
      return "Waiting for Scheduled Step";
    }
    const kind=String(session.label||"").toLowerCase();
    if(step.type==="xanax"&&/jump/.test(kind)){
      if(kind.includes("99k"))return "Stacking for 99k Happy Jump";
      if(kind.includes("mini"))return "Stacking for Mini Jump";
      if(kind.includes("low"))return "Stacking for Low-stat Jump";
      return "Stacking for Happy Jump";
    }
    if(step.type==="xanax")return "Preparing Energy";
    if(["candy","dvd","ecstasy","externalHappy"].includes(step.type))return "Boosting Happiness";
    if(step.type==="train")return "Ready to Train";
    if(step.type==="refill")return "Ready for Energy Refill";
    return "Ready for Next Step";
  }
  function energyPrepStatus(prep,program,stat,fmt){
    if(!program)return {status:"Training Plan Unavailable",next:prep.label};
    const first=(program.cycleExecution??program.execution??[]).find(actionable);
    if(prep.ready)return {status:"Ready to Start",next:"Start "+program.label+(first?" · "+energyAction(first,stat,fmt):"")};
    if(prep.due!=null){
      const status=prep.waitKind==="energy"?"Waiting for Energy":prep.waitKind==="drug"?"Waiting for Drug Cooldown":"Waiting for Scheduled Step";
      return {status,next:prep.nextAction??energyAction(first,stat,fmt)};
    }
    return {status:"Preparation Required",next:prep.label};
  }
  function gymMembership(gym){
    const name=gym?.name;
    if(!name)return '<div class="growth-instruction">Gym membership unavailable.</div>';
    return '<div class="growth-instruction">Member at '+(name==="Gun Shop"?"the ":"")+'<strong>'+esc(name)+'</strong>.'+(gym.energy!=null?' <strong>'+esc(gym.energy)+' E/train</strong>':"")+'</div>';
  }
  function sessionPanel(plan,training,names,fmt){
    const session=loadTrainingSession(),program=plan.program;
    const prep=prepState(plan,training.blockDrugs);
    trainingDraft={plan,training,prep,owner:sessionOwner};
    let label,heading="",status,due=null,controls="",boosterWait=false;
    if(session){
      const step=session.actions[session.index];
      heading=step?session.label+" · "+session.index+" / "+session.actions.length+" confirmed":"All cycle actions confirmed";
      if(!step){status="Training Cycle Complete";label="Review next cycle";controls='<button type="button" data-growth-session="review" '+(recoveryBusy?"disabled":"")+'>Plan next cycle</button>';}
      else if(training.blockDrugs&&session.drugRisk){status="Drug Restriction Active";label="Cancel and replan";}
      else {const next=sessionSchedule(session)[session.index];due=next?.due??Date.now();boosterWait=Boolean(next?.boosterWait);status=energySessionStatus(session,next);label=energyAction(step,session.stat,fmt);controls='<button type="button" data-growth-session="done">Mark done</button>';}
    }else{const display=energyPrepStatus(prep,program,plan.stat,fmt);status=display.status;label=display.next;due=prep.due;controls='<button type="button" data-growth-session="start" '+(!prep.ready?"disabled":"")+'>Start</button>';}
    const refreshLabel=recoveryBusy?"Refreshing…":session?"Continue / Refresh":"Refresh training readiness";
    const cornerControls='<div class="growth-counter-actions">'+growthWatchIndicator(growthWatchStatus(session,training))+
      '<button type="button" data-growth-session="refresh" aria-label="'+refreshLabel+'" title="'+refreshLabel+'" '+(recoveryBusy?"disabled":"")+'><span aria-hidden="true">↻</span></button>'+
      '<button type="button" data-growth-session="stop" aria-label="Cancel training program" title="Cancel training program and return to Start" '+(!session||session.index>=session.actions.length?"disabled":"")+'><span aria-hidden="true">×</span></button></div>';
    return '<div class="growth-next-step" '+(due!=null?'data-growth-due="'+due+'"':"")+' data-ready="'+(session?due!=null&&due<=Date.now():prep.ready)+'">'+'<div class="growth-counter-header"><small class="growth-counter-title">'+esc(heading)+'</small>'+cornerControls+'</div><strong class="growth-next-clock growth-stage" data-growth-stage>'+esc(status)+'</strong><strong class="growth-next-clock" data-growth-clock '+(due==null?"hidden":"")+'>'+esc(due==null?"":due<=Date.now()?"Ready":tornTctClock.formatDuration((due-Date.now())/1000))+'</strong><span data-growth-step>Next: '+esc(label)+'</span>'+'<div class="growth-session-controls">'+controls+barWarning("happy")+barWarning("energy")+'</div>'+
      (boosterWait?'<small>Already trained? Refresh to check for completed steps.</small>':"")+
      recoveryPanel()+'</div>';
  }
  function replayPanel(session,fmt){
    if(!session)return "";
    const rows=sessionSchedule(session),pending=session.actions.slice(session.index),costs={};
    for(const x of pending)if(["xanax","ecstasy","candy","dvd","refill"].includes(x.type))costs[x.type]=(costs[x.type]||0)+(x.quantity??1);
    return '<div class="growth-replay"><strong class="growth-accent">'+esc(session.label.startsWith("LOW#")?"Low Stat Jump Training Program":session.label)+'</strong><small>'+session.index+' / '+session.actions.length+' steps confirmed</small><small>Estimated completion: <span data-growth-finish>'+esc(sessionTime(rows.at(-1)?.due))+'</span></small><small>'+Object.entries(costs).map(([name,q])=>esc(q+" "+name)).join(" · ")+'</small><small>Cycle locked. The next program is selected after this cycle.</small></div>';
  }
  function growthPlanSequence(program){
    if(program?.source!=="optimal-budget"||!Array.isArray(program.sequence)||!program.sequence.length)return "";
    const names={natural:"Natural Training",maxenergy:"Maximum Energy",mini:"Mini Jump",low:"Low-stat Jump",jump:"Happy Jump",maxhappy:"99k Happy Jump",custom:"Custom"};
    return '<div class="growth-optimal-plan"><strong class="growth-accent">Following the Optimal Budget Plan:</strong><ol aria-label="Projected seven-day training cycles">'+program.sequence.map((cycle,i)=>'<li'+(i===0?' class="growth-cycle-current" aria-current="step"':"")+'>'+esc(names[cycle.id]??cycle.id)+(cycle.partial?' <small>(partial)</small>':"")+'</li>').join("")+'</ol><small>'+(program.deadline?esc("Bounded projection until "+tornActivityScheduler.time(program.deadline)):"Seven-day projection")+' · Replanned after each cycle.</small></div>';
  }
  function growthPeriodSummary(periods,fmt,confirmed){
    const estimates=tornTrainSequence.periodPurchases(periods??[1,7,28].map(days=>({days})),confirmed,{liveInputs:warTraining?.inputs,reserveXanax:warTraining?.options?.reserveXanax??0});
    const money=value=>value==null?"—":"$"+fmt(value);
    return '<div class="growth-metrics" aria-label="Training projections">'+estimates.map(period=>{
      const {days,gain,value,energy,cost,items}=period;
      const purchaseList=!items?"Purchase estimate unavailable":items.length
        ?items.map(item=>fmt(item.quantity)+" × "+item.name+(item.price==null?" (price unavailable)":"")).join(", ")
        :"No purchases needed";
      const tooltipId="growth-purchases-"+days;
      return '<div class="growth-period"><strong>'+days+' Day</strong>'+
        '<strong class="growth-accent" aria-label="Stat gain '+esc(fmt(gain))+'">'+(gain==null?"—":"+"+fmt(gain))+'</strong>'+
        '<span class="growth-cost" tabindex="0" aria-label="Purchase cost '+esc(money(cost))+'" aria-describedby="'+tooltipId+'">'+money(cost)+
        '<span class="growth-purchases" id="'+tooltipId+'" role="tooltip">'+esc(purchaseList)+'</span></span>'+
        '<span aria-label="Consumed value '+esc(money(value))+'">'+money(value)+'</span>'+
        '<span>'+ (energy==null?"—":fmt(energy)+" E")+'</span></div>';
    }).join("")+'</div>';
  }
  function timeUntilBarFull(key){
    const state=tornGuideApi.state,bars=payload("bars","bars"),bridge=state.bridge;
    const snapshot=state.fetchedAt?.bars;
    const bridgeAt=bridge?.fields?.includes(key)&&bridge.timestamp>Number(snapshot||0)?bridge.timestamp:null;
    if((!snapshot||state.errors?.bars)&&!bridgeAt)return null;
    const bar=tornBarProjection(key,bars?.[key],bridgeAt??snapshot);
    if(!bar||bar.current>=bar.maximum)return null;
    return bar.until+(Math.ceil((bar.maximum-bar.current)/bar.step)-1)*bar.interval;
  }
  function barWarning(key){
    const remaining=timeUntilBarFull(key);
    const [label,icon]=key==="happy"?["Low Happy","🍬"]:["Low Energy","⚡"];
    return '<span class="growth-bar-warning" data-growth-bar-warning="'+key+'" tabindex="0" aria-label="'+label+'" aria-describedby="growth-bar-timing-'+key+'" '+(remaining===null?"hidden":"")+'>'+
      '<span class="growth-warning-icon" aria-hidden="true">'+icon+'</span>'+
      '<span class="growth-bar-tooltip" role="tooltip"><strong>'+label+'</strong>'+
      '<span id="growth-bar-timing-'+key+'" data-growth-bar-timing>'+(remaining===null?"":tornTctClock.formatDuration(remaining)+" until full")+'</span></span></span>';
  }
  function plannedSteps(execution,names,fmt){
    const clock=t=>Number.isFinite(t)?(Math.floor(t/86400)>0?"D"+(Math.floor(t/86400)+1)+" · ":"")+Math.floor(t%86400/3600)+"h "+Math.floor(t%3600/60)+"m":"";
    return execution.filter(step=>(step.type!=="train"||step.energy>0)&&
      (!["candy","dvd"].includes(step.type)||step.quantity>0)).map(step=>{
      const wait=["wait","autoWait"].includes(step.type);
      const duration=wait&&Number.isFinite(step.end)&&Number.isFinite(step.at)?Math.max(0,step.end-step.at):null;
      let label=names[step.type]??step.type;
      if(wait){
        label=tornTrainSequence.waitTitle(step.reason??"")+(duration===null?"":" "+tornTctClock.formatDuration(duration));
      }else{
        if(step.type==="train")label+=" · "+fmt(step.energy)+" E";
        if(["candy","dvd"].includes(step.type))label+=" × "+fmt(step.quantity);
        if(step.reason)label+=" · "+step.reason;
      }
      return '<li><time>'+esc(clock(step.at))+'</time><span>'+esc(label)+'</span></li>';
    }).join("");
  }
  function rankedWar(now){
    const state=tornGuideApi.state;
    const war=payload("factionWars","wars")?.ranked;
    const start=Number(war?.start)*1000,end=Number(war?.end)*1000;
    if(!Number.isFinite(start)||start<=0||end>0&&end<=now||Number(war?.winner)>0)return null;
    const mode=typeof war.template?.mode==="string"?war.template.mode:null;
    const freshness=tornTrainSequence.liveSourceState(state,"factionWars",now);
    return {start,end:end>0?end:null,mode,stale:!freshness.ready,source:freshness.ready?"Faction API":"Last known faction API ("+freshness.status+")"};
  }
  function warStackAdvice(war,settings,live,held,avoidDrugs,now){
    return tornActivityScheduler.warPreparation(war,live,held,avoidDrugs,now);
  }
  function energyWarAdvice(training,now=Date.now()){
    const settings=energyWarSettings(),war=currentActivityWar(now);
    if(!war)return null;
    if(trainingRecoveryHeld())return {...war,first:war.cutoff,due:null,doses:[],blocked:true,active:now>=war.cutoff,label:"War schedule retained; training recovery must be reviewed before stacking advice."};
    const state=tornGuideApi.state,inventory=state.inventory.Drug;
    const catalog=payload("itemCatalog","items"),items=Array.isArray(catalog)?catalog:Object.values(catalog||{});
    const xanax=items.find(item=>normalize(item.name)==="xanax");
    const held=Array.isArray(inventory)&&!state.inventoryErrors?.Drug?inventory.reduce((sum,item)=>{
      const id=item.id??item.item_id??item.item?.id;
      return normalize(item.name??item.item?.name)==="xanax"||xanax&&id!=null&&String(id)===String(xanax.id)?
        sum+Math.max(0,Number(item.quantity??item.amount)||0):sum;
    },0):null;
    const fresh=key=>Number(state.fetchedAt?.[key]||0)>0&&now-Number(state.fetchedAt[key])<5*60000&&!state.errors?.[key];
    const stockFresh=Number(state.fetchedAt?.["inventory:Drug"]||0)>0&&now-Number(state.fetchedAt["inventory:Drug"])<5*60000;
    const live=fresh("bars")&&fresh("cooldowns")?recoverySnapshot(now):null,blocked=tornTrainSequence.liveAccountStatus(state,now).blocked;
    const advice=war.stale||blocked?{phase:war.phase,first:war.cutoff,due:null,doses:[],label:war.stale?"Last known war schedule · refresh to verify":"Training and war stacking paused · verify player status"}:warStackAdvice(war,settings,live,stockFresh?held:null,training.avoidWarDrugs,now);
    return {...war,...advice,blocked,drugWait:!war.stale&&!blocked&&live?.drug>0,active:now>=war.cutoff,attacks:tornActivityScheduler.warAttackSummary(war,now)};
  }
  function warAttackPanel(summary){
    return '<small>'+(summary?"Recent outgoing ranked-war attacks: "+number(summary.attacks)+" · respect "+number(summary.respect)+(summary.limited?" · history truncated":""):"Attack data not loaded or unavailable")+'</small><button type="button" data-activity-war-refresh>Refresh war attacks</button>';
  }
  function warProgressText(advice){
    return advice.energy==null?"Stack and readiness unverified":number(advice.energy)+" / 1,000 E · "+advice.doses.length+" future doses"+(advice.projectedEnergy==null?"":" · "+number(advice.projectedEnergy)+" E projected");
  }
  function warDisplay(advice,now=Date.now()){
    if(advice.stale||advice.blocked||advice.due==null&&advice.phase!=="active")return {status:"Verify War Readiness",next:advice.label};
    if(advice.phase==="active")return {status:"Ranked War Active",next:advice.label};
    if(advice.drugWait&&advice.doses?.length&&advice.due>now)return {status:"Waiting for Drug Cooldown",next:advice.label.replace(/^Wait, then /,"")};
    if(advice.doses?.length)return {status:"Stacking for Ranked War",next:advice.label.replace(/^Wait, then /,"")};
    return {status:"Preserving Energy for War",next:advice.label};
  }
  function warCounter(advice){
    const display=warDisplay(advice);
    return '<div class="growth-next-step" data-war-counter data-ready="'+(advice.due!=null&&advice.due<=Date.now()&&!advice.stale&&!advice.blocked)+'" '+(advice.due!=null?'data-war-due="'+advice.due+'"':"")+'><div class="growth-counter-header"><small class="growth-counter-title">Ranked war · '+esc(new Date(advice.start).toISOString().slice(0,16).replace("T"," ")+" TCT")+(advice.mode?" · "+esc(advice.mode):"")+'</small><div class="growth-counter-actions">'+growthWatchIndicator(growthWatchStatus(null,warTraining,advice))+
      '<button type="button" data-growth-session="war-refresh" aria-label="Refresh war preparation" title="Refresh war preparation" '+(recoveryBusy?"disabled":"")+'><span aria-hidden="true">↻</span></button></div></div><strong class="growth-next-clock growth-stage" data-war-stage>'+esc(display.status)+'</strong><strong class="growth-next-clock" data-war-clock>'+
      esc(advice.stale?"Verify":advice.phase==="active"?"Active":advice.due==null?"Verify":advice.due>Date.now()?tornTctClock.formatDuration((advice.due-Date.now())/1000):"Ready")+
      '</strong><span data-war-step>Next: '+esc(display.next)+'</span>'+
      (advice.phase==="active"&&!advice.stale?warAttackPanel(advice.attacks):'<small data-war-progress>'+esc(warProgressText(advice))+'</small>')+recoveryPanel()+'</div>';
  }
  let warTraining=null;
  function recoveryHoldPanel(){
    const id=tornGuideApi.state.identity?.id;
    try{if(localStorage.getItem("torn-city-guide:restore-journal:v1:"+id)!==null)return '<div class="growth-card"><div class="growth-warning"><strong>Account Restore Interrupted</strong><p>Training is held until the restore journal is resolved in Settings → Data &amp; Backup.</p></div></div>';}catch{}
    const stage=typeof tornTrainingRecovery==="undefined"?{error:"Recovery module unavailable; reload the guide."}:tornTrainingRecovery.readStage(localStorage,tornGuideApi.state.identity?.id),session=stage?.session;
    return '<div class="growth-card"><div class="growth-warning"><strong>Restored Training Session Held</strong><p>Training recommendations, detection and cycle accounting are paused. Imported actions will not resume automatically.</p>'+
      (session?'<p>'+esc(session.label)+' · '+esc(session.stat)+' · '+session.index+' / '+session.actions.length+' confirmed</p><small>Backup created: '+esc(sessionTime(stage.backupCreatedAt))+' · Last confirmation: '+esc(session.lastConfirmed==null?"Unknown":sessionTime(session.lastConfirmed))+' · Estimated cycle cost: '+esc(session.cycleSpend==null?"Unknown":"$"+number(session.cycleSpend))+'</small>':'<p>'+esc(stage?.error??"Recovery state unavailable")+'</p>')+
      '<p>Open Settings → Data &amp; Backup to inspect recovery evidence or release the hold without resuming.</p></div></div>';
  }
  function growthCard(training,prefs){
    if(trainingRecoveryHeld())return recoveryHoldPanel();
    const activeSession=loadTrainingSession();
    const p=training.plan;
    let setup=growthSettings()+(prefs.weeklyBudget==null&&prefs.priority==="growth"?'<div class="growth-warning">Set a weekly training budget in Focus. <button type="button" data-growth-budget>Set budget</button></div>':"");
    warTraining=training;
    const war=energyWarAdvice(training);
    if(war?.active&&!training.activity.statusBlocked)return '<div class="growth-card">'+setup+warCounter(war)+(activeSession?'<small>'+(war.stale?"Training session retained; verify war schedule before replanning.":"Training session held; reconciling before war preparation.")+'</small>':"")+'</div>';
    if(training.activity.blocked)return '<div class="growth-card">'+setup+'<div class="growth-warning">Training paused · '+esc(training.activity.reason??"reserved activity")+'</div>'+(activeSession?'<small>Active session retained · '+activeSession.index+' / '+activeSession.actions.length+' steps confirmed.</small>':"")+'<a href="#calendar">View calendar</a></div>';
    if(activeSession&&sessionDeadlineConflict(activeSession,training.activity))return '<div class="growth-card">'+setup+'<div class="growth-warning">Current cycle conflicts with '+esc(training.activity.reason??"a scheduled activity")+'. Confirming completed actions and replanning the remainder.</div>'+recoveryPanel()+'</div>';
    if(training.activity.deadline!=null)setup+='<small data-activity-cutoff="'+training.activity.deadline+'">Training cutoff: '+esc(tornActivityScheduler.time(training.activity.deadline))+' · '+esc(training.activity.reason??"activity")+'</small>';
    if(war)setup+='<small data-war-switch="'+war.first+'">Ranked war starts '+esc(new Date(war.start).toISOString().slice(0,16).replace("T"," ")+" TCT")+(war.mode?" · "+esc(war.mode):"")+'</small>';
    if(activeSession&&!p?.stats){const fmt=v=>v==null?"Unavailable":number(Math.round(v));const names={xanax:"Xanax",ecstasy:"Ecstasy",candy:"Candy",dvd:"Erotic DVD",refill:"Points refill"};return '<div class="growth-card">'+setup+gymMembership(activeSession.gym)+sessionPanel(p??{},training,names,fmt)+growthDetails([["summary","Summary",growthPlanSequence(activeSession)+replayPanel(activeSession,fmt)+growthPeriodSummary(activeSession.periods,fmt,activeSession.actions.slice(0,activeSession.index))],["steps","Steps",'<div class="growth-execution"><ol>'+sessionSteps(activeSession,names,fmt)+'</ol></div>'],["build","Build",'<p class="fine-print">Build data unavailable. <a href="#stats">View Stats</a></p>']])+'</div>';}
    if(p?.needsBuild)return setup+'<div class="growth-warning">Choose a stat build before receiving training recommendations. <a href="#stats">Select build</a></div>';
    if(!p?.stats)return setup+'<p class="fine-print">'+esc(p?.detail??"Load battle stats and choose a build in Stats.")+'</p><a href="#stats">View Stats</a>';
    const prog=p.program,fmt=v=>v==null?"Unavailable":number(Math.round(v)),perc=v=>Number.isFinite(v)?v.toFixed(1)+"%":"Unavailable";
    const max=Math.max(1,...p.stats.map(s=>s.target));
    const stats=p.stats.map(s=>'<div class="growth-stat '+(s.key===p.statKey?"is-target":"")+'"><div class="growth-stat-label"><strong>'+esc(s.label)+'</strong><span>'+fmt(s.current)+' / '+fmt(s.target)+'</span></div><div class="growth-stat-track" title="Current '+fmt(s.current)+'; build target '+fmt(s.target)+'"><span class="growth-target-bar" style="width:'+Math.min(100,s.target/max*100)+'%"></span><span class="growth-current-bar" style="width:'+Math.min(100,s.current/max*100)+'%"></span></div></div>').join("");
    const chips=p.perks.map(x=>'<span class="growth-perk" title="'+esc(x.items.map(y=>y.text).join("; "))+'">'+esc(x.group==="book"?"Book active":x.group.charAt(0).toUpperCase()+x.group.slice(1))+' '+(x.total>0?"+":"")+perc(x.total)+'</span>');
    if(p.bliss)chips.push('<span class="growth-perk">Ignorance Is Bliss</span>');
    if(training.educationRisk)chips.push('<span class="growth-warning">Education risk · no drugs</span>');
    const names={xanax:"Xanax",ecstasy:"Ecstasy",candy:"Candy",dvd:"Erotic DVD",train:"Train "+p.stat,refill:"Points refill",wait:"Wait",autoWait:"Wait",externalHappy:"External happiness"};
    const execution=plannedSteps(prog?.cycleExecution??prog?.execution??[],names,fmt);
    const timer=sessionPanel(p,training,names,fmt);
    const instruction=gymMembership(p.gym??activeSession?.gym);
    const build='<div class="growth-build-content"><div class="growth-row"><strong>'+esc(p.build)+'</strong><a href="#stats">View</a></div>'+stats+'<small>'+fmt(p.remaining)+' remaining to build target · '+perc(p.modifier)+' modeled gain modifier</small></div>';
    const perkChips=chips.length?'<div class="growth-perks">'+chips.join("")+'</div>':"";
    const summary=activeSession?growthPlanSequence(activeSession)+replayPanel(activeSession,fmt)+growthPeriodSummary(activeSession.periods,fmt,activeSession.actions.slice(0,activeSession.index)):
      prog?'<div class="growth-plan">'+(prog.source==="optimal-budget"?growthPlanSequence(prog):'<strong class="growth-accent growth-program-title">'+esc(prog.label)+'</strong>')+growthPeriodSummary(prog.periods,fmt)+'</div>':
      '<p class="fine-print">No training program available. Set a budget and review Stats.</p>';
    const session=loadTrainingSession();
    const steps=session?'<div class="growth-execution"><small>Confirmed times and adjusted estimates (local time).</small><ol>'+sessionSteps(session,names,fmt)+'</ol></div>':prog?'<div class="growth-execution"><small>Elapsed time from simulation start. Follow live cooldowns; estimates may change.</small><ol>'+execution+'</ol></div>':'<p class="fine-print">No training steps available.</p>';
    const tabs=[["summary","Summary",summary+perkChips],["steps","Steps",steps],["build","Build",build]];
    return '<div class="growth-card">'+setup+instruction+timer+growthDetails(tabs)+'</div>';
  }
  function refillStatus(kind,now=Date.now()){
    const state=tornGuideApi.state,stamp=Number(state.fetchedAt?.refills||0);
    const refill=payload("refills","refills");
    const used=refill?.[kind+"_refill_used"]??refill?.[kind]?.used;
    if(!stamp||state.errors?.refills||typeof used!=="boolean")return "";
    const day=Math.floor(now/86400000);
    return used&&Math.floor(stamp/86400000)===day
      ?"Refill in "+tornTctClock.formatDuration(Math.ceil(((day+1)*86400000-now)/1000))
      :"Refill Available";
  }
  function refillIndicator(kind){
    const status=refillStatus(kind);
    return '<a class="rec-header-refill rec-'+kind+'-refill '+(status==="Refill Available"?"is-available":"")+'" data-rec-refill="'+kind+'" href="https://www.torn.com/page.php?sid=points" title="'+(kind==="energy"?"Energy":"Nerve")+' refill · Points shop" '+(status?"":"hidden")+'>'+esc(status)+'</a>';
  }
  let deadlineRetryAt=0,lastActivityState=null,lastRehabCheck=0,lastWarCheck=0;
  function sessionDeadlineConflict(session,activity,now=Date.now()){
    if(trainingRecoveryHeld()||!session||session.index>=session.actions.length)return false;
    return activity.blocked||tornActivityScheduler.conflicts(sessionSchedule(session,now),activity.deadline,now,activity.war?.cutoff===activity.deadline,Math.max(28800000,activity.war?.cd??0));
  }
  async function replanActivityConflict(view,session){
    if(trainingRecoveryHeld()||recoveryBusy||Date.now()<deadlineRetryAt)return;
    recoveryBusy=true;const owner=sessionOwner,requested=Date.now();
    recoveryMessage="Activity deadline · verifying completed training before replanning.";
    try{
      await tornGuideApi.loadPage("energy",true);
      if(sessionOwner!==owner||loadTrainingSession()!==session)return;
      const st=tornGuideApi.state;
      if(["bars","cooldowns","battlestats"].some(k=>Number(st.fetchedAt?.[k]||0)<requested||st.errors?.[k]))throw Error("Fresh training data unavailable");
      const activity=activityLimits();
      if(activity.statusBlocked||activity.war?.stale){
        recoveryMessage="Training session retained; verify account status and war schedule.";return;
      }
      observeTrainingStep(session);reconcileTrainingProgress(session);
      if(!sessionDeadlineConflict(session,activity)&&session.index<session.actions.length)return;
      // Preserve the completed prefix; unknown partial-cycle spend is
      // conservatively charged at the old cycle estimate, never refunded.
      const historyKey="torn-city-guide:activity-training-history:"+owner;
      let history=[];try{history=JSON.parse(localStorage.getItem(historyKey))||[];}catch{}
      if(!Array.isArray(history))history=[];
      history.push({started:session.started,ended:Date.now(),reason:"activity deadline",label:session.label,confirmed:session.actions.slice(0,session.index),completed:session.completed??{},reservedSpend:session.cycleSpend??null});
      writeAccountValue(historyKey,JSON.stringify(history.slice(-30)));
      accountForCycle(session);
      trainingSession=null;saveTrainingSession();
      recoveryMessage="Training reconciled · activity deadline applied.";readinessExpires=Date.now()+3500;
    }catch(error){deadlineRetryAt=Date.now()+120000;recoveryMessage="Training paused: "+String(error.message??error)+". Refresh to retry.";}
    finally{recoveryBusy=false;if(view.isConnected)refreshActivityView(view);}
  }
  function tickGrowth(){
    const view=document.getElementById("topic-view"),route=tornGuideApi.routeName();
    if(route==="home"&&view?.isConnected&&!view.hidden){
      const now=Date.now();
      for(const board of view.querySelectorAll("[data-crime-state-expires]")){
        if(Number(board.dataset.crimeStateExpires)>now||board.contains(document.activeElement))continue;
        const name=board.querySelector("[data-crime-observation]")?.dataset.crimeName;
        if(!name)continue;
        const progress=crimeProgress(name),cs=skill(name)??(Number.isFinite(progress?.skill)?progress.skill:null),total=reference.find(x=>x[0]===name)?.[2]??0;
        const count=Array.isArray(progress?.uniques)?new Set(progress.uniques.map(x=>x.id)).size:null;
        board.outerHTML=crimeOptionRows(name,cs,tornRoadmap.preferences().jailRisk,incompleteUniquesOnly,count!==null&&total>0&&count>=total);
      }
    }
    if(view?.isConnected&&!view.hidden&&(route==="home"||route==="calendar")){
      const activity=activityLimits(),session=loadTrainingSession();
      const now=Date.now();
      if(!trainingRecoveryHeld()&&activity.war?.phase==="stacking"&&autoTrainingWatch()&&tornGuideApi.isConnected()&&!recoveryBusy&&!tornGuideApi.state.loading&&now-lastWarCheck>=120000){
        lastWarCheck=now;void tornGuideApi.loadPage("warPreparation",true).catch(()=>{});
      }
      const pendingRehab=tornActivityScheduler.events().some(e=>e.kind==="rehab"&&!e.completedAt&&!e.recoveryReview&&e.rehabBaseline&&e.start<=now&&e.end+86400000>now);
      if(pendingRehab&&!recoveryBusy&&!tornGuideApi.state.loading&&now-lastRehabCheck>=300000){lastRehabCheck=now;void tornGuideApi.loadPage("rehabProgress",false).catch(()=>{});}
      const key=[activity.war?.phase??"",activity.deadline??"",activity.blocked,activity.reason??""].join("|");
      // A deadline at 'now' changes each second; compare the reservation
      // identity while blocked rather than rebuilding the UI every tick.
      const stableKey=activity.blocked?[activity.war?.phase??"","blocked",activity.reason??""].join("|"):key;
      if(lastActivityState!==null&&lastActivityState!==stableKey&&!recoveryBusy)refreshActivityView(view);
      lastActivityState=stableKey;
      if(!activity.statusBlocked&&!activity.war?.stale&&sessionDeadlineConflict(session,activity)&&!recoveryBusy&&Date.now()>=deadlineRetryAt){void replanActivityConflict(view,session);return;}
    }else lastActivityState=null;
    watchTraining(view);
    updateGrowthWatchIndicator(view);
    for(const indicator of document.querySelectorAll("[data-rec-refill]")){
      const status=refillStatus(indicator.dataset.recRefill);
      indicator.hidden=!status;
      indicator.classList.toggle("is-available",status==="Refill Available");
      if(indicator.textContent!==status)indicator.textContent=status;
    }
    if(readinessExpires&&Date.now()>=readinessExpires){
      readinessExpires=0;
      if(["Readiness updated.","Training progress detected."].includes(recoveryMessage))recoveryMessage="";
      document.querySelector("[data-readiness-status]")?.remove();
    }
    for(const warning of document.querySelectorAll("[data-growth-bar-warning]")){
      if(warning.parentElement.closest("[hidden]"))continue;
      const remaining=timeUntilBarFull(warning.dataset.growthBarWarning);
      warning.hidden=remaining===null;
      const timing=warning.querySelector("[data-growth-bar-timing]");
      const value=remaining===null?"":tornTctClock.formatDuration(remaining)+" until full";
      if(timing.textContent!==value)timing.textContent=value;
    }
    const warPanel=document.querySelector("[data-war-counter]"),warSwitch=document.querySelector("[data-war-switch]");
    if(warPanel&&warTraining&&!warPanel.closest("[hidden]")){
      const war=energyWarAdvice(warTraining);
      if(war?.active){
        const clock=warPanel.querySelector("[data-war-clock]"),step=warPanel.querySelector("[data-war-step]");
        const value=war.stale?"Verify":war.phase==="active"?"Active":war.due==null?"Verify":war.due>Date.now()?tornTctClock.formatDuration((war.due-Date.now())/1000):"Ready";
        const display=warDisplay(war),stage=warPanel.querySelector("[data-war-stage]");
        warPanel.dataset.ready=String(war.due!=null&&war.due<=Date.now()&&!war.stale&&!war.blocked);
        if(war.due==null)delete warPanel.dataset.warDue;else warPanel.dataset.warDue=String(war.due);
        if(clock.textContent!==value)clock.textContent=value;
        if(stage&&stage.textContent!==display.status)stage.textContent=display.status;
        if(step.textContent!=="Next: "+display.next)step.textContent="Next: "+display.next;
        const progress=warPanel.querySelector("[data-war-progress]");if(progress)progress.textContent=warProgressText(war);
      }else refreshRecommendations(document.getElementById("topic-view"));
    }else if(warSwitch&&Number(warSwitch.dataset.warSwitch)<=Date.now()){
      refreshRecommendations(document.getElementById("topic-view"));
    }
    const el=document.querySelector("[data-growth-due]");if(!el||el.closest("[hidden]"))return;
    if(!recoveryBusy&&autoTrainingWatch()){
      const active=loadTrainingSession();
      if(reconcileTrainingProgress(active)){
        const view=document.getElementById("topic-view");
        if(view){
          if(active.index>=active.actions.length)void reviewNextCycle(view,active);
          else refreshRecommendations(view);
        }
        return;
      }
    }
    const session=loadTrainingSession();if(session&&session.index<session.actions.length){const rows=sessionSchedule(session),next=rows[session.index];el.dataset.growthDue=String(next.due);
      const stage=el.querySelector("[data-growth-stage]"),step=el.querySelector("[data-growth-step]");
      const status=energySessionStatus(session,next),label="Next: "+energyAction(next.step,session.stat,number);
      if(stage&&stage.textContent!==status)stage.textContent=status;
      if(step&&step.textContent!==label)step.textContent=label;
      const finish=document.querySelector("[data-growth-finish]");if(finish)finish.textContent=sessionTime(rows.at(-1)?.due);for(const row of document.querySelectorAll("[data-session-row]")){const x=rows[Number(row.dataset.sessionRow)],t=row.querySelector("[data-session-time]");if(x&&t){const value=sessionTime(x.due);if(t.textContent!==value)t.textContent=value;}}}
    if(session&&session.index<session.actions.length){
      const action=session.actions[session.index],due=Number(el.dataset.growthDue);
      for(const span of document.querySelectorAll('[data-session-wait="'+session.index+'"]')){
        const wait=action.waitsBefore?.[Number(span.dataset.waitIndex)];
        if(wait){
          const value=sessionWaitText(wait,due,action.at,true);
          if(span.textContent!==value)span.textContent=value;
        }
      }
    }
    const remaining=(Number(el.dataset.growthDue)-Date.now())/1000;
    if(!Number.isFinite(remaining))return;
    const ready=remaining<=0;
    const clock=el.querySelector("[data-growth-clock]");
    if(!session&&ready&&trainingDraft){
      // Countdown expiry does not prove readiness: recheck the Start control.
      const prep=prepState(trainingDraft.plan,trainingDraft.training.blockDrugs);
      const display=energyPrepStatus(prep,trainingDraft.plan?.program,trainingDraft.plan?.stat,number),stage=el.querySelector("[data-growth-stage]"),step=el.querySelector("[data-growth-step]"),button=el.querySelector('[data-growth-session="start"]');
      el.dataset.ready=String(prep.ready);
      if(prep.due==null)delete el.dataset.growthDue;else el.dataset.growthDue=String(prep.due);
      if(clock){clock.hidden=prep.due==null;clock.textContent=prep.due==null?"":tornTctClock.formatDuration(Math.max(0,(prep.due-Date.now())/1000));}
      if(stage&&stage.textContent!==display.status)stage.textContent=display.status;
      if(step&&step.textContent!=="Next: "+display.next)step.textContent="Next: "+display.next;
      if(button)button.disabled=!prep.ready;
      return;
    }
    el.dataset.ready=String(ready);
    const value=ready?"Ready":tornTctClock.formatDuration(remaining);
    if(clock&&clock.textContent!==value)clock.textContent=value;
  }
  function affordableMissionBooks(missions,now=Date.now()){
    if(!Number.isSafeInteger(missions?.credits)||!Array.isArray(missions?.rewards))return [];
    return missions.rewards.filter(offer=>String(offer?.details?.type).toLowerCase()==="book"&&
      typeof offer.details.name==="string"&&offer.details.name.trim()&&
      Number.isSafeInteger(offer.amount)&&offer.amount>0&&
      Number.isSafeInteger(offer.cost)&&offer.cost>0&&offer.cost<=missions.credits&&
      Number.isFinite(offer.expires_at)&&offer.expires_at*1000>now);
  }
  function useAndCollect(readyItems,stocks){
    const ready=[...readyItems];
    if(!tornGuideApi.state.errors?.missions){
      for(const book of affordableMissionBooks(payload("missions","missions"))){
        ready.push(recItem(book.details.name,"Mission reward · "+number(book.cost)+" Mission Credits","https://www.torn.com/loader.php?sid=missions"));
      }
    }
    for(const stock of stocks.filter(x=>x.ready===true&&x.active&&!x.passive&&x.freq>0&&x.description.trim()&&x.description!=="Benefit unavailable")
      .sort((a,b)=>a.ticker.localeCompare(b.ticker))){
      ready.push(recItem("Collect "+stock.ticker+" dividend",stock.description,"#stocks"));
    }
    return ready.length?'<ul class="crime-recommendations rec-advice">'+ready.join("")+'</ul>':'<p class="fine-print">Nothing ready to use or collect.</p>';
  }
  function adviceSections(count,trainingRecommendation){
    const prefs=tornRoadmap.preferences(),activities=tornRoadmap.selectedStyles(),growth=prefs.priority==="growth",completion=prefs.priority==="completion",risk=prefs.risk;
    const rows={growth:[],consume:[],crime:[],education:[],money:[]};
    const add=(key,title,detail,link)=>rows[key].push(recItem(title,detail,link));
    const n=v=>v!=null&&v!==""&&Number.isFinite(Number(v))?Number(v):null;
    const {iconFresh,addictionDebuff,highAddiction,enrolled,protectedEducation,educationRisk,blockDrugs,plan}=trainingRecommendation;
    if(educationRisk){
      const detail="Active education course · addiction-related battle-stat penalty "+Math.max(...addictionDebuff)+"%. Avoid all drugs until addiction is reduced. Course dismissal can occur at 5%; restarting loses progress.";
      add("education","Education dismissal risk",detail,"#education");
    }else if(enrolled&&highAddiction&&protectedEducation)add("education","Education protected by Restraint","The active job perk protects enrollment, but addiction still affects other gameplay; consider rehabilitation.","#education");
    const bars=payload("bars","bars"),cd=payload("cooldowns","cooldowns");
    const energy=n(bars?.energy?.current),cap=n(bars?.energy?.maximum),happy=n(bars?.happy?.current),happyCap=n(bars?.happy?.maximum),nerve=n(bars?.nerve?.current);
    const drug=n(cd?.drug),booster=n(cd?.booster);
    const program=plan?.program, costs=program?.costs??{};
    // Training owns all training consumables. Only recommend independent
    // crime consumables when their shared cooldowns leave training untouched.
    const session=loadTrainingSession(),now=Date.now();
    const upcoming=session?sessionSchedule(session,now).filter(x=>!x.done).map(x=>({type:x.step.type,due:x.due})):program?(program.execution??[]).filter(actionable).map(x=>({type:x.type,due:now+x.at*1000})):[];
    const knownPlan=!!session||!!program;
    const nextBooster=upcoming.find(x=>["candy","dvd"].includes(x.type));
    const usesDrugs=upcoming.some(x=>["xanax","ecstasy"].includes(x.type));
    const crimePriority=completion||prefs.priority==="crime";
    const crimeActivity=crimePriority||activities.some(x=>["Crime","OC"].includes(x));
    const nerveRoom=nerve!=null&&n(bars?.nerve?.maximum)!=null&&nerve<n(bars.nerve.maximum);
    const cdStamp=Number(tornGuideApi.state.fetchedAt?.cooldowns||0);
    const cooldownKnown=cdStamp>0&&!tornGuideApi.state.errors?.cooldowns;
    const elapsed=Math.max(0,(now-cdStamp)/1000);
    const drugLeft=cooldownKnown&&drug!==null?Math.max(0,drug-elapsed):null;
    const boosterLeft=cooldownKnown&&booster!==null?Math.max(0,booster-elapsed):null;
    const marijuana=count("Cannabis","Drug");
    if(!trainingRecoveryHeld()&&crimeActivity&&nerveRoom&&iconFresh&&!highAddiction&&!blockDrugs&&prefs.odRisk!=="low"&&drugLeft===0&&marijuana>0&&(crimePriority||knownPlan&&!usesDrugs)){
      add("consume","Cannabis · 1 ("+number(marijuana)+" held)",crimePriority&&usesDrugs?"Completion priority: Cannabis may delay training drugs. The locked plan will wait for the drug cooldown.":"No remaining training drug steps. Use for Nerve; normal drug cooldown is 60–90 minutes.","#crime");
    }
    const alcohol=tornGuideApi.state.inventory.Alcohol;
    if(crimeActivity&&nerveRoom&&knownPlan&&boosterLeft!==null&&Array.isArray(alcohol)&&!tornGuideApi.state.inventoryErrors?.Alcohol){
      const held=alcohol.reduce((sum,x)=>sum+Math.max(0,Math.floor(n(x.amount??x.quantity)??0)),0);
      const timing=session?.timing??program?.timing??{};
      const boosterCap=Math.max(0,Number(timing.boosterCap)||86400);
      // One hour normally; conservatively allow 30% extra if alcohol-specific
      // cooldown modifiers are not modeled. Never exceed the known cap.
      const unit=4680;
      const room=Math.max(0,boosterCap-boosterLeft);
      // Require the entire resulting cooldown to clear before the first
      // planned candy/DVD, rather than merely allowing one more booster.
      const window=nextBooster?Math.max(0,(nextBooster.due-now)/1000-boosterLeft):Infinity;
      // A not-yet-started plan may be started immediately; its estimated
      // preparation timing is not a guaranteed free booster window.
      const safeWindow=!session&&nextBooster?0:window;
      const amount=Math.max(0,Math.min(held,Math.floor(room/unit),Math.floor(safeWindow/unit),Math.ceil(n(bars.nerve.maximum)-nerve)));
      if(amount>0)add("consume","Alcohol · up to "+number(amount),number(held)+" held · "+(nextBooster?"Cooldown clears before the next training booster at "+sessionTime(nextBooster.due):"No remaining candy or DVD steps")+" · Conservative cooldown allowance.","#crime");
    }
    const crimeRefreshIds=[];
    rows.crime.push(crimeRecommendation(prefs.jailRisk,completion,crimeRefreshIds));

    loadEducationPreference();
    const m=educationModel();
    if(m.known&&m.courses.length){
      const groups=educationPaths.filter(([name])=>name!=="Other Perks");
      const preferred=educationView.groupBy==="effect"&&educationView.effect!=="all"?educationView.effect:null;
      const weights={"Gym Perks":growth?5:1,"Passive Battle Stats":activities.some(x=>["War","Mug","Bounty","Attack"].includes(x))?4:1,"Company Perks":prefs.priority==="company"||activities.includes("Business")?5:0,"Crime Perks":activities.some(x=>["Crime","OC"].includes(x))?5:1,"Jail Perks":activities.includes("Jail")?5:0,"Medical Perks":activities.includes("Revive")?5:0,"Attacking Perks":activities.some(x=>["War","Mug","Bounty","Attack"].includes(x))?4:0};
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
    const stocks=stockRows(),collectionStocks=tornGuideApi.state.errors?.stocks?[]:stocks,company=prefs.priority==="company"||activities.includes("Business"),education=prefs.priority==="education";
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
    return recommendationTypes.filter(([id])=>id!=="restock"&&recEnabled.has(id)).map(([id,label])=>recTileStart(id,label,crimeRefreshIds)+(id==="growth"?growthCard(trainingRecommendation,prefs):id==="calendar"?calendarCard(trainingRecommendation,false,trainingRecommendation.calendarRows):id==="consume"?useAndCollect(rows.consume,collectionStocks):((id==="crime"?crimeFilters():id==="money"?'<div class="rec-oc-filters"><small>Public Tornsy data, no Torn key</small></div>':"")+'<ul class="crime-recommendations rec-advice">'+rows[id].join("")+'</ul>'+(id==="crime"?crimeFooter(crimeRefreshIds):"")))+recTileEnd).join("");
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
    const matches=(x,name)=>normalize(x.name??x.item?.name??itemsById.get(String(x.id??x.item_id??x.item?.id))?.name)===normalize(name);
    function count(name,hint){
      const cat=category(itemsByName.get(normalize(name)))||hint;
      // Search all fetched categories for positive holdings first; missing stock
      // is only inferred when the matching catalog category was fully loaded.
      const all=Object.entries(st.inventory).filter(([k])=>ready(k)).flatMap(([,list])=>list);
      if(cat&&ready(cat))return st.inventory[cat].filter(x=>matches(x,name)).reduce((n,x)=>n+qty(x),0);
      const owned=all.filter(x=>matches(x,name)).reduce((n,x)=>n+qty(x),0);
      return owned||null;
    }
    const prefs=tornRoadmap.preferences(),trainingRecommendation=trainingRecommendationContext(prefs);activityContext=trainingRecommendation;
    const program=trainingRecommendation.plan?.program,session=loadTrainingSession(),now=Date.now();
    const planCosts=session?{}:program?.restockCosts??{};
    if(session&&!sessionDeadlineConflict(session,trainingRecommendation.activity)&&!(session.drugRisk&&trainingRecommendation.blockDrugs)){
      const end=now+restockForecastDays*86400000;
      for(const {step,done,due} of sessionSchedule(session,now)){
        if(!done&&due<=end&&["xanax","ecstasy","dvd","candy","alcohol","refill"].includes(step.type)){
          planCosts[step.type]=(planCosts[step.type]??0)+(step.quantity??1);
        }
      }
    }
    const trainingSource=(session?.label??program?.label??"Training plan")+" · "+restockForecastDays+"-day forecast";
    const buckets={training:new Map(),current:new Map(),stock:new Map(),crime:new Map(),oc:new Map()};
    const settingsCategories=new Map(), activeOptional=new Set(), rowCategories=new Map();
    function setting(name,hint,target=0,aggregate=false){
      const nameKey=normalize(name);
      const cat=category(itemsByName.get(nameKey))||rowCategories.get(nameKey)||hint||"Other";
      if(cat==="Book")return null;
      const baseline=aggregate?0:categoryStockDefault(name,cat);
      target=Math.max(target,baseline);
      if(nameKey==="blankdvds")target=1;
      const key=aggregate?"category:"+cat:nameKey;
      if(!aggregate)rowCategories.set(nameKey,cat);
      if(!settingsCategories.has(cat))settingsCategories.set(cat,new Map());
      const group=settingsCategories.get(cat),existing=group.get(key);
      if(existing)existing.target=Math.max(existing.target,target);
      else group.set(key,{name,key,target,baseline,category:cat,aggregate});
      return key;
    }
    for(const item of catalog){
      const cat=category(item);
      if(item?.name&&tornGuideApi.inventoryTypes.includes(cat))setting(item.name,cat);
    }
    for(const cat of tornGuideApi.inventoryTypes){
      for(const item of ready(cat)?st.inventory[cat]:[]){
        const name=item.name??item.item?.name??itemsById.get(String(item.id??item.item_id??item.item?.id))?.name;
        if(name)setting(name,cat);
      }
    }
    function add(bucket,item,hint,target,reason,level,custom=false){
      const key=normalize(item),optional=bucket==="stock"||bucket==="crime"||bucket==="oc";
      const cat=category(itemsByName.get(key))||rowCategories.get(key)||hint;
      if(cat==="Book"||/^book\s*:/i.test(item))return;
      if(optional&&!custom){
        setting(item,hint,target);
        activeOptional.add(key);
        const rule=restockRules.get(key);
        if(rule?.monitored===false)return;
        target=rule?.minimum??settingsCategories.get(cat??"Other")?.get(key)?.target??target;
      }
      if(bucket==="stock"&&restockRules.get(key)?.monitored===false)return;
      if(bucket==="training"&&cat&&!trainingRecommendation.inputs.sources["inventory:"+cat]?.ready)return;
      const observed=count(item,hint);
      const n=bucket==="training"&&key==="xanax"&&observed!==null?Math.max(0,observed-trainingRecommendation.options.reserveXanax):observed;
      if(n===null||n>=target)return;
      const marketPrice=bucket==="training"&&!trainingRecommendation.inputs.sources.itemCatalog.ready?null:market(item);
      const purchase=bucket==="stock"?reservePurchase(itemsByName.get(key),marketPrice):null;
      if(bucket==="stock"&&!purchase)return;
      const map=buckets[bucket],old=map.get(key);
      if(old){old.target=Math.max(old.target,target);if(!old.reasons.includes(reason))old.reasons.push(reason);old.level=Math.min(old.level,level??99);return;}
      map.set(key,{item,owned:n,target,reasons:[reason],price:purchase?.price??marketPrice,priceSource:purchase?.source,level:level??99});
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
    for(const [name,names,target,usage] of extraCrimeItems){
      const cs=skill(name);if(cs===null||cs<=1)continue;
      for(const item of names.split("|")){
        const cat=category(itemsByName.get(normalize(item)));
        const role=usage==="Equipment"&&["Tool","Enhancer"].includes(cat)?cat:usage;
        add("crime",item,cat,target,name+" "+role);
      }
    }
    for(const [level,name,tools,materials] of ocReference){
      if(!ocEnabled.has(level%2?level:level-1))continue;
      for(const item of tools.split("|").filter(Boolean))add("oc",item,null,1,"L"+level+" "+name+" · reusable",level);
      for(const item of materials.split("|").filter(Boolean))add("oc",item,null,1,"L"+level+" "+name+" · Consumable",level);
    }
    // The selected weekly program is the same object used by growth and consumable advice.
    const trainingItems=[["Xanax","Drug","xanax"],["Ecstasy","Drug","ecstasy"],["Erotic DVD","Booster","dvd"]];
    for(const [name,cat,key] of trainingItems){
      if(planCosts[key]>0&&!(cat==="Drug"&&trainingRecommendation.blockDrugs))add("training",name,cat,planCosts[key],trainingSource);
    }
    const categoryDefaults=[["Candy",50],["Alcohol",25],["Energy Drink",5]];
    const categoryReserve=(bucket,cat,target,reason,custom=false)=>{
      if(bucket==="stock"&&!custom){
        const key=setting(cat+" (any type)",cat,target,true),rule=restockRules.get(key);
        activeOptional.add(key);
        if(rule?.monitored===false)return;
        target=rule?.minimum??target;
      }
      if(!ready(cat)||!(target>0)||bucket==="training"&&cat==="Candy"&&!trainingRecommendation.inputs.sources["inventory:Candy"].ready)return;
      const owned=st.inventory[cat].reduce((n,x)=>n+qty(x),0);
      if(owned<target)buckets[bucket].set(cat,{item:cat+" (any type)",owned,target,reasons:[reason],price:null,level:99});
    };
    if(planCosts.candy>0)categoryReserve("training","Candy",planCosts.candy,trainingSource+" · Match planned happiness tier");
    if(planCosts.alcohol>0)categoryReserve("training","Alcohol",planCosts.alcohol,trainingSource);
    for(const [name,cat,target] of reserveDefaults){
      if(cat==="Drug"&&trainingRecommendation.blockDrugs)continue;
      add("stock",name,cat,target,"Optional reserve");
    }
    for(const [cat,target] of categoryDefaults){
      categoryReserve("stock",cat,target,"Optional category reserve");
    }
    for(const group of settingsCategories.values())for(const item of group.values()){
      const rule=restockRules.get(item.key);
      if(!(rule?.monitored??item.baseline>0)||activeOptional.has(item.key))continue;
      if(item.category==="Drug"&&trainingRecommendation.blockDrugs)continue;
      if(item.aggregate)categoryReserve("stock",item.category,rule.minimum??1,"Custom minimum",true);
      else add("stock",item.name,item.category,rule?.minimum??(item.target||1),rule?"Custom minimum":"Default reserve",undefined,true);
    }
    if(planCosts.refill>0){
      const owned=trainingRecommendation.inputs.points,target=planCosts.refill*30;
      if(Number.isFinite(owned)&&owned>=0&&owned<target){
        const raw=trainingRecommendation.inputs.sources.pointsCatalog.ready?payload("pointsCatalog","pointsmarket"):null;
        const prices=Object.values(raw||{}).map(x=>Number(x?.cost??x?.price??x?.cost_per_point)).filter(x=>Number.isFinite(x)&&x>0);
        buckets.training.set("points",{item:"Points",owned,target,price:prices.length?Math.min(...prices):null,reasons:[trainingSource],level:99});
      }
    }
    for(const [key,optional] of buckets.oc){
      const assigned=buckets.current.get(key);
      if(!assigned)continue;
      assigned.target=Math.max(assigned.target,optional.target);
      assigned.reasons.push(...optional.reasons.filter(reason=>!assigned.reasons.includes(reason)));
      buckets.oc.delete(key);
    }
    // Allocate only incremental purchases as targets rise across tabs.
    // Keep the training forecast separate from crime, OC and elective stock.
    const covered=new Map();
    for(const group of [buckets.training,buckets.current,buckets.crime,buckets.oc,buckets.stock]){
      for(const [key,item] of group){
        const previous=covered.get(key)??item.owned;
        if(previous>=item.target){group.delete(key);continue;}
        item.missing=item.target-previous;
        covered.set(key,item.target);
      }
    }
    const moneyValue=value=>value==null?"—":"$"+number(value);
    const rows=items=>items.map(x=>{
      const defaultReserve=x.reasons.length===1&&x.reasons[0]==="Default reserve";
      const stock='<span class="restock-stock" title="Current / needed">'+number(x.owned)+'/'+number(x.target)+'</span>';
      const priceSource=x.priceSource??"Market value",total=moneyValue(x.price===null?null:x.missing*x.price);
      return '<li class="restock-row"><div class="restock-line">'+
        '<div class="restock-item"><strong>'+esc(x.item)+'</strong>'+(defaultReserve?stock:"")+'</div><span title="Quantity to buy">× '+number(x.missing)+'</span>'+
        '<span title="'+priceSource+' per unit" aria-label="'+priceSource+' '+moneyValue(x.price)+'">'+moneyValue(x.price)+'</span>'+
        '<span title="Total purchase cost" aria-label="Total '+total+'">'+total+'</span></div>'+
        (defaultReserve?"":'<div class="restock-line restock-source"><small>'+esc(x.reasons.join(" · "))+'</small>'+stock+'</div>')+'</li>';
    }).join("");
    const sorted=group=>[...group.values()].sort((a,b)=>a.level-b.level||a.item.localeCompare(b.item));
    const tabs=[
      ["urgent","Urgent",sorted(buckets.training),trainingRecommendation.recoveryHeld?"Training recovery held; no purchase forecast.":!program&&!session?"No current training forecast.":(!trainingRecommendation.inputs.sources["inventory:Drug"].ready||!trainingRecommendation.inputs.sources["inventory:Booster"].ready||!trainingRecommendation.inputs.sources["inventory:Candy"].ready||trainingRecommendation.inputs.points===null)?"Training stock or points unverified; refresh before estimating shortages.":"No training shortages within "+restockForecastDays+" days."],
      ["crime","Crime",sorted(buckets.crime),"No crime shortages identified."],
      ["oc","OC",[...sorted(buckets.current),...sorted(buckets.oc)],"No OC shortages identified."],
      ["reserves","Reserves",sorted(buckets.stock),"No reserve shortages identified."]
    ];
    const tabbar='<div class="restock-tabs" role="group" aria-label="Restock categories">'+tabs.map(([key,label])=>
      '<button type="button" data-restock-tab="'+key+'" aria-controls="restock-panel-'+key+'" aria-pressed="'+(restockTab===key)+'">'+label+'</button>').join("")+'</div>';
    const panels=tabs.map(([key,,items,empty])=>'<div class="restock-tab-panel" id="restock-panel-'+key+'" data-restock-panel="'+key+'" '+(restockTab===key?"":"hidden")+'>'+
      (items.length?'<ul class="crime-recommendations">'+rows(items)+'</ul>':'<p class="fine-print">'+esc(empty)+'</p>')+'</div>').join("");
    const pending=tornGuideApi.inventoryTypes.filter(c=>!["Book","Collectible"].includes(c)&&!ready(c));
    const trainingUnverified=["Drug","Booster","Candy"].filter(c=>!trainingRecommendation.inputs.sources["inventory:"+c].ready);
    const controls='<div class="rec-type-toggles" role="group" aria-label="Recommendation types">'+recommendationTypes.map(([id,label])=>'<button type="button" class="rec-oc-toggle" data-rec-type="'+id+'" aria-pressed="'+recEnabled.has(id)+'">'+esc(label)+'</button>').join("")+'</div>';
    const restock=recEnabled.has("restock")?recTileStart("restock","Restock")+tabbar+panels+(pending.length?'<p class="fine-print restock-inventory-note">Inventory unavailable: '+esc(pending.join(", "))+'</p>':"")+(trainingUnverified.length?'<p class="fine-print restock-inventory-note">Training inventory unverified: '+esc(trainingUnverified.join(", "))+'</p>':"")+recTileEnd+restockSettings(settingsCategories):"";
    const priority=tornRoadmap.preferences().priority,first={growth:["growth","calendar","consume"],completion:["crime"],crime:["crime","consume"],networth:["money"],company:["money","education"],education:["education"]}[priority]??[];
    trainingRecommendation.calendarRows=calendarEvents(trainingRecommendation,trainingRecommendation.now);
    return '<section class="home-recommendations" data-home-recommendations><nav class="rec-titlebar" aria-label="Recommendation filters">'+controls+'</nav>'+homeTimeline(trainingRecommendation,trainingRecommendation.calendarRows)+'<div class="rec-tile-grid" data-rec-priority="'+esc(first.join(","))+'">'+restock+adviceSections(count,trainingRecommendation)+(!recEnabled.size?'<p class="fine-print">Select recommendation types above.</p>':"")+'</div></section>';
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
    wireActivity(view);
    layoutRecommendations(view);
    if(view.dataset.ocRecommendationsBound==="1")return;
    view.dataset.ocRecommendationsBound="1";
    const checkAfterReturn=()=>{
      if(document.visibilityState==="visible")watchTraining(view,{resume:true});
    };
    document.addEventListener("visibilitychange",checkAfterReturn);
    window.addEventListener("focus",checkAfterReturn);
    view.addEventListener("toggle",e=>{
      if(!e.target.isConnected)return;
      if(e.target.matches?.("details.rec-tile[data-rec-group]")){
        loadRecFilters();
        const id=e.target.dataset.recGroup;
        if(!recommendationTypes.some(([key])=>key===id))return;
        if(e.target.open)recExpanded.add(id);else recExpanded.delete(id);
        try{writeAccountValue("torn-city-guide:rec-expanded:"+recOwner,JSON.stringify([...recExpanded]));}catch{}
      }
    },true);
    view.addEventListener("change",e=>{if(e.target.matches("[data-growth-exclude-owned]")){try{writeAccountValue("torn-city-guide:growth-exclude-owned:"+String(tornGuideApi.state.identity?.id??"guest"),String(e.target.checked));}catch{}refreshRecommendations(view);}});
    view.addEventListener("change",event=>{
      if(event.target.matches("[data-crime-observation]")){
        const el=event.target,{crimeName,crimeTarget,crimeField}=el.dataset;
        const owner=String(tornGuideApi.state.identity?.id??"guest");
        if(!tornCrimeStates.save(owner,localStorage,crimeName,crimeTarget,crimeField,el.value)){
          el.setCustomValidity("Enter a whole percentage from 0 to 100, or clear the reading.");el.reportValidity();return;
        }
        el.setCustomValidity("");
        const board=el.closest(".crime-state-board"),active=el===document.activeElement;
        const progress=crimeProgress(crimeName),cs=skill(crimeName)??(Number.isFinite(progress?.skill)?progress.skill:null),total=reference.find(x=>x[0]===crimeName)?.[2]??0;
        const count=Array.isArray(progress?.uniques)?new Set(progress.uniques.map(u=>u.id)).size:null;
        const next=tornCrimeStates.render(crimeName,{cs,only:incompleteUniquesOnly,allCollected:count!==null&&total>0&&count>=total,uniques:progress?.uniques,catalog:payload("itemCatalog","items"),itemStatus:crimeItemStatus,owner});
        if(board){board.outerHTML=next;if(active){const input=[...view.querySelectorAll("[data-crime-observation]")].find(x=>x.dataset.crimeName===crimeName&&x.dataset.crimeTarget===crimeTarget&&x.dataset.crimeField===crimeField);input?.focus({preventScroll:true});}}
        return;
      }
      if(event.target.matches("[data-growth-watch]")){
        try{writeAccountValue("torn-city-guide:growth-watch:"+String(tornGuideApi.state.identity?.id??"guest"),String(event.target.checked));}catch{}
        const session=loadTrainingSession();if(session){delete session.watch;saveTrainingSession();}
        refreshRecommendations(view);return;
      }
      if(event.target.matches("[data-rec-crime-override]")){
        const value=event.target.value;
        if(value!=="auto"&&!crimes.some(([name])=>name===value))return;
        crimeOverride=value;
        recExpanded.add("crime");
        try{writeAccountValue("torn-city-guide:crime-override:"+recOwner,value);}catch{}
        refreshRecommendations(view);
        view.querySelector("[data-rec-crime-override]")?.focus();
        return;
      }
      const key=event.target.dataset.energyWar;
      if(!key)return;
      const settings=energyWarSettings();
      if(key==="mode")settings.mode=event.target.value;
      else if(event.target.value!==""&&event.target.validity.valid)settings[key]=Number(event.target.value);
      else {event.target.value=settings[key];return;}
      try{writeAccountValue("torn-city-guide:energy-war:"+recOwner,JSON.stringify({...settings,version:2}));}catch{}
      refreshRecommendations(view);
      view.querySelector('[data-energy-war="'+key+'"]')?.focus();
    });
    function selectGrowthTab(id,focus=false,toggle=false){
      if(!growthTabIds.includes(id))return;
      growthTab=nextGrowthTab(growthTab,id,toggle);try{writeAccountValue("torn-city-guide:growth-tab:"+recOwner,growthTab);}catch{}
      for(const el of view.querySelectorAll("[data-growth-tab]")){
        const selected=el.dataset.growthTab===growthTab,focused=el.dataset.growthTab===id;
        el.setAttribute("aria-selected",String(selected));el.setAttribute("aria-expanded",String(selected));el.tabIndex=focused?0:-1;if(focused&&focus)el.focus({preventScroll:true});
      }
      for(const el of view.querySelectorAll(".growth-tab-panel"))el.hidden=el.id!=="growth-panel-"+growthTab;
    }
    view.addEventListener("keydown",e=>{const btn=e.target.closest("[data-growth-tab]");if(!btn)return;const ids=["summary","steps","build"],i=ids.indexOf(btn.dataset.growthTab);let next;if(e.key==="ArrowRight")next=ids[(i+1)%3];else if(e.key==="ArrowLeft")next=ids[(i+2)%3];else if(e.key==="Home")next=ids[0];else if(e.key==="End")next=ids[2];else return;e.preventDefault();selectGrowthTab(next,true);});
    view.addEventListener("click",e=>{
      // Links navigate normally; non-interactive summary areas expand the tile.
      const headerAction=e.target.closest(".rec-header-actions");
      if(headerAction)e.preventDefault();
      const crimeGear=e.target.closest("[data-rec-crime-settings]");
      if(crimeGear){openCrimeSettings(view,crimeGear);return;}
      const restockChoice=e.target.closest("[data-restock-tab]");
      if(restockChoice){
        restockTab=restockChoice.dataset.restockTab;
        for(const button of view.querySelectorAll("[data-restock-tab]"))button.setAttribute("aria-pressed",String(button.dataset.restockTab===restockTab));
        for(const panel of view.querySelectorAll("[data-restock-panel]"))panel.hidden=panel.dataset.restockPanel!==restockTab;
        return;
      }
      const restockButton=e.target.closest("[data-restock-settings]");
      if(restockButton){e.preventDefault();openRestockSettings(view,restockButton);return;}
      const tab=e.target.closest("[data-growth-tab]");if(tab){selectGrowthTab(tab.dataset.growthTab,true,true);return;}
      const gear=e.target.closest("[data-growth-settings]");
      if(gear){e.preventDefault();e.stopPropagation();growthSettingsOpen=!growthSettingsOpen;recExpanded.add("growth");try{writeAccountValue("torn-city-guide:rec-expanded:"+recOwner,JSON.stringify([...recExpanded]));}catch{}refreshRecommendations(view);return;}
      if(e.target.closest("[data-growth-budget]")){if(!tornRoadmap.activitiesOpen())tornRoadmap.toggleActivities();document.querySelector('#home-activities [data-home-pref="weeklyBudget"]')?.focus();return;}
      const sessionButton=e.target.closest("[data-growth-session]");
      if(sessionButton&&!sessionButton.disabled){if(trainingRecoveryHeld()){refreshRecommendations(view);return;}const action=sessionButton.dataset.growthSession,session=loadTrainingSession();
      if(action==="war-refresh"&&!recoveryBusy){
        recoveryBusy=true;recoveryMessage="Refreshing war and Energy data…";
        refreshRecommendations(view);
        tornGuideApi.loadPage("energy",true).then(()=>{
          recoveryMessage="Readiness updated.";readinessExpires=Date.now()+3500;
        }).catch(error=>{recoveryMessage="Refresh failed: "+String(error.message??error);})
          .finally(()=>{recoveryBusy=false;if(view.isConnected)refreshRecommendations(view);});
        return;
      }
      if((action==="review"||action==="refresh")&&session&&session.index>=session.actions.length){void reviewNextCycle(view,session);return;}
      if(action==="refresh"&&!recoveryBusy){recoveryBusy=true;recoveryMessage="Refreshing Energy, Happiness and cooldowns…";const owner=sessionOwner,started=session?.started,index=session?.index,requested=Date.now();refreshRecommendations(view);(async()=>{try{
        await tornGuideApi.loadPage("energy",true);
        const current=loadTrainingSession(),st=tornGuideApi.state;
        if(sessionOwner!==owner||current?.started!==started||current?.index!==index)return;
        const live=recoverySnapshot();
        if(!live||Number(st.fetchedAt?.cooldowns||0)<requested||Math.max(Number(st.fetchedAt?.bars||0),Number(st.bridge?.timestamp||0))<requested){recoveryMessage="Fresh account data unavailable. Try Refresh again.";return;}
        if(observeTrainingStep(current)||reconcileTrainingProgress(current,live)){
          if(current.index>=current.actions.length){recoveryBusy=false;await reviewNextCycle(view,current);}
        }else {recoveryMessage="Readiness updated.";readinessExpires=Date.now()+3500;}
      }catch(error){recoveryMessage="Refresh failed: "+String(error.message??error);}finally{recoveryBusy=false;if(view.isConnected)refreshRecommendations(view);}})();return;}
      if(action==="start"&&!session&&trainingDraft?.owner===sessionOwner&&prepState(trainingDraft.plan,trainingDraft.training.blockDrugs).ready){const p=trainingDraft.plan,prog=p.program;recoveryMessage="";trainingSession={version:1,label:prog.label,source:prog.source,sequence:prog.sequence,deadline:prog.deadline,stat:p.stat,statKey:p.statKey,budget:tornRoadmap.preferences().weeklyBudget,excludeOwned:excludeOwned(),confirmedSpend:0,periods:prog.periods,drugRisk:prog.drugRisk,started:Date.now(),index:0,actions:sessionActions(prog.cycleExecution??prog.execution),cycleSpend:prog.cycleSpend,notBefore:0,completed:{},timing:prog.timing??{},gym:p.gym,maxEnergy:payload("bars","bars")?.energy?.maximum};trainingSession.watch={index:0,sample:trainingWatchSnapshot(trainingSession)};saveTrainingSession();}else if(action==="done"&&session&&session.actions[session.index]&&!sessionButton.disabled&&!sessionDeadlineConflict(session,activityLimits())){const old=session.actions[session.index],next=session.actions[session.index+1],now=Date.now(),timing=session.timing??{};session.completed??={};session.completed[session.index]=now;session.lastConfirmed=now;recoveryMessage="";if(old.type==="xanax"||old.type==="ecstasy")session.drugUntil=now+(old.type==="xanax"?timing.xanaxCD??25200:timing.ecstasyCD??12900)*1000;if(["candy","dvd"].includes(old.type))session.boosterUntil=Math.max(now,session.boosterUntil||0)+(old.quantity??1)*(old.type==="candy"?timing.candyCD??1800:timing.dvdCD??21600)*1000;if(old.type==="refill")session.refillDay=Math.floor(now/86400000);session.index++;session.notBefore=next&&!next.midnightRefill?now+Math.max(0,next.at-old.at)*1000:0;delete session.watch;saveTrainingSession();if(session.index>=session.actions.length){void reviewNextCycle(view,session);return;}}else if(action==="stop"){trainingSession=null;recoveryMessage="";saveTrainingSession();}refreshRecommendations(view);return;}
      const btn=e.target.closest("[data-rec-type],[data-rec-incomplete],[data-rec-uniques],[data-rec-history],[data-rec-crime-load]");
      if(!btn||!btn.closest("[data-home-recommendations]"))return;
      if(btn.hasAttribute("data-rec-crime-load")){
        e.preventDefault();
        btn.disabled=true;btn.setAttribute("aria-busy","true");
        void (async()=>{
          try{
            for(const id of btn.dataset.recCrimeLoad.split(","))await tornGuideApi.loadCrimeProgress(Number(id));
            refreshRecommendations(view);
            view.querySelector("[data-rec-crime-load]")?.focus();
          }catch(error){
            if(btn.isConnected){btn.disabled=false;btn.removeAttribute("aria-busy");btn.title=String(error.message??error);}
          }
        })();
        return;
      }
      if(btn.hasAttribute("data-rec-uniques")){recUniques=!recUniques;try{writeAccountValue("torn-city-guide:crime-uniques:"+recOwner,String(recUniques));}catch{}refreshRecommendations(view);view.querySelector("[data-rec-uniques]")?.focus();return;}
      if(btn.hasAttribute("data-rec-incomplete")){recIncomplete=!recIncomplete;try{writeAccountValue("torn-city-guide:crime-incomplete:"+recOwner,String(recIncomplete));}catch{}refreshRecommendations(view);view.querySelector("[data-rec-incomplete]")?.focus();return;}
      if(btn.hasAttribute("data-rec-history")){btn.disabled=true;tornInvestmentHistory.refresh().finally(()=>{if(location.hash==="#home")refreshRecommendations(view);});return;}
      if(btn.dataset.recType){
        const id=btn.dataset.recType;
        if(recEnabled.has(id))recEnabled.delete(id);else recEnabled.add(id);
        try{writeAccountValue("torn-city-guide:rec-types:"+recOwner,JSON.stringify([...recEnabled]));}catch{}
        refreshRecommendations(view);
        view.querySelector('[data-rec-type="'+id+'"]')?.focus();return;
      }
    });
  }

  function render(){
    if(tornGuideApi.crimeVersion?.()===1)return '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Crimes 1.0</h1><p>Legacy crime system detected. Crimes 2.0 guidance and unique tracking are not applicable.</p></header><section class="panel"><div class="panel-content"><a href="https://torn.report/crimes" target="_blank" rel="noopener noreferrer">Old Crimes report</a> · <a href="https://wiki.torn.com/wiki/Crimes_1.0" target="_blank" rel="noopener noreferrer">Legacy crime reference</a></div></section>';
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
  return {render,renderCalendar,wireCalendar:wireActivity,liveOptimizationContext,trainingRecommendationContext,recoveryPreview,crimes,syncNerve,recommendations,wireRecommendations,refreshRecommendations,tickGrowth};
})();
