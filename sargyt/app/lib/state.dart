import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'i18n.dart';

class CartItem {
  final Map<String, dynamic> product;
  int qty;
  CartItem(this.product, this.qty);
  double get sum => toD(product['price']) * qty;
}

/// Общее состояние приложения: вход, язык, геопозиция, корзина
class AppState extends ChangeNotifier {
  final api = Api();
  late SharedPreferences _prefs;

  String lang = 'tk';
  Map<String, dynamic>? user;
  double? lat, lng;
  String address = '';

  Map<String, dynamic>? cartVenue;
  final Map<int, CartItem> cart = {};

  bool get loggedIn => api.token != null;
  String t(String key) => tr(lang, key);
  String nm(Map m) => '${lang == 'ru' ? m['name_ru'] : m['name_tk']}';
  String err(Object e) => e is ApiError ? (tr(lang, 'err_${e.code}') != 'err_${e.code}' ? tr(lang, 'err_${e.code}') : e.message) : '$e';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    lang = _prefs.getString('lang') ?? 'tk';
    api.token = _prefs.getString('token');
    address = _prefs.getString('address') ?? '';
    if (api.token != null) {
      try {
        final r = await api.get('/api/me');
        user = Map<String, dynamic>.from(r['user']);
        await _saveToken(r['token']);
      } on ApiError catch (e) {
        if (e.code == 'unauthorized') await logout();
      }
    }
    locate(); // без ожидания
  }

  Future<void> _saveToken(String tok) async {
    api.token = tok;
    await _prefs.setString('token', tok);
  }

  Future<String?> requestCode(String phone) async {
    final r = await api.post('/api/auth/otp', {'phone': phone});
    return r['devCode']?.toString(); // только в тестовом режиме сервера
  }

  Future<void> verify(String phone, String code, String name) async {
    final r = await api.post('/api/auth/verify', {'phone': phone, 'code': code, 'lang': lang, if (name.isNotEmpty) 'name': name});
    user = Map<String, dynamic>.from(r['user']);
    await _saveToken(r['token']);
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    user = null;
    await _prefs.remove('token');
    notifyListeners();
  }

  Future<void> setLang(String l) async {
    lang = l;
    await _prefs.setString('lang', l);
    if (loggedIn) api.patch('/api/me', {'lang': l}).catchError((_) => null);
    notifyListeners();
  }

  Future<void> saveName(String name) async {
    final r = await api.patch('/api/me', {'name': name});
    user = Map<String, dynamic>.from(r['user']);
    notifyListeners();
  }

  void setAddress(String a) {
    address = a;
    _prefs.setString('address', a);
  }

  /// Геопозиция для поиска «рядом». Без Google-сервисов (LocationManager на Android).
  Future<bool> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return false;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: Platform.isAndroid
            ? AndroidSettings(accuracy: LocationAccuracy.high, forceLocationManager: true, timeLimit: const Duration(seconds: 15))
            : const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      lat = pos.latitude;
      lng = pos.longitude;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- корзина (только одно заведение за раз) ----
  int qtyOf(int productId) => cart[productId]?.qty ?? 0;
  int get cartCount => cart.values.fold(0, (s, i) => s + i.qty);
  double get subtotal => cart.values.fold(0.0, (s, i) => s + i.sum);
  bool isOtherVenue(Map venue) => cartVenue != null && cartVenue!['id'] != venue['id'] && cart.isNotEmpty;

  void add(Map<String, dynamic> venue, Map<String, dynamic> product) {
    if (isOtherVenue(venue)) cart.clear();
    cartVenue = venue;
    final id = product['id'] as int;
    cart.putIfAbsent(id, () => CartItem(product, 0)).qty++;
    notifyListeners();
  }

  void remove(int productId) {
    final it = cart[productId];
    if (it == null) return;
    if (--it.qty <= 0) cart.remove(productId);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    cartVenue = null;
    notifyListeners();
  }
}

/// Доступ к состоянию из любого виджета: App.of(context)
class App extends InheritedNotifier<AppState> {
  const App({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<App>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<App>()!.notifier!;
}
