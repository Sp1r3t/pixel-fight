"use strict";
// Reuse an uploaded ID only when the new PNG is byte-identical to the uploaded revision.
const fs=require('fs'),path=require('path');
const root=path.join(__dirname,'../..'),oldDir=path.join(root,'art/sprites/v2'),newDir=path.join(root,'art/sprites/v3');
const target=path.join(newDir,'asset-ids.json');
const oldIds=JSON.parse(fs.readFileSync(path.join(oldDir,'asset-ids.json'),'utf8'));
const manifest=JSON.parse(fs.readFileSync(path.join(newDir,'manifest.json'),'utf8'));
const uploadDir=path.join(newDir,'upload-combat');
fs.mkdirSync(uploadDir,{recursive:true});
for(const id of ['rook','brakk','sable'])for(const file of manifest.characters[id].files)fs.copyFileSync(path.join(newDir,file),path.join(uploadDir,file));
console.log('Prepared 18 combat-outfit atlases in art/sprites/v3/upload-combat');
if(fs.existsSync(target)){console.log('Preserved existing asset-ids.json');process.exit(0);}
const next={};let reused=0;
for(const c of Object.values(manifest.characters))for(const file of c.files){
 const oldFile=path.join(oldDir,file),newFile=path.join(newDir,file);
 const unchanged=fs.existsSync(oldFile)&&fs.readFileSync(oldFile).equals(fs.readFileSync(newFile));
 next[file]=unchanged?(oldIds[file]||''):'';
 if(next[file])reused++;
}
fs.writeFileSync(target,JSON.stringify(next,null,2)+'\n');
console.log(`Preserved ${reused} IDs for unchanged images; changed images await new IDs`);
