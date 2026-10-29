import { config } from '../config.js';
import { one } from '../db.js';
import { syncPayment } from '../orders-service.js';

const page = (title, body) => `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>
<style>body{font-family:system-ui,sans-serif;display:flex;min-height:90vh;align-items:center;justify-content:center;
text-align:center;background:#f6f7f9;color:#1b1f24;margin:0;padding:16px}.c{max-width:360px}
.b{display:block;margin:10px 0;padding:14px;border-radius:12px;text-decoration:none;font-weight:600}
.ok{background:#0a8f5a;color:#fff}.no{background:#e5e7eb;color:#1b1f24}h2{margin:.2em 0}</style></head>
<body><div class="c">${body}</div></body></html>`;

export default async function payRoutes(app) {
  // Возврат из платёжной формы банка. Приложение отслеживает этот URL во WebView и закрывает его.
  app.get('/return', async (req, reply) => {
    const id = Number(req.query.order);
    const o = id ? await syncPayment(id) : null;
    const paid = o?.payment_status === 'paid';
    reply.type('text/html').send(page('SARGYT', paid
      ? '<h2>✅ Töleg kabul edildi</h2><p>Оплата прошла. Вернитесь в приложение.</p>'
      : '<h2>❌ Töleg geçmedi</h2><p>Оплата не прошла. Вернитесь в приложение и попробуйте снова.</p>'));
  });

  // Заглушка банковской формы — только для режима PAYMENT_PROVIDER=mock
  if (config.payment.provider === 'mock') {
    app.get('/mock', async (req, reply) => {
      const o = await one('SELECT id, total FROM orders WHERE id=$1', [Number(req.query.order)]);
      if (!o) return reply.code(404).send('not found');
      const base = `/pay/mock/complete?order=${o.id}`;
      reply.type('text/html').send(page('Test bank', `<h2>Test bank</h2><p>Заказ #${o.id}: <b>${o.total.toFixed(2)} TMT</b></p>
        <a class="b ok" href="${base}&result=paid">Tölemek / Оплатить</a>
        <a class="b no" href="${base}&result=failed">Ýatyrmak / Отмена</a>`));
    });
    app.get('/mock/complete', async (req, reply) => {
      const id = Number(req.query.order);
      await syncPayment(id, req.query.result === 'paid' ? 'paid' : 'failed');
      reply.redirect(`/pay/return?order=${id}`);
    });
  }
}
