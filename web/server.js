const http = require('http');
const fs = require('fs');
const path = require('path');

// Default options
let serverPath = '.';
let serverPort = 8080;
let enableCors = true;

// Parse command line arguments
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  switch(args[i]) {
    case '--path':
      serverPath = args[++i];
      break;
    case '--port':
      serverPort = parseInt(args[++i], 10);
      break;
    case '--no-cors':
      enableCors = false;
      break;
    case '--help':
      console.log(`
      YAZBG Web Server
      
      Options:
        --path PATH     Set the root path to serve files from (default: current directory)
        --port PORT     Set the server port (default: 8080)
        --no-cors       Disable CORS headers
        --help          Show this help message
      
      Note: Root URL (/) will always serve yazbg.html
      `);
      process.exit(0);
  }
}

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

const server = http.createServer((req, res) => {
  // For root path or index.html, always serve yazbg.html
  const isRootRequest = req.url === '/' || req.url === '/index.html';
  const reqPath = isRootRequest ? '/yazbg.html' : req.url;
  const filePath = path.join(serverPath, reqPath);
  
  fs.readFile(filePath, (err, content) => {
    if (err) {
      console.error(`Error serving file: ${err.message}`);
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end(`File not found: ${req.url}`);
      return;
    }
    
    // Set the response headers
    const headers = { 'Content-Type': getContentType(filePath) };
    
    // Add CORS headers if enabled
    if (enableCors) {
      headers['Access-Control-Allow-Origin'] = '*';
      headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS';
      headers['Access-Control-Allow-Headers'] = 'Content-Type';
    }
    
    res.writeHead(200, headers);
    res.end(content);
  });
});

server.listen(serverPort, () => {
  console.log(`YAZBG Server running at http://localhost:${serverPort}/`);
  console.log(`Root path from: ${path.resolve(serverPath)}`);
  console.log(`Root URL (/) will serve: ${path.resolve(path.join(serverPath, 'yazbg.html'))}`);
});