"use strict";
/* Encrypted portable recovery. No network or credential handling here.
 * V1 covers only the explicit account-storage registry, not a full account.
 * The authenticated outer metadata binds ciphertext to format and player ID. */
const tornAccountBackup=(()=>{
  const format="torn-guide-backup",version=1,iterations=600000,maxFile=16000000;
  const encode=v=>new TextEncoder().encode(v);
  const decode=v=>new TextDecoder("utf-8",{fatal:true}).decode(v);
  const plain=v=>v!==null&&typeof v==="object"&&!Array.isArray(v);
  const exact=(v,fields)=>plain(v)&&Object.keys(v).length===fields.length&&fields.every(k=>Object.hasOwn(v,k));
  const validDate=v=>Number.isSafeInteger(v)&&v>=0&&v<=8640000000000000;
  const b64=bytes=>{let s="";for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(s);};
  function from64(v,max){
    if(typeof v!=="string"||v.length>Math.ceil(max/3)*4||!(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/).test(v))throw Error("Invalid backup encoding");
    const s=atob(v);if(s.length>max)throw Error("Backup exceeds size limit");return Uint8Array.from(s,c=>c.charCodeAt(0));
  }
  function cryptoReady(){
    if(!globalThis.crypto?.subtle||typeof globalThis.crypto.getRandomValues!=="function")throw Error("Encrypted backups require Web Crypto in a secure browser");
    return globalThis.crypto;
  }
  function passphrase(value){if(typeof value!=="string"||value.length<12||value.length>1024)throw Error("Use an independent recovery passphrase of at least 12 characters");return value;}
  async function keyFor(secret,salt){
    const crypto=cryptoReady();
    const base=await crypto.subtle.importKey("raw",encode(passphrase(secret)),"PBKDF2",false,["deriveKey"]);
    return crypto.subtle.deriveKey({name:"PBKDF2",hash:"SHA-256",salt,iterations},base,{name:"AES-GCM",length:256},false,["encrypt","decrypt"]);
  }
  function aad(e){return encode(JSON.stringify([e.format,e.version,e.playerId,e.createdAt,e.kdf,e.iterations,e.salt,e.iv]));}
  function metadata(e,playerId){
    if(!exact(e,["format","version","playerId","createdAt","kdf","iterations","salt","iv","ciphertext"])||e.format!==format||e.version!==version||e.kdf!=="PBKDF2-SHA256"||e.iterations!==iterations||!validDate(e.createdAt))throw Error("Unsupported or invalid backup format");
    const id=tornAccountStorage.owner(playerId);
    if(typeof e.playerId!=="string"||e.playerId!==id)throw Error("Backup belongs to a different Torn account");
    const salt=from64(e.salt,16),iv=from64(e.iv,12);
    if(salt.length!==16||iv.length!==12)throw Error("Invalid backup encryption parameters");
    return {salt,iv};
  }
  async function encrypt(playerId,records,secret,now=Date.now()){
    const id=tornAccountStorage.owner(playerId);tornAccountStorage.validRecords(records,id);
    if(!validDate(now)||!records.length)throw Error("No supported records to back up");
    const crypto=cryptoReady(),salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));
    const e={format,version,playerId:id,createdAt:now,kdf:"PBKDF2-SHA256",iterations,salt:b64(salt),iv:b64(iv)};
    const data=encode(JSON.stringify({playerId:id,createdAt:now,records}));
    if(data.length>maxFile/2)throw Error("Backup exceeds size limit");
    const key=await keyFor(secret,salt);
    const ciphertext=await crypto.subtle.encrypt({name:"AES-GCM",iv,additionalData:aad(e),tagLength:128},key,data);
    const result=JSON.stringify({...e,ciphertext:b64(new Uint8Array(ciphertext))});
    if(result.length>maxFile)throw Error("Backup exceeds size limit");
    return result;
  }
  async function decrypt(text,playerId,secret){
    if(typeof text!=="string"||text.length>maxFile)throw Error("Backup exceeds size limit");
    let e;try{e=JSON.parse(text);}catch{throw Error("Invalid backup file");}
    const {salt,iv}=metadata(e,playerId),ciphertext=from64(e.ciphertext,maxFile/2+16);
    if(ciphertext.length<16)throw Error("Invalid backup ciphertext");
    const key=await keyFor(secret,salt);
    let data;
    try{data=JSON.parse(decode(await cryptoReady().subtle.decrypt({name:"AES-GCM",iv,additionalData:aad(e),tagLength:128},key,ciphertext)));}
    catch{throw Error("Incorrect recovery passphrase or damaged backup");}
    if(!exact(data,["playerId","createdAt","records"])||data.playerId!==e.playerId||data.createdAt!==e.createdAt)throw Error("Backup identity or metadata mismatch");
    tornAccountStorage.validRecords(data.records,e.playerId);
    if(!data.records.length)throw Error("Backup contains no supported records");
    return data;
  }
  return {encrypt,decrypt,maxFile};
})();
