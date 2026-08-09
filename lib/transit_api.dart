import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'models.dart';

class TransitApi {
  static const _officialEndpoint = 'https://h5.mygolbs.com/ApiData.do';
  static const endpoint = String.fromEnvironment(
    'NLBUS_API_BASE',
    defaultValue: _officialEndpoint,
  );

  Future<Map<String, dynamic>> request(Map<String, String> parameters) async {
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
    };
    // Native clients can reproduce the request context required by the
    // official H5 endpoint. Web deployments may supply a same-origin proxy
    // through NLBUS_API_BASE because browsers control Origin themselves.
    if (!kIsWeb && endpoint == _officialEndpoint) {
      headers.addAll({
        'Origin': 'https://h5.mygolbs.com',
        'Referer': 'https://h5.mygolbs.com/?areacode=pt111601',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; NLBUS) AppleWebKit/537.36 Mobile Safari/537.36',
      });
    }
    final response = await http
        .post(Uri.parse(endpoint), headers: headers, body: parameters)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('公交服务响应异常 (${response.statusCode})');
    }
    Object? value;
    try {
      value = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (kIsWeb && endpoint == _officialEndpoint) {
        throw Exception('网页端实时数据受官方接口访问策略限制，请使用“官方页面核对”');
      }
      throw Exception('公交数据格式异常');
    }
    if (value is! Map) throw Exception('公交数据格式异常');
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>> arrays(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  Future<List<BusLine>> allLines(String cityName, String cityKey) async {
    final json = await request({
      'CMD': '119',
      'CITYNAME': cityName,
      'CITYKEY': cityKey,
      'KEY': '',
    });
    final seen = <String>{};
    return arrays(json, [
      'buslines',
      'data',
      'list',
      'rows',
      'result',
    ]).map(BusLine.fromJson).where((e) => seen.add(e.id)).toList();
  }

  Future<List<NearbyStop>> nearby(
    String cityName,
    String cityKey,
    LatLng? location,
  ) async {
    final json = await request({
      'CMD': '106',
      'CITYNAME': cityName,
      'CITYKEY': cityKey,
      'LNG': location?.longitude.toString() ?? '',
      'LAT': location?.latitude.toString() ?? '',
    });
    return arrays(json, ['data']).map(NearbyStop.fromJson).where((e) {
      final number = int.tryParse(e.distance.replaceAll(RegExp(r'[^0-9]'), ''));
      return number == null || number <= 500;
    }).toList();
  }

  Future<List<BusLine>> stationLines(
    String stationName,
    String cityName,
    String cityKey,
  ) async {
    final json = await request({
      'CMD': '115',
      'CITYNAME': cityName,
      'CITYKEY': cityKey,
      'STATIONNAME': stationName,
      'MYLAT': '',
      'MYLNG': '',
      'ALL': '1',
    });
    return arrays(json, ['data']).map(BusLine.fromJson).toList();
  }

  Future<RouteBundle> route(
    BusLine line,
    String cityName,
    String cityKey,
  ) async {
    Object? lastError;
    for (final direction in [
      line.direction,
      line.direction == '1' ? '2' : '1',
    ]) {
      try {
        final json = await request({
          'CMD': '103',
          'CITYNAME': cityName,
          'CITYKEY': cityKey,
          'LINENAME': line.name,
          'DIRECTION': direction,
        });
        final rows = arrays(json, [
          'data',
          'list',
          'stations',
          'busstations',
          'stationList',
        ]);
        if (rows.isEmpty) continue;
        final geometry = arrays(json, ['nihelist'])
            .map((p) {
              final lat = double.tryParse('${p['lat'] ?? ''}');
              final lon = double.tryParse('${p['lng'] ?? ''}');
              return lat == null || lon == null ? null : LatLng(lat, lon);
            })
            .whereType<LatLng>()
            .toList();
        return RouteBundle(
          stops: [
            for (var i = 0; i < rows.length; i++)
              RouteStop.fromJson(rows[i], i),
          ],
          geometry: geometry,
          routeId: '${json['routeId'] ?? json['routeID'] ?? line.name}',
        );
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError ?? '当前线路暂无站点数据');
  }

  Future<RealtimeData> realtime(
    BusLine line,
    int stationOrder,
    String cityName,
    String cityKey,
  ) async {
    Object? lastError;
    for (final direction in [
      line.direction,
      line.direction == '1' ? '2' : '1',
    ]) {
      try {
        final json = await request({
          'CMD': '104',
          'CITYNAME': cityName,
          'CITYKEY': cityKey,
          'LINENAME': line.name,
          'DIRECTION': direction,
          'STATIONORDER': '$stationOrder',
        });
        final data = json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : json;
        final buses = arrays(data, [
          'list',
          'buslist',
          'vehicleList',
          'vehicles',
          'rows',
          'data',
        ]);
        final plan = '${data['planTime'] ?? data['nextTime'] ?? ''}';
        if (buses.isNotEmpty || plan.isNotEmpty) {
          return RealtimeData(
            buses: [
              for (var i = 0; i < buses.length; i++)
                LiveBus.fromJson(buses[i], i),
            ],
            planTime: plan,
          );
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError ?? '当前线路暂无实时车辆');
  }

  Future<List<String>> timetable(
    BusLine line,
    RouteBundle route,
    String cityName,
  ) async {
    final json = await request({
      'CMD': '207',
      'CITYNAME': cityName,
      'CITYKEY': '',
      'ROUTEID': route.routeId,
      'DIRECTION': line.direction,
    });
    final times = <String>{};
    for (final row in arrays(json, ['list', 'data', 'rows', 'result'])) {
      final nested = row['times'];
      if (nested is List) {
        for (final item in nested) {
          if (item is String) times.add(item);
          if (item is Map) {
            times.add(
              '${item['time'] ?? item['planTime'] ?? item['departTime'] ?? ''}',
            );
          }
        }
      }
      final direct =
          '${row['time'] ?? row['planTime'] ?? row['departTime'] ?? ''}';
      if (direct.isNotEmpty) times.add(direct);
    }
    return times.where((e) => e.isNotEmpty).toList()..sort();
  }
}
