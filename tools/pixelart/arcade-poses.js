"use strict";
const {keysFor,lerpPose,GUARD}=require('./data/poses');
const {BUILDS,computeJoints}=require('./rig');
const ANIMATIONS=['Idle','Walk','Dash','Jump','Crouch','Block','Light','Heavy','Special','Super','Hit','Knockdown','CrouchLight','CrouchHeavy','AirLight','AirHeavy','Light2','Light3','BackJump'];
const FPS=[8,24,48,24,40,40,0,0,0,0,32,24,0,0,0,0,0,0,24];
const DRIVEN=new Set(['Light','Light2','Light3','Heavy','Special','Super','CrouchLight','CrouchHeavy','AirLight','AirHeavy']);
const LOOP=new Set(['Idle','Walk','Win']);
const ease=t=>t*t*(3-2*t);
// [front shoulder, front elbow, back shoulder, back elbow, front hip,
//  front knee, back hip, back knee, lean]. Both fists stay in distinct silhouettes.
const STANCES={
  rook:[48,103,-76,102,27,24,-19,22,7],
  mira:[72,65,-120,55,35,32,-28,22,13],
  brakk:[85,-5,-70,70,34,28,-32,26,3],
  juno:[90,0,-65,85,18,21,-24,23,4],
  sable:[73,93,-95,-5,38,38,-34,28,12],
  dax:[55,90,-55,115,25,26,-23,25,10],
  wren:[125,-15,-85,40,34,33,-38,29,13],
  sorren:[32,135,-110,45,18,21,-19,23,1],
  pike:[60,80,-50,90,31,23,-31,21,8],
  zip:[78,0,-120,20,42,36,-30,26,17],
  ashka:[110,-15,-100,95,37,34,-34,29,11],
  glacia:[80,70,-80,95,22,21,-23,20,3],
  tempest:[70,75,-115,30,29,24,-33,25,9],
  byte:[100,0,-70,90,26,26,-27,22,7],
  morrow:[45,100,-100,50,22,24,-28,27,1],
  astra:[120,-20,-85,30,19,20,-26,21,2],
};
// Each cinematic has its own anticipation, action line, impact and recovery.
// A visual motif is also passed to the atlas painter; supers never share a delivery pose.
const SUPER_BEATS={
  rook:[{lean:-14,sF:150,eF:30,sB:30,eB:95},{lean:22,sF:86,eF:0,sB:-118,eB:50,x:.04},{lean:-18,sF:174,eF:0,sB:44,eB:74,hF:78,kF:92,hip:.48,rot:-35,strike:'handF'},{lean:18,sF:80,eF:10,sB:38,eB:90,hip:.56,rot:0},{lean:4}],
  mira:[{lean:-16,hF:70,kF:105,sF:42,eF:80},{lean:8,hF:112,kF:0,sB:85,eB:30,rot:35,strike:'footF'},{lean:-14,hB:105,kB:0,sF:96,eF:4,rot:-65,strike:'footB'},{lean:10,hF:35,kF:25,hip:.52,rot:360,strike:'footF'},{lean:4,rot:0}],
  brakk:[{lean:-22,sF:66,eF:55,sB:70,eB:55,hF:42,kF:25},{lean:30,sF:96,eF:0,sB:88,eB:0,x:.04,strike:'handF'},{lean:-4,sF:170,eF:15,sB:166,eB:18,hip:.48,hF:70,kF:65},{lean:40,sF:38,eF:5,sB:25,eB:5,hip:.78,rot:65},{lean:4,hip:.70}],
  juno:[{lean:-8,sF:150,eF:20,open:true},{lean:4,sF:130,eF:0,sB:90,eB:0,open:true,rot:50},{lean:4,sF:95,eF:0,sB:82,eB:4,rot:0,strike:'weapon'},{lean:15,sF:72,eF:10,sB:90,eB:0,open:true,rot:-35,strike:'weapon'},{lean:4,rot:0}],
  sable:[{lean:-20,sF:-20,eF:65,sB:10,eB:70,drop:.02},{lean:26,sF:96,eF:0,sB:135,eB:0,x:.05,strike:'weapon'},{lean:-16,sF:155,eF:-15,sB:72,eB:0,rot:35,strike:'weapon'},{lean:30,sF:78,eF:0,sB:92,eB:0,rot:-35,strike:'weapon'},{lean:4,rot:0}],
  dax:[{lean:-20,sF:42,eF:100,sB:55,eB:105},{lean:24,sF:88,eF:0,sB:-100,eB:50,x:.04,strike:'handF'},{lean:22,sF:-110,eF:45,sB:94,eB:0,x:.04,strike:'handB'},{lean:30,sF:92,eF:0,sB:90,eB:2,x:.05,strike:'handF'},{lean:6}],
  wren:[{lean:-18,hF:70,kF:95,hB:-28,kB:60,hip:.52},{lean:2,hF:105,kF:0,hB:28,kB:55,hip:.46,rot:120,strike:'footF'},{lean:-24,hB:100,kB:0,hF:30,kF:70,hip:.50,rot:250,strike:'footB'},{lean:32,hF:70,kF:35,hB:12,kB:28,hip:.56,rot:360,strike:'footF'},{lean:4,hip:.58,rot:0}],
  sorren:[{lean:-12,sF:78,eF:100,sB:78,eB:100,open:true},{lean:-2,sF:80,eF:105,sB:80,eB:105,open:true,glow:1},{lean:20,sF:88,eF:0,sB:90,eB:0,open:true,strike:'handF'},{lean:16,sF:80,eF:10,sB:90,eB:0,open:true,strike:'handB'},{lean:2}],
  pike:[{lean:-24,sF:158,eF:-24,sB:30,eB:90},{lean:10,sF:42,eF:75,sB:70,eB:10},{lean:34,sF:92,eF:0,sB:82,eB:15,hF:66,kF:34,hB:-50,kB:8,x:.06,strike:'weapon'},{lean:28,sF:85,eF:0,sB:72,eB:15,x:.045,strike:'weapon'},{lean:4}],
  zip:[{lean:32,hF:48,kF:95,hB:-52,kB:110,sF:-30,eF:40,sB:-45,eB:40,drop:.035},{lean:22,x:.06,rot:45,hF:95,kF:50,strike:'footF'},{lean:-18,x:-.06,rot:-45,hB:95,kB:45,strike:'footB'},{lean:14,sF:88,eF:0,sB:82,eB:5,x:.03,strike:'handF'},{lean:8,x:0,rot:0}],
  ashka:[{lean:-18,sF:145,eF:0,sB:145,eB:0,open:true,glow:1},{lean:8,sF:170,eF:0,sB:170,eB:0,hip:.48,rot:35,strike:'weapon'},{lean:-8,hF:55,kF:60,hB:-20,kB:45,sF:95,eF:0,sB:85,eB:0,hip:.47,rot:200,strike:'weapon'},{lean:12,sF:88,eF:0,sB:78,eB:10,glow:.8,rot:360,strike:'weapon'},{lean:3,rot:0}],
  glacia:[{lean:-12,sF:100,eF:70,sB:60,eB:100,glow:.5},{lean:4,sF:55,eF:45,sB:110,eB:40,glow:1,open:true},{lean:12,sF:90,eF:0,sB:70,eB:5,glow:1,open:true,strike:'weapon'},{lean:6,sF:65,eF:24,sB:100,eB:35,glow:.8,open:true},{lean:2,glow:.2}],
  tempest:[{lean:-24,sF:150,eF:-20,sB:-105,eB:45},{lean:-4,sF:170,eF:-25,sB:12,eB:80},{lean:35,sF:62,eF:0,sB:38,eB:70,x:.05,rot:24,strike:'weapon'},{lean:25,sF:88,eF:0,sB:30,eB:90,x:.035,rot:-24,strike:'weapon'},{lean:4,rot:0}],
  byte:[{lean:-12,sF:95,eF:70,sB:72,eB:100,open:true,glow:.8},{lean:2,sF:80,eF:30,sB:98,eB:5,open:true,glow:1},{lean:14,sF:90,eF:0,sB:80,eB:10,open:true,glow:1,strike:'handF'},{lean:12,sF:72,eF:20,sB:92,eB:0,open:true,glow:.8,strike:'handB'},{lean:2,glow:.2}],
  morrow:[{lean:-25,sF:165,eF:-20,sB:22,eB:75,glow:.6},{lean:22,sF:94,eF:0,sB:32,eB:85,x:.04,glow:1,strike:'weapon'},{lean:-12,sF:150,eF:-10,sB:110,eB:0,rot:30,glow:1,strike:'weapon'},{lean:26,sF:80,eF:0,sB:92,eB:0,x:.045,rot:-25,glow:.8,strike:'weapon'},{lean:2,rot:0,glow:.2}],
  astra:[{lean:-14,sF:110,eF:65,sB:110,eB:65,open:true,glow:.7},{lean:0,sF:90,eF:0,sB:90,eB:0,open:true,glow:1,hip:.56},{lean:8,sF:100,eF:0,sB:70,eB:25,open:true,glow:1,rot:45},{lean:12,sF:88,eF:0,sB:80,eB:0,open:true,glow:1,rot:360},{lean:2,glow:.2,rot:0}],
};
function stance(id){const s=STANCES[id];return {...GUARD,sF:s[0],eF:s[1],sB:s[2],eB:s[3],hF:s[4],kF:s[5],hB:s[6],kB:s[7],lean:s[8]};}
function lightKeys(name,base){
  if(name==='Light2')return [base,{...base,lean:base.lean-8,sB:-120,eB:47,sF:base.sF+8,eF:86},
    {...base,lean:base.lean+19,sB:100,eB:-15,sF:64,eF:92,x:.025,strike:'handB'},
    {...base,lean:base.lean+13,sB:100,eB:-10,sF:62,eF:88,x:.018,strike:'handB'},base];
  if(name==='Light3')return [base,{...base,lean:base.lean-14,sF:-34,eF:80,sB:43,eB:90},
    {...base,lean:base.lean+24,sF:78,eF:0,sB:-51,eB:74,hF:base.hF+14,x:.04,strike:'handF'},
    {...base,lean:base.lean+19,sF:80,eF:8,sB:-46,eB:75,x:.028,strike:'handF'},base];
  return null;
}

// Armed fighters attack with the item they carry. Each step uses a different
// weapon line (thrust, reverse cut, committed finisher) instead of leaving the
// prop idle while the other hand throws the same generic punch.
function weaponKeys(name,base,kind){
  if(!['Light','Light2','Light3','Heavy','CrouchLight','CrouchHeavy','AirLight','AirHeavy'].includes(name))return null;
  const contact=(pose)=>({...base,...pose,strike:'weapon'});
  const recover={...base};
  if(name==='CrouchLight')return [
    {...base,lean:base.lean+12,hF:base.hF+25,kF:105,hB:base.hB-8,kB:112,sF:base.sF-18},
    contact({lean:base.lean+20,hF:base.hF+22,kF:108,hB:base.hB-6,kB:115,sF:88,eF:0,x:.025}),
    contact({lean:base.lean+14,hF:base.hF+24,kF:108,sF:82,eF:5,x:.02}),recover];
  if(name==='CrouchHeavy')return [
    {...base,lean:-16,hF:base.hF+25,kF:100,sF:152,eF:-24},
    contact({lean:30,hF:base.hF+28,kF:95,sF:62,eF:0,x:.045}),
    contact({lean:24,hF:base.hF+26,kF:100,sF:75,eF:-2,x:.035}),recover];
  if(name==='AirLight')return [
    {...base,hip:.57,lean:-4,hF:75,kF:82,hB:-5,kB:45,sF:base.sF-10},
    contact({hip:.56,lean:14,hF:72,kF:88,hB:-8,kB:48,sF:91,eF:-2,x:.025}),
    contact({hip:.57,lean:5,hF:68,kF:82,hB:-10,kB:44,sF:75,eF:8}),recover];
  if(name==='AirHeavy')return [
    {...base,hip:.56,lean:-20,hF:95,kF:72,hB:-25,kB:45,sF:155,eF:-25},
    contact({hip:.53,lean:28,hF:110,kF:25,hB:-35,kB:30,sF:76,eF:0,x:.045}),
    contact({hip:.54,lean:20,hF:102,kF:32,sF:86,eF:0,x:.035}),recover];
  if(kind==='DualKnives'){
    if(name==='Light')return [base,{...base,sF:base.sF-16,eF:92},{...base,lean:20,sF:91,eF:-4,sB:base.sB+18,eB:92,x:.03,strike:'weapon'}, {...base,lean:14,sF:78,eF:8,x:.02,strike:'weapon'},recover];
    if(name==='Light2')return [base,{...base,lean:-12,sF:base.sF+24,eF:88,sB:base.sB-15,eB:92},{...base,lean:24,sF:base.sF-10,eF:90,sB:92,eB:-4,x:.035,strike:'weapon'},{...base,lean:17,sB:82,eB:8,x:.025,strike:'weapon'},recover];
    if(name==='Light3'||name==='Heavy')return [base,{...base,lean:-18,sF:154,eF:-28,sB:-112,eB:35},{...base,lean:32,sF:66,eF:-6,sB:74,eB:0,hF:base.hF+15,x:.055,strike:'weapon'},{...base,lean:22,sF:80,eF:0,sB:88,eB:0,x:.04,strike:'weapon'},recover];
  }
  if(name==='Light2'&&(kind==='Fans'||kind==='Disc'))return [base,{...base,sF:base.sF+12,eF:92,sB:-110,eB:55},{...base,lean:18,sB:96,eB:-8,sF:62,eF:88,x:.03,strike:'weapon'},recover];
  if(kind==='Spear'||kind==='Staff'){
    if(name==='Light')return [base,{...base,sF:42,eF:72},contact({lean:17,sF:91,eF:-3,x:.04}),contact({lean:13,sF:88,eF:2,x:.03}),recover];
    if(name==='Light2')return [base,{...base,lean:-12,sF:151,eF:-38},contact({lean:8,sF:42,eF:3,x:.035}),contact({lean:12,sF:55,eF:-2,x:.025}),recover];
    if(name==='Light3')return [base,{...base,lean:-18,sF:-65,eF:42},contact({lean:26,sF:103,eF:-7,hF:base.hF+13,x:.055}),contact({lean:18,sF:96,eF:0,x:.04}),recover];
    return [base,{...base,lean:-20,sF:166,eF:-28},contact({lean:30,sF:78,eF:0,hF:base.hF+18,x:.06}),contact({lean:20,sF:83,eF:3,x:.04}),recover];
  }
  if(kind==='Katana'||kind==='Scythe'){
    if(name==='Light')return [base,{...base,lean:-9,sF:158,eF:-22},contact({lean:21,sF:60,eF:-9,x:.04}),contact({lean:15,sF:70,eF:-5,x:.03}),recover];
    if(name==='Light2')return [base,{...base,lean:19,sF:42,eF:0},contact({lean:-12,sF:143,eF:-18,x:.025}),contact({lean:-6,sF:132,eF:-10,x:.02}),recover];
    if(name==='Light3')return [base,{...base,lean:-22,sF:-48,eF:25},contact({lean:32,sF:92,eF:-6,hF:base.hF+14,x:.055}),contact({lean:24,sF:88,eF:0,x:.04}),recover];
    return [base,{...base,lean:-28,sF:176,eF:-20},contact({lean:35,sF:74,eF:-12,hF:base.hF+20,x:.065}),contact({lean:22,sF:80,eF:-5,x:.045}),recover];
  }
  if(name==='AirLight'||name==='AirHeavy'){
    const kick=name==='AirHeavy';
    return [
      {...base,hip:.56,lean:kick?-20:-4,hF:kick?95:75,kF:kick?72:82,hB:-15,kB:45,sF:150,eF:20},
      contact({hip:.53,lean:kick?28:14,hF:kick?110:72,kF:kick?25:88,hB:-22,kB:40,sF:kick?76:91,eF:0,x:.04}),
      contact({hip:.54,lean:18,hF:kick?102:68,kF:32,sF:84,eF:0,x:.03}),recover];
  }
  if(kind==='Fans'||kind==='Disc'){
    if(name==='Light2')return [base,{...base,sF:base.sF+12,eF:92,sB:-110,eB:55},contact({lean:18,sB:96,eB:-8,sF:62,eF:88,x:.03,strike:'handB'}),recover];
    if(name==='Heavy')return [base,{...base,lean:-14,sF:166,eF:-20},contact({lean:28,sF:83,eF:-6,hF:base.hF+14,x:.055}),contact({lean:18,sF:88,eF:0,x:.035}),recover];
    return [base,{...base,lean:-10,sF:145,eF:-30},contact({lean:20,sF:88,eF:-4,x:.04}),contact({lean:14,sF:92,eF:0,x:.03}),recover];
  }
  return null;
}

const BACKFLIP=new Set(['mira','wren','zip','ashka']);
function backJumpKeys(base,id){
  const flip=BACKFLIP.has(id);
  return [
    {...base,lean:-12,hF:base.hF+24,kF:88,hB:base.hB-16,kB:92,drop:.018},
    {...base,lean:-24,hF:flip?72:42,kF:flip?128:110,hB:flip?-18:-54,kB:flip?115:128,hip:.58,rot:flip?-55:0,x:-.018},
    {...base,lean:flip?-8:-18,hF:flip?-8:20,kF:flip?42:92,hB:flip?72:40,kB:flip?96:104,hip:.54,rot:flip?-190:0,x:-.025},
    {...base,lean:flip?16:-10,hF:flip?-36:18,kF:flip?60:80,hB:flip?42:-18,kB:flip?80:100,hip:.60,rot:flip?-360:0,x:-.018},
    {...base,lean:-4,hF:base.hF-12,kF:30,hB:base.hB+8,kB:35,drop:.025},base];
}

function unarmedKeys(name,base,id){
  if(name==='Heavy'&&id==='dax')return [base,
    {...base,lean:-18,sF:148,eF:8,sB:36,eB:96,hF:base.hF+14},
    {...base,lean:30,sF:82,eF:0,sB:104,eB:4,x:.055,strike:'handF'},
    {...base,lean:24,sF:88,eF:2,sB:92,eB:8,x:.04,strike:'handF'},base];
  if(name==='Heavy'&&['sorren','byte','astra'].includes(id))return [base,
    {...base,lean:-18,sF:150,eF:28,sB:140,eB:34,glow:.75,open:true},
    {...base,lean:18,sF:92,eF:0,sB:80,eB:8,glow:1,open:true,x:.045,strike:'handF'},
    {...base,lean:14,sF:86,eF:4,sB:74,eB:12,glow:.8,open:true,x:.035,strike:'handF'},base];
  // Character-specific hand strings: the active hand alternates across Light,
  // Light2 and Light3, while kickers and channelers get their own silhouettes.
  if(['rook','brakk','dax'].includes(id)&&['Light','Light2','Light3'].includes(name)){
    const power=id==='brakk'?1.35:id==='dax'?1.12:1;
    const back=name==='Light2',hook=name==='Light3';
    const lead=back?'sB':'sF',elbow=back?'eB':'eF',other=back?'sF':'sB',otherElbow=back?'eF':'eB';
    const prep={...base,lean:base.lean-(hook?15:8),[lead]:hook?-38:back?base.sB-12:base.sF-16,[elbow]:hook?72:96,[other]:hook?48:base.sB-18,[otherElbow]:hook?82:92};
    const hit={...base,lean:base.lean+18*power,[lead]:hook?104:92,[elbow]:hook?-8:0,[other]:back?18:-42,[otherElbow]:back?64:84,hF:base.hF+8,x:.035*power,strike:back?'handB':'handF'};
    return [prep,hit,{...hit,lean:hit.lean-4,x:hit.x-.006},base];
  }
  if(['mira','wren','zip'].includes(id)&&['Light','Light2','Light3'].includes(name)){
    const kick=name!=='Light';
    const leg=name==='Light2'?'hF':'hB',knee=name==='Light2'?'kF':'kB';
    const wind={...base,lean:id==='zip'?18:-10,hF:base.hF+20,kF:78,sF:base.sF-24,sB:base.sB+28};
    const active={...base,lean:id==='mira'?-16:-22,[leg]:name==='Light3'?112:125,[knee]:name==='Light3'?0:4,hF:name==='Light3'?base.hF+16:base.hF-12,kF:name==='Light3'?96:base.kF,sF:36,eF:70,sB:112,eB:58,x:id==='zip'?.05:.035,strike:name==='Light'?'handF':'foot'+(name==='Light2'?'F':'B')};
    if(!kick){active.hF=base.hF+10;active.kF=35;active.sF=92;active.eF=0;active.strike='handF';}
    return [wind,active,{...active,lean:active.lean+5,x:(active.x||0)-.008},base];
  }
  if(['sorren','byte','astra'].includes(id)&&['Light','Light2','Light3'].includes(name)){
    const back=name==='Light2',high=name==='Light3';
    const wind={...base,lean:-10,sF:back?base.sF+18:base.sF-20,sB:back?base.sB-22:base.sB+16,eF:70,eB:74,open:true,glow:.35};
    const spell={...base,lean:high?-8:14,sF:back?74:94,eF:0,sB:back?96:72,eB:4,open:true,glow:1,hF:high?base.hF+14:base.hF,x:.025,strike:back?'handB':'handF'};
    return [wind,spell,{...spell,lean:spell.lean-3,glow:.8,x:.018},base];
  }
  if(name==='Heavy'&&['mira','wren','zip'].includes(id))return [base,
    {...base,lean:-14,hF:64,kF:92,sF:42,sB:70,eB:65},
    {...base,lean:-26,hF:112,kF:0,sF:20,eF:55,sB:82,eB:50,x:.04,strike:'footF'},
    {...base,lean:-20,hF:104,kF:8,x:.03,strike:'footF'},base];
  if(name==='Heavy'&&id==='brakk')return [base,
    {...base,lean:-20,sF:65,eF:50,sB:75,eB:55,hF:48,kF:25},
    {...base,lean:32,sF:93,eF:0,sB:88,eB:0,hF:55,kF:18,x:.045,strike:'handF'},
    {...base,lean:26,sF:86,eF:4,sB:82,eB:5,x:.035,strike:'handB'},base];
  if(name==='Heavy'&&id==='dax')return [base,
    {...base,lean:-18,sF:35,eF:105,sB:-120,eB:55},
    {...base,lean:30,sF:88,eF:0,sB:102,eB:-12,x:.045,strike:'handB'},
    {...base,lean:24,sF:90,eF:0,sB:92,eB:0,x:.035,strike:'handF'},base];
  if(name==='Heavy'&&['sorren','byte','astra'].includes(id))return [base,
    {...base,lean:-15,sF:75,eF:105,sB:70,eB:105,open:true,glow:.45},
    {...base,lean:22,sF:90,eF:0,sB:78,eB:8,open:true,glow:1,x:.04,strike:'handF'},
    {...base,lean:18,sF:82,eF:4,sB:92,eB:0,open:true,glow:.7,x:.025,strike:'handB'},base];
  if(['AirLight','AirHeavy'].includes(name)&&['mira','wren','zip'].includes(id)){
    const heavy=name==='AirHeavy';return [
      {...base,hip:.56,lean:-12,hF:76,kF:90,hB:-30,kB:65},
      {...base,hip:.52,lean:-20,hF:heavy?118:108,kF:0,hB:34,kB:65,sF:55,sB:80,eB:45,x:.035,strike:'footF'},
      {...base,hip:.54,lean:-14,hF:heavy?112:100,kF:6,x:.025,strike:'footF'},base];
  }
  if(['AirLight','AirHeavy'].includes(name)&&['sorren','byte','astra'].includes(id)){
    return [
      {...base,hip:.56,lean:-6,hF:55,kF:65,hB:-25,kB:55,sF:75,eF:85,open:true,glow:.35},
      {...base,hip:.53,lean:16,hF:52,kF:72,hB:-22,kB:48,sF:92,eF:0,sB:88,eB:0,open:true,glow:1,x:.035,strike:'handF'},
      {...base,hip:.55,lean:8,sF:80,eF:5,sB:92,eB:0,open:true,glow:.55,strike:'handB'},base];
  }
  // Agile fighters weave kicks into the light chain; bruisers use alternating
  // hooks; mystics use open-hand strikes. This keeps silhouettes character-led.
  if((id==='mira'||id==='wren'||id==='zip')&&name==='Light3')return [base,
    {...base,lean:-16,hF:55,kF:92,sF:35,sB:82},
    {...base,lean:-24,hF:108,kF:2,sF:18,eF:55,sB:86,eB:48,x:.035,strike:'footF'},
    {...base,lean:-18,hF:104,kF:6,x:.025,strike:'footF'},base];
  if((id==='brakk'||id==='dax')&&name==='Light2')return [base,
    {...base,lean:-12,sB:-135,eB:55,sF:62,eF:88},
    {...base,lean:25,sB:104,eB:-18,sF:54,eF:96,x:.045,strike:'handB'},
    {...base,lean:18,sB:98,eB:-10,x:.03,strike:'handB'},base];
  if((id==='sable'||id==='sorren'||id==='byte'||id==='astra')&&name==='Light3')return [base,
    {...base,lean:-8,sF:12,eF:92,sB:-10,eB:96,open:true},
    {...base,lean:22,sF:90,eF:0,sB:86,eB:4,x:.045,open:true,strike:'handF'},
    {...base,lean:16,sF:88,eF:4,sB:84,eB:8,x:.03,open:true,strike:'handB'},base];
  return null;
}
function sampleArcade(animation,frame,count,c,look){
  const phase=frame/count;
  const base=stance(c.id);
  if(animation==='BackJump'){
    const keys=backJumpKeys(base,c.id).map(p=>({...p,hip:p.hip===undefined?computeJoints(p,BUILDS[look.build]).hipY-(p.drop||0):p.hip}));
    const pos=frame/(count-1)*(keys.length-1),a=Math.floor(pos),b=Math.min(a+1,keys.length-1);
    return lerpPose(keys[a],keys[b],ease(pos-a));
  }
  if(animation==='Super'){
    const beats=[base,...(SUPER_BEATS[c.id]||SUPER_BEATS.rook),base];
    const pos=frame/(count-1)*(beats.length-1),a=Math.floor(pos),b=Math.min(a+1,beats.length-1);
    const result=lerpPose({...base,...beats[a]},{...base,...beats[b]},ease(pos-a));
    result.superPhase=frame/(count-1);result.superKind=c.superDelivery;result.superStyle=c.id;
    return result;
  }
  if(animation==='Idle') {
    const b=Math.sin(phase*2*Math.PI);
    // Hips, knees, ankles and horizontal origin are EXACTLY constant throughout idle.
    return {...base,sF:base.sF+b*1.8,eF:base.eF+b,
      sB:base.sB-b*1.5,eB:base.eB-b,breath:b*.003,head:b*.35,x:0,drop:0};
  }
  const raw=weaponKeys(animation,base,look.weapon&&look.weapon.kind)
    ||unarmedKeys(animation,base,c.id)
    ||lightKeys(animation,base)
    ||[...keysFor(animation,c.specialKind,c.superDelivery)];
  if(DRIVEN.has(animation)&&!animation.startsWith('Air')&&!animation.startsWith('Crouch'))raw[raw.length-1]=base;
  if(animation==='Light'||animation==='Heavy'||animation==='Special'||animation==='Super')raw[0]=base;
  // Explicit hip heights must blend continuously with grounded poses (no midpoint snap).
  const keys=raw.map(p=>({...p,hip:computeJoints(p,BUILDS[look.build]).hipY-(p.drop||0)}));
  let p=LOOP.has(animation)?phase:frame/(count-1);
  let a,b,t;
  if(DRIVEN.has(animation)){
    let first=keys.findIndex(k=>k.strike),last=first;
    if(first<0)first=Math.min(2,keys.length-1);
    last=first;
    while(last+1<keys.length && (keys[last+1].strike||keys[last+1].glow>=.6))last++;
    // AnimationSelect maps startup/active/recovery to thirds. Keep contact poses in the middle third.
    const pos=p<1/3?p*3*first:p<2/3?first+(p*3-1)*(last-first):last+(p*3-2)*(keys.length-1-last);
    a=Math.floor(pos);b=Math.min(a+1,keys.length-1);t=ease(pos-a);
  }else{
    const pos=p*(LOOP.has(animation)?keys.length:keys.length-1);
    a=Math.floor(pos);b=LOOP.has(animation)?(a+1)%keys.length:Math.min(a+1,keys.length-1);t=ease(pos-a);
  }
  const result=lerpPose(keys[a],keys[b],t);
  if(animation==='Super') {
    result.superPhase=phase;
    result.superKind=c.superDelivery;
  }
  if(c.id==='tempest'&&animation==='Super') {result.lean=Math.min(result.lean,30);result.x=0;}
  return result;
}
module.exports={sampleArcade,ANIMATIONS,FPS,LOOP,DRIVEN,STANCES,stance};
