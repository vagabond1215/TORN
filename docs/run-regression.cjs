"use strict";
// Native test runner: node docs/run-regression.cjs (from any cwd).
const fs=require("node:fs"),path=require("node:path"),{spawnSync}=require("node:child_process");
const base=__dirname,tests=path.join(base,"tests");
const js=fs.readdirSync(base,{withFileTypes:true}).filter(x=>x.isFile()&&x.name.endsWith(".js")).map(x=>path.join(base,x.name)).sort();
const fixtures=fs.readdirSync(tests,{withFileTypes:true}).filter(x=>x.isFile()&&/\.(cjs|mjs)$/.test(x.name)).map(x=>path.join(tests,x.name)).sort();
let failed=0;
const execute=(label,args)=>{const result=spawnSync(process.execPath,args,{cwd:path.dirname(base),stdio:"inherit",timeout:120000});const ok=result.status===0&&!result.error;if(!ok)failed++;console.log((ok?"PASS ":"FAIL ")+label+(result.error?" ("+result.error.message+")":""));};
console.log("Node "+process.version+" · "+js.length+" syntax checks · "+fixtures.length+" isolated test files");
for(const f of js)execute("syntax "+path.basename(f),["--check",f]);
for(const f of fixtures)execute(path.basename(f),[f]);
console.log(failed?failed+" failure(s)":"All native checks passed");
process.exitCode=failed?1:0;
