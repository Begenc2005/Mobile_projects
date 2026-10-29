import { config } from './config.js';

// Отправка SMS. Провайдер 'http' — универсальный GET/POST на шлюз оператора.
export async function sendSms(phone, text, log) {
  if (config.sms.provider === 'log') {
    log?.info({ phone, text }, 'SMS (log provider)');
    return;
  }
  const url = config.sms.url
    .replace('{phone}', encodeURIComponent(phone))
    .replace('{text}', encodeURIComponent(text));
  const res = await fetch(url, {
    method: 'GET',
    headers: config.sms.token ? { Authorization: `Bearer ${config.sms.token}` } : {},
  });
  if (!res.ok) throw new Error(`SMS gateway error ${res.status}`);
}
