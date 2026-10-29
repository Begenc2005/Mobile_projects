import { one, many } from '../db.js';
import { fail } from '../app.js';
import { normalizePhone } from './auth.js';
import { createOrder, getOrder, changeStatus, startPayment, syncPayment } from '../orders-service.js';

export default async function orderRoutes(app) {
  app.post('/orders', {
    preHandler: app.auth,
    schema: {
      body: {
        type: 'object',
        required: ['venue_id', 'items', 'address', 'phone', 'payment_method'],
        properties: {
          venue_id: { type: 'integer' },
          items: {
            type: 'array', minItems: 1, maxItems: 50,
            items: {
              type: 'object', required: ['product_id', 'qty'],
              properties: { product_id: { type: 'integer' }, qty: { type: 'integer', minimum: 1, maximum: 99 } },
            },
          },
          address: { type: 'string', minLength: 3, maxLength: 300 },
          lat: { type: 'number' }, lng: { type: 'number' },
          phone: { type: 'string' },
          comment: { type: 'string', maxLength: 500 },
          payment_method: { enum: ['card', 'cash'] },
        },
      },
    },
  }, async (req) => {
    const phone = normalizePhone(req.body.phone);
    if (!phone) fail(400, 'bad_phone');
    return createOrder(req.user.id, { ...req.body, phone });
  });

  app.get('/orders', { preHandler: app.auth }, async (req) => many(
    `SELECT o.id, o.status, o.payment_method, o.payment_status, o.total, o.created_at,
            v.name_ru AS venue_name_ru, v.name_tk AS venue_name_tk, v.logo_url
     FROM orders o JOIN venues v ON v.id=o.venue_id
     WHERE o.user_id=$1 ORDER BY o.id DESC LIMIT 50`, [req.user.id],
  ));

  const own = async (req) => {
    const o = await getOrder(Number(req.params.id));
    if (!o || o.user_id !== req.user.id) fail(404, 'not_found');
    return o;
  };

  app.get('/orders/:id', { preHandler: app.auth }, async (req) => {
    let o = await own(req);
    if (o.status === 'awaiting_payment') { await syncPayment(o.id); o = await getOrder(o.id); }
    return o;
  });

  // Повторная попытка оплаты
  app.post('/orders/:id/pay', { preHandler: app.auth }, async (req) => {
    const o = await own(req);
    if (o.status !== 'awaiting_payment') fail(409, 'not_awaiting_payment');
    return startPayment(o);
  });

  // Клиент может отменить, пока заведение не приняло заказ
  app.post('/orders/:id/cancel', { preHandler: app.auth }, async (req) => {
    const o = await own(req);
    if (!['awaiting_payment', 'new'].includes(o.status)) fail(409, 'cannot_cancel', 'Order already accepted');
    return changeStatus(o, 'cancelled');
  });

  // Повтор заказа: вернуть позиции, которые ещё доступны
  app.get('/orders/:id/repeat', { preHandler: app.auth }, async (req) => {
    const o = await own(req);
    const venue = await one(`SELECT id FROM venues WHERE id=$1 AND status='active'`, [o.venue_id]);
    if (!venue) fail(404, 'venue_not_found');
    const items = await many(
      `SELECT oi.product_id, oi.qty FROM order_items oi JOIN products p ON p.id=oi.product_id
       WHERE oi.order_id=$1 AND p.available`, [o.id],
    );
    return { venue_id: o.venue_id, items };
  });
}
