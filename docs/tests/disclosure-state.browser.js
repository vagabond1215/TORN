"use strict";
/* Real DOM + localStorage + MutationObserver. Unique test keys, restore
 * original stored preferences after testing. Run only in a test browser
 * profile or dedicated local fixture origin (not with a live Guide open).
 */
(async()=>{
 const out=document.getElementById("result"),host=document.getElementById("topic-view"),rail=document.getElementById("guide-right-rail");
 const key=tornDisclosureState.storageKey,previous=localStorage.getItem(key),prefix="fixture:"+Date.now()+":";
 const check=(ok,msg)=>{if(!ok)throw Error(msg);};
 const tick=()=>new Promise(resolve=>setTimeout(resolve,0));
 const markup=(id,open,label)=>'<details data-collapse-key="'+prefix+id+'" '+(open?"open":"")+'><summary>'+label+'</summary><p>Body</p></details>';
 try{
  host.innerHTML=markup("default-open",true,"Count 1")+markup("default-closed",false,"Count 1");
  rail.innerHTML=markup("default-open",true,"Independent rail");
  await tick();
  const old=host.firstElementChild;
  old.querySelector("summary").click();host.lastElementChild.querySelector("summary").click();
  await tick();
  check(!old.open&&host.lastElementChild.open,"User toggle");
  host.innerHTML=markup("default-open",true,"Count 9")+markup("default-closed",false,"Count 9");
  await tick();
  check(!host.firstElementChild.open&&host.lastElementChild.open,"Refresh preserves both states");
  check(rail.firstElementChild.open,"Rail scope independent");
  old.open=true;await tick();check(!host.firstElementChild.open,"Detached node cannot replace preference");
  const copy=tornDisclosureState.createStore(localStorage);
  check(copy.get(tornDisclosureState.keyFor(host.firstElementChild),true)===false,"Fresh store remembers closed");
  check(copy.get(tornDisclosureState.keyFor(host.lastElementChild),false)===true,"Fresh store remembers open");
  host.innerHTML="";await tick();host.innerHTML=markup("default-closed",false,"Returned later")+markup("default-open",true,"Changed order");
  await tick();
  check(host.firstElementChild.open&&!host.lastElementChild.open,"Route return and reorder");
  tornDisclosureState.remember(host.lastElementChild,true);await tick();
  host.innerHTML=markup("default-open",false,"Explicit opening");await tick();
  check(host.firstElementChild.open,"Explicit section open survives rebuild");
  out.textContent="PASS: native DOM, actual summary clicks, MutationObserver, localStorage, changed order, separate scopes and fresh-store restoration.";out.dataset.result="pass";
 }catch(error){out.textContent="FAIL: "+error.message;out.dataset.result="fail";console.error(error);}
 finally{if(previous===null)localStorage.removeItem(key);else localStorage.setItem(key,previous);}
})();
