"use strict";
const fs=require('fs'),path=require('path');
const {Canvas}=require('./lib/canvas');
const {encodePNG}=require('./lib/png');
const {OUTLINE}=require('./rig');
const {drawArcade,DESIGNS}=require('./arcade');
const {sampleArcade,ANIMATIONS,FPS,LOOP}=require('./arcade-poses');
const {LOOKS}=require('./data/looks');
const {CHARACTERS}=require('./data/characters');
const SIZE=128,FRAMES=16,SUPER_FRAMES=64,COLS=8,PER_PAGE=4,PAGES=6,SS=2;
const outputPath=process.argv[3];
const out=path.resolve(__dirname,'../..',outputPath||'art/sprites/v3');
fs.mkdirSync(out,{recursive:true});
function render(c,anim,f,count=anim==='Super'?SUPER_FRAMES:FRAMES){
  const canvas=new Canvas(SIZE*SS,SIZE*SS);
  drawArcade(canvas,SIZE*SS,LOOKS[c.id],c.palette,sampleArcade(anim,f,count,c,LOOKS[c.id]),c.id);
  return canvas.toSprite(SIZE,SIZE,[...canvas.paletteSet.values()],OUTLINE);
}
function blit(dst,w,src,x,y,scale=1){
  for(let py=0;py<SIZE;py++)for(let px=0;px<SIZE;px++){
    const s=(py*SIZE+px)*4;if(!src[s+3])continue;
    for(let sy=0;sy<scale;sy++)for(let sx=0;sx<scale;sx++)src.copy(dst,((y+py*scale+sy)*w+x+px*scale+sx)*4,s,s+4);
  }
}
const manifest={version:4,artRevision:'combat-outfits',frameWidth:SIZE,frameHeight:SIZE,columns:COLS,rowsPerPage:8,frames:FRAMES,superFrames:SUPER_FRAMES,animations:{},characters:{}};
ANIMATIONS.filter(name=>name!=='Super').forEach(name=>{const i=ANIMATIONS.indexOf(name);manifest.animations[name]={page:Math.floor((i-(i>ANIMATIONS.indexOf('Super')?1:0))/PER_PAGE)+1,row:((i-(i>ANIMATIONS.indexOf('Super')?1:0))%PER_PAGE)*2,frames:FRAMES,fps:FPS[i],loop:LOOP.has(name)};});
manifest.animations.Super={page:PAGES,row:0,frames:SUPER_FRAMES,fps:0,loop:false};
const requested=process.argv[2];const only=requested&&requested!=='all'?requested:undefined;const list=only?CHARACTERS.filter(c=>c.id===only):CHARACTERS;
if(!list.length)throw Error('Unknown character '+only);
const overview=Buffer.alloc(1024*1024*4);
for(let p=0;p<overview.length;p+=4){overview[p]=24;overview[p+1]=27;overview[p+2]=39;overview[p+3]=255;}
for(const [idx,c] of list.entries()){
  const pages=Array.from({length:PAGES},()=>Buffer.alloc(1024*1024*4));
  for(const anim of ANIMATIONS){
    const meta=manifest.animations[anim];
    for(let f=0;f<meta.frames;f++){
    const pixels=render(c,anim,f,meta.frames);
    blit(pages[meta.page-1],1024,pixels,(f%COLS)*SIZE,(meta.row+Math.floor(f/COLS))*SIZE);
    if(anim==='Idle'&&f===0){
      blit(overview,1024,pixels,(idx%4)*256,Math.floor(idx/4)*256,2);
      fs.writeFileSync(path.join(out,c.id+'-portrait.png'),encodePNG(SIZE,SIZE,pixels));
    }
    }
  }
  const files=pages.map((data,i)=>{const name=`${c.id}_${i+1}.png`;fs.writeFileSync(path.join(out,name),encodePNG(1024,1024,data));return name;});
  manifest.characters[c.id]={title:DESIGNS[c.id].title,motif:DESIGNS[c.id].motif,files};
  console.log(`${c.id}: ${ANIMATIONS.length} animations, ${ANIMATIONS.filter(name=>name!=='Super').length*FRAMES+SUPER_FRAMES} frames, ${PAGES} atlases`);
}
fs.writeFileSync(path.join(out,only?only+'-overview.png':'roster.png'),encodePNG(1024,1024,overview));
fs.writeFileSync(path.join(out,only?only+'-manifest.json':'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
if(!only){
  let luau='--!strict\n-- Generated from arcade-poses.js. Local atlas rows; each animation wraps after 8 frames.\nlocal Types = require(script.Parent.Parent.Types)\nlocal animations: { [Types.AnimationName]: Types.SpriteAnimation } = {\n';
  for(const [name,a] of Object.entries(manifest.animations))luau+=`\t${name} = { page = ${a.page}, row = ${a.row}, frames = ${a.frames}, fps = ${a.fps}, loop = ${a.loop} },\n`;
  luau+='}\nreturn animations\n';
  fs.writeFileSync(path.join(out,'ArcadeSpriteLayout.luau'),luau);
  if(!outputPath)fs.writeFileSync(path.join(__dirname,'../../src/shared/Config/ArcadeSpriteLayout.luau'),luau);
  const template=fs.readFileSync(path.join(__dirname,'preview-template.html'),'utf8');
  fs.writeFileSync(path.join(out,'preview.html'),template.replace('/*MANIFEST*/',JSON.stringify(manifest)));
  fs.writeFileSync(path.join(out,'asset-ids.example.json'),JSON.stringify(Object.fromEntries(Object.values(manifest.characters).flatMap(c=>c.files.map(f=>[f,'']))),null,2)+'\n');
}
module.exports={render};
