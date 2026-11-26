"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const {webcrypto}=require("node:crypto");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const api=new Function("globalThis",read("training-recovery.js")+"\n"+read("account-storage.js")+"\n"+read("account-revisions.js")+"\n"+read("account-backup.js")+"\nreturn tornAccountBackup;")({crypto:webcrypto});
(async()=>{
 const records=[{section:"build",value:'{"choice":"balanced","total":1000}'},{section:"notes:gym",value:"private note"}];
 const pass="a separate recovery passphrase";
 const first=await api.encrypt(123,records,pass,123456);
 const second=await api.encrypt(123,records,pass,123456);
 assert.notEqual(first,second);
 assert.ok(!first.includes("private note")&&!first.includes(pass));
 assert.deepEqual((await api.decrypt(first,123,pass)).records,records);
 await assert.rejects(api.decrypt(first,456,pass),/different Torn account/);
 await assert.rejects(api.decrypt(first,123,"a different recovery passphrase"),/Incorrect/);
 const e=JSON.parse(first);
 for(const field of ["createdAt","ciphertext","iv"]){
  const bad={...e,[field]:field==="createdAt"?e.createdAt+1:(e[field][0]==="A"?"B":"A")+e[field].slice(1)};
  await assert.rejects(api.decrypt(JSON.stringify(bad),123,pass),/Incorrect/);
 }
 await assert.rejects(api.decrypt(JSON.stringify({...e,iterations:1}),123,pass),/format/);
 await assert.rejects(api.encrypt(123,[{section:"api:v2:remember",value:"key"}],pass),/Unsupported/);
 await assert.rejects(api.encrypt(123,records,"short"),/passphrase/);
 const revisions=new Function("globalThis",read("training-recovery.js")+"\n"+read("account-storage.js")+"\n"+read("account-revisions.js")+"\nreturn tornAccountRevisions;")({crypto:webcrypto});
 const manifest=await revisions.observe(revisions.empty(123),{records,omitted:[]},123);
 const v2=await api.encrypt(123,records,pass,123456,manifest);
 assert.equal(JSON.parse(v2).version,2);
 assert.deepEqual((await api.decrypt(v2,123,pass)).manifest,manifest);
 const deleted=await revisions.observe(manifest,{records:[],omitted:[]},123);
 const tomb=await api.encrypt(123,[],pass,123456,deleted);
 assert.deepEqual((await api.decrypt(tomb,123,pass)).manifest,deleted);
 await assert.rejects(api.encrypt(123,records,pass,123456,deleted),/digest/);
 await assert.rejects(api.decrypt(JSON.stringify({...JSON.parse(v2),version:1}),123,pass),/Incorrect/);
 console.log("Encrypted V1/V2 round trips, random salt/IV, ownership, tamper, credential exclusion and authenticated tombstones passed.");
})().catch(e=>{console.error(e);process.exitCode=1;});
