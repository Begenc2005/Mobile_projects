import 'api.dart';

/// Demo build (no server, no SMS): flutter build apk --dart-define=DEMO=true
/// Replaces the server with in-memory data. Code for login is always 1234.
const bool demoMode = bool.fromEnvironment('DEMO');

typedef M = Map<String, dynamic>;

class DemoBackend {
  DemoBackend._();
  static final I = DemoBackend._();

  // name_ru|name_tk, price
  static final _raw = [
    (1, 'restaurant', 'Чайхана «Беркарар»', '«Berkarar» çaýhanasy', 10, 30, 25, true, {
      'Горячее|Gyzgyn naharlar': [['Плов|Palow', 45], ['Манты|Manty', 40], ['Шашлык из баранины|Goýun şaşlygy', 55], ['Дограма|Dogroma', 35]],
      'Напитки|Içgiler': [['Зелёный чай|Gök çaý', 8], ['Айран|Aýran', 10], ['Компот|Kompot', 9]],
    }),
    (2, 'cafe', 'Кафе «Ýyldyz»', '«Ýyldyz» kafesi', 8, 20, 20, true, {
      'Выпечка|Bişirilen önümler': [['Ишлекли|Işlekli', 30], ['Гутап с мясом|Etli gutap', 12], ['Самса|Somsa', 10]],
      'Кофе|Kofe': [['Капучино|Kapuçino', 25], ['Латте|Latte', 27], ['Американо|Amerikano', 20]],
    }),
    (3, 'grocery', 'Маркет «Gündelik»', '«Gündelik» market', 7, 40, 30, true, {
      'Молочные|Süýt önümleri': [['Молоко 1 л|Süýt 1 l', 14], ['Сыр 400 г|Peýnir 400 g', 48], ['Яйца 10 шт|Ýumurtga 10 sany', 22]],
      'Хлеб|Çörek': [['Чурек|Çörek', 5], ['Батон|Baton', 6]],
    }),
    (4, 'pharmacy', 'Аптека «Saglyk»', '«Saglyk» dermanhanasy', 10, 0, 15, true, {
      'Без рецепта|Reseptsiz': [['Парацетамол 500 мг|Parasetamol 500 mg', 12], ['Пластырь|Plastyr', 6], ['Термометр|Termometr', 45]],
    }),
    (5, 'restaurant', 'Ресторан «Margiana»', '«Margiana» restorany', 8, 25, 30, true, {
      'Основное|Esasy naharlar': [['Плов|Palow', 40], ['Шурпа|Çorba', 30]],
      'Напитки|Içgiler': [['Чай|Çaý', 6]],
    }),
    (6, 'cafe', 'Кафе «Balkan»', '«Balkan» kafesi', 6, 20, 15, false, {
      'Фастфуд|Fastfud': [['Бургер|Burger', 35], ['Лаваш|Lawaş', 28], ['Картофель фри|Kartoşka fri', 15]],
      'Напитки|Içgiler': [['Кола 0.5|Kola 0.5', 8]],
    }),
  ];

  late final List<M> venues = [];
  final Map<int, M> venueFull = {};
  final Map<int, M> productById = {};
  final List<M> orders = [];
  M? user;
  int _nextOrder = 1001;

  bool _built = false;
  void _build() {
    if (_built) return;
    _built = true;
    var pid = 1, cid = 1;
    for (final v in _raw) {
      final (id, type, ru, tk, fee, min, prep, open, menu) = v;
      final venue = <String, dynamic>{
        'id': id, 'type': type, 'name_ru': ru, 'name_tk': tk, 'description_ru': '', 'description_tk': '',
        'city_id': 1, 'address': 'Demo', 'lat': null, 'lng': null, 'phone': '+99361000$id',
        'logo_url': null, 'is_open': open, 'delivery_fee': fee, 'min_order': min,
        'delivery_radius_km': 7, 'prep_minutes': prep, 'accepts_cash': true,
        'distance_km': null, 'delivers_here': null,
      };
      venues.add(venue);
      final cats = <M>[], prods = <M>[];
      var sort = 0;
      menu.forEach((cat, items) {
        final c = cat.split('|');
        final catId = cid++;
        cats.add({'id': catId, 'name_ru': c[0], 'name_tk': c[1], 'sort': sort++});
        for (final it in items) {
          final n = (it[0] as String).split('|');
          final p = <String, dynamic>{
            'id': pid++, 'category_id': catId, 'name_ru': n[0], 'name_tk': n[1],
            'description_ru': '', 'description_tk': '', 'price': it[1], 'image_url': null, 'venue_id': id,
          };
          prods.add(p);
          productById[p['id'] as int] = p;
        }
      });
      venueFull[id] = {...venue, 'categories': cats, 'products': prods};
    }
  }

  Never _fail(String code, [String? msg]) => throw ApiError(code, msg ?? code);

  /// Status advances by itself every 8 seconds so the whole flow can be shown.
  static const _flow = ['new', 'accepted', 'preparing', 'on_the_way', 'delivered'];
  M _view(M o) {
    if (o['_cancelled'] == true) return _clean({...o, 'status': 'cancelled'});
    final i = DateTime.now().difference(o['_t'] as DateTime).inSeconds ~/ 8;
    return _clean({...o, 'status': _flow[i.clamp(0, _flow.length - 1)]});
  }

  M _clean(M o) => {...o}..removeWhere((k, _) => k.startsWith('_'));

  Future<dynamic> handle(String method, String path, [Object? body]) async {
    _build();
    await Future.delayed(const Duration(milliseconds: 250));
    final uri = Uri.parse(path);
    final seg = uri.pathSegments; // api, x, ...
    final b = (body is Map) ? Map<String, dynamic>.from(body) : <String, dynamic>{};

    if (seg.length >= 3 && seg[1] == 'auth') {
      if (seg[2] == 'otp') return {'ok': true, 'phone': b['phone'], 'devCode': '1234'};
      if (seg[2] == 'verify') {
        if ('${b['code']}' != '1234') _fail('bad_code');
        final name = '${b['name'] ?? ''}';
        user = {'id': 1, 'phone': b['phone'], 'name': name.isEmpty ? 'Demo' : name, 'role': 'customer', 'lang': b['lang'] ?? 'tk'};
        return {'token': 'demo', 'user': user};
      }
    }
    user ??= {'id': 1, 'phone': '+99361000000', 'name': 'Demo', 'role': 'customer', 'lang': 'tk'};

    if (seg[1] == 'me') {
      if (method == 'PATCH') {
        if (b['name'] != null) user!['name'] = b['name'];
        if (b['lang'] != null) user!['lang'] = b['lang'];
        return {'user': user};
      }
      return {'user': user, 'token': 'demo'};
    }

    if (seg[1] == 'venues') {
      if (seg.length == 2) {
        final type = uri.queryParameters['type'];
        final q = (uri.queryParameters['q'] ?? '').toLowerCase();
        return venues.where((v) {
          if (type != null && v['type'] != type) return false;
          if (q.isEmpty) return true;
          final full = venueFull[v['id']]!;
          return '${v['name_ru']} ${v['name_tk']}'.toLowerCase().contains(q) ||
              (full['products'] as List).any((p) => '${p['name_ru']} ${p['name_tk']}'.toLowerCase().contains(q));
        }).toList();
      }
      final v = venueFull[int.tryParse(seg[2])];
      if (v == null) _fail('not_found');
      return v;
    }

    if (seg[1] == 'orders') {
      if (seg.length == 2 && method == 'POST') {
        final venue = venueFull[b['venue_id']];
        if (venue == null) _fail('venue_not_found');
        if (venue['is_open'] != true) _fail('venue_closed', 'Venue is closed');
        final items = <M>[];
        double sub = 0;
        for (final it in (b['items'] as List)) {
          final p = productById[it['product_id']];
          if (p == null) _fail('items_unavailable');
          final qty = it['qty'] as int;
          sub += (p['price'] as num) * qty;
          items.add({'product_id': p['id'], 'name_ru': p['name_ru'], 'name_tk': p['name_tk'], 'price': p['price'], 'qty': qty});
        }
        if (sub < (venue['min_order'] as num)) _fail('below_min_order', 'Minimum order ${venue['min_order']} TMT');
        final fee = venue['delivery_fee'] as num;
        final o = <String, dynamic>{
          'id': _nextOrder++, 'user_id': 1, 'venue_id': venue['id'], 'status': 'new',
          'payment_method': b['payment_method'], 'payment_status': b['payment_method'] == 'card' ? 'paid' : 'none',
          'subtotal': sub, 'delivery_fee': fee, 'total': sub + fee, 'address': b['address'], 'phone': b['phone'],
          'comment': b['comment'], 'reject_reason': null, 'created_at': DateTime.now().toUtc().toIso8601String(),
          'venue_name_ru': venue['name_ru'], 'venue_name_tk': venue['name_tk'], 'venue_phone': venue['phone'],
          'prep_minutes': venue['prep_minutes'], 'items': items, '_t': DateTime.now(),
        };
        orders.insert(0, o);
        return {'order': _view(o), 'payment': null};
      }
      if (seg.length == 2) {
        return [for (final o in orders) _view(o)];
      }
      final o = orders.where((x) => '${x['id']}' == seg[2]).firstOrNull;
      if (o == null) _fail('not_found');
      if (seg.length == 3) return _view(o);
      switch (seg[3]) {
        case 'cancel':
          if (_view(o)['status'] != 'new') _fail('cannot_cancel', 'Order already accepted');
          o['_cancelled'] = true;
          return _view(o);
        case 'repeat':
          return {'venue_id': o['venue_id'], 'items': [for (final i in o['items']) {'product_id': i['product_id'], 'qty': i['qty']}]};
        case 'pay':
          return {'formUrl': 'about:blank'};
      }
    }
    _fail('not_found');
  }
}
