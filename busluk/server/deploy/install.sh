#!/bin/sh
# Установка на чистый Ubuntu/Debian сервер. Запуск: sudo sh install.sh
set -e
apt-get update
apt-get install -y postgresql postgresql-contrib nginx certbot
PASS=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
sudo -u postgres psql -c "CREATE USER busluk PASSWORD '$PASS'" || true
sudo -u postgres psql -c "CREATE DATABASE busluk OWNER busluk" || true
sudo -u postgres psql -d busluk -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
id busluk >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin busluk
mkdir -p /var/lib/busluk/img && chown -R busluk /var/lib/busluk
install -m 755 ../busluk /usr/local/bin/busluk
if [ ! -f /etc/busluk.env ]; then
  sed "s#ПАРОЛЬ#$PASS#; s#замените-на-длинную-случайную-строку#$(head -c 24 /dev/urandom | base64 | tr -d '/+=')#" ../busluk.env.example > /etc/busluk.env
  chmod 600 /etc/busluk.env
  echo ">>> Заполните /etc/busluk.env (домен, SMPP, банк, ADMIN_TOKEN)"
fi
install -m 644 busluk.service /etc/systemd/system/busluk.service
systemctl daemon-reload && systemctl enable --now busluk
echo ">>> Сервер запущен. Дальше: nginx.conf -> /etc/nginx/sites-enabled/, затем certbot --nginx -d busluk.tm"
