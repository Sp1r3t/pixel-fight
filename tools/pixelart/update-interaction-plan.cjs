const fs = require('fs'), path = require('path');
const root = path.resolve(__dirname, '../../art/sprites/rework/new-skins');
const target = path.join(root, 'interaction-plan.json');
const plan = JSON.parse(fs.readFileSync(target));
plan.abilities.hex = { Super: ['Bound', 'Launched'] };
plan.status = 'Reaction selection and movement are integrated in the game code. Artwork generation, sprite upload and paired visual review remain pending.';
fs.writeFileSync(target, JSON.stringify(plan, null, 2));
console.log(JSON.stringify({ interactingActors: Object.keys(plan.abilities).length, status: plan.status }));
