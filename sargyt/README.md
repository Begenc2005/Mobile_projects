# SARGYT — агрегатор доставки (Ашхабад · Мары · Балканабат)

Еда, продукты, аптеки, магазины. Заведения доставляют сами, агрегатор берёт комиссию 10–15% с суммы товаров.

## Состав

| Папка | Что это |
|---|---|
| `app/` | Мобильное приложение Flutter — **один код для Android и iOS**, языки TM/RU |
| `server/` | API на Node.js (Fastify) + PostgreSQL. Лёгкий: ~60 МБ ОЗУ |
| `panel/` | Веб-панель для заведений (заказы, меню, отчёт) и админа (заявки, договоры, комиссия, сверка). Открывается по адресу `/panel/` |
| `deploy/` | docker-compose, nginx, пример `.env` для сервера Türkmentelekom |

## Как работает

1. Клиент входит по SMS-коду, видит заведения рядом (по GPS), выбирает блюда/товары.
2. Платит картой Altyn Asyr (через платёжную страницу банка) или наличными.
3. Заказ появляется в панели заведения со звуком → «Принять» → «Готовится» → «В пути» → «Доставлен». Клиент видит статус в приложении.
4. Заведение подаёт заявку в панели → админ вписывает № договора и комиссию → заведение становится активным.
5. Расчёт: при оплате картой деньги приходят на счёт агрегатора, заведению перечисляется *сумма − комиссия*; при наличных заведение платит агрегатору комиссию. Отчёт за период — в панели.

## Запуск сервера (Türkmentelekom, Ubuntu 22/24)

```bash
apt install docker.io docker-compose-v2 nginx certbot python3-certbot-nginx
cd deploy && cp .env.example .env   # заполнить
docker compose up -d
cp nginx.conf /etc/nginx/sites-enabled/sargyt && certbot --nginx -d api.sargyt.tm
```
Без Docker: Node 20+, PostgreSQL 14+, `cd server && npm ci && npm run migrate && npm start`.
Демо-данные: `npm run seed`. Тесты: `DEV_OTP=1 ADMIN_PHONES=+99365000000 npm test`.

Минимальный VPS: 2 vCPU, 2–4 ГБ ОЗУ, 40 ГБ SSD.

## Сборка приложения

```bash
cd app && ./setup_platforms.sh
flutter build apk --release --dart-define=API_URL=https://api.sargyt.tm      # Android
flutter build ipa --release --dart-define=API_URL=https://api.sargyt.tm      # iOS (на Mac)
```
Геолокация работает без Google-сервисов (на Android — через системный LocationManager).

## Что нужно получить до запуска

- **Эквайринг**: договор с банком (Halkbank, Senagat, Rysgal, TDB и др.) на интернет-эквайринг Altyn Asyr → логин/пароль мерчанта и URL шлюза → в `.env`. Адаптер `server/src/payment.js` сделан под REST-протокол `register.do / getOrderStatus.do / refund.do` — сверить с документацией банка. До этого работает тестовый режим `PAYMENT_PROVIDER=mock`.
- **SMS-шлюз**: у оператора/агрегатора SMS → URL в `.env` (`SMS_HTTP_URL`).
- **Домен .tm** и **сервер** на Türkmentelekom.
- **Аккаунты** Google Play и Apple Developer для публикации; либо раздавать APK напрямую.

## Следующие шаги (не вошло в MVP)
Push-уведомления, карта с выбором точки, промокоды, рейтинги и отзывы, такси (отдельный модуль), выгрузка отчёта в Excel.
