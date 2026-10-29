import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../state.dart';
import 'venue_screen.dart';
import 'cart_screen.dart';

const venueTypes = ['restaurant', 'cafe', 'grocery', 'pharmacy', 'shop'];
const typeIcons = {
  'restaurant': Icons.restaurant,
  'cafe': Icons.local_cafe,
  'grocery': Icons.local_grocery_store,
  'pharmacy': Icons.local_pharmacy,
  'shop': Icons.shopping_bag,
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? type;
  String query = '';
  List venues = [];
  bool loading = true;
  String? error;
  Timer? _debounce;
  double? _lastLat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // как только появилась геопозиция — перезагрузить список «рядом»
    final s = App.of(context);
    if (s.lat != null && s.lat != _lastLat) {
      _lastLat = s.lat;
      WidgetsBinding.instance.addPostFrameCallback((_) => load());
    }
  }

  Future<void> load() async {
    final s = App.read(context);
    setState(() { loading = true; error = null; });
    final params = <String, String>{
      if (s.lat != null) 'lat': '${s.lat}',
      if (s.lng != null) 'lng': '${s.lng}',
      if (type != null) 'type': type!,
      if (query.isNotEmpty) 'q': query,
    };
    try {
      final r = await s.api.get('/api/venues?${Uri(queryParameters: params).query}');
      if (mounted) setState(() { venues = r as List; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = s.err(e); loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('SARGYT', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
        actions: [
          IconButton(icon: Icon(s.lat == null ? Icons.location_off_outlined : Icons.my_location), onPressed: () => s.locate()),
        ],
      ),
      floatingActionButton: s.cartCount == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
              icon: const Icon(Icons.shopping_basket),
              label: Text('${s.cartCount} · ${money(s.subtotal)}'),
            ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: s.t('search'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () { query = v.trim(); load(); });
                },
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip(s, null, s.t('all'), Icons.apps),
                  for (final t in venueTypes) _chip(s, t, s.t(t), typeIcons[t]!),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(s.t('nearby'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (!loading && error != null)
              Center(child: Column(children: [Text(error!), TextButton(onPressed: load, child: Text(s.t('retry')))])),
            if (!loading && error == null && venues.isEmpty) Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(s.t('empty')))),
            for (final v in venues) _VenueCard(venue: Map<String, dynamic>.from(v)),
          ],
        ),
      ),
    );
  }

  Widget _chip(AppState s, String? value, String label, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: type == value,
          showCheckmark: false,
          onSelected: (_) { setState(() => type = value); load(); },
        ),
      );
}

class _VenueCard extends StatelessWidget {
  final Map<String, dynamic> venue;
  const _VenueCard({required this.venue});

  @override
  Widget build(BuildContext context) {
    final s = App.of(context);
    final open = venue['is_open'] == true;
    final delivers = venue['delivers_here'] != false;
    final fee = toD(venue['delivery_fee']);
    final info = [
      if (venue['distance_km'] != null) '${venue['distance_km']} ${s.t('km')}',
      '~${venue['prep_minutes']} ${s.t('min')}',
      '${s.t('delivery')}: ${fee == 0 ? s.t('free') : money(fee)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Opacity(
        opacity: open && delivers ? 1 : 0.55,
        child: Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VenueScreen(venueId: venue['id'] as int))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: const Color(0xFFE8F6EF),
                    child: venue['logo_url'] != null
                        ? Image.network(venue['logo_url'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(typeIcons[venue['type']]))
                        : Icon(typeIcons[venue['type']], color: Theme.of(context).colorScheme.primary, size: 30),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.nm(venue), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(info, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    if (!open || !delivers)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(!open ? s.t('closed') : s.t('notDelivering'), style: const TextStyle(color: Colors.deepOrange, fontSize: 13)),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
