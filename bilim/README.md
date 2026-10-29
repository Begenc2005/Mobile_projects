# Bilim — school and tutor in one phone

Android + iOS app (Flutter), Turkmen/Russian, server on Türkmentelekom.

## Structure
- `app/` — Flutter app (one codebase for Android and iOS)
- `server/` — API (FastAPI + SQLite), Docker, nginx
- `content/` — lessons in JSON (TK/RU) — the same files feed the app and the server
- `prototype/bilim.html` — a working web version for showing to people

## What's in the app
- 11 subjects: mathematics, physics, chemistry, biology, informatics, Turkmen, Russian, English, literature, history, geography
- Lesson = steps: theory → example → questions (multiple choice / answer input / true-false) → "Dünýä bilimi" (world knowledge)
- Hint, check, explanation of the mistake; a hint = the question goes into review
- Review using the Leitner method: 1, 2, 4, 8, 16, 32 days
- Points, daily streak, progress per subject
- Help: AI tutor (if a key is set on the server) → hint from the lessons → support ticket to a human
- Offline: lessons are inside the app, updated from the server with ETag; progress syncs when the internet is back
- Login by phone number + SMS code

## Server launch (Türkmentelekom VPS, 1–2 vCPU, 2 GB RAM is enough to start)
```bash
cp server/.env.example server/.env    # fill in ADMIN_TOKEN, SMS gateway
mkdir server/certs                     # fullchain.pem + privkey.pem
docker compose -f server/docker-compose.yml up -d --build
```
Tests: `cd server && pip install -r requirements.txt pytest && pytest`

## Building the app
```bash
cd app
flutter create . --platforms=android,ios --org tm.bilim   # generates the android/ios folders
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release --dart-define=API=https://bilim.tm
flutter build ipa --release --dart-define=API=https://bilim.tm   # on a Mac with Xcode
```

## Adding content
One file per subject `content/<subject>.json`, steps of type `theory | example | choice | input | truefalse | world`.
Every text is `{"tk": "...", "ru": "..."}`. In `input` several correct answers are separated with `|`.
After editing, rebuild `manifest.json` and restart the server — apps will pull it in themselves.
Lessons are written in our own words to the curriculum topics; textbook texts are only with the permission of the Ministry of Education/publisher.
