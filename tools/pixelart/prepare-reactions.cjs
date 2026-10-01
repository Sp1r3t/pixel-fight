const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const roster=JSON.parse(fs.readFileSync(path.join(root,'roster.json')));
const states={
 'reactions-grab':[
 ['Pulled','Chest catches a tether impact, torso recoils toward attacker on LEFT, feet skid LEFT while body still faces LEFT, stop near attacker. Hands react rather than attack.'],
 ['Grabbed','Arms and torso tense as held around waist by an external attacker; four distinct struggling poses, head neck and shoulders anatomically aligned.'],
 ['Lifted','Waist grip lifts body, feet lose ground, body arches horizontally face up, settle into overhead held horizontal pose. Entire head rotates with shoulders.'],
 ['Thrown','Horizontal held pose transitions into forward tumbling, rotating head torso together, full body airborne fall ready for ground impact.']
 ],
 'reactions-control':[
 ['Launched','Incoming uppercut launches whole body, spine recoils, knees trail then tuck, airborne peak and falling pose.'],
 ['Slammed','Falling body rotates into back-first impact, natural bent knees, fully horizontal stunned ground pose and settled lying pose. Head lies with torso.'],
 ['Bound','An outside cage restrains the character: start recoil, hands pushing invisible restraint, full-body struggling pose, released backward stagger. No cage drawn into sprite; separate effect layer supplies cage.'],
 ['Suspended','Outside magic lifts the character: start ankle lift, limbs trail with center of mass suspended, curved weightless recoil, falling recovery. No attacker, magic or second body drawn.']
 ]};
const jobs=[];
for(const c of roster) for(const [panel,rows] of Object.entries(states)) {
 const prompt=`Use case: stylized-concept. Pixel-art GAME REACTION animation atlas of ${c.id}, the VICTIM of an outside attack. Reference ONLY ${c.quadrant} figure. Preserve exact ${c.appearance}. Preserve original weapon ${c.weapon}; hold loosely or let hang beside body without attacking. Match crisp chunky outlined pixel art from reference. Transparent square canvas. EXACT FOUR equal columns and FOUR equal rows, four successive frames per row. ONE complete character per cell; full body, head, hair, clothing, appendages and weapon all fit within the cell with generous empty margins. Same scale across sixteen cells. No attacker, victim silhouette, duplicate body, text, borders, scenery or baked-in hook/chain/cage. Attacker and connecting effects will be separate synchronized layers. Natural head-neck-torso rotation, joints, grounded toes and weight distribution. Adapt to this actual anatomy: robots keep mechanical joints, krakens coil and extend tentacles instead of invented human legs, floating spirits keep cloak/ribcage, golems keep heavy plates, winged creatures fold wings while held. Body class ${c.role}: show its actual bulk and inertia, never replace its anatomy. Face LEFT toward outside attacker, except head rotates naturally in falls.\n`+rows.map(([name,description],i)=>`ROW ${i+1} ${name}: ${description}`).join('\n');
 jobs.push({id:c.id,panel,reference:path.resolve(root,'..',c.reference),prompt,states:rows.map(r=>r[0])});
}
fs.writeFileSync(path.join(root,'reaction-prompts.json'),JSON.stringify(jobs,null,2));
fs.writeFileSync(path.join(root,'interaction-plan.json'),JSON.stringify({
 architecture:'Victim-specific reaction frames, attacker-specific timing and attachment paths; no baked-in victim silhouettes.',
 victims:roster.map(c=>({id:c.id,bodyClass:c.role,appearance:c.appearance})),
 reactions:states,
 pairAdjustments:['waist/center-of-mass attachment','head and shoulder orientation','weapon clearance','wing/shell/tentacle clearance','ground contact and scale'],
 abilities:{brakk:{Super:['Pulled','Grabbed','Lifted','Thrown','Slammed'],Special:['Grabbed']},morrow:{Special:['Pulled'],Super:['Pulled','Suspended','Launched','Slammed']},tidebreaker:{Special:['Pulled'],Super:['Pulled','Grabbed','Lifted','Slammed']},glacia:{Super:['Bound','Suspended','Slammed']},byte:{Super:['Bound','Launched']},kessa:{Super:['Bound','Suspended']},astra:{Super:['Suspended','Launched','Slammed']},nocturne:{Super:['Suspended','Launched','Slammed']},sovereign:{Super:['Bound','Suspended','Slammed']},null:{Super:['Suspended','Launched','Slammed']}},
 status:'Reaction selection and movement are integrated in the game code. Artwork generation, sprite upload and paired visual review remain pending.'
},null,2));
console.log(JSON.stringify({victims:roster.length,reactionPanels:jobs.length,reactionStates:8}));
