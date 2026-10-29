// Демо-данные: по несколько заведений в Ашхабаде, Мары и Балканабате
import { pool, one } from './db.js';

const partner = await one(
  `INSERT INTO users (phone, name, role) VALUES ('+99361000001','Demo partner','partner')
   ON CONFLICT (phone) DO UPDATE SET role='partner' RETURNING id`);

const venues = [
  { city: 1, type: 'restaurant', ru: 'Чайхана «Беркарар»', tk: '«Berkarar» çaýhanasy', lat: 37.9351, lng: 58.3880, fee: 10, min: 30,
    menu: { 'Горячее|Gyzgyn naharlar': [['Плов|Palow', 45], ['Манты|Manty', 40], ['Шашлык из баранины|Goýun şaşlygy', 55], ['Дограма|Dogroma', 35]],
             'Напитки|Içgiler': [['Зелёный чай|Gök çaý', 8], ['Айран|Aýran', 10], ['Компот|Kompot', 9]] } },
  { city: 1, type: 'cafe', ru: 'Кафе «Ýyldyz»', tk: '«Ýyldyz» kafesi', lat: 37.9450, lng: 58.3790, fee: 8, min: 20,
    menu: { 'Выпечка|Bişirilen önümler': [['Ишлекли|Işlekli', 30], ['Гутап с мясом|Etli gutap', 12], ['Самса|Somsa', 10]],
            'Кофе|Kofe': [['Капучино|Kapuçino', 25], ['Латте|Latte', 27], ['Американо|Amerikano', 20]] } },
  { city: 1, type: 'grocery', ru: 'Маркет «Gündelik»', tk: '«Gündelik» market', lat: 37.9560, lng: 58.3600, fee: 7, min: 40,
    menu: { 'Молочные|Süýt önümleri': [['Молоко 1 л|Süýt 1 l', 14], ['Сыр 400 г|Peýnir 400 g', 48], ['Яйца 10 шт|Ýumurtga 10 sany', 22]],
            'Хлеб|Çörek': [['Чурек|Çörek', 5], ['Батон|Baton', 6]] } },
  { city: 1, type: 'pharmacy', ru: 'Аптека «Saglyk»', tk: '«Saglyk» dermanhanasy', lat: 37.9500, lng: 58.3950, fee: 10, min: 0,
    menu: { 'Без рецепта|Reseptsiz': [['Парацетамол 500 мг|Parasetamol 500 mg', 12], ['Пластырь|Plastyr', 6], ['Термометр|Termometr', 45]] } },
  { city: 2, type: 'restaurant', ru: 'Ресторан «Margiana»', tk: '«Margiana» restorany', lat: 37.5980, lng: 61.8350, fee: 8, min: 25,
    menu: { 'Основное|Esasy naharlar': [['Плов|Palow', 40], ['Шурпа|Çorba', 30]], 'Напитки|Içgiler': [['Чай|Çaý', 6]] } },
  { city: 3, type: 'cafe', ru: 'Кафе «Balkan»', tk: '«Balkan» kafesi', lat: 39.5120, lng: 54.3650, fee: 6, min: 20,
    menu: { 'Фастфуд|Fastfud': [['Бургер|Burger', 35], ['Лаваш|Lawaş', 28], ['Картофель фри|Kartoşka fri', 15]], 'Напитки|Içgiler': [['Кола 0.5|Kola 0.5', 8]] } },
];

for (const [i, v] of venues.entries()) {
  const exists = await one('SELECT id FROM venues WHERE name_ru=$1', [v.ru]);
  if (exists) continue;
  const venue = await one(
    `INSERT INTO venues (owner_id, type, name_ru, name_tk, city_id, address, lat, lng, phone, status, is_open,
       delivery_fee, min_order, delivery_radius_km, commission_pct, contract_no, contract_signed_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'active',true,$10,$11,7,12,$12,current_date) RETURNING id`,
    [partner.id, v.type, v.ru, v.tk, v.city, 'Demo address', v.lat, v.lng, `+9936100000${i + 2}`, v.fee, v.min, `DEMO-${i + 1}`],
  );
  let sort = 0;
  for (const [cat, items] of Object.entries(v.menu)) {
    const [cru, ctk] = cat.split('|');
    const c = await one('INSERT INTO categories (venue_id, name_ru, name_tk, sort) VALUES ($1,$2,$3,$4) RETURNING id',
      [venue.id, cru, ctk, sort++]);
    for (const [name, price] of items) {
      const [ru, tk] = name.split('|');
      await one('INSERT INTO products (venue_id, category_id, name_ru, name_tk, price) VALUES ($1,$2,$3,$4,$5) RETURNING id',
        [venue.id, c.id, ru, tk, price]);
    }
  }
}
console.log('seed done');
await pool.end();
