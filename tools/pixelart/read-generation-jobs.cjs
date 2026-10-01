const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const roster=JSON.parse(fs.readFileSync(path.join(root,'roster.json')));
const prompts={...JSON.parse(fs.readFileSync(path.join(root,'panel-prompts.json'))),...JSON.parse(fs.readFileSync(path.join(root,'combat-prompts.json')))};
const jobs=[];
for(const c of roster) for(const panel of ['super','motion','defense','situational','recovery','combat']) {
 const key=c.id+'-'+panel;
 if(!fs.existsSync(path.join(root,key+'.png'))) jobs.push({id:c.id,panel,reference:path.resolve(root,'..',c.reference),prompt:prompts[key]||prompts[c.id]});
}
const reactions=JSON.parse(fs.readFileSync(path.join(root,'reaction-prompts.json')));
for(const j of reactions)if(!fs.existsSync(path.join(root,j.id+'-'+j.panel+'.png')))jobs.push(j);
jobs.sort((a,b)=>{
 const ca=roster.findIndex(c=>c.id===a.id),cb=roster.findIndex(c=>c.id===b.id);
 return ca-cb;
});
console.log(JSON.stringify(jobs));
