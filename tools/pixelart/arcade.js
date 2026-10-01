"use strict";
// Art direction v2: articulated, angular anatomy; four-tone clusters, no gradients.
const { hex, shade } = require('./lib/canvas');
const { computeJoints, BUILDS } = require('./rig');

function vivid(c, boost=1.35) {
  const lo=Math.min(c.r,c.g,c.b),hi=Math.max(c.r,c.g,c.b),mid=(lo+hi)/2;
  const lift=hi<125?16:hi<190?9:0;
  return {r:Math.max(0,Math.min(255,Math.round(mid+(c.r-mid)*boost+lift))),
    g:Math.max(0,Math.min(255,Math.round(mid+(c.g-mid)*boost+lift))),
    b:Math.max(0,Math.min(255,Math.round(mid+(c.b-mid)*boost+lift)))};
}

const DESIGNS = {
  rook:    { title:'Street Vanguard', motif:'wraps', hair:'#E8C15B', top:'Gi', pants:'#283C78', accent:'#D94343', stance:0 },
  mira:    { title:'Cyclone Kickboxer', motif:'stripes', hair:'#522B42', top:'Top', pants:'#233951', accent:'#EFAF56', stance:1 },
  brakk:   { title:'Mountain Grappler', motif:'stone', hair:'#4E3028', top:'Armor', coat:'#495A76', pants:'#493B31', accent:'#C38B4B', stance:2 },
  juno:    { title:'Orbit Ace', motif:'pilot', hair:'#251E32', top:'Jacket', pants:'#293F5D', accent:'#F1AD50', stance:3 },
  sable:   { title:'Shade Walker', motif:'ninja', hair:'#171A31', top:'Gi', pants:'#32304E', accent:'#BF3448', stance:4 },
  dax:     { title:'Knockout Artist', motif:'boxing', hair:'#231E27', top:'Tank', pants:'#8D2E3D', accent:'#E8D9B2', stance:5 },
  wren:    { title:'Talon Acrobat', motif:'feathers', hair:'#E4D2A4', top:'Top', pants:'#24473F', accent:'#B6D776', stance:6 },
  sorren:  { title:'Still Water Monk', motif:'monk', hair:'#342A24', top:'Gi', pants:'#B45F35', accent:'#E2BD76', stance:7 },
  pike:    { title:'Longreach Lancer', motif:'knight', hair:'#342A30', top:'Armor', pants:'#28374C', accent:'#D9B967', stance:8 },
  zip:     { title:'Rocket Rookie', motif:'racer', hair:'#E7B84D', top:'Jacket', pants:'#243E49', accent:'#F1CE62', stance:9 },
  ashka:   { title:'Pyre Dancer', motif:'flame', hair:'#672C33', top:'Top', pants:'#8C2935', accent:'#F2B855', stance:10 },
  glacia:  { title:'Frost Warden', motif:'ice', hair:'#DFEBEA', top:'Armor', pants:'#284C71', accent:'#B5EEE8', stance:11 },
  tempest: { title:'Storm Ronin', motif:'samurai', hair:'#232335', top:'Gi', pants:'#303547', accent:'#D8AC61', stance:12 },
  byte:    { title:'Glitch Operator', motif:'tech', hair:'#283043', top:'Jacket', pants:'#283140', accent:'#67DBC4', stance:13 },
  morrow:  { title:'Lantern Reaper', motif:'reaper', hair:'#1D2634', top:'Cloak', pants:'#263A3E', accent:'#85CFAF', stance:14 },
  astra:   { title:'Starbound Oracle', motif:'stars', hair:'#D5C4E3', top:'Robe', pants:'#423B70', accent:'#ECC987', stance:15 },
};

function drawArcade(canvas, size, look, palette, pose, id) {
  const design = DESIGNS[id];
  const d = { ...BUILDS[look.build] };
  // Adult arcade proportions: substantial shoulders, narrow waist, defined calves.
  d.torsoW *= 1.20; d.armW *= 1.36; d.foreW *= 1.20; d.legW *= 1.40;
  d.shinW *= 1.40; d.head *= 0.94; d.shoulderSpread = d.torsoW * .47;
  if (['wraps','ninja','monk','samurai','flame'].includes(design.motif)) d.legW *= 1.35;
  if (look.build === 'Small') { d.torsoLen *= 1.10; d.thigh *= 1.08; d.shin *= 1.08; }
  const j = computeJoints(pose, d);
  const skin = vivid(hex(look.skin),1.08), cloth = vivid(hex(design.coat||palette.primary)), pants = vivid(hex(design.pants),1.45);
  const trim = vivid(hex(design.accent),1.25), hair = vivid(hex(design.hair),1.20), ink = hex('#171522');
  const light = c => shade(c,-0.27), shadow = c => shade(c,0.28), deep = c => shade(c,0.48);
  const shapes=[];
  const poly = (points,c) => shapes.push({points,c});
  const line = (a,b,w,c) => {
    const dx=b[0]-a[0],dy=b[1]-a[1],l=Math.hypot(dx,dy)||1;
    const nx=-dy/l*w/2,ny=dx/l*w/2;
    poly([[a[0]+nx,a[1]+ny],[b[0]+nx,b[1]+ny],[b[0]-nx,b[1]-ny],[a[0]-nx,a[1]-ny]],c);
  };
  const joint = name => [j[name+'X'],j[name+'Y']];
  const mix = (a,b,t)=>[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
  if(pose.superPhase!==undefined) {
    const phase=pose.superPhase;
    const beat=Math.max(0,1-Math.abs(phase-.56)/.36),
      cx=Math.max(.28,Math.min(.70,j.hipX)),cy=Math.max(.30,Math.min(.72,j.hipY-.12));
    const P=(x,y)=>[Math.max(.045,Math.min(.955,x)),Math.max(.045,Math.min(.935,y))];
    const shard=(x,y,s,c=trim)=>poly([P(x,y-s),P(x+s,y),P(x,y+s),P(x-s,y)],c);
    const slash=(x,y,dx,dy,w,c=light(trim))=>poly([P(x-dy*w,y+dx*w),P(x+dx,y+dy),P(x+dy*w,y-dx*w),P(x-dx,y-dy)],c);
    // Distinct signature marks stay inside the sprite tile and evolve through all 64 frames.
    switch(id){
      case 'rook': for(let n=0;n<3;n++)slash(cx-.18+n*.11,cy+.12, .10+beat*.08,-.08,.009,n===1?light(trim):trim); break;
      case 'mira': for(let n=0;n<5;n++){const a=phase*6+n*1.25;slash(cx+Math.cos(a)*.17,cy+Math.sin(a)*.15,.07,-.025,.008,n%2?trim:light(trim));} break;
      case 'brakk': for(let n=0;n<4;n++){const x=cx-.20+n*.13;poly([P(x-.045,.88),P(x+.005,.78-beat*.08),P(x+.045,.88),P(x+.02,.91)],n%2?trim:light(trim));} break;
      case 'juno': for(let n=0;n<3;n++){const a=phase*6.28+n*2.1;shard(cx+Math.cos(a)*.23,cy+Math.sin(a)*.19,.025, n%2?trim:light(trim));} break;
      case 'sable': for(let n=0;n<7;n++)slash(cx-.24+n*.075,cy-.12+(n%2)*.1,.07,-.11,.008,n%2?trim:light(trim)); break;
      case 'dax': for(let n=0;n<3;n++){const x=cx+.18*phase-n*.10;poly([P(x-.06,cy-.03),P(x+.06,cy-.01),P(x+.09,cy+.04),P(x-.04,cy+.03)],n===1?light(trim):trim);} break;
      case 'wren': for(let n=0;n<7;n++){const x=cx-.22+n*.07,y=cy-.2+Math.abs(3-n)*.018;poly([P(x,y),P(x+.045,y-.06),P(x+.018,y+.025)],n%2?trim:light(trim));} break;
      case 'sorren': for(let n=0;n<8;n++){const a=n*Math.PI/4+phase;shard(cx+Math.cos(a)*.20,cy+Math.sin(a)*.17,.018,n%2?trim:light(trim));} break;
      case 'pike': slash(cx+.14,cy+.05,.30,.025,.012,light(trim));shard(cx+.37,cy+.075,.024,trim);break;
      case 'zip': for(let n=0;n<4;n++){const x=cx-.25+n*.14;poly([P(x,cy+.18),P(x+.08,cy+.08),P(x+.04,cy),P(x+.13,cy-.12)],n%2?trim:light(trim));}break;
      case 'ashka': poly([P(cx-.24,cy),P(cx-.12,cy-.17),P(cx-.03,cy-.07),P(cx+.04,cy-.24),P(cx+.11,cy-.05),P(cx+.24,cy-.14),P(cx+.17,cy+.04),P(cx,cy+.12)],light(trim));break;
      case 'glacia': for(let n=0;n<5;n++){const x=cx-.24+n*.12,y=.83-(n%2)*.05;poly([P(x,y),P(x+.035,y-.12-beat*.04),P(x+.07,y),P(x+.035,y+.035)],n%2?light(trim):trim);}break;
      case 'tempest': for(let n=0;n<8;n++){const x=cx-.26+n*.07;poly([P(x,cy-.20),P(x+.035,cy-.13),P(x+.01,cy-.07),P(x+.06,cy+.02),P(x+.035,cy-.10),P(x+.055,cy-.16)],n%2?trim:light(trim));}break;
      case 'byte': for(let n=0;n<10;n++){const x=cx-.25+(n%5)*.12,y=cy-.22+Math.floor(n/5)*.42;const s=.015+(n%3)*.006;poly([P(x-s,y-s),P(x+s,y-s),P(x+s,y+s),P(x-s,y+s)],n%2?trim:light(trim));}break;
      case 'morrow': for(let n=0;n<6;n++){const a=-1.4+n*.55+phase*1.3;slash(cx+Math.cos(a)*.21,cy+Math.sin(a)*.18,.075,-.045,.012,n%2?trim:light(trim));}break;
      case 'astra': for(let n=0;n<5;n++)shard(cx,cy,.035+n*.022,n%2?trim:light(trim));for(let n=0;n<6;n++)shard(cx-.23+n*.09,cy+.23,.012,trim);break;
      default: shard(cx,cy,.05+beat*.05,light(trim));
    }
  }
  // Local coordinate brush follows each segment, so seams and muscles never float.
  function segment(a,b,w,c,kind='cloth') {
    const dx=b[0]-a[0],dy=b[1]-a[1],l=Math.hypot(dx,dy)||1;
    const pt=(u,v)=>[a[0]+dx*v+dy/l*w*u,a[1]+dy*v-dx/l*w*u];
    const shape=(pts,col)=>poly(pts.map(([u,v])=>pt(u,v)),col);
    shape([[-.34,-.09],[.25,-.12],[.53,.18],[.42,.55],[.25,1.07],[-.26,1.07],[-.51,.42]],deep(c));
    shape([[-.30,-.05],[.21,-.06],[.40,.22],[.28,.65],[.19,1],[-.24,1],[-.39,.34]],c);
    shape([[-.28,.04],[-.02,-.02],[.13,.22],[-.03,.56],[-.26,.77],[-.34,.30]],light(c));
    shape([[.18,.34],[.38,.27],[.29,.62],[.18,.94],[-.07,.90]],shadow(c));
    if(kind==='cloth') {
      shape([[-.27,.67],[.22,.53],[.07,.66],[-.13,.76]],deep(c));
      shape([[-.18,.92],[.20,.77],[.10,.89]],light(c));
    } else {
      shape([[.07,.36],[.30,.32],[.24,.43],[.06,.52]],shadow(c));
    }
    return { pt,shape };
  }
  const bodyA=joint('hip'),bodyB=joint('shoulder');
  const tx=j.shoulderX-j.hipX,ty=j.shoulderY-j.hipY,tl=Math.hypot(tx,ty);
  const B=(u,v)=>[j.hipX+tx*v-ty/tl*d.torsoW*u,j.hipY+ty*v+tx/tl*d.torsoW*u];
  const body=(pts,c)=>poly(pts.map(([u,v])=>B(u,v)),c);
  // Distinct silhouettes: split coat tails, wing mantle, tabard and ninja scarf.
  if(['ice','reaper','stars','knight','feathers'].includes(design.motif)) {
    body([[-.4,1],[-.72,.82],[-.82,-.65],[-.30,-.38],[-.06,-.68],[.3,-.52],[.25,.8]],deep(cloth));
    body([[-.45,.88],[-.60,.1],[-.63,-.44],[-.37,-.3],[-.2,.65]],shadow(cloth));
    for(let n=0;n<3;n++) body([[-.65+n*.24,-.38],[-.5+n*.24,-.56],[-.42+n*.24,-.35]],trim);
  }
  if(['ninja','wraps','samurai'].includes(design.motif)) {
    body([[-.2,1.12],[-.65,1.05],[-.85,1.15],[-.75,.96],[-.58,.90],[-.1,1.0]],trim);
  }
  function arm(side,back,part='all') {
    const bare=['Bare','Top','Tank'].includes(design.top)||['monk','samurai'].includes(design.motif);
    const upper=bare?skin:cloth, lower=bare?skin:cloth;
    const S=joint('shoulder'+side),E=joint('elbow'+side),H=joint('hand'+side);
    const tint=c=>back?shadow(c):c;
    if(part!=='fore')segment(S,E,d.armW,tint(upper),bare?'skin':'cloth');
    if(part==='upper')return;
    const f=segment(E,H,d.foreW,tint(lower),bare?'skin':'cloth');
    const gauntlet=['knight','ice','tech'].includes(design.motif);
    const wrapped=['wraps','ninja','monk','stripes'].includes(design.motif);
    if(gauntlet||wrapped) {
      f.shape([[-.44,.48],[.44,.43],[.40,1.02],[-.4,1.02]],tint(gauntlet?trim:hex('#DAD4BE')));
      for(let i=0;i<3;i++) f.shape([[-.38,.57+i*.13],[.38,.52+i*.13],[.38,.56+i*.13],[-.38,.61+i*.13]],shadow(gauntlet?cloth:skin));
    }
    const glove=design.motif==='boxing'?hex('#E7403A'):wrapped?hex('#E9DFCF'):gauntlet?trim:skin;
    const hw=d.hand*(design.motif==='boxing'?1.6:1.1);
    const p=(x,y)=>[H[0]+x*hw,H[1]+y*hw];
    poly([p(-.5,-.25),p(-.3,-.53),p(.34,-.50),p(.53,-.19),p(.43,.36),p(-.18,.47),p(-.54,.14)],deep(glove));
    poly([p(-.36,-.22),p(-.22,-.39),p(.30,-.37),p(.4,-.12),p(.28,.24),p(-.3,.28)],tint(glove));
    line(p(-.28,-.23),p(.26,-.25),.007,light(glove));
    for(let i=0;i<3;i++) line(p(-.2+i*.18,-.18),p(-.2+i*.18,.06),.004,shadow(glove));
    line(p(-.43,.09),p(.04,.20),.012,light(glove));
  }
  function leg(side,back) {
    const H=joint('hip'+side),K=joint('knee'+side),A=joint('ankle'+side);
    const c=back?shadow(pants):pants;
    const thigh=segment(H,K,d.legW,c);
    const short=['boxing','stripes'].includes(design.motif);
    segment(K,A,d.shinW,short?(back?shadow(skin):skin):c,short?'skin':'cloth');
    if(['stripes','racer','pilot','tech'].includes(design.motif)) thigh.shape([[.21,.08],[.37,.15],[.29,.83],[.14,.95]],trim);
    if(['knight','ice','samurai','stone'].includes(design.motif)) {
      const a=mix(K,A,.15),b=mix(K,A,.8); const s=segment(a,b,d.shinW*1.04,design.motif==='samurai'?shadow(trim):trim);
      for(let i=0;i<3;i++) s.shape([[-.35,.15+i*.23],[.30,.15+i*.23],[.28,.21+i*.23],[-.35,.21+i*.23]],deep(cloth));
    }
    const boot=short?deep(pants):hex('#343039');
    const foot=[[A[0]-.025,A[1]-.034],[A[0]+.022,A[1]-.027],[A[0]+.066,A[1]+.004],[A[0]+.078,A[1]+.021],[A[0]-.027,A[1]+.021]];
    poly(foot,deep(boot));
    poly([[A[0]-.018,A[1]-.026],[A[0]+.016,A[1]-.02],[A[0]+.054,A[1]+.004],[A[0]-.018,A[1]+.008]],boot);
    line([A[0]-.02,A[1]+.012],[A[0]+.067,A[1]+.012],.008,trim);
    for(let i=0;i<3;i++) line([A[0]-.013,A[1]-.019+i*.008],[A[0]+.019+i*.006,A[1]-.021+i*.008],.004,light(boot));
  }
  arm('B',true,'upper'); leg('B',true);
  const bare=design.top==='Bare'; const torso=bare?skin:cloth;
  body([[-.33,-.12],[.34,-.12],[.4,.4],[.61,.94],[.34,1.14],[-.25,1.13],[-.60,.91],[-.43,.43]],deep(torso));
  body([[-.27,-.03],[.27,-.03],[.32,.42],[.47,.95],[.25,1.07],[-.2,1.06],[-.47,.87],[-.35,.43]],torso);
  body([[-.43,.84],[-.2,1.02],[.01,.94],[-.05,.65],[-.37,.62]],light(torso));
  body([[.03,.95],[.35,1.0],[.44,.83],[.30,.64],[.04,.65]],light(torso));
  if(bare) {
    body([[-.37,.58],[-.03,.55],[0,.63],[.33,.57],[.29,.51],[-.27,.52]],shadow(skin));
    for(let i=0;i<3;i++) for(const s of [-1,1]) body([[s*.035,.43-i*.14],[s*.22,.46-i*.14],[s*.24,.35-i*.14],[s*.03,.32-i*.14]],i===2?shadow(skin):light(skin));
    body([[-.29,.36],[-.27,.03],[-.16,-.02],[-.20,.31]],shadow(skin));
  } else if(['Gi','Robe','Cloak'].includes(design.top)) {
    body([[-.27,1.08],[.18,.43],[.35,.43],[-.08,1.10]],trim);
    body([[.25,1.08],[-.32,.18],[-.18,.14],[.39,1.01]],shadow(trim));
  } else if(design.top==='Armor') {
    const plate=design.motif==='stone'?cloth:trim;
    body([[-.42,.92],[-.17,1.06],[.0,.89],[.29,1.04],[.43,.89],[.31,.56],[-.31,.56]],plate);
    body([[-.34,.83],[-.09,.93],[-.04,.65],[-.28,.66]],light(plate));
    for(let i=0;i<3;i++) body([[-.3,.47-i*.14],[.3,.47-i*.14],[.28,.38-i*.14],[-.28,.38-i*.14]],shadow(plate));
    if(design.motif==='stone') {
      body([[-.40,.92],[.40,.92],[.38,.85],[-.38,.85]],trim);
      body([[-.035,.86],[.035,.86],[.035,.12],[-.035,.12]],deep(plate));
      for(let i=0;i<2;i++)body([[-.30,.45-i*.22],[.30,.45-i*.22],[.29,.42-i*.22],[-.29,.42-i*.22]],trim);
    }
  } else {
    body([[-.23,1.08],[.1,.73],[.22,1.07]],skin);
    body([[-.32,1.04],[-.05,.65],[-.14,.40],[-.40,.92]],trim);
    body([[.30,1.03],[.02,.65],[.16,.46],[.42,.92]],shadow(trim));
    for(const s of [-1,1]) body([[s*.17,.46],[s*.34,.46],[s*.32,.27],[s*.17,.25]],shadow(cloth));
  }
  // Costume-specific marks are large readable clusters, not random pixel noise.
  if(design.motif==='ninja') body([[-.42,.13],[.28,1.1],[.47,1.02],[-.24,.06]],trim);
  if(design.motif==='monk') for(let i=0;i<7;i++) {const a=i/6*Math.PI; const p=B(Math.cos(a)*.34,.81-Math.sin(a)*.28);poly([[p[0]-.011,p[1]-.009],[p[0]+.01,p[1]-.009],[p[0]+.011,p[1]+.009],[p[0]-.01,p[1]+.011]],trim);}
  if(design.motif==='pilot'||design.motif==='racer') body([[.15,.70],[.34,.70],[.34,.60],[.15,.60]],trim);
  if(design.motif==='tech') {body([[-.30,.60],[-.20,.6],[-.20,.19],[-.30,.19]],trim);body([[.12,.75],[.30,.75],[.30,.68],[.12,.68]],trim);}
  // Signature costume pixels: each fighter carries a different readable chest emblem.
  const mark=(x,y,w,c)=>body([[x-w,y],[x,y+w],[x+w,y],[x,y-w]],c);
  switch(design.motif){
    case 'wraps': body([[-.30,.47],[.05,.39],[.32,.47],[.08,.50]],shadow(cloth));mark(.03,.60,.07,trim);break;
    case 'stripes': for(let i=0;i<3;i++)body([[-.30+i*.14,.78],[-.16+i*.14,.60],[-.10+i*.14,.61],[-.24+i*.14,.80]],trim);break;
    case 'stone': for(let i=0;i<3;i++)mark(-.2+i*.18,.58,.025,light(trim));break;
    case 'pilot': mark(.06,.60,.14,trim);mark(.06,.60,.07,hex('#FFF2D3'));break;
    case 'ninja': for(let i=0;i<3;i++)mark(-.14+i*.15,.76-i*.15,.045,light(trim));break;
    case 'boxing': body([[-.27,.61],[.23,.61],[.19,.48],[-.25,.48]],hex('#FAE7C3'));mark(.03,.53,.06,trim);break;
    case 'feathers': for(let i=0;i<3;i++)body([[0,.78-i*.18],[.22,.65-i*.18],[0,.70-i*.18],[-.22,.65-i*.18]],trim);break;
    case 'monk': mark(0,.56,.17,trim);mark(0,.56,.08,cloth);break;
    case 'knight': for(let i=0;i<3;i++)mark(-.23+i*.23,.58,.025,light(trim));break;
    case 'racer': body([[-.22,.8],[.10,.62],[-.04,.61],[.29,.41],[.16,.64],[.27,.67]],trim);break;
    case 'flame': body([[0,.83],[.19,.56],[.04,.59],[.11,.39],[-.15,.62]],trim);mark(.02,.56,.055,hex('#FFF3C0'));break;
    case 'ice': for(let i=-1;i<=1;i++)mark(i*.21,.54,.07,light(trim));break;
    case 'samurai': body([[-.28,.77],[.24,.69],[.28,.60],[-.27,.66]],trim);for(let i=0;i<3;i++)mark(-.16+i*.14,.70,.025,deep(cloth));break;
    case 'tech': for(let i=0;i<3;i++)body([[-.20+i*.19,.78],[-.12+i*.19,.78],[-.12+i*.19,.68],[-.20+i*.19,.68]],light(trim));break;
    case 'reaper': mark(0,.66,.13,light(trim));body([[-.05,.60],[.06,.60],[.04,.40],[-.04,.40]],deep(cloth));break;
    case 'stars': for(let i=0;i<3;i++)mark(-.22+i*.20,.75-(i%2)*.23,.055,light(trim));break;
  }
  // The rear forearm crosses the chest; drawing it here keeps both fists readable.
  arm('B',true,'fore');
  leg('F',false);
  body([[-.34,.08],[.33,.08],[.33,-.04],[-.34,-.04]],deep(trim));
  body([[-.33,.08],[.30,.08],[.29,.015],[-.33,.015]],trim);
  body([[-.08,.08],[.09,.08],[.09,-.05],[-.08,-.05]],light(trim));
  if(['wraps','ninja','flame','samurai','monk'].includes(design.motif)) body([[-.08,-.02],[.10,-.03],[.23,-.40],[.08,-.46]],trim);
  segment(joint('shoulder'),joint('neck'),.052,skin,'skin');
  const hx=j.headX,hy=j.headY,h=d.head;
  // The face is authored in head-local coordinates. Rotate those coordinates with
  // the neck/body so a knocked-down fighter's head lies on the floor instead of
  // remaining unnaturally upright.
  const headRadians=(j.headAngle+j.rot)*Math.PI/180;
  const headCos=Math.cos(headRadians),headSin=Math.sin(headRadians);
  const H=(x,y)=>[
    hx+(x*headCos-y*headSin)*h,
    hy+(x*headSin+y*headCos)*h,
  ];
  const head=(pts,c)=>poly(pts.map(([x,y])=>H(x,y)),c);
  if(['reaper','stars','ice'].includes(design.motif)) head([[-.62,.58],[-.61,-.38],[-.24,-.75],[.40,-.60],[.56,.60]],deep(cloth));
  head([[-.4,-.39],[.12,-.5],[.38,-.24],[.40,.03],[.57,.18],[.36,.23],[.27,.52],[-.04,.56],[-.39,.28]],shadow(skin));
  head([[-.30,-.28],[.10,-.39],[.28,-.20],[.3,.06],[.46,.17],[.24,.18],[.2,.42],[-.03,.44],[-.28,.18]],skin);
  head([[-.17,-.19],[.14,-.25],[.25,-.07],[.13,.01],[-.1,.02]],light(skin));
  head([[-.38,-.03],[-.26,-.09],[-.21,.13],[-.31,.22],[-.39,.14]],skin);
  if(!['monk','stone','reaper'].includes(design.motif)) {
    head([[-.49,.02],[-.48,-.4],[-.20,-.68],[.03,-.81],[.05,-.62],[.39,-.72],[.26,-.47],[.50,-.40],[.25,-.24],[-.14,-.31],[-.26,.10]],hair);
    head([[-.36,-.38],[-.1,-.57],[.02,-.64],[-.04,-.43],[.25,-.50],[.12,-.32]],light(hair));
  }
  if(['stripes','flame','stars'].includes(design.motif)) head([[-.4,-.30],[-.72,-.1],[-.82,.56],[-.61,.90],[-.55,.28],[-.34,.12]],hair);
  if(design.motif==='samurai') head([[-.32,-.6],[-.42,-.97],[-.08,-1.05],[.08,-.84],[-.05,-.58]],hair);
  if(design.motif==='knight') {
    head([[-.5,.18],[-.53,-.41],[-.22,-.64],[.28,-.55],[.44,-.19],[.14,-.22],[-.2,-.13],[-.19,.26]],trim);
    head([[-.14,-.6],[-.22,-1.1],[.20,-1.04],[.39,-.77],[.19,-.61]],cloth);
  }
  line(H(-.02,.01),H(.30,-.02),.008,ink);
  line(H(-.26,.04),H(-.13,.025),.008,hex('#FFF5E4'));
  line(H(-.17,.035),H(-.15,.08),.006,ink);
  line(H(.03,.05),H(.29,.035),.008,hex('#F3E7D0'));
  line(H(.22,.03),H(.22,.10),.006,ink);
  line(H(.10,.31),H(.30,.29),.006,deep(skin));
  if(['wraps','feathers','ninja'].includes(design.motif)) head([[-.44,-.2],[.33,-.26],[.35,-.13],[-.43,-.07]],trim);
  if(design.motif==='ninja'||design.motif==='reaper') {head([[-.2,.14],[.38,.13],[.3,.47],[.05,.58],[-.24,.38]],design.motif==='reaper'?hex('#DBD6BD'):pants);line(H(-.06,.23),H(.27,.26),.007,shadow(trim));}
  if(['pilot','racer','tech'].includes(design.motif)) {head([[-.12,-.08],[.39,-.10],[.38,.10],[-.13,.12]],ink);head([[-.05,-.04],[.32,-.06],[.28,.03],[-.06,.05]],trim);}
  if(['ice','stars'].includes(design.motif)) head([[-.43,-.35],[-.44,-.73],[-.18,-.48],[.02,-.86],[.14,-.49],[.40,-.7],[.31,-.35]],trim);
  if(design.motif==='stone') head([[-.3,.21],[-.07,.36],[.29,.27],[.20,.68],[-.17,.67],[-.36,.39]],hair);
  arm('F',false);
  // Weapons have an actual blade/profile instead of circles on a stick.
  if(look.weapon) {
    const a=joint('handF'),e=joint('elbowF'),len=Math.hypot(a[0]-e[0],a[1]-e[1]);
    let dx=(a[0]-e[0])/len,dy=(a[1]-e[1])/len;
    // Keep long weapons in the grip while rotating them away from atlas borders.
    // Never crop a blade, resize it, or shrink the fighter during a move.
    const preferred=Math.atan2(dy,dx),kind=look.weapon.kind;
    if(['Spear','Staff','Scythe','Katana'].includes(kind)) {
      let best=Infinity;
      const reach=kind==='Spear'?.37:kind==='Staff'?.34:.31;
      const width=kind==='Scythe'?.15:.04;
      for(let step=0;step<360;step++) {
        const angle=step*Math.PI/180,cx=Math.cos(angle),cy=Math.sin(angle);
        const corners=[[-width,-.1],[width,-.1],[-width,reach],[width,reach]];
        if(corners.every(([u,v])=>{const x=a[0]+cx*v-cy*u,y=a[1]+cy*v+cx*u;return x>.02&&x<.98&&y>.02&&y<.98;})){
          const difference=Math.abs(Math.atan2(Math.sin(angle-preferred),Math.cos(angle-preferred)));
          if(difference<best){best=difference;dx=cx;dy=cy;}
        }
      }
    }
    const W=(u,v)=>[a[0]+dx*v-dy*u,a[1]+dy*v+dx*u];
    const wp=(pts,c)=>poly(pts.map(([u,v])=>W(u,v)),c);
    if(['Spear','Staff','Scythe','Katana'].includes(kind)) {
      const reach=kind==='Katana'?.23:.28;
      line(W(0,-.1),W(0,reach),.015,deep(trim)); line(W(-.003,-.09),W(-.003,reach),.005,trim);
      if(kind==='Staff') wp([[0,.34],[-.033,.29],[0,.245],[.033,.29]],light(trim));
      if(kind==='Spear') wp([[0,.37],[-.025,.28],[0,.295],[.025,.28]],light(trim));
      if(kind==='Katana') {wp([[-.006,.04],[-.012,.23],[.014,.31],[.019,.23],[.01,.04]],hex('#E2E4D6'));line(W(-.038,.04),W(.038,.04),.012,trim);}
      if(kind==='Scythe') wp([[0,.27],[-.045,.31],[-.115,.27],[-.15,.18],[-.09,.24],[0,.245]],light(trim));
    } else if(kind==='Disc') {
      wp([[-.045,0],[-.02,-.03],[.04,-.02],[.06,.02],[.025,.05],[-.025,.04]],trim);
      wp([[-.022,.01],[0,-.01],[.03,.01],[.008,.03]],ink);
    } else if(kind==='Fans') {
      wp([[0,0],[-.09,.055],[-.075,.095],[0,.13],[.075,.095],[.09,.055]],trim);
      for(let n=-2;n<=2;n++)line(W(0,0),W(n*.034,.11-Math.abs(n)*.012),.006,cloth);
      const bh=joint('handB'),B=(x,y)=>[bh[0]+x,bh[1]+y];
      poly([[0,0],[-.08,.05],[-.065,.085],[0,.12],[.065,.085],[.08,.05]].map(p=>B(p[0],p[1])),deep(trim));
      for(let n=-2;n<=2;n++)line(B(0,0),B(n*.03,.10-Math.abs(n)*.011),.005,cloth);
    }
    else if(kind==='DualKnives') {
      for(const side of ['F','B']) {
        const h=joint('hand'+side),e=joint('elbow'+side),l=Math.hypot(h[0]-e[0],h[1]-e[1])||1;
        const dx=(h[0]-e[0])/l,dy=(h[1]-e[1])/l,nx=-dy,ny=dx;
        const end=[h[0]+dx*.16,h[1]+dy*.16],base=[h[0]+dx*.035,h[1]+dy*.035],w=.014;
        poly([[base[0]+nx*w,base[1]+ny*w],end,[base[0]-nx*w,base[1]-ny*w]],light(trim));
        line([h[0]-dx*.018,h[1]-dy*.018],base,.012,deep(trim));
      }
    }
  }
  if(pose.superPhase!==undefined) {
    const phase=pose.superPhase;
    const hand=['brakk','morrow'].includes(id)?joint('handB'):joint('handF');
    const hx=Math.max(.10,Math.min(.87,hand[0])),hy=Math.max(.12,Math.min(.84,hand[1]));
    const shard=(x,y,s,c)=>poly([[x,y-s],[x+s,y],[x,y+s],[x-s,y]],c);
    if(id==='juno')for(let n=0;n<3;n++){const a=phase*6.28+n*2.1;shard(hx+Math.cos(a)*.08,hy+Math.sin(a)*.07,.022,light(trim));}
    else if(id==='ashka'){shard(hx,hy-.04,.035,light(trim));shard(hx-.04,hy+.02,.018,trim);}
    else if(id==='glacia'){for(let n=0;n<3;n++)shard(hx-.04+n*.04,hy-.035,.012,light(trim));}
    else if(id==='tempest'){
      const x=hx+.11*Math.sin(phase*12),y=hy-.08;
      poly([[x,y-.07],[x+.025,y-.018],[x+.01,y+.035],[x+.045,y+.075],[x-.005,y+.025],[x+.006,y-.02]],light(trim));
    }else if(id==='byte'){
      const step=Math.floor(phase*12)%3,box=.018+step*.005;shard(hx,hy,box,trim);
    }else if(id==='astra'){
      shard(hx,hy,.04,light(trim));shard(hx,hy,.017,hex('#FFF7DB'));
    }else if(id==='morrow'){
      const a=phase*3.14;shard(hx+Math.cos(a)*.08,hy+Math.sin(a)*.05,.022,light(trim));
    }else if(id==='brakk'){
      poly([[hx-.10,hy+.06],[hx,hy-.01],[hx+.10,hy+.06],[hx+.02,hy+.04]],light(trim));
    }else if(id==='sable'){
      poly([[hx-.08,hy-.04],[hx+.08,hy-.08],[hx+.04,hy-.035],[hx-.06,hy+.01]],light(trim));
    }else{
      shard(hx+.04*Math.sin(phase*6.28),hy-.035,.018,light(trim));
    }
  }
  // Translate only extreme airborne/fallen poses into the frame. Idle is already
  // inside these margins, so its root and feet remain bit-identical across all frames.
  let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
  for(const s of shapes)for(const [x,y] of s.points){minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);}
  const fit=Math.min(1,.96/(maxX-minX),.96/(maxY-minY));
  const loX=.5+(minX-.5)*fit,hiX=.5+(maxX-.5)*fit;
  const loY=.5+(minY-.5)*fit,hiY=.5+(maxY-.5)*fit;
  const shiftX=loX<.018?.018-loX:hiX>.982?.982-hiX:0;
  const shiftY=loY<.018?.018-loY:hiY>.982?.982-hiY:0;
  for(const s of shapes)canvas.fillPolygon(s.points.map(([x,y])=>[(.5+(x-.5)*fit+shiftX)*size,(.5+(y-.5)*fit+shiftY)*size]),s.c,1);
}
module.exports={drawArcade,DESIGNS};
