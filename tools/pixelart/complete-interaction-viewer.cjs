const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '../../art/sprites/rework/new-skins');
const file = path.join(root, 'interactions.html');
let html = fs.readFileSync(file, 'utf8');
const marker = 'let time=0,last=performance.now(),paused=false;';
if (!html.includes(marker)) throw new Error('Missing viewer timeline marker');
if (!html.includes('timelines.hex=')) {
  html = html.replace(marker, `timelines.hex=[[.68,'Bound'],[1,'Launched']];
timelines.astra=[[.62,'Suspended'],[.85,'Launched'],[1,'Slammed']];
timelines.nocturne=timelines.astra;
timelines.sovereign=[[.44,'Bound'],[.8,'Suspended'],[1,'Slammed']];
timelines.null=[[.6,'Suspended'],[.86,'Launched'],[1,'Slammed']];
${marker}`);
}
fs.writeFileSync(file, html);
console.log('Pair viewer now matches all eleven control-ability timelines.');
