// One source for the native Roblox illustration and its SVG review sheet.
const fs = require('fs');
const W = 912, H = 284;
const palettes = [
 ['#c5b18d','#aea387','#8e9278','#626f5b','#d9ca9c','#637f7c'],
 ['#bbc4bc','#a5b4b0','#7b918c','#506967','#d3d7c0','#6c999c'],
 ['#c7ae87','#ad9474','#927b5f','#64523f','#e0c49a','#849283'],
 ['#bda081','#a08772','#866655','#593f35','#d3b084','#b66b3e'],
 ['#aaaea2','#919889','#747f76','#3e5450','#c8c6a0','#638e87']
];
const mix = (a,b,t) => '#'+[1,3,5].map(i=>Math.round(parseInt(a.slice(i,i+2),16)*(1-t)+parseInt(b.slice(i,i+2),16)*t).toString(16).padStart(2,'0')).join('');
const chapters = [];
const names = ['Долина рассвета', 'Тропа ледяных пиков', 'Город без имени', 'Земли пепла', 'Врата затмения'];
function make(index) {
 let seed = 421 + index * 731;
 const rand = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
 const rects = [], svg = [];
 const palette = palettes[index];
 function rect(x,y,w,h,c,a=0,r=0,round=0) {
  if(w<=0||h<=0)return;
  rects.push([+x.toFixed(2),+y.toFixed(2),+w.toFixed(2),+h.toFixed(2),c,a,+r.toFixed(2),round]);
  svg.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${c}" opacity="${1-a}" rx="${round}" ${r?`transform="rotate(${r} ${x+w/2} ${y+h/2})"`:''}/>`);
 }
 function line(x1,y1,x2,y2,c,th=1,a=0) {
  const dx=x2-x1,dy=y2-y1,len=Math.hypot(dx,dy);
  rect((x1+x2)/2-len/2,(y1+y2)/2-th/2,len,th,c,a,Math.atan2(dy,dx)*180/Math.PI);
 }
 function poly(points,c,a=0) {
  if(a>0){const rgb=h=>[1,3,5].map(i=>parseInt(h.slice(i,i+2),16));const front=rgb(c),back=rgb(palette[0]);c='#'+front.map((v,i)=>Math.round(v*(1-a)+back[i]*a).toString(16).padStart(2,'0')).join('');a=0;}
  const min=Math.max(0,Math.floor(Math.min(...points.map(p=>p[1]))));
  const max=Math.min(H,Math.ceil(Math.max(...points.map(p=>p[1]))));
  // Even four-pixel spans retain the hand-drawn contour at phone scale.
  for(let y=min;y<max;y+=3) {
   const sy=y+1.5, xs=[];
   for(let i=0;i<points.length;i++) {
    const p=points[i],q=points[(i+1)%points.length];
    if((p[1]<=sy&&q[1]>sy)||(q[1]<=sy&&p[1]>sy))xs.push(p[0]+(sy-p[1])*(q[0]-p[0])/(q[1]-p[1]));
   }
   xs.sort((a,b)=>a-b);
   for(let i=0;i+1<xs.length;i+=2)rect(xs[i],y,xs[i+1]-xs[i],Math.min(3.5,H-y),c,a);
  }
 }
 function ridge(base,amplitude,c,phase) {
  const pts=[];
  for(let x=-30;x<=W+30;x+=45)pts.push([x,base+Math.sin(x*.008+phase)*amplitude+Math.sin(x*.021+phase)*amplitude*.38]);
  poly([...pts,[W+30,H],[-30,H]],c);
  for(let i=1;i<pts.length;i++)line(...pts[i-1],...pts[i],palette[3],.8,.62);
 }
 function mountain(x,y,w,h,snow=false) {
  const pts=[[x-w*.52,y+h],[x-w*.38,y+h*.8],[x-w*.28,y+h*.65],[x-w*.2,y+h*.56],[x-w*.1,y+h*.3],[x-w*.035,y+h*.19],[x,y],[x+w*.09,y+h*.22],[x+w*.16,y+h*.36],[x+w*.23,y+h*.42],[x+w*.33,y+h*.68],[x+w*.43,y+h*.79],[x+w*.56,y+h]];
  poly(pts,palette[2]);
  poly([[x,y],[x+w*.16,y+h*.37],[x+w*.33,y+h*.66],[x+w*.56,y+h],[x+w*.08,y+h],[x-w*.04,y+h*.6]],palette[3],.2);
  if(snow)poly([[x-w*.11,y+h*.3],[x,y],[x+w*.13,y+h*.3],[x+w*.04,y+h*.24],[x,y+h*.31],[x-w*.045,y+h*.2]],palette[4]);
  for(let j=0;j<5;j++)line(x-w*.19-j*5,y+h*.52+j*9,x-w*.32-j*4,y+h*.7+j*9,palette[3],.8,.48);
  for(let j=0;j<7;j++)line(x+w*.14+j*4,y+h*.47+j*7,x+w*.29+j*4,y+h*.61+j*7,palette[4],.8,.66);
 }
 function pine(x,y,s=1) {
  const c=palette[3];
  rect(x-1*s,y-3*s,2*s,13*s,c,.12);
  poly([[x,y-23*s],[x-4*s,y-13*s],[x-2*s,y-13*s],[x-7*s,y-4*s],[x-4*s,y-4*s],[x-10*s,y+5*s],[x+10*s,y+5*s],[x+4*s,y-4*s],[x+7*s,y-4*s],[x+2*s,y-13*s],[x+4*s,y-13*s]],c,.12);
  line(x,y-18*s,x-3*s,y+3*s,palette[4],.6,.5);
 }
 function temple(x,y,s=1,levels=3) {
  const ink=palette[3],light=palette[4];
  rect(x-22*s,y-5*s,44*s,8*s,ink,.1);
  for(let level=0;level<levels;level++) {
   const yy=y-14*s-level*20*s,ww=(46-level*7)*s;
   rect(x-ww*.37,yy-13*s,ww*.74,17*s,light);
   rect(x-ww*.37,yy-13*s,ww*.74,2*s,ink);
   for(const side of [-1,1])rect(x+side*ww*.25-1*s,yy-11*s,2*s,15*s,ink,.12);
   poly([[x-ww*.66,yy-11*s],[x-ww*.43,yy-13*s],[x,yy-24*s],[x+ww*.43,yy-13*s],[x+ww*.66,yy-11*s],[x+ww*.45,yy-7*s],[x-ww*.45,yy-7*s]],ink);
   line(x-ww*.53,yy-12*s,x,yy-20*s,light,.8,.35);
  }
  rect(x-5*s,y-17*s,10*s,15*s,ink);
  for(let j=0;j<3;j++)rect(x-(25+j*5)*s,y+(4+j*3)*s,(50+j*10)*s,2*s,light);
 }
 rect(0,0,W,H,palette[0]);
 // Paper flecks and distant ranges are part of the art, rather than a repeating tile.
 ridge(78,22,palette[1],index*.7);
 for(let j=0;j<5;j++)mountain(310+j*132,34+rand()*55,180+rand()*100,85+rand()*45,index===1);
 ridge(178,29,palette[0],1.4+index);
 // Water belongs to the valley and the glacial gorge, not to every region.
 if(index<2) {
  const river=[];
  for(let j=0;j<=48;j++) {
   const t=j/48;
   river.push(index===0?[390+Math.sin(t*6.5)*62+t*132,105+t*179]:[610+Math.sin(t*5)*32,110+t*174]);
  }
  for(let j=1;j<river.length;j++)line(...river[j-1],...river[j],palette[3],index===0?16:22,.56);
  for(let j=1;j<river.length;j++)line(...river[j-1],...river[j],palette[5],index===0?11:8,.2);
  for(let j=1;j<river.length;j+=4)line(river[j][0]-3,river[j][1],river[j][0]+4,river[j][1]+3,palette[4],.8,.55);
 }
 ridge(259,17,palette[1],2.3);
 // Fine contour marks and scattered stone give the large paper surfaces scale.
 for(let j=0;j<110;j++) {
  const x=rand()*W,y=130+rand()*154;
  line(x,y,x+4+rand()*9,y-1+rand()*2,palette[3],.7,.72);
 }
 for(let j=0;j<38;j++) {
  const x=rand()*W,y=153+rand()*110;
  if(index===3) {
   // Scorched stumps and broken basalt replace living woodland near the volcano.
   line(x,y,x-2,y-9,palette[3],2,.2);
   line(x-1,y-5,x+4,y-7,palette[3],1,.2);
   poly([[x+3,y+4],[x+7,y-1],[x+12,y+4]],palette[3],.25);
  } else if(Math.abs(x-460)>75)pine(x,y,.42+rand()*.44);
 }
 if(index===0) {
  temple(690,161,1.1,3); temple(195,132,.6,1);
  // Bridge across the winding river, with rails and supports.
  for(let j=0;j<11;j++)rect(434+j*5,173-j*.4,3,15,palette[4]);
  line(431,172,491,168,palette[3],2);line(431,188,491,184,palette[3],2);
 } else if(index===1) {
  mountain(717,17,260,152,true); mountain(655,55,118,104,true);
  temple(216,136,.65,2);
  line(593,204,688,183,palette[3],2);
  for(let j=0;j<12;j++)line(593+j*8,204-j*1.8,593+j*8,214-j*1.8,palette[3],1);
 } else if(index===2) {
  for(let j=0;j<9;j++)temple(622+(j%3)*53,150+Math.floor(j/3)*31,.55+(j%2)*.12,1+j%2);
  temple(686,142,1.3,4);
  // Courtyard walls have a gate and follow the edge of the settlement.
  line(605,213,680,226,palette[3],5);line(710,226,786,208,palette[3],5);
  for(let j=0;j<4;j++)rect(607+j*18,208+j*3,8,8,palette[3]);
  for(let j=0;j<4;j++)rect(717+j*18,220-j*4,8,8,palette[3]);
 } else if(index===3) {
  const x=690,y=25;mountain(x,y,260,150);
  poly([[x-27,y+10],[x-20,y-1],[x+17,y-1],[x+31,y+11],[x+10,y+17],[x-10,y+14]],palette[3]);
  const lava=[];
  for(let j=0;j<18;j++)lava.push([x-5+Math.sin(j*.34)*9+j*.8,y+17+j*7]);
  for(let j=1;j<lava.length;j++)line(...lava[j-1],...lava[j],palette[5],3+j*.15,.18);
  for(let j=9;j<17;j++)line(lava[j][0],lava[j][1],lava[j][0]+(j-8)*2,lava[j][1]+8,palette[5],1.6,.35);
  for(let j=0;j<9;j++)rect(x-13+Math.sin(j)*13,y-10-j*4,30+j*4,7,palette[3],.65+j*.025,0,4);
  temple(224,145,.8,2);
 } else {
  // Monumental final gate, eclipse and leaning stone guardians.
  rect(675,18,56,56,palette[4],0,0,28);rect(680,17,49,49,palette[3],0,0,25);
  rect(644,86,12,115,palette[3]);rect(748,86,12,115,palette[3]);
  poly([[629,80],[640,87],[764,87],[777,80],[767,96],[640,96]],palette[3]);
  rect(637,104,132,7,palette[3]);rect(659,112,84,88,palette[3],.6);
  for(let j=0;j<4;j++)rect(642-j*8,205+j*5,120+j*16,3,palette[4]);
  temple(215,140,.6,3);
 }
 // Both sides of a seam fade into the same mixed parchment, hiding hard joins.
 for(const side of [-1,1]) {
  const neighbor=index+side;
  if(neighbor<0||neighbor>=palettes.length)continue;
  const seam=mix(palette[0],palettes[neighbor][0],.5);
  for(let x=0;x<84;x+=3) {
   const t=1-x/84, opacity=t*t*(3-2*t);
   rect(side<0?x:W-x-3,0,3,H,seam,1-opacity);
  }
 }
 // Sparse engravings at the edge of the page.
 for(let j=0;j<180;j++)rect(rand()*W,rand()*H,.6+rand()*1.3,.6+rand()*1.3,palette[3],.9);
 return {name:names[index],color:palette[0],rects,svg:svg.join('')};
}
for(let i=0;i<5;i++)chapters.push(make(i));
fs.mkdirSync('art/ui/campaign',{recursive:true});
const native = '--!strict\n-- Generated by tools/ui/campaign-art.cjs; do not edit spans by hand.\nlocal data: any = '+JSON.stringify({width:W,height:H,chapters:chapters.map(({name,color,rects})=>({name,color,rects}))}).replace(/"(width|height|chapters|name|color|rects)":/g,'$1 = ').replace(/\[/g,'{').replace(/\]/g,'}')+'\nreturn data\n';
fs.writeFileSync('src/client/UI/CampaignArtwork.luau',native);
fs.writeFileSync('art/ui/campaign/atlas.svg',`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H*5}" viewBox="0 0 ${W} ${H*5}">${chapters.map((c,i)=>`<g transform="translate(0 ${i*H})">${c.svg}<text x="25" y="38" fill="#433b2d" font-family="Georgia" font-size="25">${c.name}</text></g>`).join('')}</svg>`);
fs.writeFileSync('art/ui/campaign/geometry.json',JSON.stringify({width:W,height:H,chapters:chapters.map(({name,color,rects})=>({name,color,rects}))}));
console.log(chapters.map(c=>({name:c.name,spans:c.rects.length})));
