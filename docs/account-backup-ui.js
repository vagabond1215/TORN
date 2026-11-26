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
    const controls=()=>{exportButton.disabled=busy;importButton.disabled=busy;close.disabled=busy;sync();};
    const clear=()=>{secret.value="";confirmation.value="";file.value="";};
    open.addEventListener("click",()=>{
      if(!tornGuideApi.isConnected()||busy)return;
      clear();message("Verified account required. Version 1 covers supported settings, notes, checklists and simple calendar events only.");
      dialog.showModal();
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
          if(!snap.records.length)throw Error("No supported saved settings or notes to export");
          message("Encrypting "+snap.records.length+" supported records…");
          const data=await tornAccountBackup.encrypt(id,snap.records,password);
          if(!verified.isCurrent())throw Error("Account changed before export");
          const url=URL.createObjectURL(new Blob([data],{type:"application/json"}));
          const link=document.createElement("a");
          link.href=url;link.download="torn-"+id+"-"+new Date().toISOString().slice(0,10)+".tornbackup";document.body.append(link);
          try{link.click();}finally{link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
          message("Download requested for "+snap.records.length+" records. Save the file outside browser storage and retain the passphrase."+ (snap.omitted.length?" Unsupported saved sections skipped: "+snap.omitted.join(", ")+".":"")+" Sessions, expenditure ledgers, archives and device settings are not included.");
        }else{
          message("Checking and decrypting selected backup…");
          const data=await tornAccountBackup.decrypt(await chosen.text(),id,password);
          if(!verified.isCurrent())throw Error("Account changed before recovery");
          // Explicit approval, no silent overwrite or partial account merge.
          if(!window.confirm("Restore "+data.records.length+" supported records for Torn player "+id+"? Existing supported account data or session/history will prevent recovery. The guide will reload; session-only API connections must reconnect.")){message("Recovery cancelled; no changes made.");return;}
          const count=tornAccountStorage.restoreEmpty(localStorage,id,data.records,verified.isCurrent);
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
