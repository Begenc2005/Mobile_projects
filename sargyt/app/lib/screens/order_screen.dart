import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../state.dart';
import 'payment_screen.dart';

const _steps = ['new', 'accepted', 'preparing', 'on_the_way', 'delivered'];
const _final = ['delivered', 'cancelled', 'rejected'];

/// Отслеживание заказа: опрос сервера каждые 5 сек, пока заказ активен
class OrderScreen extends StatefulWidget {
  final int orderId;
  const OrderScreen({super.key, required this.orderId});
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Map<String, dynamic>? o;
  Timer? timer;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (o != null && !_final.contains(o!['status'])) load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final s = App.read(context);
    try {
      final r = await s.api.get('/api/orders/${widget.orderId}');
      if (mounted) setState(() { o = Map<String, dynamic>.from(r); error = null; });
    } catch (e) {
      if (mounted) setState(() => error = s.err(e));
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    try { await fn(); } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(App.read(context).err(e))));
    }
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    if (o == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: error != null ? Text(error!) : const CircularProgressIndicator()));
    }
    final st = o!['status'] as String;
    final step = _steps.indexOf(st);
    final venue = {'name_ru': o!['venue_name_ru'], 'name_tk': o!['venue_name_tk']};
    final payFailed = st == 'awaiting_payment' && o!['payment_status'] == 'failed';

    return Scaffold(
      appBar: AppBar(title: Text('${s.t('order')} #${o!['id']}')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(s.nm(venue), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(payFailed ? s.t('payFailed') : s.t('st_$st'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: ['cancelled', 'rejected'].contains(st) || payFailed ? Colors.deepOrange : Theme.of(context).colorScheme.primary)),
              if (o!['reject_reason'] != null && st == 'rejected') Text('${o!['reject_reason']}'),
              if (step >= 0) ...[
                const SizedBox(height: 12),
                Row(children: [
                  for (var i = 0; i < _steps.length; i++)
                    Expanded(
                      child: Container(
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= step ? Theme.of(context).colorScheme.primary : Colors.black12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              for (final i in (o!['items'] as List))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${i['qty']} × ${s.nm(i)}')),
                    Text(money(toD(i['price']) * (i['qty'] as num))),
                  ]),
                ),
              const Divider(),
              Row(children: [Expanded(child: Text(s.t('delivery'))), Text(money(o!['delivery_fee']))]),
              Row(children: [
                Expanded(child: Text(s.t('total'), style: const TextStyle(fontWeight: FontWeight.w800))),
                Text(money(o!['total']), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Icon(o!['payment_method'] == 'card' ? Icons.credit_card : Icons.payments_outlined, size: 18),
                const SizedBox(width: 6),
                Text(s.t(o!['payment_method'])),
              ]),
              const SizedBox(height: 6),
              Row(children: [const Icon(Icons.place_outlined, size: 18), const SizedBox(width: 6), Expanded(child: Text('${o!['address']}'))]),
            ]),
          ),
          const SizedBox(height: 16),
          if (st == 'awaiting_payment')
            FilledButton(
              onPressed: () => act(() async {
                final r = await s.api.post('/api/orders/${o!['id']}/pay');
                if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(url: r['formUrl'])));
              }),
              child: Text(s.t('payAgain')),
            ),
          if (st == 'awaiting_payment' || st == 'new')
            TextButton(
              onPressed: () => act(() async { await s.api.post('/api/orders/${o!['id']}/cancel'); }),
              child: Text(s.t('cancel'), style: const TextStyle(color: Colors.deepOrange)),
            ),
          if (!_final.contains(st) && st != 'awaiting_payment')
            Text('${s.t('call')}: ${o!['venue_phone']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }
}
