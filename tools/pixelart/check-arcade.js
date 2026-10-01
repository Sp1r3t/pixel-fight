"use strict";
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),zlib=require('zlib'),crypto=require('crypto');
const {sampleArcade,ANIMATIONS,STANCES}=require('./arcade-poses');
const {CHARACTERS}=require('./data/characters');
const {LOOKS}=require('./data/looks');
const {computeJoints,BUILDS}=require('./rig');
const {drawArcade,DESIGNS}=require('./arcade');
const {PATTERNS,PALETTE,pixels}=require('./icons');
let clipped=[];
for(const id of ['rook','brakk','sable'])assert(['Gi','Armor'].includes(DESIGNS[id].top),`${id}: closed combat uniform required`);
assert.equal(Object.keys(STANCES).length,16);
assert.equal(new Set(Object.values(STANCES).map(v=>v.join(','))).size,16);
for(const c of CHARACTERS){
 const look=LOOKS[c.id],base=computeJoints(sampleArcade('Idle',0,16,c,look),BUILDS[look.build]);
 for(let f=0;f<=16;f++){
  const pose=sampleArcade('Idle',f,16,c,look),j=computeJoints(pose,BUILDS[look.build]);
  for(const part of ['hip','kneeF','kneeB','ankleF','ankleB'])for(const axis of ['X','Y'])assert.equal(j[part+axis],base[part+axis],`${c.id}: planted ${part}${axis}`);
  if(f===16)for(const key of ['shoulderX','shoulderY','handFX','handFY','headY'])assert(Math.abs(j[key]-base[key])<1e-9,`${c.id}: idle loop seam`);
 }
 const dimension={...BUILDS[look.build],torsoW:BUILDS[look.build].torsoW*1.2,shoulderSpread:BUILDS[look.build].torsoW*1.2*.47};
 const idle=computeJoints(sampleArcade('Idle',0,16,c,look),dimension);
 assert(idle.handBX<idle.shoulderX-.07,`${c.id}: rear fist should be outside the torso`);
 assert(idle.handFX>idle.shoulderX+.09,`${c.id}: front fist should be outside the torso`);
 for(const anim of ANIMATIONS)for(let f=0;f<(anim==='Super'?64:16);f++){
  const pose=sampleArcade(anim,f,anim==='Super'?64:16,c,look);let outside=false,bounds=[Infinity,Infinity,-Infinity,-Infinity];
  drawArcade({fillPolygon(points){for(const [x,y] of points){bounds[0]=Math.min(bounds[0],x);bounds[1]=Math.min(bounds[1],y);bounds[2]=Math.max(bounds[2],x);bounds[3]=Math.max(bounds[3],y);if(x<.008||x>.992||y<.008||y>.992)outside=true;}}},1,look,c.palette,pose,c.id);
  if(outside)clipped.push(`${c.id}/${anim}/${f}:${bounds.map(v=>v.toFixed(2)).join('/')}`);
 }
}
for(const [name,p] of Object.entries(PATTERNS)){
 const rows=pixels(p);assert.equal(rows.length,16);
 for(const row of rows){assert.equal(row.length,16);for(const v of row)assert(v==='.'||PALETTE[v],`${name}: missing color`);}
}
const root=path.join(__dirname,'../../art/sprites/v3');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'),'utf8'));
assert.equal(Object.keys(manifest.characters).length,16);assert.equal(Object.keys(manifest.animations).length,20);
function readAtlas(file){
 const png=fs.readFileSync(path.join(root,file));assert.equal(png.readUInt32BE(16),1024);assert.equal(png.readUInt32BE(20),1024);
 const pieces=[];let cursor=8;
 while(cursor<png.length){const len=png.readUInt32BE(cursor),kind=png.toString('ascii',cursor+4,cursor+8);if(kind==='IDAT')pieces.push(png.subarray(cursor+8,cursor+8+len));cursor+=len+12;}
 return zlib.inflateSync(Buffer.concat(pieces));
}
function frameHash(raw,f,row=0){
 const h=crypto.createHash('sha256');
 for(let y=0;y<128;y++){
  const start=(row+Math.floor(f/8))*128+y;
  assert.equal(raw[start*(4097)],0);
  const x=(f%8)*128,off=start*4097+1+x*4;
  h.update(raw.subarray(off,off+128*4));
 }
 return h.digest('hex');
}
for(const c of Object.values(manifest.characters)){
 assert.equal(c.files.length,6);
 const atlases=c.files.map(readAtlas),idle=atlases[0],superSheet=atlases[5];
 for(const [name,anim] of Object.entries(manifest.animations))for(let frame=0;frame<anim.frames;frame++){
  const raw=atlases[anim.page-1],x=(frame%8)*128,y=(anim.row+Math.floor(frame/8))*128;
  let visible=false;
  for(let py=0;py<128&&!visible;py++)for(let px=0;px<128;px++)if(raw[(y+py)*4097+1+(x+px)*4+3]>0){visible=true;break;}
  assert(visible,`${c.title}/${name}/${frame}: empty sprite frame`);
 }
 const superHashes=new Set(Array.from({length:64},(_,f)=>frameHash(superSheet,f)));
 assert(superHashes.size>=48,`${c.title}: super should contain at least 48 distinct drawings`);
 const first=frameHash(idle,0);
 assert(first!==frameHash(superSheet,0),`${c.title}: idle and super must differ`);
}
if(clipped.length){console.log('Clipped poses:',clipped.length,clipped.slice(0,12));process.exitCode=1;}else console.log('PASS: 16 distinct guarded stances, visible fists, 5888 poses inside atlas bounds, planted idle, 46 icon grids, 96 atlases');
