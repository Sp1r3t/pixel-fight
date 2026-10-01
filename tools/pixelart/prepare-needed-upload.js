"use strict";
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {DESIGNS}=require('./arcade');
const root=path.join(__dirname,'../../art/sprites/v3');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'),'utf8'));
const ids=JSON.parse(fs.readFileSync(path.join(root,'asset-ids.json'),'utf8'));
const files=[];
for(const [id,c] of Object.entries(manifest.characters)){
 const missing=c.files.filter(file=>!ids[file]);
 if(missing.length)assert(DESIGNS[id].top!=='Bare',`${id}: exposed torso must be redesigned before upload`);
 files.push(...missing);
}
const target=path.join(root,'upload-needed');
fs.mkdirSync(target,{recursive:true});
for(const file of fs.readdirSync(target))assert(files.includes(file),`Stale file in upload-needed: ${file}; prepare a clean folder before uploading`);
for(const file of files){
 fs.copyFileSync(path.join(root,file),path.join(target,file));
 assert(fs.readFileSync(path.join(root,file)).equals(fs.readFileSync(path.join(target,file))));
}
fs.writeFileSync(path.join(root,'upload-needed-list.txt'),files.join('\n')+'\n');
console.log(`Prepared exactly ${files.length} PNGs: ${files.join(', ')}`);
