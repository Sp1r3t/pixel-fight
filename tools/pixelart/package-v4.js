"use strict";
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=path.join(__dirname,'../../art/sprites');
const source=path.join(root,'v3'),target=path.join(root,'v4');
const ids=JSON.parse(fs.readFileSync(path.join(source,'asset-ids.json'),'utf8'));
const manifest=JSON.parse(fs.readFileSync(path.join(source,'manifest.json'),'utf8'));
const files=Object.values(manifest.characters).flatMap(c=>c.files).filter(file=>!ids[file]);
assert.equal(files.length,26,'Upload list changed; inspect it before packaging');
fs.mkdirSync(target,{recursive:true});
for(const file of fs.readdirSync(target))assert(files.includes(file),`Unexpected existing file in v4: ${file}`);
for(const file of files){
 const original=fs.readFileSync(path.join(source,file));
 fs.writeFileSync(path.join(target,file),original);
 assert(original.equals(fs.readFileSync(path.join(target,file))),`Copy mismatch: ${file}`);
}
assert.equal(fs.readdirSync(target).length,26);
console.log('v4 contains exactly 26 verified PNG copies for upload');
