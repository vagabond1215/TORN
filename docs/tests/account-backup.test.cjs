"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const {webcrypto}=require("node:crypto");
const read=p=>fs.readFileSync(path.join(__dirname,"..",p),"utf8");
const api=new Function("globalThis",read("training-recovery.js")+"\n"+read("account-storage.js")+"\n"+read("account-backup.js")+"\nreturn tornAccountBackup;")({crypto:webcrypto});
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
 console.log("Encrypted backup round trip, random salt/IV, ownership, tamper, credential exclusion passed.");
})().catch(e=>{console.error(e);process.exitCode=1;});
