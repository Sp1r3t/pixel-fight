const http=require('http'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../../art/sprites/rework');
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.png':'image/png'};
const server=http.createServer((req,res)=>{let file;try{const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);file=path.resolve(root,'.'+name);}catch{res.writeHead(400);res.end();return;}if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}fs.stat(file,(err,stat)=>{if(err||!stat.isFile()){res.writeHead(404);res.end();return;}res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});fs.createReadStream(file).pipe(res);});});
server.listen(Number(process.argv[2])||8136,'127.0.0.1',()=>console.log('Preview: http://127.0.0.1:'+server.address().port+'/new-skins/preview.html'));
