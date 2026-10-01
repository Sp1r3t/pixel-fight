const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const roster=JSON.parse(fs.readFileSync(path.join(root,'roster.json'))),panels=['motion','defense','combat','situational','recovery','super','reactions-grab','reactions-control'];
const rows=roster.map(c=>({id:c.id,panels:panels.filter(p=>fs.existsSync(path.join(root,c.id+'-'+p+'.png')))}));
console.log(JSON.stringify({generated:rows.reduce((n,r)=>n+r.panels.length,0),total:288,ultimates:rows.filter(r=>r.panels.includes('super')).length,reactionSets:rows.filter(r=>r.panels.includes('reactions-grab')&&r.panels.includes('reactions-control')).length,completeDraftSets:rows.filter(r=>r.panels.length===8).map(r=>r.id)}));
