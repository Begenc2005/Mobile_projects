import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import multipart from '@fastify/multipart';
import fstatic from '@fastify/static';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { config } from './config.js';
import authRoutes from './routes/auth.js';
import catalogRoutes from './routes/catalog.js';
import orderRoutes from './routes/orders.js';
import partnerRoutes from './routes/partner.js';
import adminRoutes from './routes/admin.js';
import payRoutes from './routes/pay.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../uploads');

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message || code);
    this.statusCode = status;
    this.code = code;
  }
}
export const fail = (status, code, message) => { throw new HttpError(status, code, message); };

export async function build(opts = {}) {
  const app = Fastify({ logger: opts.logger ?? true, trustProxy: true, bodyLimit: 1_000_000 });

  await app.register(cors, { origin: true });
  await app.register(jwt, { secret: config.jwtSecret, sign: { expiresIn: '90d' } });
  await app.register(multipart, { limits: { fileSize: 2 * 1024 * 1024, files: 1 } });

  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  await app.register(fstatic, { root: UPLOAD_DIR, prefix: '/uploads/', maxAge: '30d' });
  await app.register(fstatic, {
    root: path.join(__dirname, '../../panel'), prefix: '/panel/', decorateReply: false,
  });

  // --- аутентификация и роли ---
  app.decorate('auth', async (req) => {
    try { await req.jwtVerify(); } catch { fail(401, 'unauthorized'); }
  });
  app.decorate('role', (...roles) => async (req) => {
    await app.auth(req);
    if (!roles.includes(req.user.role)) fail(403, 'forbidden');
  });

  app.setErrorHandler((err, req, reply) => {
    const status = err.statusCode || 500;
    if (status >= 500) req.log.error(err);
    reply.code(status).send({
      error: err.code && typeof err.code === 'string' ? err.code.toLowerCase() : 'error',
      message: status >= 500 ? 'Internal error' : err.message,
    });
  });

  app.get('/health', async () => ({ ok: true }));
  app.get('/', async (req, reply) => reply.redirect('/panel/'));

  await app.register(authRoutes, { prefix: '/api' });
  await app.register(catalogRoutes, { prefix: '/api' });
  await app.register(orderRoutes, { prefix: '/api' });
  await app.register(partnerRoutes, { prefix: '/api/partner' });
  await app.register(adminRoutes, { prefix: '/api/admin' });
  await app.register(payRoutes, { prefix: '/pay' });

  return app;
}
