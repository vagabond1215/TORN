"use strict";
// Read-only calendar comparison presentation. No writers or API calls.
const tornCalendarPreviewUI=(()=>{
  const time=at=>new Date(at).toISOString().replace("T"," ").replace("Z"," TCT");
  function description(row){
    if(row===null)return ["Not present in this snapshot"];
    const out=[row.title,row.kind+" · "+(row.blocking?"Blocking":"Nonblocking"),time(row.start)+" to "+time(row.end)];
    if(row.kind==="rehab"){
      if(row.completedAt!==undefined)out.push("Completed: "+time(row.completedAt),"Recorded rehab cost: "+(row.rehabCost===null?"Unknown":"$"+row.rehabCost.toLocaleString("en-US")));
      else if(row.rehabBaseline)out.push("Pending rehabilitation evidence; separate review required");
      if(row.recoveryReview)out.push("Recovery review required");
    }
    return out;
  }
  function render(doc,container,plan,onChange){
    container.replaceChildren();
    const controls=new Map(),choices=new Map();
    const element=(tag,text,cls)=>{const el=doc.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;};
    const changed=plan.rows.filter(r=>r.change!=="unchanged");
    const unchanged=plan.rows.length-changed.length;
    container.append(element("p",changed.length+" changed or missing records · "+unchanged+" unchanged · "+changed.filter(r=>r.choices.length).length+" selectable for preview","fine-print"));
    const addVersion=(grid,label,value)=>{
      const block=element("div",undefined,"calendar-review-version");block.append(element("strong",label));
      for(const line of description(value))block.append(element("div",line));
      grid.append(block);
    };
    for(const [i,row] of changed.entries()){
      const details=element("details",undefined,"calendar-review-row");
      const summary=element("summary",(row.before??row.after).title+" · "+row.change+" · "+(row.choices.length?"Reviewable":row.action==="keep-local"?"Keep local":"Protected / review only"));
      details.append(summary,element("p","Event ID: "+row.id,"fine-print"));
      const grid=element("div",undefined,"calendar-review-versions");
      if(plan.commonBase)addVersion(grid,"Common backup",row.base);
      addVersion(grid,"Local",row.before);addVersion(grid,"Incoming",row.after);
      details.append(grid,element("p",row.reason,"fine-print"));
      if(row.choices.length){
        const label=element("label","Preview choice"),select=element("select");
        select.setAttribute("aria-label","Preview choice for event "+(i+1));
        for(const [v,title] of [["keep-local","Keep local"],["take-incoming","Preview incoming"]]){
          const opt=element("option",title);opt.value=v;select.append(opt);
        }
        select.value="keep-local";choices.set(row.id,"keep-local");controls.set(row.id,select);
        select.addEventListener("change",()=>{choices.set(row.id,select.value==="take-incoming"?"take-incoming":"keep-local");onChange();});
        label.append(select);details.append(label);
      }
      container.append(details);
    }
    if(!changed.length)container.append(element("p","No calendar differences to review.","fine-print"));
    return Object.freeze({
      decisions:()=>changed.filter(r=>choices.get(r.id)==="take-incoming").map(r=>({id:r.id,choice:"take-incoming",reviewKey:r.reviewKey})),
      disable:disabled=>{for(const select of controls.values())select.disabled=disabled;}
    });
  }
  return Object.freeze({description,render});
})();
