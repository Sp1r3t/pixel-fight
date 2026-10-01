const fs=require('fs');
const images={};
function add(id,file){ if(!fs.existsSync(file))return;const buffer=fs.readFileSync(file);images[id]={url:'/'+file,width:buffer.readUInt32BE(16),height:buffer.readUInt32BE(20)}; }
const arcade=fs.readFileSync('src/shared/Config/CharacterSpriteUploads.luau','utf8');
for(const m of arcade.matchAll(/(\w+)\s*=\s*\{([\s\S]*?)\}/g)) {
 let page=0;for(const id of m[2].matchAll(/"(rbxassetid:\/\/\d+)"/g))add(id[1],`art/sprites/v3/${m[1]}_${++page}.png`);
}
const legacy=fs.readFileSync('src/shared/Config/CharacterSprites.luau','utf8');
for(const m of legacy.matchAll(/(\w+) = sheet\("([^"]+)", "([^"]+)"\)/g)){add(m[2],`art/sprites/${m[1]}_a.png`);add(m[3],`art/sprites/${m[1]}_b.png`);}
fs.writeFileSync('art/ui/campaign/image-map.json',JSON.stringify(images));
