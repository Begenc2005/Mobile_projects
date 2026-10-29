import 'package:flutter/material.dart';
import '../api.dart';
import '../state.dart';
import 'order_screen.dart';
import 'venue_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List orders = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    final s = App.read(context);
    try {
      final r = await s.api.get('/api/orders');
      if (mounted) setState(() { orders = r as List; loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  // Повтор: кладём доступные позиции в корзину и открываем заведение
  Future<void> repeat(AppState s, int id) async {
    try {
      final r = await s.api.get('/api/orders/$id/repeat');
      final venue = Map<String, dynamic>.from(await s.api.get('/api/venues/${r['venue_id']}'));
      final products = {for (final p in venue['products'] as List) p['id']: Map<String, dynamic>.from(p)};
      final v = Map<String, dynamic>.from(venue)..remove('products')..remove('categories');
      s.clearCart();
      for (final it in r['items'] as List) {
        final p = products[it['product_id']];
        if (p == null) continue;
        for (var i = 0; i < (it['qty'] as int); i++) { s.add(v, p); }
      }
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => VenueScreen(venueId: v['id'] as int)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.err(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('orders'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: orders.isEmpty
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(48), child: Center(child: Text(s.t('empty'))))])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final o = Map<String, dynamic>.from(orders[i]);
                        final date = DateTime.parse(o['created_at']).toLocal();
                        return ListTile(
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          title: Text(s.nm({'name_ru': o['venue_name_ru'], 'name_tk': o['venue_name_tk']}),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('#${o['id']} · ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} '
                              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} · ${s.t('st_${o['status']}')}'),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(money(o['total']), style: const TextStyle(fontWeight: FontWeight.w700)),
                            if (o['status'] == 'delivered')
                              InkWell(onTap: () => repeat(s, o['id'] as int), child: Text(s.t('repeat'), style: TextStyle(color: Theme.of(context).colorScheme.primary))),
                          ]),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(orderId: o['id'] as int)));
                            load();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}
