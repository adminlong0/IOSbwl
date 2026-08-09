import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'transit_api.dart';

class AppStore extends ChangeNotifier {
  final api = TransitApi();
  String cityName = '莆田市';
  String cityKey = 'pt111601';
  List<BusLine> lines = [];
  List<NearbyStop> nearbyStops = [];
  Set<String> favorites = {};
  List<String> searchHistory = [];
  ThemeMode themeMode = ThemeMode.system;
  Color accent = const Color(0xff20a464);
  double refreshInterval = 0;
  LatLng? userLocation;
  bool loading = false;
  String? error;

  List<BusLine> get favoriteLines =>
      lines.where((e) => favorites.contains(e.id)).toList();
  List<BusLine> favoriteFirst(Iterable<BusLine> source) =>
      [...source]..sort((a, b) {
        final af = favorites.contains(a.id), bf = favorites.contains(b.id);
        if (af != bf) return af ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    searchHistory = prefs.getStringList('searchHistory') ?? [];
    refreshInterval = prefs.getDouble('refreshInterval') ?? 0;
    themeMode = ThemeMode.values[prefs.getInt('themeMode')?.clamp(0, 2) ?? 0];
    accent = Color(prefs.getInt('accent') ?? 0xff20a464);
    await Future.wait([loadLines(), locate()]);
  }

  Future<void> loadLines() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      lines = await api.allLines(cityName, cityKey);
    } catch (e) {
      error = friendly(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('定位服务未开启');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('未获得定位权限');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      userLocation = LatLng(position.latitude, position.longitude);
      nearbyStops = await api.nearby(cityName, cityKey, userLocation);
      error = null;
    } catch (e) {
      try {
        nearbyStops = await api.nearby(cityName, cityKey, null);
      } catch (_) {
        error = friendly(e);
      }
    }
    notifyListeners();
  }

  List<BusLine> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return favoriteFirst(
      lines.where(
        (e) =>
            e.name.toLowerCase().contains(q) ||
            e.destination.toLowerCase().contains(q),
      ),
    );
  }

  Future<void> rememberSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    searchHistory.remove(q);
    searchHistory.insert(0, q);
    if (searchHistory.length > 12) {
      searchHistory = searchHistory.take(12).toList();
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteSearch(String value) async {
    searchHistory.remove(value);
    await _save();
    notifyListeners();
  }

  Future<void> toggleFavorite(BusLine line) async {
    favorites.contains(line.id)
        ? favorites.remove(line.id)
        : favorites.add(line.id);
    await _save();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    themeMode = value;
    await _save();
    notifyListeners();
  }

  Future<void> setAccent(Color value) async {
    accent = value;
    await _save();
    notifyListeners();
  }

  Future<void> setRefresh(double value) async {
    refreshInterval = value;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', favorites.toList());
    await prefs.setStringList('searchHistory', searchHistory);
    await prefs.setDouble('refreshInterval', refreshInterval);
    await prefs.setInt('themeMode', themeMode.index);
    await prefs.setInt('accent', accent.toARGB32());
  }

  String exportConfig() => jsonEncode({
    'favorites': favorites.toList(),
    'searchHistory': searchHistory,
    'refreshInterval': refreshInterval,
    'themeMode': themeMode.index,
    'accent': accent.toARGB32(),
  });
  String friendly(Object e) => e.toString().replaceFirst('Exception: ', '');
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);
  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
