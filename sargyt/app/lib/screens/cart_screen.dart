import 'package:flutter/material.dart';
import '../api.dart';
import '../state.dart';
import 'payment_screen.dart';
import 'order_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final TextEditingController address;
  late final TextEditingController phone;
  final comment = TextEditingController();
  String method = 'card';
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final s = App.read(context);
    address = TextEditingController(text: s.address);
    phone = TextEditingController(text: s.user?['phone'] ?? '');
    if (s.cartVenue?['accepts_cash'] == false) method = 'card';
  }

  Future<void> submit(AppState s) async {
    if (address.text.trim().length < 3) {
      setState(() => error = s.t('address'));
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      s.setAddress(address.text.trim());
      final r = await s.api.post('/api/orders', {
        'venue_id': s.cartVenue!['id'],
        'items': [for (final i in s.cart.values) {'product_id': i.product['id'], 'qty': i.qty}],
        'address': address.text.trim(),
        if (s.lat != null) 'lat': s.lat,
        if (s.lng != null) 'lng': s.lng,
        'phone': phone.text,
        if (comment.text.trim().isNotEmpty) 'comment': comment.text.trim(),
        'payment_method': method,
      });
      final orderId = r['order']['id'] as int;
      s.clearCart();
      if (!mounted) return;
      if (method == 'card' && r['payment'] != null) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(url: r['payment']['formUrl'])));
      }
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(orderId: orderId)));
    } catch (e) {
      setState(() => error = s.err(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    final v = s.cartVenue;
    if (v == null || s.cart.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(s.t('cart'))), body: Center(child: Text(s.t('emptyCart'))));
    }
    final fee = toD(v['delivery_fee']);
    final belowMin = s.subtotal < toD(v['min_order']);
    return Scaffold(
      appBar: AppBar(title: Text(s.nm(v))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _box(Column(children: [
            for (final i in s.cart.values)
              Row(children: [
                Expanded(child: Text(s.nm(i.product))),
                IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => s.remove(i.product['id'] as int)),
                Text('${i.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => s.add(v, i.product)),
                SizedBox(width: 90, child: Text(money(i.sum), textAlign: TextAlign.right)),
              ]),
          ])),
          const SizedBox(height: 12),
          _box(Column(children: [
            TextField(controller: address, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: s.t('address'))),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: Icon(s.lat == null ? Icons.location_searching : Icons.my_location),
                label: Text(s.lat == null ? s.t('useGps') : '${s.lat!.toStringAsFixed(5)}, ${s.lng!.toStringAsFixed(5)}'),
                onPressed: () => s.locate(),
              ),
            ),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.t('phone'))),
            TextField(controller: comment, decoration: InputDecoration(labelText: s.t('comment'))),
          ])),
          const SizedBox(height: 12),
          _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('payment'), style: const TextStyle(fontWeight: FontWeight.w700)),
            RadioListTile<String>(value: 'card', groupValue: method, onChanged: (x) => setState(() => method = x!),
                title: Text(s.t('card')), secondary: const Icon(Icons.credit_card), contentPadding: EdgeInsets.zero),
            if (v['accepts_cash'] != false)
              RadioListTile<String>(value: 'cash', groupValue: method, onChanged: (x) => setState(() => method = x!),
                  title: Text(s.t('cash')), secondary: const Icon(Icons.payments_outlined), contentPadding: EdgeInsets.zero),
          ])),
          const SizedBox(height: 12),
          _box(Column(children: [
            _line(s.t('subtotal'), money(s.subtotal)),
            _line(s.t('delivery'), fee == 0 ? s.t('free') : money(fee)),
            const Divider(),
            _line(s.t('total'), money(s.subtotal + fee), bold: true),
            if (belowMin)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${s.t('minOrder')}: ${money(v['min_order'])}', style: const TextStyle(color: Colors.deepOrange)),
              ),
          ])),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: busy || belowMin ? null : () => submit(s),
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('${s.t('placeOrder')} · ${money(s.subtotal + fee)}'),
          ),
        ),
      ),
    );
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: child,
      );

  Widget _line(String a, String b, {bool bold = false}) {
    final st = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400, fontSize: bold ? 17 : 15);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(a, style: st)), Text(b, style: st)]),
    );
  }
}
