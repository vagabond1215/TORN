"use strict";
// Browser-only UI. Identity verification is provided by the API coordinator.
// No automatic recovery or password storage in this first portable release.
const tornBackupUI=(()=>{
  let busy=false;
  const get=id=>document.getElementById(id);
  function sync(){
    const button=get("backup-open");if(button)button.disabled=busy||!tornGuideApi.isConnected();
  }
  function wire(){
    const open=get("backup-open"),dialog=get("backup-dialog"),form=get("backup-form");
    const status=get("backup-status"),secret=get("backup-passphrase"),confirmation=get("backup-confirm"),file=get("backup-file");
    const exportButton=get("backup-export"),importButton=get("backup-import"),close=get("backup-close");
    if(!open||!dialog||!form)return;
    const message=x=>{status.textContent=x;};
    const controls=()=>{exportButton.disabled=busy;importButton.disabled=busy;close.disabled=busy;inspect.disabled=busy||!presented?.session;discard.disabled=busy||!presented?.session;sync();};
    const review=get("backup-recovery-review"),summary=get("backup-review-summary"),evidence=get("backup-review-evidence"),inspect=get("backup-review-inspect"),discard=get("backup-review-discard");
    let presented=null;
    function showReview(){
      presented=tornTrainingRecovery.readStage(localStorage,tornGuideApi.state.identity?.id);
      review.hidden=!presented;evidence.textContent="";
      inspect.disabled=!presented?.session;discard.disabled=!presented?.session;
      const x=presented?.session;
      summary.textContent=x?"Player #"+presented.playerId+" · "+x.label+" · "+x.index+"/"+x.actions.length+" confirmed. Backup "+new Date(presented.backupCreatedAt).toLocaleString()+". Last confirmation "+(x.lastConfirmed==null?"unknown":new Date(x.lastConfirmed).toLocaleString())+". Estimated cycle cost "+(x.cycleSpend==null?"unknown":"$"+x.cycleSpend.toLocaleString())+".":presented?.error??"";
    }
    async function reviewAction(mode){
      if(busy||!presented?.session)return;
      const stage=presented;busy=true;controls();
      try{
        const verified=await tornGuideApi.verifyBackupOwner();
        const stillCurrent=()=>verified.isCurrent()&&verified.playerId===stage.playerId&&tornTrainingRecovery.readStage(localStorage,verified.playerId)?.raw===stage.raw;
        if(!stillCurrent())throw Error("Account or recovery record changed");
        if(mode==="discard"){
          if(!window.confirm("Release the hold and discard this staged session without resuming or charging its estimated cycle cost? Keep your backup and manually reconcile any uncertain spending."))return;
          tornTrainingRecovery.discardStage(localStorage,verified.playerId,stage.raw,stillCurrent);
          location.reload();return;
        }
        const requested=Date.now();await tornGuideApi.loadPage("energy",true);
        if(!stillCurrent())throw Error("Account or recovery record changed");
        const state=tornGuideApi.state,live=tornTrainSequence.liveInputs(state,Date.now(),tornBarProjection);
        const required=["bars","cooldowns","battlestats","profile","gym","perks","icons"];
        if(required.some(k=>Number(state.fetchedAt?.[k]||0)<requested||state.errors?.[k]||state.cachedSources?.[k])||live.criticalIssues.length||!live.energy||!live.happy||live.drug===null||live.booster===null||live.account?.blocked)throw Error("Fresh account evidence incomplete; recovery remains held");
        const raw=state.data.battlestats?.battlestats?.[stage.session.statKey],stat=typeof raw==="object"?raw?.value:raw;
        if(stat==null||!Number.isFinite(Number(stat)))throw Error("Battle stat unavailable");
        const next=stage.session.actions[stage.session.index],anchor=stage.session.statCheckpoint;
        evidence.textContent="Fresh observations: Energy "+live.energy.current+", Happiness "+live.happy.current+", "+stage.session.stat+" "+Number(stat).toLocaleString()+", drug cooldown "+Math.ceil(live.drug/60)+" min, booster cooldown "+Math.ceil(live.booster/60)+" min. Saved checkpoint "+(anchor?.actual??next?.before?.stat??"unknown")+". These observations do not prove which disconnected actions occurred. Session remains held; continuation will require separate reconciliation.";
      }catch(error){evidence.textContent=String(error?.message??"Recovery review failed");}
      finally{busy=false;controls();}
    }
    inspect.addEventListener("click",()=>void reviewAction("inspect"));
    discard.addEventListener("click",()=>void reviewAction("discard"));
    const clear=()=>{secret.value="";confirmation.value="";file.value="";};
    open.addEventListener("click",()=>{
      if(!tornGuideApi.isConnected()||busy)return;
      clear();message("Verified account required. Version 1 covers supported settings, notes, checklists, calendar events, existing expenditure records, validated training sessions and cycle history.");
      showReview();dialog.showModal();
    });
    close.addEventListener("click",()=>{if(!busy)dialog.close();});
    dialog.addEventListener("cancel",event=>{if(busy)event.preventDefault();});
    dialog.addEventListener("close",clear);
    form.addEventListener("submit",event=>event.preventDefault());
    async function run(mode){
      if(busy)return;
      let password=secret.value,repeat=confirmation.value;
      const chosen=file.files?.[0];
      // Clear the DOM fields promptly; keep no persistent passphrase state.
      secret.value="";confirmation.value="";
      if(password.length<12||password.length>1024){message("Enter a recovery passphrase of 12–1024 characters.");return;}
      if(mode==="export"&&password!==repeat){message("Recovery passphrases do not match.");return;}
      repeat="";
      if(mode==="import"&&(!chosen||chosen.size>tornAccountBackup.maxFile)){message("Choose a supported .tornbackup file within the size limit.");return;}
      busy=true;controls();
      try{
        message("Verifying your account with Torn…");
        const verified=await tornGuideApi.verifyBackupOwner(),id=verified.playerId;
        if(!verified.isCurrent())throw Error("Account changed");
        if(mode==="export"){
          const snap=tornAccountStorage.snapshot(localStorage,id);
          const critical=snap.omitted.filter(x=>["calendar-events","training-spend-estimates","activity-spend","training-session-review","training-cycle-history"].includes(x));
          if(critical.length)throw Error("Cannot safely export: invalid calendar, expenditure or training records ("+critical.join(", ")+"). Preserve local data for review.");
          if(!snap.records.length)throw Error("No supported saved account records to export");
          message("Encrypting "+snap.records.length+" supported records…");
          const data=await tornAccountBackup.encrypt(id,snap.records,password);
          if(!verified.isCurrent())throw Error("Account changed before export");
          const url=URL.createObjectURL(new Blob([data],{type:"application/json"}));
          const link=document.createElement("a");
          link.href=url;link.download="torn-"+id+"-"+new Date().toISOString().slice(0,10)+".tornbackup";document.body.append(link);
          try{link.click();}finally{link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
          message("Download requested for "+snap.records.length+" records. Save the file outside browser storage and retain the passphrase."+ (snap.omitted.length?" Unsupported saved sections skipped: "+snap.omitted.join(", ")+".":"")+" Validated training sessions restore on hold, not as runnable plans. Personal/market archives and device settings are not included. Restored pending rehab reservations require manual review.");
        }else{
          message("Checking and decrypting selected backup…");
          const data=await tornAccountBackup.decrypt(await chosen.text(),id,password);
          if(!verified.isCurrent())throw Error("Account changed before recovery");
          // Explicit approval, no silent overwrite or partial account merge.
          if(!window.confirm("Restore "+data.records.length+" supported records for Torn player "+id+"? Existing supported account data or session/history will prevent recovery. Restored training sessions will be held for review and cannot resume yet. Restored pending rehab will not auto-confirm; review reservations manually. The guide will reload; session-only API connections must reconnect.")){message("Recovery cancelled; no changes made.");return;}
          const count=tornAccountStorage.restoreEmpty(localStorage,id,data.records,verified.isCurrent,{createdAt:data.createdAt});
          message("Restored "+count+" supported records. Reloading guide…");
          location.reload();
        }
      }catch(error){message(String(error?.message??"Backup operation failed"));}
      finally{password="";file.value="";busy=false;controls();}
    }
    exportButton.addEventListener("click",()=>void run("export"));
    importButton.addEventListener("click",()=>void run("import"));
    sync();
  }
  return {wire,sync};
})();
