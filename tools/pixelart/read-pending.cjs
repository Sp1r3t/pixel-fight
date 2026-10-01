const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const roster=JSON.parse(fs.readFileSync(path.join(root,'roster.json')));
const prompts={...JSON.parse(fs.readFileSync(path.join(root,'panel-prompts.json'))),...JSON.parse(fs.readFileSync(path.join(root,'combat-prompts.json')))};
const id=process.argv[2]||'dax',panel=process.argv[3]||'super';
console.log(JSON.stringify({actor:roster.find(c=>c.id===id),prompt:prompts[id+'-'+panel]}));
