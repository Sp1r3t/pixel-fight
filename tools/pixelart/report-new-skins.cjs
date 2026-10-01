const fs=require('fs'),path=require('path');
const root=path.resolve('art/sprites/rework/new-skins'),m=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
const counts={actors:Object.keys(m.characters).length,complete:Object.values(m.characters).filter(c=>c.frameCount===128).length,panels:Object.values(m.characters).reduce((n,c)=>n+c.frameCount/16,0),pending:m.pending.length};
console.log(JSON.stringify(counts));
for(const id of process.argv.slice(2)){const c=m.characters[id];console.log(JSON.stringify({id,panels:c.panels}));}
