import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'dist');
const port=4173;
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.js':'text/javascript; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.zip':'application/zip','.txt':'text/plain; charset=utf-8'};
const server=http.createServer(async(req,res)=>{
 try{
  const requestPath=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  const target=path.resolve(root,'.'+(requestPath.endsWith('/')?requestPath+'index.html':requestPath));
  if(target!==root&&!target.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  if(!(await stat(target)).isFile())throw new Error('not a file');
  const data=await readFile(target);res.writeHead(200,{'Content-Type':types[path.extname(target)]||'application/octet-stream','Cache-Control':'no-store'});res.end(req.method==='HEAD'?undefined:data);
 }catch{res.writeHead(404,{'Content-Type':'text/plain'});res.end('Not found');}
});
server.listen(port,'127.0.0.1',()=>process.stdout.write('Local: http://127.0.0.1:'+port+'\n'));
