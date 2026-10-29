// Сквозной тест: клиент -> заказ -> оплата (mock) -> заведение -> доставка -> отчёт
// Запуск: DEV_OTP=1 ADMIN_PHONES=+99365000000 DATABASE_URL=... npm test
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { build } from '../src/app.js';
import { pool } from '../src/db.js';

const app = await build({ logger: false });
after(async () => { await app.close(); await pool.end(); });

const call = async (method, url, { token, body } = {}) => {
  const res = await app.inject({ method, url, payload: body, headers: token ? { authorization: `Bearer ${token}` } : {} });
  return { status: res.statusCode, body: res.headers['content-type']?.includes('json') ? res.json() : res.body };
};
const login = async (phone, name) => {
  const otp = await call('POST', '/api/auth/otp', { body: { phone } });
  assert.equal(otp.status, 200, JSON.stringify(otp.body));
  const v = await call('POST', '/api/auth/verify', { body: { phone, code: otp.body.devCode, name, lang: 'ru' } });
  assert.equal(v.status, 200);
  return v.body.token;
};
const rnd = () => String(Math.floor(1e6 + Math.random() * 8e6)).padStart(7, '0');

test('full order flow', async () => {
  // партнёр подаёт заявку
  let partner = await login(`+9936${rnd()}`, 'Partner');
  const created = await call('POST', '/api/partner/venues', { token: partner, body: {
    type: 'restaurant', name_ru: 'Тест кафе', name_tk: 'Synag kafe', city_id: 1, address: 'Bitarap Türkmenistan 1',
    lat: 37.94, lng: 58.38, phone: '861234567', delivery_fee: 10, min_order: 20, delivery_radius_km: 5,
  } });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  partner = created.body.token;
  const venueId = created.body.venue.id;
  assert.equal(created.body.venue.status, 'pending');
  assert.equal(created.body.venue.phone, '+99361234567');

  // нельзя открыть до одобрения
  assert.equal((await call('PATCH', `/api/partner/venues/${venueId}`, { token: partner, body: { is_open: true } })).status, 409);
  // партнёр не может менять комиссию
  assert.equal((await call('PATCH', `/api/partner/venues/${venueId}`, { token: partner, body: { commission_pct: 1 } })).status, 400);

  const cat = await call('POST', `/api/partner/venues/${venueId}/categories`, { token: partner, body: { name_ru: 'Горячее', name_tk: 'Gyzgyn' } });
  const p1 = await call('POST', `/api/partner/venues/${venueId}/products`, { token: partner, body: { category_id: cat.body.id, name_ru: 'Плов', name_tk: 'Palow', price: 45 } });
  const p2 = await call('POST', `/api/partner/venues/${venueId}/products`, { token: partner, body: { name_ru: 'Чай', name_tk: 'Çaý', price: 7.5 } });
  assert.equal(p1.status, 200);

  // админ одобряет
  const admin = await login('+99365000000', 'Admin');
  assert.equal((await call('PATCH', `/api/admin/venues/${venueId}`, { token: admin, body: { status: 'active' } })).status, 409);
  const appr = await call('PATCH', `/api/admin/venues/${venueId}`, { token: admin, body: { status: 'active', contract_no: 'YT-001', commission_pct: 15 } });
  assert.equal(appr.body.status, 'active');
  assert.equal((await call('PATCH', `/api/partner/venues/${venueId}`, { token: partner, body: { is_open: true } })).body.is_open, true);
  // обычный пользователь не админ
  assert.equal((await call('GET', '/api/admin/stats', { token: partner })).status, 403);

  // клиент ищет рядом
  const client = await login(`+9937${rnd()}`, 'Client');
  const near = await call('GET', '/api/venues?lat=37.941&lng=58.381&type=restaurant');
  const found = near.body.find((v) => v.id === venueId);
  assert.ok(found && found.delivers_here && found.distance_km < 1);
  assert.equal(found.commission_pct, undefined, 'commission is not public');
  const menu = await call('GET', `/api/venues/${venueId}`);
  assert.equal(menu.body.products.length, 2);

  // слишком далеко
  const far = await call('POST', '/api/orders', { token: client, body: {
    venue_id: venueId, items: [{ product_id: p1.body.id, qty: 1 }], address: 'Mary', lat: 37.59, lng: 61.83, phone: '+99371234567', payment_method: 'cash' } });
  assert.equal(far.body.error, 'too_far');
  // меньше минимальной суммы
  const small = await call('POST', '/api/orders', { token: client, body: {
    venue_id: venueId, items: [{ product_id: p2.body.id, qty: 1 }], address: 'Addr 1', phone: '+99371234567', payment_method: 'cash' } });
  assert.equal(small.body.error, 'below_min_order');

  // заказ картой
  const ord = await call('POST', '/api/orders', { token: client, body: {
    venue_id: venueId, items: [{ product_id: p1.body.id, qty: 2 }, { product_id: p2.body.id, qty: 2 }],
    address: 'Bitarap Türkmenistan 10, kw 5', lat: 37.942, lng: 58.382, phone: '71234567', payment_method: 'card' } });
  assert.equal(ord.status, 200, JSON.stringify(ord.body));
  const o = ord.body.order;
  assert.equal(o.subtotal, 105);
  assert.equal(o.total, 115);
  assert.equal(o.commission_amount, 15.75); // 15% от 105
  assert.equal(o.status, 'awaiting_payment');
  assert.match(ord.body.payment.formUrl, /\/pay\/mock/);

  // заведение не видит неоплаченный заказ
  assert.equal((await call('GET', '/api/partner/orders?active=true', { token: partner })).body.length, 0);

  // оплата на тестовой странице банка
  const paid = await call('GET', `/pay/mock/complete?order=${o.id}&result=paid`);
  assert.equal(paid.status, 302);
  const ret = await call('GET', `/pay/return?order=${o.id}`);
  assert.match(ret.body, /Töleg kabul edildi/);
  assert.equal((await call('GET', `/api/orders/${o.id}`, { token: client })).body.status, 'new');

  // чужой клиент не видит заказ
  const other = await login(`+9936${rnd()}`, 'Other');
  assert.equal((await call('GET', `/api/orders/${o.id}`, { token: other })).status, 404);

  // заведение ведёт заказ
  const active = await call('GET', '/api/partner/orders?active=true', { token: partner });
  assert.equal(active.body.length, 1);
  assert.equal(active.body[0].items.length, 2);
  assert.equal((await call('POST', `/api/partner/orders/${o.id}/status`, { token: partner, body: { status: 'delivered' } })).status, 409);
  for (const s of ['accepted', 'preparing', 'on_the_way', 'delivered']) {
    const r = await call('POST', `/api/partner/orders/${o.id}/status`, { token: partner, body: { status: s } });
    assert.equal(r.body.status, s);
  }
  // после принятия клиент отменить не может
  assert.equal((await call('POST', `/api/orders/${o.id}/cancel`, { token: client })).status, 409);

  // заказ наличными, отклонён заведением
  const cash = await call('POST', '/api/orders', { token: client, body: {
    venue_id: venueId, items: [{ product_id: p1.body.id, qty: 1 }], address: 'Addr 2', phone: '71234567', payment_method: 'cash' } });
  assert.equal(cash.body.order.status, 'new');
  const rej = await call('POST', `/api/partner/orders/${cash.body.order.id}/status`, { token: partner, body: { status: 'rejected', reason: 'Нет плова' } });
  assert.equal(rej.body.status, 'rejected');

  // заказ наличными, доставлен
  const cash2 = await call('POST', '/api/orders', { token: client, body: {
    venue_id: venueId, items: [{ product_id: p1.body.id, qty: 1 }], address: 'Addr 3', phone: '71234567', payment_method: 'cash' } });
  for (const s of ['accepted', 'on_the_way', 'delivered']) {
    await call('POST', `/api/partner/orders/${cash2.body.order.id}/status`, { token: partner, body: { status: s } });
  }

  // отчёт: карта 115 (комиссия 15.75), наличные 55 (комиссия 6.75)
  const today = new Date().toISOString().slice(0, 10);
  const rep = await call('GET', `/api/partner/report?venue_id=${venueId}&from=${today}&to=${today}`, { token: partner });
  assert.deepEqual(rep.body, {
    orders: 2, gmv: 170, commission: 22.5, card_total: 115, cash_total: 55, payable_to_venue: 99.25, owed_by_venue: 6.75,
  });
  const adm = await call('GET', `/api/admin/report?from=${today}&to=${today}`, { token: admin });
  assert.ok(adm.body.venues.some((v) => v.id === venueId && v.commission === 22.5));

  // история и повтор заказа
  assert.ok((await call('GET', '/api/orders', { token: client })).body.length >= 3);
  const rep2 = await call('GET', `/api/orders/${o.id}/repeat`, { token: client });
  assert.equal(rep2.body.items.length, 2);
});

test('card payment failure and cancel', async () => {
  const client = await login(`+9936${rnd()}`, 'C2');
  const venues = (await call('GET', '/api/venues?city=3')).body;
  const v = (await call('GET', `/api/venues/${venues[0].id}`)).body;
  const ord = await call('POST', '/api/orders', { token: client, body: {
    venue_id: v.id, items: [{ product_id: v.products[0].id, qty: 1 }], address: 'Balkanabat', phone: '61111111', payment_method: 'card' } });
  const id = ord.body.order.id;
  await call('GET', `/pay/mock/complete?order=${id}&result=failed`);
  const o = (await call('GET', `/api/orders/${id}`, { token: client })).body;
  assert.equal(o.payment_status, 'failed');
  assert.equal(o.status, 'awaiting_payment');
  const retry = await call('POST', `/api/orders/${id}/pay`, { token: client });
  assert.match(retry.body.formUrl, /pay\/mock/);
  assert.equal((await call('POST', `/api/orders/${id}/cancel`, { token: client })).body.status, 'cancelled');
});

test('auth validation', async () => {
  assert.equal((await call('POST', '/api/auth/otp', { body: { phone: '12345' } })).status, 400);
  const phone = `+9936${rnd()}`;
  await call('POST', '/api/auth/otp', { body: { phone } });
  assert.equal((await call('POST', '/api/auth/otp', { body: { phone } })).status, 429);
  for (let i = 0; i < 5; i++) await call('POST', '/api/auth/verify', { body: { phone, code: '0000' } });
  assert.equal((await call('POST', '/api/auth/verify', { body: { phone, code: '0000' } })).body.error, 'code_expired');
  assert.equal((await call('GET', '/api/orders')).status, 401);
});
