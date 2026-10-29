import crypto from 'node:crypto';
import { one, q } from '../db.js';
import { config } from '../config.js';
import { sendSms } from '../sms.js';
import { fail } from '../app.js';

// Туркменские мобильные номера: +993 6X XXXXXX (TMCELL 61-65, 71 Altyn Asyr/Ashgabat City)
export function normalizePhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  let local = digits;
  if (local.startsWith('993')) local = local.slice(3);
  if (local.startsWith('8') && local.length === 9) local = local.slice(1);
  if (!/^[67]\d{7}$/.test(local)) return null;
  return `+993${local}`;
}

const hash = (s) => crypto.createHash('sha256').update(config.jwtSecret + s).digest('hex');
const adminPhones = new Set(
  (process.env.ADMIN_PHONES || '').split(',').map(normalizePhone).filter(Boolean),
);

export function publicUser(u) {
  return { id: u.id, phone: u.phone, name: u.name, role: u.role, lang: u.lang };
}

export default async function authRoutes(app) {
  app.post('/auth/otp', {
    schema: { body: { type: 'object', required: ['phone'], properties: { phone: { type: 'string' } } } },
  }, async (req) => {
    const phone = normalizePhone(req.body.phone);
    if (!phone) fail(400, 'bad_phone', 'Invalid phone number');

    // не чаще раза в 60 сек на номер
    const prev = await one('SELECT expires_at FROM otp_codes WHERE phone=$1', [phone]);
    if (prev && new Date(prev.expires_at) - Date.now() > 4 * 60_000) fail(429, 'too_often', 'Wait a minute');

    const code = String(crypto.randomInt(1000, 10000));
    await q(
      `INSERT INTO otp_codes (phone, code_hash, expires_at, attempts) VALUES ($1,$2, now() + interval '5 minutes', 0)
       ON CONFLICT (phone) DO UPDATE SET code_hash=$2, expires_at=now() + interval '5 minutes', attempts=0`,
      [phone, hash(phone + code)],
    );
    await sendSms(phone, `SARGYT kod: ${code}`, req.log);
    return config.devOtp ? { ok: true, phone, devCode: code } : { ok: true, phone };
  });

  app.post('/auth/verify', {
    schema: {
      body: {
        type: 'object', required: ['phone', 'code'],
        properties: {
          phone: { type: 'string' }, code: { type: 'string' },
          name: { type: 'string', maxLength: 80 }, lang: { enum: ['tk', 'ru'] },
        },
      },
    },
  }, async (req) => {
    const phone = normalizePhone(req.body.phone);
    if (!phone) fail(400, 'bad_phone');
    const row = await one('SELECT * FROM otp_codes WHERE phone=$1', [phone]);
    if (!row || new Date(row.expires_at) < new Date() || row.attempts >= 5) fail(400, 'code_expired');
    if (row.code_hash !== hash(phone + req.body.code)) {
      await q('UPDATE otp_codes SET attempts = attempts + 1 WHERE phone=$1', [phone]);
      fail(400, 'bad_code');
    }
    await q('DELETE FROM otp_codes WHERE phone=$1', [phone]);

    let user = await one(
      `INSERT INTO users (phone, name, lang) VALUES ($1, $2, $3)
       ON CONFLICT (phone) DO UPDATE SET name = COALESCE(users.name, EXCLUDED.name)
       RETURNING *`,
      [phone, req.body.name || null, req.body.lang || 'tk'],
    );
    if (adminPhones.has(phone) && user.role !== 'admin') {
      user = await one(`UPDATE users SET role='admin' WHERE id=$1 RETURNING *`, [user.id]);
    }
    if (user.blocked) fail(403, 'blocked');
    const token = app.jwt.sign({ id: user.id, role: user.role });
    return { token, user: publicUser(user) };
  });

  app.get('/me', { preHandler: app.auth }, async (req) => {
    const u = await one('SELECT * FROM users WHERE id=$1', [req.user.id]);
    if (!u) fail(401, 'unauthorized');
    // роль могла измениться (стал партнёром) — выдаём свежий токен
    return { user: publicUser(u), token: app.jwt.sign({ id: u.id, role: u.role }) };
  });

  app.patch('/me', {
    preHandler: app.auth,
    schema: { body: { type: 'object', properties: { name: { type: 'string', maxLength: 80 }, lang: { enum: ['tk', 'ru'] } } } },
  }, async (req) => {
    const u = await one(
      `UPDATE users SET name=COALESCE($2,name), lang=COALESCE($3,lang) WHERE id=$1 RETURNING *`,
      [req.user.id, req.body.name ?? null, req.body.lang ?? null],
    );
    return { user: publicUser(u) };
  });
}
