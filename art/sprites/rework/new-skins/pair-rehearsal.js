/* Runtime composition of existing textures: contact points, foreground hands
   and free world-space effects. No raster artwork is replaced by this scene. */
(() => {
  const $ = id => document.getElementById(id), canvas = $('arena'), ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height, floor = 540, images = {};
  const files = ['brakk_6','brakk_7','brakk_8','brakk_1','brakk_2','brakk_5','rook_1','rook_3','rook_5','rook_6','rook_7','rook_8'];
  const ready = Promise.all(files.map(name => new Promise((resolve, reject) => { const img = new Image(); images[name] = img; img.onload = resolve; img.onerror = () => reject(new Error(name)); img.src = 'packed/' + name + '.png'; })));
  const smooth = u => { u = Math.max(0, Math.min(1, u)); return u*u*(3-2*u); };
  const lerp = (a,b,u) => a+(b-a)*u;
  const progress = (t,a,b) => Math.max(0,Math.min(1,(t-a)/(b-a)));
  const point = (x,y) => ({x,y});
  const mix = (a,b,u) => point(lerp(a.x,b.x,u),lerp(a.y,b.y,u));
  const add = (a,b) => point(a.x+b.x,a.y+b.y);
  const sub = (a,b) => point(a.x-b.x,a.y-b.y);
  const frameNumber = (t,a,b,n=4) => Math.min(n-1,Math.floor(progress(t,a,b)*n));
  let elapsed=0, paused=false, last=performance.now(), loaded=false,hitFreeze=0,lastHit='';
  const durations={brakk:2.4,rook:1.8},sceneDuration=()=>durations[$('scene').value];
  const flashCanvas=document.createElement('canvas');flashCanvas.width=flashCanvas.height=256;
  const flashCtx=flashCanvas.getContext('2d');
  // Coordinates are measured in the actual 256px atlas cells, not a guessed
  // distance between fighter centers. Each lifting pose has two hand sockets.
  const hands = {
    0:[[113,147],[184,131]],1:[[105,151],[164,158]],2:[[111,122],[152,163]],
    3:[[189,130],[46,145]],4:[[139,145],[159,155]],5:[[165,151],[183,140]],
    6:[[149,157],[167,161]],7:[[185,126],[204,121]],8:[[153,169],[177,169]],
    9:[[147,213],[170,208]],10:[[103,78],[154,52]],11:[[108,70],[154,70]],
    12:[[100,69],[142,99]],13:[[130,211],[154,214]],14:[[107,217],[167,145]],15:[[113,147],[184,131]],
  };
  function pose(file, frame, feetX, feetY, scale=1, mirror=false) {
    return {file,frame,scale,mirror,angle:0,x:feetX-128*scale,y:feetY-246*scale};
  }
  function localPoint(p, x,y) {
    if(p.mirror)x=256-x;
    const dx=(x-128)*p.scale,dy=(y-128)*p.scale,c=Math.cos(p.angle),s=Math.sin(p.angle);
    return point(p.x+128*p.scale+dx*c-dy*s,p.y+128*p.scale+dx*s+dy*c);
  }
  function setSocket(p, socket, target) { const origin=localPoint(p,...socket); p.x+=target.x-origin.x;p.y+=target.y-origin.y; }
  function twoPointGrip(p, sockets, targets) {
    const body=sub(point(...sockets[1]),point(...sockets[0])),handsVector=sub(targets[1],targets[0]);
    if(p.mirror)body.x=-body.x;
    p.angle=Math.atan2(handsVector.y,handsVector.x)-Math.atan2(body.y,body.x);
    p.scale=Math.hypot(handsVector.x,handsVector.y)/Math.hypot(body.x,body.y);
    setSocket(p,sockets[0],targets[0]);
  }
  function stableGrip(p,center,direction,targets,scale=1.05) {
    // Hands may slide along the shin or torso, but the fighter never changes size.
    const span=Math.hypot(targets[1].x-targets[0].x,targets[1].y-targets[0].y)/scale;
    const length=Math.hypot(...direction),dx=direction[0]/length*span/2,dy=direction[1]/length*span/2;
    twoPointGrip(p,[[center[0]-dx,center[1]-dy],[center[0]+dx,center[1]+dy]],p.mirror?[targets[1],targets[0]]:targets);
  }
  function drawPose(p, excludeHook=false) {
    ctx.save();ctx.translate(p.x+128*p.scale,p.y+128*p.scale);ctx.rotate(p.angle);ctx.scale(p.mirror?-p.scale:p.scale,p.scale);ctx.translate(-128,-128);
    if(excludeHook){
      ctx.beginPath();ctx.rect(0,0,256,256);
      const cut=p.frame===3?[[214,90],[256,90],[256,185],[214,185]]:p.frame===4?[[169,157],[181,140],[256,140],[256,193],[170,193]]:[[171,160],[184,147],[256,147],[256,222],[171,222]];
      cut.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.clip('evenodd');
    }
    // Body masks follow the silhouette; baked debris and speed streaks are
    // excluded from rendering and recreated as independent world effects.
    if(p.rigArms&&(p.frame!==10||p.armAngles.some(r=>Math.abs(r)>.001))){
      ctx.beginPath();[[116,91],[147,91],[150,134],[169,155],[181,185],[224,218],[224,250],[49,250],[49,202],[82,170],[108,144]].forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.clip();
    }
    ctx.drawImage(images[p.file],p.frame%4*256,Math.floor(p.frame/4)*256,256,256,0,0,256,256);
    if(p.flash){
      flashCtx.clearRect(0,0,256,256);flashCtx.globalCompositeOperation='source-over';
      flashCtx.drawImage(images[p.file],p.frame%4*256,Math.floor(p.frame/4)*256,256,256,0,0,256,256);
      flashCtx.globalCompositeOperation='source-atop';flashCtx.fillStyle='#fff4c4';flashCtx.fillRect(0,0,256,256);
      ctx.globalAlpha=p.flash;ctx.drawImage(flashCanvas,0,0);ctx.globalAlpha=1;
    }
    ctx.restore();
  }
  function drawHand(p, socket, radius=17) {
    const [x,y]=socket, left=Math.max(0,x-radius),top=Math.max(0,y-radius),size=radius*2;
    ctx.save();ctx.translate(p.x+128*p.scale,p.y+128*p.scale);ctx.rotate(p.angle);ctx.scale(p.mirror?-p.scale:p.scale,p.scale);ctx.translate(-128,-128);
    ctx.drawImage(images[p.file],p.frame%4*256+left,Math.floor(p.frame/4)*256+top,size,size,left,top,size,size);ctx.restore();
  }
  const liftArms=[
    {shoulder:[112,133],outline:[[102,155],[76,134],[69,118],[74,104],[94,77],[97,65],[113,63],[123,77],[117,94],[110,112],[123,127],[122,145]]},
    {shoulder:[151,132],outline:[[137,144],[145,114],[146,91],[145,63],[147,47],[160,39],[173,47],[178,65],[177,101],[178,116],[163,137],[153,146]]},
  ];
  function liftHand(a,index) {
    const s=liftArms[index].shoulder,h=hands[10][index],r=a.armAngles[index],dx=h[0]-s[0],dy=h[1]-s[1];
    return localPoint(a,s[0]+dx*Math.cos(r)-dy*Math.sin(r),s[1]+dx*Math.sin(r)+dy*Math.cos(r));
  }
  function drawLiftArm(a,index,handOnly=false) {
    // One complete painted arm rotates as a unit. Elbow, cuff and hand keep
    // their original shape and proportions; no separate stretched fragments.
    const arm=liftArms[index],s=arm.shoulder,world=localPoint(a,...s);
    if(!handOnly&&a.frame===10&&Math.abs(a.armAngles[index])<.001)return;
    ctx.save();ctx.translate(world.x,world.y);ctx.rotate(a.angle+a.armAngles[index]);ctx.scale(a.scale,a.scale);ctx.translate(-s[0],-s[1]);
    ctx.beginPath();arm.outline.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.clip();
    if(handOnly){const h=hands[10][index];ctx.beginPath();ctx.rect(h[0]-14,h[1]-13,28,26);ctx.clip();}
    ctx.drawImage(images.brakk_6,512,512,256,256,0,0,256,256);ctx.restore();
  }
  function marker(p,color,label) {if(!$('anchors').checked)return;ctx.fillStyle=color;ctx.fillRect(p.x-4,p.y-4,8,8);ctx.font='13px system-ui';ctx.fillText(label,p.x+9,p.y-8);}
  function groundShadow(x,y,width,height,alpha=.25) {ctx.fillStyle=`rgba(0,0,0,${alpha})`;ctx.beginPath();ctx.ellipse(x,y,width,height,0,0,Math.PI*2);ctx.fill();}
  function chain(start,end,tension=1) {
    const length=Math.hypot(end.x-start.x,end.y-start.y),count=Math.max(2,Math.ceil(length/9));
    for(let i=0;i<=count;i++) {const u=i/count,x=Math.round(lerp(start.x,end.x,u)/2)*2,y=Math.round((lerp(start.y,end.y,u)+Math.sin(u*Math.PI)*16*(1-tension))/2)*2;
      ctx.fillStyle='#090d17';ctx.fillRect(x-5,y-4,10,8);ctx.fillStyle=i%2?'#8c8982':'#ddd2bb';ctx.fillRect(x-3,y-2,6,4);ctx.fillStyle='#182438';ctx.fillRect(x-1,y-1,2,2);}
  }
  function hook(position, angle=0,backOnRight=false) {
    // The open jaw surrounds the far silhouette; its mouth is the attachment.
    // Independent geometry keeps the whole metal curve visible outside the body.
    ctx.save();ctx.translate(position.x,position.y);ctx.rotate(angle);ctx.scale(backOnRight?1:-1,1);
    const edge=[[0,-5],[4,-16],[15,-23],[28,-19],[35,-8],[35,8],[28,19],[14,22],[3,14],[0,7],[7,4],[12,12],[23,12],[28,5],[28,-6],[23,-13],[13,-15],[8,-10],[7,-3]];
    ctx.beginPath();edge.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.fillStyle='#777f88';ctx.fill();ctx.strokeStyle='#0b1220';ctx.lineWidth=3;ctx.stroke();
    ctx.strokeStyle='#d1d6d7';ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(7,-12);ctx.lineTo(15,-19);ctx.lineTo(26,-15);ctx.lineTo(31,-6);ctx.lineTo(31,6);ctx.lineTo(24,15);ctx.lineTo(14,17);ctx.stroke();
    ctx.restore();
  }
  function latch(position, t,backOnRight=false) {
    // A foreground tooth overlaps the cloth while the curved hook surrounds
    // its edge: the chain visibly catches fabric instead of floating behind it.
    ctx.save();ctx.translate(position.x,position.y);ctx.rotate(backOnRight?.25:-.25);ctx.scale(backOnRight?-1:1,1);
    // A pinched fold bridges the body silhouette and the hook's catching tooth.
    ctx.fillStyle='#17395c';ctx.beginPath();ctx.moveTo(-12,0);ctx.lineTo(3,-6);ctx.lineTo(5,6);ctx.closePath();ctx.fill();
    ctx.fillStyle='#3b80b3';ctx.fillRect(-9,-1,11,3);
    ctx.fillStyle='#080d16';ctx.fillRect(-6,-3,15,6);ctx.fillRect(4,-7,5,10);
    ctx.fillStyle='#d4cbb6';ctx.fillRect(-4,-1,10,2);ctx.fillRect(5,-5,2,6);
    ctx.restore();if(t<.305)sparks(position,'#dbc8aa',8,progress(t,.27,.305));
  }
  function sparks(p,color,count=12,life=0) {
    for(let i=0;i<count;i++){const a=i/count*Math.PI*2,r=12+life*(40+(i%3)*19),size=Math.max(2,6-life*5);ctx.fillStyle=i%2?color:'#fff2c2';ctx.fillRect(Math.round((p.x+Math.cos(a)*r)/2)*2,Math.round((p.y+Math.sin(a)*r*.65)/2)*2,size,size);}
  }
  function worldDust(center,u) {
    if(u<0||u>1)return;for(let i=0;i<24;i++){const dir=i%2?-1:1,age=u*(.8+(i%4)*.12),x=center.x+dir*age*(70+i*4),y=floor-Math.sin(age*Math.PI)*(12+(i%5)*8);ctx.globalAlpha=(1-u)*.8;ctx.fillStyle=i%3?'#b69161':'#dac49c';ctx.fillRect(Math.round(x/3)*3,Math.round(y/3)*3,5+(i%4)*3,4+(i%3)*3);}ctx.globalAlpha=1;
  }
  function background(t) {
    ctx.fillStyle='#152235';ctx.fillRect(0,0,W,H);ctx.fillStyle='#1e3047';ctx.fillRect(0,330,W,floor-330);ctx.fillStyle='#35465a';ctx.fillRect(0,floor,W,H-floor);ctx.fillStyle='#738391';ctx.fillRect(0,floor,W,3);
    ctx.fillStyle='#2b3c50';for(let x=0;x<W;x+=90)ctx.fillRect(x,floor+24,65,3);
    ctx.fillStyle='#8da3be';ctx.font='14px system-ui';ctx.fillText('Свободная сцена — эффекты движутся по всей арене',22,31);
  }
  function brakkScene(t) {
    const cuts=[0,.1,.19,.25,.31,.38,.45,.51,.57,.63,.69,.76,.81,.85,.9,.95];
    let fi=0;for(let i=0;i<cuts.length;i++)if(t>=cuts[i])fi=i;
    const move=smooth(progress(t,.4,.58)), air=Math.sin(progress(t,.76,.85)*Math.PI)*70;
    const a=pose('brakk_6',fi,310+move*90,floor-(t>=.76&&t<.85?air:0),1.45);
    if(t>=.63&&t<.8){a.frame=t<.76?10:11;a.rigArms=true;}
    // Use complete, clean landing poses rather than cutting debris off a body.
    if(t>=.8&&t<.85)a.frame=11;
    else if(t>=.85&&t<.9){a.file='brakk_2';a.frame=7;}
    else if(t>=.9&&t<.95){a.file='brakk_2';a.frame=5;}
    let state='Idle',rf=0,file='rook_1',mirror=$('faceAttacker').checked;
    if(t>=.27&&t<.51){state='Pulled';rf=frameNumber(t,.27,.51);file='rook_7';}
    else if(t>=.51&&t<.63){state='Grabbed';rf=5;file='rook_7';}
    else if(t>=.63&&t<.8){state='Lifted';rf=t<.665?8:9;file='rook_7';}
    else if(t>=.8&&t<.86){state='Thrown';rf=12+frameNumber(t,.8,.86);file='rook_7';}
    else if(t>=.86&&t<.96){state='Slammed';rf=4+frameNumber(t,.86,.96);file='rook_8';}
    else if(t>=.96){state='WakeUp';rf=4+frameNumber(t,.96,1);file='rook_5';}
    const v=pose(file,rf,785-340*smooth(progress(t,.32,.51)),floor,1.05,mirror);
    if(t>=.27&&t<.32){v.angle=-Math.sin(progress(t,.27,.32)*Math.PI)*.12;v.x-=Math.sin(progress(t,.27,.32)*Math.PI)*10;}
    let hs=hands[fi].map(h=>localPoint(a,...h));
    if(a.rigArms){const raise=smooth(progress(t,.63,.735));a.armAngles=[2*(1-raise),1.85*(1-raise)];hs=[liftHand(a,0),liftHand(a,1)];}
    let attachment=null;
    // A single attachment owns both victim motion and hook endpoint.
    // Held poses rotate with the line between the two gripping hands.
    if(state==='Grabbed'||state==='Lifted'){
      if(state==='Lifted'){
        const support=rf===8?[[125,173],[52,12]]:[[142,179],[68,12]];
        stableGrip(v,...support,hs);
      }else{
        // Both hands surround the same raised shin; the leg cannot drift
        // behind the attacker's torso or attach at an unrelated waist point.
        stableGrip(v,mirror?[152,189]:[82,181],mirror?[24,0]:[30,0],hs);
      }
      attachment=mix(hs[0],hs[1],.5);
    }
    if(state==='Thrown'){
      const u=progress(t,.8,.86),releaseAir=Math.sin(progress(.8,.76,.85)*Math.PI)*70,releaseActor=pose('brakk_6',11,400,floor-releaseAir,1.45),releaseHands=hands[10].map(h=>localPoint(releaseActor,...h));
      v.file='rook_7';v.frame=9;stableGrip(v,[142,179],[68,12],releaseHands);
      const start=localPoint(v,142,177),initialAngle=v.angle;v.angle=lerp(initialAngle,0,smooth(u));
      setSocket(v,[142,177],point(lerp(start.x,565,u),start.y-15*u+(515-start.y+15)*u*u));
    }
    if(state==='Slammed'){v.frame=t<.92?6:7;v.scale=1.1;v.y=floor-246*v.scale;}
    if(state==='Slammed'||state==='WakeUp'){v.x=565-128*v.scale;}
    groundShadow(310+move*90,floor+3,65,11);groundShadow(state==='Lifted'||state==='Thrown'?450:(v.x+128*v.scale),floor+3,50,8,.2);
    const backSocket=state==='Pulled'?[[64,143],[65,145],[75,145],[91,150]][rf]:[63,148];
    const tether=t>=.21&&t<.5?{origin:localPoint(a,...hands[fi][0]),back:localPoint(v,...backSocket)}:null;
    let hookTip=null;
    if(tether){
      // Pass beyond the far silhouette, then curl inward around the back.
      // The flight and chain are behind the fighter; the catching tooth is in front.
      const cast=progress(t,.21,.27),overshoot=point(tether.back.x+(mirror?42:-42),tether.back.y-18);
      hookTip=t<.27?(cast<.72?mix(tether.origin,overshoot,smooth(cast/.72)):mix(overshoot,tether.back,smooth((cast-.72)/.28))):tether.back;
    }
    drawPose(a,fi>=3&&fi<=5);
    if(a.rigArms)[0,1].forEach(i=>drawLiftArm(a,i));
    if(tether){chain(tether.origin,add(hookTip,point(mirror?25:-25,-3)),t<.27?.2:smooth(progress(t,.27,.32)));hook(hookTip,mirror?.25:-.25,mirror);}
    drawPose(v);
    if(attachment){
      if(a.rigArms)[0,1].forEach(i=>drawLiftArm(a,i,true));
      else {const middle=mix(hs[0],hs[1],.5);ctx.save();ctx.beginPath();ctx.rect(0,0,W,H);ctx.rect(middle.x-10,middle.y-27,20,54);ctx.clip('evenodd');for(const h of hands[fi])drawHand(a,h,16);ctx.restore();
        // Finger tips wrap the visible blue shin, leaving the leg's center
        // exposed between both palms rather than covering it with a hand patch.
        ctx.fillStyle='#dfccb0';ctx.fillRect(middle.x-12,middle.y-4,5,9);ctx.fillRect(middle.x+7,middle.y-4,5,9);
      }
      marker(attachment,'#67ffe2',state==='Grabbed'?'голень / две ладони':'тело / хват');hs.forEach((h,i)=>marker(h,'#ffc168','кисть '+(i+1)));
    }
    if(tether&&t>=.27){latch(hookTip,t,mirror);marker(tether.back,'#67ffe2','зацеп за спину');}
    if(t>=.85&&t<.95)worldDust(point(565,floor),progress(t,.85,.95));
    const labels={Idle:t<.21?'Замах':'Бросок крюка',Pulled:'Зацеп за спину и натяжение цепи',Grabbed:'Захват голени двумя ладонями',Lifted:'Подъём — руки поддерживают тело',Thrown:'Бросок и вращение тела',Slammed:'Контакт с землёй',WakeUp:'Восстановление'};
    $('phase').textContent=labels[state];$('legend').textContent=(mirror?'Rook стоит лицом к Brakk. ':'Rook стоит спиной к Brakk. ')+'Крюк проходит за телом, огибает спину и цепляется за одежду. При захвате голень видна между ладонями.';
  }
  function dragonHead(p,angle,scale=1.5){
    ctx.save();ctx.translate(p.x,p.y);ctx.rotate(angle);ctx.scale(scale,scale);ctx.translate(-32,-36);
    // Curved flame silhouette removes the straight cut where the original
    // dragon continued into the fighter's surrounding effect.
    const edge=[[10,15],[18,10],[24,3],[29,9],[34,16],[44,18],[51,23],[64,26],[65,40],[60,47],[50,50],[48,60],[36,70],[24,69],[15,58],[8,45],[0,34],[3,27]];
    ctx.beginPath();edge.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.clip();
    ctx.drawImage(images.rook_6,256+166,512+22,65,72,0,0,65,72);ctx.restore();
  }
  function dragon(p,t,origin) {
    const length=Math.min(430,Math.max(45,(t-.4)*2500)),segments=48;
    const center=u=>point(p.x-u*length-34,p.y+Math.sin(u*9-t*28)*42*Math.sin(u*Math.PI));
    // Continuous tapered flame ribbons, drawn in arena coordinates.
    for(const [width,color] of [[67,'#ad2718'],[54,'#ed501b'],[39,'#ffa62e'],[23,'#fff198']]){
      ctx.beginPath();for(let side=0;side<2;side++)for(let j=0;j<=segments;j++){
        const u=(side?segments-j:j)/segments,c=center(u),radius=width*Math.pow(1-u,.65)+(j%3===0?5:0),x=Math.round(c.x/4)*4,y=Math.round((c.y+(side?1:-1)*radius)/4)*4;
        side||j?ctx.lineTo(x,y):ctx.moveTo(x,y);
      }ctx.closePath();ctx.fillStyle=color;ctx.fill();
    }
    for(let i=1;i<14;i++){
      const u=i/15,c=center(u),r=(1-u)*54;ctx.fillStyle=i%2?'#ffcc54':'#f07521';
      ctx.beginPath();ctx.moveTo(c.x+12,c.y-r);ctx.lineTo(c.x-10,c.y-r-26*(1-u));ctx.lineTo(c.x-23,c.y-r+9);ctx.closePath();ctx.fill();
    }
    dragonHead(p,0,3.5);
    // Swept horns, a narrow eye and an open fanged jaw make the fire head
    // read as an attacking dragon rather than a rounded projectile.
    const face=(vertices,color)=>{ctx.fillStyle=color;ctx.beginPath();vertices.forEach(([x,y],i)=>{x=Math.round((p.x+x)/3)*3;y=Math.round((p.y+y)/3)*3;i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.closePath();ctx.fill();};
    face([[-55,-35],[-108,-101],[-81,-84],[-34,-38]],'#ed6721');
    face([[-45,-38],[-96,-95],[-69,-73],[-27,-36]],'#fff4ba');
    face([[-26,-32],[-60,-89],[-39,-72],[-7,-28]],'#ffbd4c');
    face([[-15,-25],[7,-19],[1,-12],[-10,-15]],'#712119');
    face([[-10,-22],[3,-18],[-3,-16]],'#fffbd1');
    face([[10,-1],[37,1],[23,15],[-5,7]],'#8a271b');
    face([[8,0],[17,2],[12,13]],'#fff9ca');face([[22,1],[30,2],[24,10]],'#fff9ca');
    for(let i=0;i<22;i++){const u=i/22,c=center(u);ctx.fillStyle=i%2?'#ffe79a':'#ff762a';const y=c.y+Math.sin(i*1.7+t*45)*(80-30*u);ctx.fillRect(Math.round(c.x/4)*4,Math.round(y/4)*4,4+i%3*2,4+i%3*2);}
  }
  function fireImpact(p,u) {
    if(u<0||u>1)return;
    ctx.save();ctx.globalAlpha=1-u;
    for(const [radius,color] of [[155,'#e95b22'],[113,'#ffba45'],[66,'#fff4bf']]){
      ctx.beginPath();for(let i=0;i<32;i++){const angle=i/32*Math.PI*2,r=(i%2?.45:1)*(20+radius*Math.sqrt(u)),x=Math.round((p.x+Math.cos(angle)*r)/4)*4,y=Math.round((p.y+Math.sin(angle)*r*.9)/4)*4;i?ctx.lineTo(x,y):ctx.moveTo(x,y);}ctx.closePath();ctx.fillStyle=color;ctx.fill();
    }
    ctx.strokeStyle='#ffcc63';ctx.lineWidth=8*(1-u)+2;ctx.beginPath();const radius=35+155*u;
    for(let i=0;i<=32;i++){const angle=i/32*Math.PI*2,x=Math.round((p.x+Math.cos(angle)*radius)/4)*4,y=Math.round((p.y+Math.sin(angle)*radius)/4)*4;i?ctx.lineTo(x,y):ctx.moveTo(x,y);}ctx.stroke();
    sparks(p,'#ffaf3c',28,u);ctx.restore();
  }
  function burningBody(v,u) {
    if(u<0||u>1)return;
    ctx.save();ctx.globalAlpha=(1-u)*.85;
    for(let i=0;i<13;i++){
      const p=localPoint(v,85+(i*29)%104,110+(i*31)%114),height=22+20*Math.sin(i*2+u*25),width=10+i%3*5;
      ctx.fillStyle=i%2?'#ff8528':'#ffd575';ctx.beginPath();ctx.moveTo(p.x-width,p.y+9);ctx.lineTo(p.x+width,p.y+9);ctx.lineTo(p.x+6,p.y-height);ctx.lineTo(p.x-3,p.y-height*.45);ctx.closePath();ctx.fill();
    }ctx.restore();
  }
  function rookScene(t) {
    let af=0,afile='rook_1',ax=285,ay=floor;
    if(t>=.13&&t<.36){afile='rook_3';af=0;ay-=Math.sin(progress(t,.13,.36)*Math.PI)*5;}
    else if(t>=.36&&t<.54){afile='rook_3';af=8+frameNumber(t,.36,.54);ax+=90*smooth(progress(t,.36,.54));ay-=Math.sin(progress(t,.36,.54)*Math.PI)*65;}
    else if(t>=.54&&t<.66){afile='rook_3';af=12+frameNumber(t,.54,.66);ax+=90;}
    else if(t>=.66){ax+=90;}
    const a=pose(afile,af,ax,ay,1.1),v=pose('brakk_1',0,795,floor,1.35,true);
    if(t>=.52&&t<.85){v.file='brakk_8';v.frame=frameNumber(t,.52,.85);v.y-=Math.sin(progress(t,.52,.85)*Math.PI)*145;v.x+=smooth(progress(t,.52,.85))*100;v.angle=Math.sin(progress(t,.52,.85)*Math.PI)*.28;}
    else if(t>=.85&&t<.94){v.file='brakk_8';v.frame=4+frameNumber(t,.85,.94);v.x+=100;}
    else if(t>=.94){v.file='brakk_5';v.frame=4+frameNumber(t,.94,1);v.x+=100;}
    const impact=progress(t,.52,.69),burn=progress(t,.52,.85);
    if(t>=.52&&t<.575)v.flash=1-progress(t,.52,.575);
    groundShadow(ax,floor+3,55,10);groundShadow(v.x+128*v.scale,floor+3,65,11);
    if(t>=.13&&t<.36){const charge=progress(t,.13,.36),center=point(ax,400);for(let i=0;i<14;i++){const angle=i/14*Math.PI*2+t*20,r=60*(1-charge)+15;ctx.fillStyle=i%2?'#ffb54b':'#a5e7ff';ctx.fillRect(center.x+Math.cos(angle)*r,center.y+Math.sin(angle)*r*.75,4,4);}}
    if(t>=.4){const origin=point(430,365),p=point(origin.x+(t-.4)*1900,origin.y+Math.sin((t-.4)*5)*12);dragon(p,t,origin);marker(p,'#67ffe2','эффект в арене');}
    if(t>=.52&&t<.69)fireImpact(localPoint(v,118,145),impact);
    drawPose(a);drawPose(v);
    if(t>=.52&&t<.85)burningBody(v,burn);
    if(t>=.52&&t<.69)sparks(localPoint(v,118,145),'#ffaf3c',18,impact);
    if(t>=.85&&t<.94)worldDust(point(895,floor),progress(t,.85,.94));
    $('phase').textContent=t<.13?'Стойка':t<.36?'Накопление энергии':t<.52?'Взрывной удар и выпуск дракона':t<.69?'Огненный удар — вспышка и отбрасывание':t<.94?'Падение Brakk и затухание огня':'Восстановление';
    $('legend').textContent='Большой огненный дракон летит через арену. В момент контакта: короткая остановка удара, вспышка на теле Brakk, огненный взрыв, отбрасывание и догорающие языки пламени.';
  }
  function render(t) {
    ctx.imageSmoothingEnabled=false;ctx.fillStyle='#152235';ctx.fillRect(0,0,W,H);ctx.save();
    if($('scene').value==='brakk'){
      // Follow the held fighter during the jump so raised hands stay in view.
      const cameraLift=t>=.76&&t<.85?Math.sin(progress(t,.76,.85)*Math.PI)*70*1.25:0;
      ctx.translate(560,330+cameraLift);ctx.scale(1.5,1.5);ctx.translate(-550,-365);
    }
    else if(t>=.52&&t<.61){const fade=1-progress(t,.52,.61);ctx.translate(Math.sin(t*430)*6*fade,Math.cos(t*330)*3*fade);}
    background(t);if($('scene').value==='brakk')brakkScene(t);else rookScene(t);ctx.restore();
    const duration=sceneDuration();$('timeline').value=t;$('time').textContent=(t*duration).toFixed(2)+' / '+duration.toFixed(2)+' с';
  }
  function tick(now){const dt=Math.min((now-last)/1000,.06);last=now;if(loaded){const duration=sceneDuration();if(!paused){
    if(hitFreeze>0)hitFreeze=Math.max(0,hitFreeze-dt);
    else {const before=(elapsed%duration)/duration;elapsed+=dt*Number($('speed').value);const after=(elapsed%duration)/duration,hit=$('scene').value==='brakk'?.86:.52,key=$('scene').value+':'+Math.floor(elapsed/duration);
      if(before<hit&&after>=hit&&lastHit!==key){elapsed=Math.floor(elapsed/duration)*duration+hit*duration;hitFreeze=.055;lastHit=key;}
    }
  }render((elapsed%duration)/duration);}requestAnimationFrame(tick);}
  $('pause').onclick=()=>{paused=!paused;$('pause').textContent=paused?'Продолжить':'Пауза';};
  $('restart').onclick=()=>{elapsed=0;hitFreeze=0;lastHit='';};$('step').onclick=()=>{paused=true;$('pause').textContent='Продолжить';elapsed+=sceneDuration()/96;};
  $('scene').onchange=()=>{elapsed=0;hitFreeze=0;lastHit='';$('faceAttacker').parentElement.hidden=$('scene').value!=='brakk';};$('timeline').oninput=()=>{paused=true;$('pause').textContent='Продолжить';elapsed=Number($('timeline').value)*sceneDuration();hitFreeze=0;};
  ready.then(()=>{loaded=true;requestAnimationFrame(tick);}).catch(e=>{$('phase').textContent='Не загрузился рисунок: '+e.message;});
})();
