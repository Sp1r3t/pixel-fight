const http = require('http');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../..');
http.createServer((request,response)=>{
 const target = path.resolve(root, '.'+decodeURIComponent((request.url||'/').split('?')[0]));
 if(!target.startsWith(root+path.sep)) {response.writeHead(403);response.end();return;}
 fs.readFile(target,(error,body)=>{
  if(error){response.writeHead(404);response.end();return;}
  response.setHeader('Content-Type',target.endsWith('.png')?'image/png':target.endsWith('.svg')?'image/svg+xml':target.endsWith('.json')?'application/json':'text/html; charset=utf-8');
  response.end(body);
 });
}).listen(8641,'127.0.0.1',()=>console.log('UI review: http://127.0.0.1:8641/art/ui/campaign/atlas.svg'));
