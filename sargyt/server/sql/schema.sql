-- SARGYT — схема базы данных (PostgreSQL 14+)
-- Суммы в манатах (TMT), numeric(12,2)

CREATE TABLE IF NOT EXISTS cities (
  id        smallint PRIMARY KEY,
  code      text UNIQUE NOT NULL,
  name_ru   text NOT NULL,
  name_tk   text NOT NULL,
  lat       double precision NOT NULL,
  lng       double precision NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id          bigserial PRIMARY KEY,
  phone       text UNIQUE NOT NULL,            -- +9936XXXXXXX
  name        text,
  role        text NOT NULL DEFAULT 'customer' CHECK (role IN ('customer','partner','admin')),
  lang        text NOT NULL DEFAULT 'tk' CHECK (lang IN ('tk','ru')),
  blocked     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS otp_codes (
  phone       text PRIMARY KEY,
  code_hash   text NOT NULL,
  expires_at  timestamptz NOT NULL,
  attempts    int NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS venues (
  id                 bigserial PRIMARY KEY,
  owner_id           bigint NOT NULL REFERENCES users(id),
  type               text NOT NULL CHECK (type IN ('restaurant','cafe','grocery','pharmacy','shop')),
  name_ru            text NOT NULL,
  name_tk            text NOT NULL,
  description_ru     text,
  description_tk     text,
  city_id            smallint NOT NULL REFERENCES cities(id),
  address            text NOT NULL,
  lat                double precision NOT NULL,
  lng                double precision NOT NULL,
  phone              text NOT NULL,
  logo_url           text,
  status             text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','blocked')),
  is_open            boolean NOT NULL DEFAULT false,
  commission_pct     numeric(5,2) NOT NULL DEFAULT 12.00 CHECK (commission_pct BETWEEN 0 AND 50),
  delivery_fee       numeric(12,2) NOT NULL DEFAULT 0,
  min_order          numeric(12,2) NOT NULL DEFAULT 0,
  delivery_radius_km numeric(5,2) NOT NULL DEFAULT 5,
  prep_minutes       int NOT NULL DEFAULT 30,
  accepts_cash       boolean NOT NULL DEFAULT true,
  -- договор
  legal_name         text,          -- ИП/ХО название
  tax_id             text,
  contract_no        text,
  contract_signed_at date,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS venues_city_idx ON venues(city_id, status, type);
CREATE INDEX IF NOT EXISTS venues_owner_idx ON venues(owner_id);

CREATE TABLE IF NOT EXISTS categories (
  id        bigserial PRIMARY KEY,
  venue_id  bigint NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  name_ru   text NOT NULL,
  name_tk   text NOT NULL,
  sort      int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS categories_venue_idx ON categories(venue_id);

CREATE TABLE IF NOT EXISTS products (
  id              bigserial PRIMARY KEY,
  venue_id        bigint NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  category_id     bigint REFERENCES categories(id) ON DELETE SET NULL,
  name_ru         text NOT NULL,
  name_tk         text NOT NULL,
  description_ru  text,
  description_tk  text,
  price           numeric(12,2) NOT NULL CHECK (price >= 0),
  image_url       text,
  available       boolean NOT NULL DEFAULT true,
  sort            int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS products_venue_idx ON products(venue_id, available);
CREATE INDEX IF NOT EXISTS products_search_idx ON products USING gin (to_tsvector('simple', name_ru || ' ' || name_tk));

CREATE TABLE IF NOT EXISTS orders (
  id                 bigserial PRIMARY KEY,
  user_id            bigint NOT NULL REFERENCES users(id),
  venue_id           bigint NOT NULL REFERENCES venues(id),
  status             text NOT NULL CHECK (status IN
                       ('awaiting_payment','new','accepted','preparing','on_the_way','delivered','cancelled','rejected')),
  payment_method     text NOT NULL CHECK (payment_method IN ('card','cash')),
  payment_status     text NOT NULL DEFAULT 'none' CHECK (payment_status IN ('none','pending','paid','failed','refunded')),
  bank_order_id      text,
  subtotal           numeric(12,2) NOT NULL,
  delivery_fee       numeric(12,2) NOT NULL,
  total              numeric(12,2) NOT NULL,
  commission_pct     numeric(5,2) NOT NULL,
  commission_amount  numeric(12,2) NOT NULL,   -- считается от subtotal (без доставки)
  address            text NOT NULL,
  lat                double precision,
  lng                double precision,
  phone              text NOT NULL,
  comment            text,
  reject_reason      text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS orders_user_idx  ON orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_venue_idx ON orders(venue_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS order_items (
  id          bigserial PRIMARY KEY,
  order_id    bigint NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  bigint REFERENCES products(id) ON DELETE SET NULL,
  name_ru     text NOT NULL,
  name_tk     text NOT NULL,
  price       numeric(12,2) NOT NULL,
  qty         int NOT NULL CHECK (qty BETWEEN 1 AND 99)
);

INSERT INTO cities (id, code, name_ru, name_tk, lat, lng) VALUES
  (1, 'ashgabat',   'Ашхабад',   'Aşgabat',   37.9601, 58.3261),
  (2, 'mary',       'Мары',      'Mary',      37.5936, 61.8302),
  (3, 'balkanabat', 'Балканабат','Balkanabat',39.5108, 54.3672)
ON CONFLICT (id) DO NOTHING;
