import http from 'node:http';
import os from 'node:os';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'dist');
const port=Number(process.env.PORT)||4173;
// `node site/server.mjs` serves to this machine only.
// `node site/server.mjs --lan` (or HOST=0.0.0.0) also serves to other devices on the same Wi-Fi.
const lan=process.argv.includes('--lan')||process.env.HOST==='0.0.0.0';
const host=lan?'0.0.0.0':(process.env.HOST||'127.0.0.1');
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.js':'text/javascript; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.zip':'application/zip','.txt':'text/plain; charset=utf-8','.xml':'application/xml; charset=utf-8'};
const server=http.createServer(async(req,res)=>{
 try{
  const requestPath=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  const target=path.resolve(root,'.'+(requestPath.endsWith('/')?requestPath+'index.html':requestPath));
  if(target!==root&&!target.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  if(!(await stat(target)).isFile())throw new Error('not a file');
  const data=await readFile(target);res.writeHead(200,{'Content-Type':types[path.extname(target)]||'application/octet-stream','Cache-Control':'no-store'});res.end(req.method==='HEAD'?undefined:data);
 }catch{res.writeHead(404,{'Content-Type':'text/plain'});res.end('Not found');}
});
server.listen(port,host,()=>{
 process.stdout.write('Local:   http://127.0.0.1:'+port+'\n');
 if(!lan)return;
 const addresses=Object.values(os.networkInterfaces()).flat().filter(a=>a&&a.family==='IPv4'&&!a.internal).map(a=>a.address);
 for(const address of addresses)process.stdout.write('Network: http://'+address+':'+port+'\n');
 if(!addresses.length)process.stdout.write('Network: no Wi-Fi or Ethernet address found\n');
 process.stdout.write('Other devices on this Wi-Fi can open a Network address. Allow Node.js through Windows Firewall on private networks if prompted.\n');
});
