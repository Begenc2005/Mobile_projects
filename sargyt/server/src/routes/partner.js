import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { one, many, q } from '../db.js';
import { config } from '../config.js';
import { fail, UPLOAD_DIR } from '../app.js';
import { normalizePhone } from './auth.js';
import { PARTNER_TRANSITIONS, changeStatus, getOrder } from '../orders-service.js';

const TYPES = ['restaurant', 'cafe', 'grocery', 'pharmacy', 'shop'];
const venueProps = {
  type: { enum: TYPES },
  name_ru: { type: 'string', minLength: 1, maxLength: 120 },
  name_tk: { type: 'string', minLength: 1, maxLength: 120 },
  description_ru: { type: 'string', maxLength: 1000 },
  description_tk: { type: 'string', maxLength: 1000 },
  city_id: { type: 'integer' },
  address: { type: 'string', minLength: 3, maxLength: 300 },
  lat: { type: 'number', minimum: 35, maximum: 43 },
  lng: { type: 'number', minimum: 52, maximum: 67 },
  phone: { type: 'string' },
  logo_url: { type: 'string', maxLength: 500 },
  is_open: { type: 'boolean' },
  delivery_fee: { type: 'number', minimum: 0, maximum: 1000 },
  min_order: { type: 'number', minimum: 0, maximum: 10000 },
  delivery_radius_km: { type: 'number', minimum: 0.5, maximum: 50 },
  prep_minutes: { type: 'integer', minimum: 5, maximum: 240 },
  accepts_cash: { type: 'boolean' },
  legal_name: { type: 'string', maxLength: 200 },
  tax_id: { type: 'string', maxLength: 50 },
};
// Поля, которые партнёр может менять сам (комиссия, статус, договор — только админ)
const EDITABLE = Object.keys(venueProps);

const productProps = {
  category_id: { type: ['integer', 'null'] },
  name_ru: { type: 'string', minLength: 1, maxLength: 160 },
  name_tk: { type: 'string', minLength: 1, maxLength: 160 },
  description_ru: { type: 'string', maxLength: 1000 },
  description_tk: { type: 'string', maxLength: 1000 },
  price: { type: 'number', minimum: 0, maximum: 100000 },
  image_url: { type: ['string', 'null'], maxLength: 500 },
  available: { type: 'boolean' },
  sort: { type: 'integer' },
};

function updateSql(table, allowed, body, idCol = 'id') {
  const keys = Object.keys(body).filter((k) => allowed.includes(k));
  if (!keys.length) fail(400, 'nothing_to_update');
  const sets = keys.map((k, i) => `${k}=$${i + 2}`).join(', ');
  return { sql: `UPDATE ${table} SET ${sets} WHERE ${idCol}=$1 RETURNING *`, values: keys.map((k) => body[k]) };
}

export default async function partnerRoutes(app) {
  // Любой вошедший пользователь может подать заявку на подключение заведения
  app.post('/venues', {
    preHandler: app.auth,
    schema: {
      body: {
        type: 'object',
        required: ['type', 'name_ru', 'name_tk', 'city_id', 'address', 'lat', 'lng', 'phone'],
        properties: venueProps,
      },
    },
  }, async (req) => {
    const b = req.body;
    const phone = normalizePhone(b.phone) || b.phone;
    const cols = EDITABLE.filter((k) => b[k] !== undefined && k !== 'is_open');
    const values = cols.map((k) => (k === 'phone' ? phone : b[k]));
    const venue = await one(
      `INSERT INTO venues (owner_id, commission_pct, ${cols.join(',')})
       VALUES ($1, $2, ${cols.map((_, i) => `$${i + 3}`).join(',')}) RETURNING *`,
      [req.user.id, config.defaultCommissionPct, ...values],
    );
    await q(`UPDATE users SET role='partner' WHERE id=$1 AND role='customer'`, [req.user.id]);
    return { venue, token: app.jwt.sign({ id: req.user.id, role: req.user.role === 'admin' ? 'admin' : 'partner' }) };
  });

  // Дальше — только партнёры (и админ)
  app.addHook('preHandler', async (req) => {
    if (req.routeOptions.url === '/api/partner/venues' && req.method === 'POST') return;
    await app.role('partner', 'admin')(req);
  });

  const ownVenue = async (req, venueId) => {
    const v = await one('SELECT * FROM venues WHERE id=$1', [Number(venueId)]);
    if (!v || (v.owner_id !== req.user.id && req.user.role !== 'admin')) fail(404, 'venue_not_found');
    return v;
  };

  app.get('/venues', async (req) => many('SELECT * FROM venues WHERE owner_id=$1 ORDER BY id', [req.user.id]));

  app.get('/venues/:id', async (req) => {
    const v = await ownVenue(req, req.params.id);
    const [categories, products] = await Promise.all([
      many('SELECT * FROM categories WHERE venue_id=$1 ORDER BY sort, id', [v.id]),
      many('SELECT * FROM products WHERE venue_id=$1 ORDER BY sort, id', [v.id]),
    ]);
    return { ...v, categories, products };
  });

  app.patch('/venues/:id', {
    schema: { body: { type: 'object', properties: venueProps, additionalProperties: false } },
  }, async (req) => {
    const v = await ownVenue(req, req.params.id);
    if (req.body.is_open && v.status !== 'active') fail(409, 'not_approved', 'Venue is not approved yet');
    if (req.body.phone) req.body.phone = normalizePhone(req.body.phone) || req.body.phone;
    const { sql, values } = updateSql('venues', EDITABLE, req.body);
    return one(sql, [v.id, ...values]);
  });

  // --- категории ---
  const catBody = {
    type: 'object', required: ['name_ru', 'name_tk'],
    properties: { name_ru: { type: 'string', minLength: 1 }, name_tk: { type: 'string', minLength: 1 }, sort: { type: 'integer' } },
  };
  app.post('/venues/:id/categories', { schema: { body: catBody } }, async (req) => {
    const v = await ownVenue(req, req.params.id);
    return one('INSERT INTO categories (venue_id, name_ru, name_tk, sort) VALUES ($1,$2,$3,$4) RETURNING *',
      [v.id, req.body.name_ru, req.body.name_tk, req.body.sort || 0]);
  });
  const ownCategory = async (req) => {
    const c = await one('SELECT * FROM categories WHERE id=$1', [Number(req.params.cid)]);
    if (!c) fail(404, 'not_found');
    await ownVenue(req, c.venue_id);
    return c;
  };
  app.patch('/categories/:cid', { schema: { body: { ...catBody, required: [] } } }, async (req) => {
    const c = await ownCategory(req);
    const { sql, values } = updateSql('categories', ['name_ru', 'name_tk', 'sort'], req.body);
    return one(sql, [c.id, ...values]);
  });
  app.delete('/categories/:cid', async (req) => {
    const c = await ownCategory(req);
    await q('DELETE FROM categories WHERE id=$1', [c.id]);
    return { ok: true };
  });

  // --- товары / блюда ---
  app.post('/venues/:id/products', {
    schema: { body: { type: 'object', required: ['name_ru', 'name_tk', 'price'], properties: productProps } },
  }, async (req) => {
    const v = await ownVenue(req, req.params.id);
    const b = req.body;
    if (b.category_id) {
      const c = await one('SELECT venue_id FROM categories WHERE id=$1', [b.category_id]);
      if (!c || c.venue_id !== v.id) fail(400, 'bad_category');
    }
    return one(
      `INSERT INTO products (venue_id, category_id, name_ru, name_tk, description_ru, description_tk, price, image_url, available, sort)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [v.id, b.category_id || null, b.name_ru, b.name_tk, b.description_ru || null, b.description_tk || null,
        b.price, b.image_url || null, b.available ?? true, b.sort || 0],
    );
  });
  const ownProduct = async (req) => {
    const p = await one('SELECT * FROM products WHERE id=$1', [Number(req.params.pid)]);
    if (!p) fail(404, 'not_found');
    await ownVenue(req, p.venue_id);
    return p;
  };
  app.patch('/products/:pid', {
    schema: { body: { type: 'object', properties: productProps, additionalProperties: false } },
  }, async (req) => {
    const p = await ownProduct(req);
    if (req.body.category_id) {
      const c = await one('SELECT venue_id FROM categories WHERE id=$1', [req.body.category_id]);
      if (!c || c.venue_id !== p.venue_id) fail(400, 'bad_category');
    }
    const { sql, values } = updateSql('products', Object.keys(productProps), req.body);
    return one(sql, [p.id, ...values]);
  });
  app.delete('/products/:pid', async (req) => {
    const p = await ownProduct(req);
    await q('DELETE FROM products WHERE id=$1', [p.id]);
    return { ok: true };
  });

  // Загрузка картинки (jpg/png/webp до 2 МБ)
  app.post('/upload', async (req) => {
    const file = await req.file();
    if (!file) fail(400, 'no_file');
    const ext = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' }[file.mimetype];
    if (!ext) fail(400, 'bad_type', 'Only jpg, png, webp');
    const name = crypto.randomBytes(12).toString('hex') + ext;
    await pipeline(file.file, fs.createWriteStream(path.join(UPLOAD_DIR, name)));
    if (file.file.truncated) { fs.rmSync(path.join(UPLOAD_DIR, name)); fail(413, 'too_large', 'Max 2 MB'); }
    return { url: `${config.publicUrl}/uploads/${name}` };
  });

  // --- заказы заведения ---
  app.get('/orders', {
    schema: { querystring: { type: 'object', properties: { venue_id: { type: 'integer' }, active: { type: 'boolean' } } } },
  }, async (req) => {
    const params = [req.user.id];
    let where = 'v.owner_id=$1';
    if (req.query.venue_id) { params.push(req.query.venue_id); where += ` AND o.venue_id=$${params.length}`; }
    where += req.query.active
      ? ` AND o.status IN ('new','accepted','preparing','on_the_way')`
      : ` AND o.status <> 'awaiting_payment'`;
    const orders = await many(
      `SELECT o.*, v.name_ru AS venue_name_ru, v.name_tk AS venue_name_tk FROM orders o JOIN venues v ON v.id=o.venue_id
       WHERE ${where} ORDER BY o.id DESC LIMIT 200`, params,
    );
    if (orders.length) {
      const items = await many('SELECT order_id, name_ru, name_tk, price, qty FROM order_items WHERE order_id = ANY($1::bigint[]) ORDER BY id',
        [orders.map((o) => o.id)]);
      for (const o of orders) o.items = items.filter((i) => i.order_id === o.id);
    }
    return orders;
  });

  app.post('/orders/:id/status', {
    schema: {
      body: {
        type: 'object', required: ['status'],
        properties: { status: { enum: ['accepted', 'preparing', 'on_the_way', 'delivered', 'rejected'] }, reason: { type: 'string', maxLength: 300 } },
      },
    },
  }, async (req) => {
    const o = await getOrder(Number(req.params.id));
    if (!o) fail(404, 'not_found');
    await ownVenue(req, o.venue_id);
    if (!(PARTNER_TRANSITIONS[o.status] || []).includes(req.body.status)) {
      fail(409, 'bad_transition', `Cannot go from ${o.status} to ${req.body.status}`);
    }
    const updated = await changeStatus(o, req.body.status, req.body.reason);
    if (req.body.status === 'delivered' && o.payment_method === 'cash') {
      await q(`UPDATE orders SET payment_status='paid' WHERE id=$1`, [o.id]);
      updated.payment_status = 'paid';
    }
    return updated;
  });

  // Отчёт заведения за период: продажи, комиссия, расчёт с агрегатором
  app.get('/report', {
    schema: {
      querystring: {
        type: 'object', required: ['venue_id', 'from', 'to'],
        properties: { venue_id: { type: 'integer' }, from: { type: 'string', format: 'date' }, to: { type: 'string', format: 'date' } },
      },
    },
  }, async (req) => {
    const v = await ownVenue(req, req.query.venue_id);
    return one(SETTLEMENT_SQL('o.venue_id=$1'), [v.id, req.query.from, req.query.to]);
  });
}

// Расчёт: картой деньги приходят агрегатору -> он должен заведению (сумма - комиссия);
// наличными деньги у заведения -> заведение должно агрегатору комиссию.
export const SETTLEMENT_SQL = (where) => `
  SELECT
    count(*)::int                                                         AS orders,
    COALESCE(sum(o.total),0)                                              AS gmv,
    COALESCE(sum(o.commission_amount),0)                                  AS commission,
    COALESCE(sum(o.total) FILTER (WHERE o.payment_method='card'),0)       AS card_total,
    COALESCE(sum(o.total) FILTER (WHERE o.payment_method='cash'),0)       AS cash_total,
    COALESCE(sum(o.total - o.commission_amount) FILTER (WHERE o.payment_method='card'),0) AS payable_to_venue,
    COALESCE(sum(o.commission_amount) FILTER (WHERE o.payment_method='cash'),0)           AS owed_by_venue
  FROM orders o
  WHERE ${where} AND o.status='delivered'
    AND o.created_at >= $2::date AND o.created_at < ($3::date + 1)`;
