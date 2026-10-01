const fs=require('fs'),path=require('path'),sharp=require('C:/Users/Tanshi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=path.resolve('art/sprites/rework/new-skins'),m=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'))),panels=['motion','defense','combat','situational','recovery','super','reactions-grab','reactions-control'];
async function main(){fs.mkdirSync(path.join(root,'gifs'),{recursive:true});let count=0;
for(const c of Object.values(m.characters)){
 const groups={};for(const [name,a]of Object.entries(m.animations)){const p=c.panels[panels[a.page-1]];if(p?.file)groups[name]=Array.from({length:a.frames},(_,i)=>({file:p.file,left:(i%4)*256,top:(a.row+Math.floor(i/4))*256,width:256,height:256}));}
 if(groups.Light)groups.Combo=['Light','Light2','Light3','Heavy'].flatMap(n=>groups[n]);
 for(const [name,frames]of Object.entries(groups)){const buffers=[];for(const f of frames)buffers.push(await sharp(path.join(root,f.file)).extract({left:f.left,top:f.top,width:256,height:256}).flatten({background:'#182135'}).ensureAlpha().raw().toBuffer());const file=path.join(root,'gifs',c.id+'-'+name+'.gif');await sharp(Buffer.concat(buffers),{raw:{width:256,height:256*frames.length,channels:4,pageHeight:256}}).gif({loop:0,delay:Array(frames.length).fill(name==='Super'?125:name==='Idle'?167:90),dither:0}).toFile(file);const meta=await sharp(file,{animated:true}).metadata();if(meta.pages!==frames.length)throw Error('GIF frame count mismatch '+file);count++;}
}console.log('Exported '+count+' GIF previews from generated frames.');}
main().catch(e=>{console.error(e);process.exitCode=1;});
