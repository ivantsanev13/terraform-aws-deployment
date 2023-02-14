const os = require("os");
const http = require('http');

const hostname = os.hostname();
const port = 3000;
console.log('hosted-name', hostname);
const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Simple Node.js app');
});

server.listen(port, hostname, () => {
  console.log(`Server running at http://${hostname}:${port}/`);
});