# Dost — местный мессенджер для Туркменистана

Этап 1: личные и групповые чаты, текст, фото, голосовые, реакции, ответы, редактирование и удаление, статусы «прочитано», «печатает…», «в сети». Интерфейс на туркменском и русском.

```
dost/
├── server/   — сервер на Go (REST + WebSocket + хранение медиа), PostgreSQL
├── deploy/   — docker-compose для сервера Türkmentelekom (Postgres + API + HTTPS)
├── app/      — приложение Flutter (один код → Android + iOS)
└── .github/workflows/build.yml — автосборка APK и iOS в GitHub
```

## Как сделано для слабого интернета

| Что | Как |
|---|---|
| Сообщения | WebSocket со сжатием permessage-deflate, короткие JSON-ключи |
| Фото | Сжатие на телефоне до 1280 px, JPEG 70% (4 МБ → ~150 КБ) |
| Голосовые | AAC 32 кбит/с моно, около 4 КБ в секунду |
| Списки и история | gzip, загрузка порциями по 50 |
| Обрыв связи | Очередь отправки, автоповтор, догрузка пропущенного (`/api/sync`), без дублей |
| Офлайн | Локальная база SQLite: чаты открываются мгновенно и без сети |
| Медиа | Кэш навсегда, докачка (Range), автозагрузку фото можно выключить |

## 1. Запуск сервера (Türkmentelekom VPS, Ubuntu)

```bash
# один раз: установить Docker
curl -fsSL https://get.docker.com | sh

cd dost/deploy
cp .env.example .env        # заполнить DOMAIN, DB_PASSWORD, DOST_SECRET (openssl rand -hex 32)
mkdir certs                 # fullchain.pem и privkey.pem для домена
docker compose up -d --build
curl https://ВАШ_ДОМЕН/health    # {"ok":true,...}
```

Пока SMS-шлюза нет, `DEV_MODE=1`: код входа показывается прямо в приложении. **Перед запуском для людей нужно поставить `DEV_MODE=0`** и указать `SMS_GATEWAY_URL` и `SMS_GATEWAY_TOKEN`. Формат запроса к шлюзу настраивается в `server/auth.go` → `httpSMS.Send`.

Проверка сервера одной командой: `cd server && go run ./tools/smoke http://localhost:8080` (нужен `DEV_MODE=1`).

## 2. Сборка приложения

Нужен Flutter (stable) и Android Studio, а для iOS — Mac с Xcode.

```bash
cd dost/app
flutter create --org tm.dost --project-name dost --platforms android,ios .
python3 tool/setup_platforms.py          # разрешения: микрофон, фото, контакты
flutter pub get
flutter run --dart-define=DOST_API=https://api.dost.tm               # на телефоне
flutter build apk --release --dart-define=DOST_API=https://api.dost.tm
```

Для теста без HTTPS (`http://IP:8080`) используйте `python3 tool/setup_platforms.py --allow-http`.

**Без своего компьютера:** загрузите папку в GitHub, и Actions сами соберут APK и iOS (вкладка Actions → Artifacts).

## Что дальше (этапы)

1. **Push-уведомления.** Сейчас сообщения приходят, когда приложение открыто. Варианты: фоновый сервис на Android и APNs на iOS; FCM — если Google доступен из ТМ.
2. Видео, файлы, стикеры, аудио- и видеозвонки (WebRTC + свой TURN-сервер).
3. Сквозное шифрование.
4. Кошелёк и переводы через банк-партнёр.
