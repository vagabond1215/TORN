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
    const comparison=get("backup-comparison");
    const status=get("backup-status"),secret=get("backup-passphrase"),confirmation=get("backup-confirm"),file=get("backup-file");
    const exportButton=get("backup-export"),importButton=get("backup-import"),close=get("backup-close");
    if(!open||!dialog||!form)return;
    const message=x=>{status.textContent=x;};
    const controls=()=>{const pending=!journalPanel.hidden;exportButton.disabled=busy||pending;importButton.disabled=busy||pending;journalFinish.disabled=busy||!journal?.complete||journal.conflict;journalRollback.disabled=busy||!journal||journal.conflict;close.disabled=busy;inspect.disabled=busy||pending||!presented?.session;discard.disabled=busy||pending||!presented?.session;preview.disabled=busy||pending||!presented?.session||!attest.checked;count.disabled=busy||!presented?.session;attest.disabled=busy||!presented?.session;sync();};
    const review=get("backup-recovery-review"),summary=get("backup-review-summary"),evidence=get("backup-review-evidence"),inspect=get("backup-review-inspect"),discard=get("backup-review-discard");
    const count=get("backup-review-count"),attest=get("backup-review-attest"),preview=get("backup-review-preview"),actionList=get("backup-review-action-list"),previewList=get("backup-review-preview-list");
    const journalPanel=get("backup-journal"),journalStatus=get("backup-journal-status"),journalFinish=get("backup-journal-finish"),journalRollback=get("backup-journal-rollback");
    let presented=null,journal=null;
    function showJournal(){
      journal=null;
      const id=tornGuideApi.state.identity?.id;
      try{
        journal=tornAccountStorage.readJournal(localStorage,id);
        journalPanel.hidden=!journal;
        journalStatus.textContent=journal?journal.rows.filter(x=>x.state==="matched").length+" of "+journal.rows.length+" destinations match the interrupted restore. "+(journal.conflict?"Conflicting changes detected; preserve the original backup and journal.":journal.complete?"All values match; you can finalize or roll back.":"Restore incomplete; roll back before trying again."):"";
      }catch(error){journalPanel.hidden=false;journalStatus.textContent=String(error?.message??error);}
    }
    async function resolveJournal(mode){
      if(busy||!journal||journal.conflict)return;
      const initial=journal;busy=true;controls();
      try{
        const verified=await tornGuideApi.verifyBackupOwner();
        if(!window.confirm(mode==="finish"?"Finalize this fully matched restore?":"Roll back the interrupted restore? Only matching destination values will be removed; keep your original backup."))return;
        await tornAccountStorage.withRecoveryLock(verified.playerId,navigator.locks,()=>{
          if(mode==="finish")tornAccountStorage.finishJournal(localStorage,verified.playerId,initial.raw,verified.isCurrent);
          else tornAccountStorage.rollbackJournal(localStorage,verified.playerId,initial.raw,verified.isCurrent);
        });
        location.reload();
      }catch(error){journalStatus.textContent=String(error?.message??error);}
      finally{busy=false;controls();}
    }
    journalFinish.addEventListener("click",()=>void resolveJournal("finish"));
    journalRollback.addEventListener("click",()=>void resolveJournal("rollback"));
    function clearPreview(){previewList.replaceChildren();evidence.textContent="";}
    function actionText(x){const name={xanax:"Xanax",ecstasy:"Ecstasy",candy:"Candy",dvd:"Erotic DVD",train:"Train",refill:"Energy refill",externalHappy:"External Happiness boost"}[x.type]??x.type;return name+(x.type==="train"?" "+x.energy+" E":x.quantity>1?" × "+x.quantity:"");}
    function append(list,text){const li=document.createElement("li");li.textContent=text;list.append(li);}
    count.addEventListener("input",()=>{attest.checked=false;clearPreview();controls();});
    attest.addEventListener("change",()=>{clearPreview();controls();});
    preview.addEventListener("click",()=>void reviewAction("preview"));
    function showReview(){
      presented=tornTrainingRecovery.readStage(localStorage,tornGuideApi.state.identity?.id);
      review.hidden=!presented;evidence.textContent="";
      inspect.disabled=!presented?.session;discard.disabled=!presented?.session;
      const x=presented?.session;
      count.min=String(x?.index??0);count.max=String(x?.actions.length??0);count.value=String(x?.index??0);attest.checked=false;
      actionList.replaceChildren();previewList.replaceChildren();
      for(const [i,a] of (x?.actions??[]).entries())append(actionList,actionText(a)+(i<x.index?" · saved confirmed":" · not confirmed by backup"));
      controls();
      summary.textContent=x?"Player #"+presented.playerId+" · "+x.label+" · "+x.index+"/"+x.actions.length+" confirmed. Backup "+new Date(presented.backupCreatedAt).toLocaleString()+". Last confirmation "+(x.lastConfirmed==null?"unknown":new Date(x.lastConfirmed).toLocaleString())+". Estimated cycle cost "+(x.cycleSpend==null?"unknown":"$"+x.cycleSpend.toLocaleString())+".":presented?.error??"";
    }
    async function reviewAction(mode){
      if(busy||!presented?.session||tornAccountStorage.journalPending(localStorage,presented.playerId))return;
      const stage=presented,reviewed=count.value===""?NaN:Number(count.value),attested=attest.checked;clearPreview();busy=true;controls();
      try{
        const verified=await tornGuideApi.verifyBackupOwner();
        const stillCurrent=()=>verified.isCurrent()&&verified.playerId===stage.playerId&&tornTrainingRecovery.readStage(localStorage,verified.playerId)?.raw===stage.raw;
        if(!stillCurrent())throw Error("Account or recovery record changed");
        if(mode==="discard"){
          if(!window.confirm("Release the hold and discard this staged session without resuming or charging its estimated cycle cost? Keep your backup and manually reconcile any uncertain spending."))return;
          await tornAccountStorage.withRecoveryLock(verified.playerId,navigator.locks,()=>{
            if(tornAccountStorage.journalPending(localStorage,verified.playerId))throw Error("Resolve the restore journal first");
            tornTrainingRecovery.discardStage(localStorage,verified.playerId,stage.raw,stillCurrent);
          });
          location.reload();return;
        }
        const requested=Date.now();await tornGuideApi.loadPage("energy",true);
        if(!stillCurrent())throw Error("Account or recovery record changed");
        const state=tornGuideApi.state,live=tornTrainSequence.liveInputs(state,Date.now(),tornBarProjection);
        const report=tornTrainingRecovery.evidenceReport(stage,live,state,requested);
        if(mode==="preview"){
          const result=tornCrimeGuide.recoveryPreview(stage,reviewed,attested,report,requested);
          if(!stillCurrent())throw Error("Account or recovery record changed");
          evidence.textContent=(result.complete?"All actions reviewed as complete; no remaining preview.":"Projected remaining Energy "+result.used.toLocaleString()+" · stat gain "+result.gain.toLocaleString()+".")+" "+result.note+" Original saved prefix "+result.savedConfirmed+"; manually reviewed prefix "+result.reviewedConfirmed+". Nothing has been saved or resumed.";
          for(const a of result.remaining)append(previewList,new Date(result.generatedAt+a.at*1000).toISOString().slice(0,16).replace("T"," ")+" TCT · "+actionText(a));
          return;
        }
        evidence.textContent="Fresh API observations: Energy "+report.energy+", Happiness "+report.happy+", "+stage.session.stat+" "+report.stat.toLocaleString()+", drug cooldown "+Math.ceil(report.drug/60)+" min, booster cooldown "+Math.ceil(report.booster/60)+" min, daily refill "+(report.refillUsed?"used":"available")+". Saved observed stat checkpoint "+(report.savedCheckpoint??"unknown")+"; modeled next-action stat "+(report.modeledNextStat??"unknown")+". "+(report.warVerified===false?"Faction war schedule not verified. ":"")+"These observations do not prove which disconnected actions occurred. Session remains held; continuation requires separate reconciliation.";
      }catch(error){evidence.textContent=String(error?.message??"Recovery review failed");}
      finally{busy=false;controls();}
    }
    inspect.addEventListener("click",()=>void reviewAction("inspect"));
    discard.addEventListener("click",()=>void reviewAction("discard"));
    const clear=()=>{secret.value="";confirmation.value="";file.value="";comparison.replaceChildren();};
    open.addEventListener("click",()=>{
      if(!tornGuideApi.isConnected()||busy)return;
      clear();message("Verified account required. Version 2 adds section revision tracking to supported settings, notes, checklists, calendar events, expenditure records, validated training sessions and cycle history. Version 1 files remain readable.");
      showJournal();showReview();dialog.showModal();
    });
    close.addEventListener("click",()=>{if(!busy)dialog.close();});
    dialog.addEventListener("cancel",event=>{if(busy)event.preventDefault();});
    dialog.addEventListener("close",clear);
    form.addEventListener("submit",event=>event.preventDefault());
    async function run(mode){
      if(busy)return;
      comparison.replaceChildren();
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
          const snap=await tornAccountStorage.withRecoveryLock(id,navigator.locks,()=>tornAccountRevisions.capture(localStorage,id,verified.isCurrent));
          const critical=snap.omitted.filter(x=>["calendar-events","training-spend-estimates","activity-spend","training-session-review","training-cycle-history"].includes(x));
          if(critical.length)throw Error("Cannot safely export: invalid calendar, expenditure or training records ("+critical.join(", ")+"). Preserve local data for review.");
          if(!snap.records.length&&!snap.manifest.entries.length)throw Error("No supported saved account records to export");
          message("Encrypting "+snap.records.length+" supported records…");
          const data=await tornAccountBackup.encrypt(id,snap.records,password,Date.now(),snap.manifest);
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
          // On a populated account, compare without applying incoming data.
          const local=tornAccountStorage.snapshot(localStorage,id),hasManifest=localStorage.getItem(tornAccountRevisions.key(id))!==null||tornAccountStorage.deletionMarkers(localStorage,id).length>0;
          if(local.records.length||local.omitted.length||hasManifest){
            if(!data.manifest){message("Version 1 backup has no revision history. Recovery into an existing account is disabled; keep both copies.");return;}
            const current=await tornAccountStorage.withRecoveryLock(id,navigator.locks,()=>tornAccountRevisions.capture(localStorage,id,verified.isCurrent));
            const plan=await tornAccountRevisions.planMerge(current,data,id);
            if(!verified.isCurrent())throw Error("Account changed during comparison");
            const labels={"keep-local":"Keep local","unchanged":"Identical","eligible":"Eligible preference update","review":"Conflict or untracked; review required","protected-review":"Protected section; specialized review required"};
            comparison.replaceChildren();
            for(const row of plan.rows)append(comparison,row.section+" · "+labels[row.action]+" ("+row.status+")"+(row.localDeleted?" · local deletion":"")+(row.incomingDeleted?" · backup deletion":""));
            message("Read-only merge preview: "+plan.eligible.length+" eligible preference updates, "+plan.review.length+" sections require review. No incoming records applied. Keep the original encrypted backup.");return;
          }
          // Explicit approval, no silent overwrite or partial account merge.
          if(!window.confirm("Restore "+data.records.length+" supported records for Torn player "+id+"? Existing supported account data or session/history will prevent recovery. Restored training sessions will be held for review and cannot resume yet. Restored pending rehab will not auto-confirm; review reservations manually. The guide will reload; session-only API connections must reconnect.")){message("Recovery cancelled; no changes made.");return;}
          if(!navigator.locks?.request&&!window.confirm("This browser does not support cross-tab recovery locking. Close other guide tabs before restoring. Continue in this tab?")){message("Restore cancelled.");return;}
          const count=await tornAccountStorage.withRecoveryLock(id,navigator.locks,()=>data.manifest?tornAccountRevisions.restore(localStorage,id,data.records,data.manifest,verified.isCurrent,{createdAt:data.createdAt}):tornAccountStorage.restoreJournaled(localStorage,id,data.records,verified.isCurrent,{createdAt:data.createdAt}));
          message("Restored "+count+" supported records. Reloading guide…");
          location.reload();
        }
      }catch(error){message(String(error?.message??"Backup operation failed"));}
      finally{password="";file.value="";busy=false;showJournal();controls();}
    }
    exportButton.addEventListener("click",()=>void run("export"));
    importButton.addEventListener("click",()=>void run("import"));
    sync();
  }
  return {wire,sync};
})();
