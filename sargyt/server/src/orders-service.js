import { one, many, q, tx } from './db.js';
import { fail } from './app.js';
import { registerPayment, checkPayment, refundPayment } from './payment.js';

const r2 = (n) => Math.round(n * 100) / 100;

function distanceKm(aLat, aLng, bLat, bLng) {
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(bLat - aLat), dLng = rad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.sqrt(h));
}

// Переходы статусов, которые выполняет заведение (оно же доставляет)
export const PARTNER_TRANSITIONS = {
  new: ['accepted', 'rejected'],
  accepted: ['preparing', 'on_the_way', 'rejected'],
  preparing: ['on_the_way'],
  on_the_way: ['delivered'],
};

export async function createOrder(userId, body) {
  const venue = await one(`SELECT * FROM venues WHERE id=$1 AND status='active'`, [body.venue_id]);
  if (!venue) fail(404, 'venue_not_found');
  if (!venue.is_open) fail(409, 'venue_closed', 'Venue is closed');
  if (body.payment_method === 'cash' && !venue.accepts_cash) fail(409, 'cash_not_accepted');

  if (Number.isFinite(body.lat) && Number.isFinite(body.lng)) {
    const d = distanceKm(venue.lat, venue.lng, body.lat, body.lng);
    if (d > venue.delivery_radius_km) fail(409, 'too_far', 'Address is outside delivery zone');
  }

  // Объединяем одинаковые позиции, цены берём только из БД
  const qty = new Map();
  for (const it of body.items) qty.set(it.product_id, (qty.get(it.product_id) || 0) + it.qty);
  const ids = [...qty.keys()];
  const products = await many(
    `SELECT id, name_ru, name_tk, price FROM products WHERE venue_id=$1 AND available AND id = ANY($2::bigint[])`,
    [venue.id, ids],
  );
  if (products.length !== ids.length) fail(409, 'items_unavailable', 'Some items are no longer available');

  const items = products.map((p) => ({ ...p, qty: Math.min(qty.get(p.id), 99) }));
  const subtotal = r2(items.reduce((s, i) => s + i.price * i.qty, 0));
  if (subtotal < venue.min_order) fail(409, 'below_min_order', `Minimum order ${venue.min_order} TMT`);
  const deliveryFee = venue.delivery_fee;
  const total = r2(subtotal + deliveryFee);
  const commission = r2((subtotal * venue.commission_pct) / 100);
  const isCard = body.payment_method === 'card';

  const order = await tx(async (c) => {
    const o = (await c.query(
      `INSERT INTO orders (user_id, venue_id, status, payment_method, payment_status, subtotal, delivery_fee,
         total, commission_pct, commission_amount, address, lat, lng, phone, comment)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING *`,
      [userId, venue.id, isCard ? 'awaiting_payment' : 'new', body.payment_method, isCard ? 'pending' : 'none',
        subtotal, deliveryFee, total, venue.commission_pct, commission, body.address,
        body.lat ?? null, body.lng ?? null, body.phone, body.comment || null],
    )).rows[0];
    for (const i of items) {
      await c.query(
        'INSERT INTO order_items (order_id, product_id, name_ru, name_tk, price, qty) VALUES ($1,$2,$3,$4,$5,$6)',
        [o.id, i.id, i.name_ru, i.name_tk, i.price, i.qty],
      );
    }
    return o;
  });

  let payment = null;
  if (isCard) payment = await startPayment(order);
  return { order: await getOrder(order.id), payment };
}

export async function startPayment(order) {
  const { bankOrderId, formUrl } = await registerPayment({
    orderId: order.id, amount: order.total, description: `SARGYT #${order.id}`,
  });
  await q(`UPDATE orders SET bank_order_id=$2, payment_status='pending', updated_at=now() WHERE id=$1`, [order.id, bankOrderId]);
  return { formUrl };
}

/** Сверка оплаты с банком; переводит заказ в 'new' при успехе */
export async function syncPayment(orderId, mockResult) {
  const o = await one('SELECT * FROM orders WHERE id=$1', [orderId]);
  if (!o || o.payment_method !== 'card' || o.status !== 'awaiting_payment' || !o.bank_order_id) return o;
  const st = await checkPayment(o.bank_order_id, mockResult);
  if (st === 'paid') {
    return one(`UPDATE orders SET payment_status='paid', status='new', updated_at=now()
                WHERE id=$1 AND status='awaiting_payment' RETURNING *`, [orderId]);
  }
  if (st === 'failed') {
    return one(`UPDATE orders SET payment_status='failed', updated_at=now() WHERE id=$1 RETURNING *`, [orderId]);
  }
  return o;
}

export async function changeStatus(order, status, reason) {
  const updated = await one(
    `UPDATE orders SET status=$2, reject_reason=$3, updated_at=now() WHERE id=$1 AND status=$4 RETURNING *`,
    [order.id, status, reason || null, order.status],
  );
  if (!updated) fail(409, 'status_changed', 'Order status was changed, refresh');
  if ((status === 'rejected' || status === 'cancelled') && order.payment_status === 'paid') {
    const ok = await refundPayment(order.bank_order_id, order.total);
    if (ok) await q(`UPDATE orders SET payment_status='refunded' WHERE id=$1`, [order.id]);
  }
  return getOrder(order.id);
}

export async function getOrder(id) {
  const o = await one(
    `SELECT o.*, v.name_ru AS venue_name_ru, v.name_tk AS venue_name_tk, v.phone AS venue_phone, v.prep_minutes
     FROM orders o JOIN venues v ON v.id=o.venue_id WHERE o.id=$1`, [id],
  );
  if (!o) return null;
  o.items = await many('SELECT product_id, name_ru, name_tk, price, qty FROM order_items WHERE order_id=$1 ORDER BY id', [id]);
  return o;
}

/** Фоновая задача: сверка зависших оплат и отмена неоплаченных через 20 минут */
export function startPaymentSweeper(log) {
  const tick = async () => {
    try {
      const pending = await many(
        `SELECT id, created_at FROM orders WHERE status='awaiting_payment' AND created_at < now() - interval '1 minute'`,
      );
      for (const p of pending) {
        const o = await syncPayment(p.id);
        if (o?.status === 'awaiting_payment' && new Date(p.created_at) < Date.now() - 20 * 60_000) {
          await q(`UPDATE orders SET status='cancelled', payment_status='failed', updated_at=now()
                   WHERE id=$1 AND status='awaiting_payment'`, [p.id]);
        }
      }
    } catch (e) { log.error(e, 'payment sweeper'); }
  };
  return setInterval(tick, 60_000);
}
