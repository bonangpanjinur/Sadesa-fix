import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.resolve(__dirname, '..', 'data');
const JOBS_FILE = path.join(DATA_DIR, 'jobs.json');
const PORT = Number(process.env.PORT || 18181);
const HOST = process.env.HOST || '127.0.0.1';
const MAX_BODY = 1024 * 1024;
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || '*';
const jobs = new Map();
const queue = [];
let processing = false;

fs.mkdirSync(DATA_DIR, { recursive: true });
try {
  const persisted = JSON.parse(fs.readFileSync(JOBS_FILE, 'utf8'));
  for (const job of persisted.slice(-500)) jobs.set(job.jobId, job);
} catch { /* first run */ }

function persistJobs() {
  fs.writeFileSync(JOBS_FILE, JSON.stringify([...jobs.values()].slice(-500), null, 2));
}

function json(res, status, payload) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': ALLOWED_ORIGIN,
    'access-control-allow-headers': 'content-type, x-print-bridge-token',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-private-network': 'true',
    'vary': 'Origin, Access-Control-Request-Private-Network',
    'cache-control': 'no-store',
  });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > MAX_BODY) {
        reject(new Error('Payload terlalu besar'));
        req.destroy();
      }
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

function getConfig() {
  const configFile = process.env.PRINT_BRIDGE_CONFIG || path.join(DATA_DIR, 'config.json');
  try { return JSON.parse(fs.readFileSync(configFile, 'utf8')); } catch {
    return { printers: [] };
  }
}

async function sendTcp(printer, bytes) {
  await new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: printer.host, port: Number(printer.port || 9100), timeout: 7000 });
    socket.once('connect', () => socket.end(Buffer.from(bytes)));
    socket.once('timeout', () => { socket.destroy(); reject(new Error('Timeout koneksi printer TCP')); });
    socket.once('error', reject);
    socket.once('close', hadError => { if (!hadError) resolve(); });
  });
}

async function sendSerial(printer, bytes) {
  let SerialPort;
  try { ({ SerialPort } = await import('serialport')); }
  catch { throw new Error('Dependensi serialport belum terpasang untuk printer USB'); }
  await new Promise((resolve, reject) => {
    const port = new SerialPort({ path: printer.path, baudRate: Number(printer.baudRate || 9600), autoOpen: false });
    port.open(error => {
      if (error) return reject(error);
      port.write(Buffer.from(bytes), writeError => {
        if (writeError) { port.close(); return reject(writeError); }
        port.drain(drainError => {
          port.close(() => drainError ? reject(drainError) : resolve());
        });
      });
    });
  });
}

async function sendToPrinter(printer, bytes) {
  if (printer.type === 'tcp') return sendTcp(printer, bytes);
  if (printer.type === 'serial') return sendSerial(printer, bytes);
  throw new Error(`Tipe printer tidak didukung: ${printer.type}`);
}

async function processQueue() {
  if (processing) return;
  processing = true;
  while (queue.length) {
    const job = queue.shift();
    if (!job || job.status === 'printed') continue;
    const config = getConfig();
    const printer = config.printers.find(item => item.id === job.printerId) || config.printers.find(item => item.isDefault);
    job.status = 'printing'; job.updatedAt = new Date().toISOString(); persistJobs();
    try {
      if (!printer) throw new Error('Printer default belum dikonfigurasi');
      const bytes = Buffer.from(job.data, 'base64');
      for (let copy = 0; copy < Math.max(1, Number(job.copies || 1)); copy += 1) await sendToPrinter(printer, bytes);
      job.status = 'printed'; job.printerId = printer.id; job.error = null;
    } catch (error) {
      job.status = 'failed'; job.error = error instanceof Error ? error.message : String(error); job.attempts = (job.attempts || 0) + 1;
    }
    job.updatedAt = new Date().toISOString(); persistJobs();
  }
  processing = false;
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return json(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host || HOST}`);
  if (url.pathname === '/health' && req.method === 'GET') {
    return json(res, 200, { ok: true, service: 'sadesa-pos-print-bridge', version: '0.1.0', queue: queue.length, time: new Date().toISOString() });
  }
  if (url.pathname === '/printers' && req.method === 'GET') return json(res, 200, { printers: getConfig().printers });
  if (url.pathname === '/jobs' && req.method === 'GET') return json(res, 200, { jobs: [...jobs.values()].slice(-100).reverse() });
  if (url.pathname.startsWith('/jobs/') && req.method === 'GET') {
    const job = jobs.get(decodeURIComponent(url.pathname.slice('/jobs/'.length)));
    return job ? json(res, 200, job) : json(res, 404, { error: 'Job tidak ditemukan' });
  }
  if (url.pathname === '/jobs' && req.method === 'POST') {
    try {
      const body = JSON.parse(await readBody(req));
      if (!body.jobId || !body.saleId || !body.data) return json(res, 400, { error: 'jobId, saleId, dan data wajib diisi' });
      const existing = jobs.get(body.jobId);
      if (existing) return json(res, 200, existing);
      const job = { jobId: body.jobId, saleId: body.saleId, saleNumber: body.saleNumber || '', outletId: body.outletId || '', createdAt: body.createdAt || new Date().toISOString(), printerId: body.printerId || null, copies: body.copies || 1, data: body.data, status: 'queued', attempts: 0, error: null, updatedAt: new Date().toISOString() };
      jobs.set(job.jobId, job); queue.push(job); persistJobs(); void processQueue();
      return json(res, 202, job);
    } catch (error) { return json(res, 400, { error: error instanceof Error ? error.message : 'Payload tidak valid' }); }
  }
  return json(res, 404, { error: 'Endpoint tidak ditemukan' });
});

server.listen(PORT, HOST, () => console.log(`SaDesa Print Bridge listening on http://${HOST}:${PORT}`));
