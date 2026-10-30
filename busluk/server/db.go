package main

const schema = `
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS users(
  id bigserial PRIMARY KEY,
  phone text UNIQUE NOT NULL,
  name text NOT NULL DEFAULT '',
  blocked bool NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS sessions(
  th bytea PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  seen_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS otps(
  phone text PRIMARY KEY,
  ch bytea NOT NULL,
  exp timestamptz NOT NULL,
  tries int NOT NULL DEFAULT 0);

-- status: 0 активно, 1 скрыто владельцем, 2 заблокировано модератором, 3 истекло, 4 удалено
CREATE TABLE IF NOT EXISTS ads(
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users ON DELETE CASCADE,
  cat int NOT NULL,
  city int NOT NULL,
  region int NOT NULL,
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  price bigint NOT NULL DEFAULT 0,
  neg bool NOT NULL DEFAULT false,
  attrs jsonb NOT NULL DEFAULT '{}',
  photos text[] NOT NULL DEFAULT '{}',
  tel text NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  bumped_at timestamptz NOT NULL DEFAULT now(),
  vip_until timestamptz,
  views int NOT NULL DEFAULT 0,
  sx text NOT NULL DEFAULT '');

CREATE INDEX IF NOT EXISTS ads_feed  ON ads(status, bumped_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS ads_cat   ON ads(cat, status, bumped_at DESC);
CREATE INDEX IF NOT EXISTS ads_city  ON ads(city, status, bumped_at DESC);
CREATE INDEX IF NOT EXISTS ads_user  ON ads(user_id, status);
CREATE INDEX IF NOT EXISTS ads_vip   ON ads(vip_until) WHERE vip_until IS NOT NULL;
CREATE INDEX IF NOT EXISTS ads_sx    ON ads USING gin(sx gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ads_attrs ON ads USING gin(attrs jsonb_path_ops);

-- status: 0 создан, 1 оплачен, 2 отказ
CREATE TABLE IF NOT EXISTS payments(
  id bigserial PRIMARY KEY,
  order_no text UNIQUE NOT NULL,
  bank_id text NOT NULL DEFAULT '',
  user_id bigint NOT NULL,
  ad_id bigint NOT NULL,
  svc text NOT NULL,
  amount bigint NOT NULL,
  status smallint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz);
CREATE INDEX IF NOT EXISTS pay_pending ON payments(created_at) WHERE status=0;

CREATE TABLE IF NOT EXISTS reports(
  id bigserial PRIMARY KEY,
  ad_id bigint NOT NULL,
  user_id bigint,
  reason text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS reports_ad ON reports(ad_id);
`

func migrate() error {
	if _, err := db.Exec(schema); err != nil {
		return err
	}
	return nil
}
