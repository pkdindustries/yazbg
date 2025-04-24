const http = require('http');
const fs = require('fs');
const path = require('path');

const docroot = '.'; // Current directory as default
const port = 8181;

const server = http.createServer((req, res)  => {
  const filePath = path.join(docroot, req.url === '/' ? 'index.html' : req.url);

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('File not found');
    } else {
      res.writeHead(200, {
        'Content-Type': getContentType(filePath),
        'Access-Control-Allow-Origin': '*', // Allow from any origin
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
      });
      res.end(content);
    }
  });
});

function getContentType(filePath) {
  const extname = path.extname(filePath);
  switch (extname) {
    case '.html': return 'text/html';
    case '.css': return 'text/css';
    case '.js': return 'text/javascript';
    case '.json': return 'application/json';
    case '.png': return 'image/png';
    case '.jpg': return 'image/jpg';
    case '.wasm': return 'application/wasm';
    default: return 'application/octet-stream';
  }
}

server.listen(port, () => {
  console.log(`Server running at http://localhost:${port}/`);
});
