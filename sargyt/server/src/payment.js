import { config } from './config.js';

/**
 * Оплата туркменскими банковскими картами (Altyn Asyr и др.).
 * Адаптер 'rbs' — REST-протокол register.do / getOrderStatus.do, который используют
 * платёжные шлюзы эквайринга. Параметры подключения выдаёт банк при заключении договора
 * эквайринга; перед запуском сверить протокол с документацией банка.
 * Адаптер 'mock' — для разработки: страница-заглушка «Оплатить / Отменить».
 */

const toMinor = (amount) => Math.round(amount * 100); // манаты -> тенге (копейки)

export async function registerPayment({ orderId, amount, description }) {
  const p = config.payment;
  const returnUrl = `${config.publicUrl}/pay/return?order=${orderId}`;

  if (p.provider === 'mock') {
    const bankOrderId = `mock-${orderId}-${Date.now()}`;
    return { bankOrderId, formUrl: `${config.publicUrl}/pay/mock?bank=${bankOrderId}&order=${orderId}` };
  }

  const params = new URLSearchParams({
    userName: p.userName,
    password: p.password,
    orderNumber: `Y${orderId}-${Date.now().toString(36)}`, // уникален для банка, даже при повторной попытке
    amount: String(toMinor(amount)),
    currency: p.currency,
    returnUrl,
    failUrl: returnUrl,
    language: p.language,
    description: description.slice(0, 99),
    sessionTimeoutSecs: String(p.sessionTimeoutSecs),
  });
  const res = await fetch(`${p.baseUrl}/register.do`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params,
  });
  const data = await res.json();
  if (!data.orderId || !data.formUrl) {
    throw new Error(`Payment register failed: ${data.errorCode} ${data.errorMessage || ''}`);
  }
  return { bankOrderId: data.orderId, formUrl: data.formUrl };
}

/** Возвращает 'paid' | 'pending' | 'failed' */
export async function checkPayment(bankOrderId, mockResult) {
  const p = config.payment;
  if (p.provider === 'mock') return mockResult || 'pending';

  const params = new URLSearchParams({ userName: p.userName, password: p.password, orderId: bankOrderId });
  const res = await fetch(`${p.baseUrl}/getOrderStatus.do`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params,
  });
  const data = await res.json();
  // OrderStatus: 0 — зарегистрирован, 1 — холд, 2 — оплачен, 3 — отменён, 4 — возврат, 5 — ACS, 6 — отклонён
  switch (Number(data.OrderStatus)) {
    case 2: return 'paid';
    case 0: case 1: case 5: return 'pending';
    default: return 'failed';
  }
}

export async function refundPayment(bankOrderId, amount) {
  const p = config.payment;
  if (p.provider === 'mock') return true;
  const params = new URLSearchParams({
    userName: p.userName, password: p.password, orderId: bankOrderId, amount: String(toMinor(amount)),
  });
  const res = await fetch(`${p.baseUrl}/refund.do`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params,
  });
  const data = await res.json();
  return String(data.errorCode) === '0';
}
