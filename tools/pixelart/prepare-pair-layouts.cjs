const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework/new-skins');
const roster=JSON.parse(fs.readFileSync(path.join(root,'roster.json')));
const plan=JSON.parse(fs.readFileSync(path.join(root,'interaction-plan.json')));
const pairs=[];
for(const attacker of roster)for(const victim of roster){
 const text=victim.appearance,features=[];
 if(/robot|automaton|cybernetic/.test(text))features.push('mechanical-joints');
 if(/tentacles/.test(text))features.push('tentacle-center');
 if(/wing|harpy|raven/.test(text))features.push('fold-wings');
 if(/shell|turtle/.test(text))features.push('shell-clearance');
 if(/floating|no visible feet/.test(text))features.push('floating-body');
 const gap=victim.role==='tank'?2.8:victim.role==='agile'?1.8:2.2;
 pairs.push({attacker:attacker.id,victim:victim.id,
  victimAssets:[victim.id+'_7.png',victim.id+'_8.png'],
  superReactions:plan.abilities[attacker.id]?.Super||['Hit','Launched','Slammed'],
  specialReactions:plan.abilities[attacker.id]?.Special||[],
  attachment:{center:'torso-center-of-mass',clearanceStuds:gap,features},
  review:'pending-paired-visual-review'});
}
fs.writeFileSync(path.join(root,'pair-layouts.json'),JSON.stringify({status:'draft',pairs},null,2));
console.log(JSON.stringify({pairs:pairs.length,victims:roster.length,allRequireVisualReview:true}));
