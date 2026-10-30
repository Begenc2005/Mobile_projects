# Buşluk — маркетплейс объявлений (Android + iOS + сервер)

Авто, недвижимость, услуги мастеров и ещё 10 разделов (≈100 категорий). Интерфейс на туркменском и русском. Вход по номеру телефона и SMS-коду. Доход — платное поднятие и VIP через банковский эквайринг.

```
server/    Go-сервер (один бинарник) + PostgreSQL — ставится на сервер Türkmentelekom
android/   нативное приложение Kotlin, без библиотек
ios/       нативное приложение SwiftUI, без библиотек
```

## Почему быстро и экономно

| Что | Как |
|---|---|
| Размер Android | без AndroidX/Compose, интерфейс кодом, R8 → APK около 0,3–0,5 МБ |
| Размер iOS | только системные фреймворки, `-Osize` → около 1–3 МБ |
| Страница ленты (20 объявлений) | короткие ключи JSON + gzip → ≈ 0,6–1 КБ |
| Справочник категорий/городов | 5 КБ один раз, дальше `304 Not Modified` (ETag) |
| Иконки категорий | эмодзи — 0 байт картинок |
| Фото в ленте | миниатюра 320 px ≈ 10–20 КБ; полное фото — только в карточке |
| Фото при подаче | телефон сжимает до 1280 px ≈ 200 КБ вместо 4–8 МБ |
| Повторные фото | кэш на диске навсегда (имена не меняются) |
| Подсказки поиска | запрос только после паузы 0,4 с |
| Избранное | хранится на телефоне, трафика нет |

**Поиск:** понимает опечатки (`toyta` → Toyota), кириллицу и латиницу одинаково (`тойота` = `toyota`, `santehnik` = `сантехник`), подсказывает разделы при наборе, фильтры по городу/велаяту, цене, фото и характеристикам (марка, год, пробег, комнаты, площадь…).

## 1. Сервер

Нужны: Linux (Ubuntu/Debian), PostgreSQL 13+, домен с HTTPS (приложения работают только по HTTPS).

```sh
cd server/deploy
sudo sh install.sh                       # PostgreSQL, пользователь, служба systemd
sudo nano /etc/busluk.env                # домен, SMPP, банк, ADMIN_TOKEN
sudo cp nginx.conf /etc/nginx/sites-enabled/busluk && sudo certbot --nginx -d busluk.tm
sudo systemctl restart busluk nginx
```

Готовый бинарник `server/busluk` — Linux x86-64. Пересборка (интернет не нужен, зависимости в `vendor/`): `go build -o busluk .` (Go 1.22+).

**SMS.** Заполните `SMPP_*` данными от TMCell/Altyn Asyr (адрес SMSC, логин, имя отправителя). Пока `SMPP_HOST` пуст — коды пишутся в журнал (`journalctl -u busluk`).

**Оплата.** Заполните `PAY_URL`, `PAY_USER`, `PAY_PASS` из договора эквайринга (Halkbank / Senagat / Rysgal — REST-шлюз `register.do`). Пока пусто — тестовая оплата одной кнопкой. Услуга включается автоматически после оплаты; если клиент закрыл браузер — сервер сам проверит платёж в течение 5 минут. Цены — `PRICE_*` в TMT.

**Модерация:** `https://busluk.tm/admin` (пароль — `ADMIN_TOKEN`): жалобы, блокировка объявлений и авторов, подарить VIP, выручка.

**Проверка магазинами.** `DEMO_PHONE` + `DEMO_CODE` — вход без SMS для ревьюеров Apple/Google.

## 2. Android

1. Откройте папку `android` в Android Studio.
2. В `app/build.gradle.kts` укажите адрес сервера (`BASE`).
3. Build → Generate Signed App Bundle/APK → release.

minSdk 24 (Android 7+). Разрешение только одно — интернет.

## 3. iOS

На Mac с Xcode 15+:

```sh
brew install xcodegen
cd ios && xcodegen        # создаст Busluk.xcodeproj
open Busluk.xcodeproj
```

Адрес сервера — `Api.base` в `Busluk/Api.swift`. Выберите свою команду (Signing), затем Product → Archive. iOS 16+. Код из SMS подставляется автоматически.

Без XcodeGen: новый проект iOS App (SwiftUI) с именем Busluk → удалите созданные файлы → перетащите содержимое `ios/Busluk` → добавьте URL Type со схемой `busluk`.

## API (кратко)

| Метод | Путь | Что делает |
|---|---|---|
| GET | `/v1/meta` | категории, характеристики, города, цены (ETag) |
| POST | `/v1/auth/send` `{phone}` | SMS-код |
| POST | `/v1/auth/verify` `{phone, code}` | токен |
| GET | `/v1/ads?q=&g=&c=&r=&pmin=&pmax=&f=brand:toyota,year:2010-2018&s=new\|cheap\|dear&ph=1&o=` | лента/поиск |
| GET | `/v1/suggest?q=` | подсказки |
| GET/POST/PUT/DELETE | `/v1/ads/{id}` | карточка / создать / изменить / удалить |
| POST | `/v1/ads/{id}/state` `{st:0\|1}` | скрыть / вернуть (истёкшее продлевается бесплатно) |
| POST | `/v1/photo` (тело — JPEG) | загрузить фото |
| GET | `/v1/my/ads` | мои объявления |
| POST | `/v1/pay` `{ad, svc: bump\|vip7\|vip30}` | ссылка на оплату |

Объявление активно 30 дней, VIP — пока оплачен. Лимит — 20 новых объявлений в сутки на номер.
