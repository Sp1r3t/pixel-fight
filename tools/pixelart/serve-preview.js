"use strict";
const http=require('http'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art');
const port=Number(process.argv[2]||8765);
http.createServer((req,res)=>{
  let file;
  try{file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));}catch{res.writeHead(400).end();return;}
  if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
  fs.readFile(file,(error,data)=>{
    if(error){res.writeHead(404).end('Not found');return;}
    const types={'.png':'image/png','.html':'text/html; charset=utf-8','.json':'application/json; charset=utf-8'};
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'text/plain; charset=utf-8','Cache-Control':'no-store'});res.end(data);
  });
}).listen(port,'127.0.0.1',()=>console.log(`Preview: http://127.0.0.1:${port}/sprites/v2/preview.html`));
