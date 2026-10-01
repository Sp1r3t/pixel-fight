/* Technical crop/atlas export; generated source artwork stays untouched. */
const fs=require('fs'),path=require('path');
const sharp=require('C:/Users/Tanshi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const roster=JSON.parse(fs.readFileSync(path.join(root,'roster.json'),'utf8'));
const panels=['motion','defense','combat','situational','recovery','super','reactions-grab','reactions-control'];
const rows=[['Idle','Walk','Dash','Jump'],['BackJump','Crouch','Block','Hit'],['Light','Light2','Light3','Heavy'],['CrouchLight','CrouchHeavy','AirLight','AirHeavy'],['Knockdown','WakeUp','Special'],['Super'],['Pulled','Grabbed','Lifted','Thrown'],['Launched','Slammed','Bound','Suspended']];
const animations={};
rows.forEach((names,p)=>names.forEach((name,r)=>{animations[name]={page:p+1,row:r,frames:name==='Special'?8:name==='Super'?16:4,fps:name==='Idle'?6:name==='Super'?8:12,loop:['Idle','Walk'].includes(name)};}));
function cuts(hist){const n=hist.length,out=[0];for(let i=1;i<4;i++){const ideal=n*i/4,radius=n/16;let best=ideal,score=Infinity;for(let p=Math.ceil(ideal-radius);p<ideal+radius;p++){let cost=0;for(let j=-2;j<=2;j++)cost+=(hist[p+j]||0);cost+=Math.abs(p-ideal)*0.02;if(cost<score){score=cost;best=p;}}out.push(Math.round(best));}out.push(n);return out;}
async function exportPanel(id,panel){
 const file=path.join(root,id+'-'+panel+'.png');if(!fs.existsSync(file))return {missing:true};
 const meta=await sharp(file).metadata();if(!meta.hasAlpha||Math.abs(meta.width/meta.height-1)>.02)return {error:'Square transparent 4x4 panel required'};
 const {data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true}),w=info.width,h=info.height;
 const ys=Array(h).fill(0);for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>160)ys[y]++;
 const yCuts=cuts(ys),boxes=[],flags=[];
 for(let row=0;row<4;row++){
  const top=yCuts[row],bottom=yCuts[row+1],xs=Array(w).fill(0);
  for(let y=top;y<bottom;y++)for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>160)xs[x]++;
  const xCuts=cuts(xs);
  for(let col=0;col<4;col++){
   const left=xCuts[col],right=xCuts[col+1];let minX=right,maxX=left,minY=bottom,maxY=top,opaque=0,edge=0;
   for(let y=top;y<bottom;y++)for(let x=left;x<right;x++)if(data[(y*w+x)*4+3]>64){opaque++;minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);if(x===left||x===right-1||y===top||y===bottom-1)edge++;}
   if(opaque<80){flags.push({frame:row*4+col,reason:'empty'});boxes.push(null);continue;}
   if(edge>10)flags.push({frame:row*4+col,reason:'occupied crop boundary',pixels:edge});
   minX=Math.max(left,minX-6);maxX=Math.min(right-1,maxX+6);minY=Math.max(top,minY-6);maxY=Math.min(bottom-1,maxY+6);
   boxes.push({left:minX,top:minY,width:maxX-minX+1,height:maxY-minY+1});
  }
 }
 const scale=Math.min(1,...boxes.filter(Boolean).map(b=>Math.min(236/b.width,236/b.height)));
 const inputs=[];
 for(let i=0;i<16;i++){const b=boxes[i];if(!b)continue;const width=Math.max(1,Math.round(b.width*scale)),height=Math.max(1,Math.round(b.height*scale));let pipeline=sharp(file).extract(b).resize(width,height,{kernel:'nearest'});const mirror=panel.startsWith('reactions-')&&!['rook','dax'].includes(id);if(mirror)pipeline=pipeline.flop();const input=await pipeline.png().toBuffer();inputs.push({input,left:(i%4)*256+Math.round((256-width)/2),top:Math.floor(i/4)*256+246-height});}
 const filename=id+'_'+(panels.indexOf(panel)+1)+'.png';
 await sharp({create:{width:1024,height:1024,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite(inputs).png().toFile(path.join(root,'packed',filename));
 return {file:'packed/'+filename,source:id+'-'+panel+'.png',boxes,scale,flags};
}
async function main(){
 fs.mkdirSync(path.join(root,'packed'),{recursive:true});
 const report={revision:'approved-concepts-panels-2026-09-30',frameWidth:256,frameHeight:256,columns:4,animations,characters:{},pending:[],repairs:[]};
 const selected=process.argv.slice(2);
 if(selected.length&&fs.existsSync(path.join(root,'manifest.json'))){const prior=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));if(prior.revision===report.revision){report.characters=prior.characters;report.pending=prior.pending.filter(p=>!selected.includes(p.id));report.repairs=prior.repairs.filter(p=>!selected.includes(p.id));}}
 for(const c of roster){if(selected.length&&!selected.includes(c.id))continue;const entries={},files=[];let ready=true;
  for(const panel of panels){const r=await exportPanel(c.id,panel);entries[panel]=r;if(r.missing||r.error){ready=false;report.pending.push({id:c.id,panel,...r});}else{files.push(r.file);if(r.flags.length)report.repairs.push({id:c.id,panel,flags:r.flags});}}
  report.characters[c.id]={...c,files,panels:entries,frameCount:Object.values(entries).filter(e=>e.file).length*16,status:ready?'assembled-for-review':'drawing'};
  console.log(c.id+': '+files.length+'/8 panels');
 }
 fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(report,null,2));
 fs.writeFileSync(path.join(root,'manifest.js'),'window.SKIN_MANIFEST='+JSON.stringify(report)+';');
 fs.writeFileSync(path.join(root,'asset-ids.example.json'),JSON.stringify(Object.fromEntries(roster.flatMap(c=>panels.map((_,i)=>[c.id+'_'+(i+1)+'.png','']))),null,2));
 let luau='--!strict\n-- Approved concept animation pages: 256px cells, four columns.\nlocal Types = require(script.Parent.Parent.Types)\nlocal animations: { [Types.AnimationName]: Types.SpriteAnimation } = {\n';
 for(const [name,a]of Object.entries(animations))luau+='\t'+name+' = { page = '+a.page+', row = '+a.row+', frames = '+a.frames+', fps = '+a.fps+', loop = '+a.loop+' },\n';
 luau+='}\nreturn animations\n';fs.writeFileSync(path.join(root,'ConceptSpriteLayout.luau'),luau);fs.writeFileSync(path.resolve(root,'../../../../src/shared/Config/ConceptSpriteLayout.luau'),luau);
 console.log(JSON.stringify({actors:Object.keys(report.characters).length,pending:report.pending.length,repairPanels:report.repairs.length}));
}
main().catch(e=>{console.error(e);process.exitCode=1;});

