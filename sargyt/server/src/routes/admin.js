import { one, many } from '../db.js';
import { fail } from '../app.js';
import { SETTLEMENT_SQL } from './partner.js';
import { getOrder, changeStatus } from '../orders-service.js';

export default async function adminRoutes(app) {
  app.addHook('preHandler', app.role('admin'));

  app.get('/stats', async () => one(`
    SELECT
      (SELECT count(*) FROM users)::int AS users,
      (SELECT count(*) FROM venues WHERE status='active')::int AS venues_active,
      (SELECT count(*) FROM venues WHERE status='pending')::int AS venues_pending,
      (SELECT count(*) FROM orders WHERE created_at::date = current_date AND status<>'awaiting_payment')::int AS orders_today,
      (SELECT COALESCE(sum(total),0) FROM orders WHERE created_at::date = current_date AND status='delivered') AS gmv_today,
      (SELECT COALESCE(sum(commission_amount),0) FROM orders WHERE created_at::date = current_date AND status='delivered') AS commission_today`));

  app.get('/venues', {
    schema: { querystring: { type: 'object', properties: { status: { enum: ['pending', 'active', 'blocked'] } } } },
  }, async (req) => many(
    `SELECT v.*, u.phone AS owner_phone, u.name AS owner_name, c.name_ru AS city_name
     FROM venues v JOIN users u ON u.id=v.owner_id JOIN cities c ON c.id=v.city_id
     ${req.query.status ? 'WHERE v.status=$1' : ''} ORDER BY v.id DESC`,
    req.query.status ? [req.query.status] : [],
  ));

  // Одобрение заявки, договор, индивидуальная комиссия 10–15%
  app.patch('/venues/:id', {
    schema: {
      body: {
        type: 'object', additionalProperties: false,
        properties: {
          status: { enum: ['pending', 'active', 'blocked'] },
          commission_pct: { type: 'number', minimum: 0, maximum: 50 },
          contract_no: { type: 'string', maxLength: 50 },
          contract_signed_at: { type: 'string', format: 'date' },
          legal_name: { type: 'string', maxLength: 200 },
          tax_id: { type: 'string', maxLength: 50 },
        },
      },
    },
  }, async (req) => {
    const keys = Object.keys(req.body);
    if (!keys.length) fail(400, 'nothing_to_update');
    if (req.body.status === 'active') {
      const v = await one('SELECT contract_no FROM venues WHERE id=$1', [Number(req.params.id)]);
      if (!v) fail(404, 'not_found');
      if (!v.contract_no && !req.body.contract_no) fail(409, 'no_contract', 'Set contract number before activation');
    }
    const sets = keys.map((k, i) => `${k}=$${i + 2}`);
    if (req.body.status && req.body.status !== 'active') sets.push('is_open=false');
    const v = await one(`UPDATE venues SET ${sets.join(', ')} WHERE id=$1 RETURNING *`,
      [Number(req.params.id), ...keys.map((k) => req.body[k])]);
    if (!v) fail(404, 'not_found');
    return v;
  });

  app.get('/orders', {
    schema: { querystring: { type: 'object', properties: { status: { type: 'string' }, venue_id: { type: 'integer' } } } },
  }, async (req) => {
    const params = []; const where = [];
    if (req.query.status) { params.push(req.query.status); where.push(`o.status=$${params.length}`); }
    if (req.query.venue_id) { params.push(req.query.venue_id); where.push(`o.venue_id=$${params.length}`); }
    return many(
      `SELECT o.*, v.name_ru AS venue_name_ru, u.phone AS user_phone FROM orders o
       JOIN venues v ON v.id=o.venue_id JOIN users u ON u.id=o.user_id
       ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY o.id DESC LIMIT 300`, params,
    );
  });

  // Принудительная отмена (спорные случаи) — с возвратом денег на карту
  app.post('/orders/:id/cancel', async (req) => {
    const o = await getOrder(Number(req.params.id));
    if (!o) fail(404, 'not_found');
    if (['delivered', 'cancelled', 'rejected'].includes(o.status)) fail(409, 'final_status');
    return changeStatus(o, 'cancelled', 'admin');
  });

  // Сверка со всеми заведениями за период
  app.get('/report', {
    schema: {
      querystring: {
        type: 'object', required: ['from', 'to'],
        properties: { from: { type: 'string', format: 'date' }, to: { type: 'string', format: 'date' } },
      },
    },
  }, async (req) => {
    const venues = await many('SELECT id, name_ru, contract_no, commission_pct FROM venues WHERE status<>\'pending\' ORDER BY id');
    const rows = [];
    for (const v of venues) {
      const s = await one(SETTLEMENT_SQL('o.venue_id=$1'), [v.id, req.query.from, req.query.to]);
      if (s.orders) rows.push({ ...v, ...s });
    }
    const totals = await one(SETTLEMENT_SQL('true AND $1::int IS NOT NULL'), [0, req.query.from, req.query.to]);
    return { from: req.query.from, to: req.query.to, totals, venues: rows };
  });

  app.patch('/users/:id', {
    schema: { body: { type: 'object', additionalProperties: false, properties: { blocked: { type: 'boolean' }, role: { enum: ['customer', 'partner', 'admin'] } } } },
  }, async (req) => {
    const keys = Object.keys(req.body);
    if (!keys.length) fail(400, 'nothing_to_update');
    const u = await one(`UPDATE users SET ${keys.map((k, i) => `${k}=$${i + 2}`).join(', ')} WHERE id=$1 RETURNING id, phone, name, role, blocked`,
      [Number(req.params.id), ...keys.map((k) => req.body[k])]);
    if (!u) fail(404, 'not_found');
    return u;
  });
}
