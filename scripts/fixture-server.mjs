import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const types = { '.css': 'text/css', '.js': 'text/javascript', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf' };

// Fixture pages and optional module assets are available only on this machine.
export async function startFixtureServer(pages, { modules } = {}) {
  const moduleRoot = modules ? fs.realpathSync(modules) : null;
  const server = http.createServer((request, response) => {
    let pathname;
    try {
      pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    } catch {
      response.statusCode = 400;
      return response.end();
    }

    const name = pathname.slice(1).replace(/\.html$/, '');
    if (Object.hasOwn(pages, name)) {
      response.setHeader('content-type', 'text/html; charset=utf-8');
      return response.end(pages[name]);
    }

    let file;
    if (moduleRoot && pathname.startsWith('/modules/')) {
      try {
        file = fs.realpathSync(path.resolve(moduleRoot, pathname.slice('/modules/'.length)));
        const relative = path.relative(moduleRoot, file);
        if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative) || !fs.statSync(file).isFile()) {
          file = null;
        }
      } catch {
        file = null;
      }
    }
    if (!file) {
      response.statusCode = 404;
      return response.end();
    }
    response.setHeader('content-type', types[path.extname(file)] ?? 'application/octet-stream');
    fs.createReadStream(file).on('error', () => {
      response.statusCode = 404;
      response.end();
    }).pipe(response);
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return { server, origin: `http://127.0.0.1:${server.address().port}` };
}
