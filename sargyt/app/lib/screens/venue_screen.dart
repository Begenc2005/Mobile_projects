import 'package:flutter/material.dart';
import '../api.dart';
import '../state.dart';
import 'cart_screen.dart';

class VenueScreen extends StatefulWidget {
  final int venueId;
  const VenueScreen({super.key, required this.venueId});
  @override
  State<VenueScreen> createState() => _VenueScreenState();
}

class _VenueScreenState extends State<VenueScreen> {
  Map<String, dynamic>? venue;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = App.read(context);
    try {
      final r = await s.api.get('/api/venues/${widget.venueId}');
      if (mounted) setState(() => venue = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => error = s.err(e));
    }
  }

  Future<void> _add(AppState s, Map<String, dynamic> product) async {
    final v = Map<String, dynamic>.from(venue!)..remove('products')..remove('categories');
    if (s.isOtherVenue(v)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(s.t('clearCartQ')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('no'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('yes'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    s.add(v, product);
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    if (venue == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: error != null ? Text(error!) : const CircularProgressIndicator()));
    }
    final v = venue!;
    final products = List<Map<String, dynamic>>.from((v['products'] as List).map((e) => Map<String, dynamic>.from(e)));
    final cats = [
      ...List<Map<String, dynamic>>.from((v['categories'] as List).map((e) => Map<String, dynamic>.from(e))),
      {'id': null, 'name_ru': '', 'name_tk': ''},
    ];
    final inThisVenue = s.cartVenue?['id'] == v['id'] && s.cartCount > 0;

    return Scaffold(
        appBar: AppBar(title: Text(s.nm(v))),
        bottomNavigationBar: inThisVenue
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                    child: Text('${s.t('cart')} · ${s.cartCount} · ${money(s.subtotal)}'),
                  ),
                ),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((v['description_${s.lang}'] ?? '').toString().isNotEmpty) Text('${v['description_${s.lang}']}'),
                const SizedBox(height: 6),
                Text(
                  '${s.t('delivery')}: ${toD(v['delivery_fee']) == 0 ? s.t('free') : money(v['delivery_fee'])} · '
                  '${s.t('minOrder')}: ${money(v['min_order'])} · ~${v['prep_minutes']} ${s.t('min')}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                if (v['is_open'] != true)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.t('closed'), style: const TextStyle(color: Colors.deepOrange))),
              ]),
            ),
            for (final c in cats)
              if (products.any((p) => p['category_id'] == c['id'])) ...[
                if (c['id'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                    child: Text(s.nm(c), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                for (final p in products.where((p) => p['category_id'] == c['id']))
                  _ProductTile(product: p, enabled: v['is_open'] == true, onAdd: () => _add(s, p)),
              ],
          ],
        ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool enabled;
  final VoidCallback onAdd;
  const _ProductTile({required this.product, required this.enabled, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    final id = product['id'] as int;
    final qty = s.qtyOf(id);
    final desc = (product['description_${s.lang}'] ?? '').toString();
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        if (product['image_url'] != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(product['image_url'], width: 72, height: 72, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.nm(product), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (desc.isNotEmpty) Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 4),
            Text(money(product['price']), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        if (qty == 0)
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(44, 40)),
            onPressed: enabled ? onAdd : null,
            child: const Icon(Icons.add),
          )
        else
          Row(children: [
            IconButton.filledTonal(onPressed: () => s.remove(id), icon: const Icon(Icons.remove)),
            Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            IconButton.filledTonal(onPressed: enabled ? onAdd : null, icon: const Icon(Icons.add)),
          ]),
      ]),
    );
  }
}
