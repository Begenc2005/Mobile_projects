// Все настройки — через переменные окружения (.env на сервере Türkmentelekom)
const env = process.env;

export const config = {
  port: Number(env.PORT || 8080),
  host: env.HOST || '0.0.0.0',
  publicUrl: env.PUBLIC_URL || 'http://localhost:8080',
  databaseUrl: env.DATABASE_URL || 'postgres://postgres@localhost:5432/sargyt',
  jwtSecret: env.JWT_SECRET || 'dev-secret-change-me',
  // dev: код OTP возвращается в ответе и пишется в лог (НЕ включать в проде)
  devOtp: env.DEV_OTP === '1',
  defaultCommissionPct: Number(env.DEFAULT_COMMISSION_PCT || 12),

  sms: {
    provider: env.SMS_PROVIDER || 'log',   // 'log' | 'http'
    url: env.SMS_HTTP_URL || '',           // шлюз SMS (TMCELL / агрегатор), шаблон с {phone} и {text}
    token: env.SMS_HTTP_TOKEN || '',
  },

  payment: {
    provider: env.PAYMENT_PROVIDER || 'mock', // 'mock' | 'rbs'
    // REST-шлюз эквайринга банка (тип RBS: register.do / getOrderStatus.do).
    // Точный URL, логин и пароль мерчанта выдаёт банк-эквайер (Halkbank, Senagat, Rysgal, TDB и т.д.)
    baseUrl: env.PAYMENT_BASE_URL || '',
    userName: env.PAYMENT_USER || '',
    password: env.PAYMENT_PASSWORD || '',
    currency: env.PAYMENT_CURRENCY || '934', // ISO 4217: TMT
    language: env.PAYMENT_LANGUAGE || 'ru',
    sessionTimeoutSecs: Number(env.PAYMENT_TIMEOUT || 900),
  },
};

if (!config.devOtp && config.jwtSecret === 'dev-secret-change-me' && env.NODE_ENV === 'production') {
  throw new Error('JWT_SECRET must be set in production');
}
