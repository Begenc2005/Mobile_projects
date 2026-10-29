import { one, many } from '../db.js';
import { fail } from '../app.js';

// Расстояние по прямой в км (haversine) — без PostGIS, чтобы сервер был лёгким
export const DIST_SQL = (latP, lngP) => `
  (6371 * 2 * asin(sqrt(
    power(sin(radians(v.lat - ${latP}) / 2), 2) +
    cos(radians(${latP})) * cos(radians(v.lat)) * power(sin(radians(v.lng - ${lngP}) / 2), 2)
  )))`;

const VENUE_PUBLIC = `v.id, v.type, v.name_ru, v.name_tk, v.description_ru, v.description_tk, v.city_id,
  v.address, v.lat, v.lng, v.phone, v.logo_url, v.is_open, v.delivery_fee, v.min_order,
  v.delivery_radius_km, v.prep_minutes, v.accepts_cash`;

export default async function catalogRoutes(app) {
  app.get('/cities', async () => many('SELECT * FROM cities ORDER BY id'));

  // Заведения рядом: ?lat=&lng=&type=&city=&q=
  app.get('/venues', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          lat: { type: 'number' }, lng: { type: 'number' },
          type: { enum: ['restaurant', 'cafe', 'grocery', 'pharmacy', 'shop'] },
          city: { type: 'integer' }, q: { type: 'string', maxLength: 60 },
          limit: { type: 'integer', minimum: 1, maximum: 100, default: 50 },
        },
      },
    },
  }, async (req) => {
    const { lat, lng, type, city, q, limit } = req.query;
    const hasGeo = Number.isFinite(lat) && Number.isFinite(lng);
    const params = [];
    const where = [`v.status = 'active'`];
    let dist = 'NULL::float8';
    if (hasGeo) {
      params.push(lat, lng);
      dist = DIST_SQL('$1', '$2');
    }
    if (type) { params.push(type); where.push(`v.type = $${params.length}`); }
    if (city) { params.push(city); where.push(`v.city_id = $${params.length}`); }
    if (q) {
      params.push(`%${q}%`);
      const i = params.length;
      where.push(`(v.name_ru ILIKE $${i} OR v.name_tk ILIKE $${i} OR EXISTS (
        SELECT 1 FROM products p WHERE p.venue_id = v.id AND p.available AND (p.name_ru ILIKE $${i} OR p.name_tk ILIKE $${i})))`);
    }
    params.push(limit);
    const rows = await many(
      `SELECT ${VENUE_PUBLIC}, ${dist} AS distance_km FROM venues v
       WHERE ${where.join(' AND ')}
       ORDER BY v.is_open DESC, ${hasGeo ? 'distance_km' : 'v.id DESC'} LIMIT $${params.length}`,
      params,
    );
    return rows.map((r) => ({
      ...r,
      distance_km: r.distance_km == null ? null : Math.round(r.distance_km * 10) / 10,
      delivers_here: r.distance_km == null ? null : r.distance_km <= r.delivery_radius_km,
    }));
  });

  // Карточка заведения с меню
  app.get('/venues/:id', async (req) => {
    const id = Number(req.params.id);
    const venue = await one(`SELECT ${VENUE_PUBLIC} FROM venues v WHERE v.id=$1 AND v.status='active'`, [id]);
    if (!venue) fail(404, 'not_found');
    const [categories, products] = await Promise.all([
      many('SELECT id, name_ru, name_tk, sort FROM categories WHERE venue_id=$1 ORDER BY sort, id', [id]),
      many(`SELECT id, category_id, name_ru, name_tk, description_ru, description_tk, price, image_url
            FROM products WHERE venue_id=$1 AND available ORDER BY sort, id`, [id]),
    ]);
    return { ...venue, categories, products };
  });
}
