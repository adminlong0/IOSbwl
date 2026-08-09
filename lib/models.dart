import 'package:latlong2/latlong.dart';

String _s(
  Map<String, dynamic> json,
  List<String> keys, [
  String fallback = '',
]) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return fallback;
}

int _i(Map<String, dynamic> json, List<String> keys, [int fallback = 0]) {
  for (final key in keys) {
    final value = int.tryParse('${json[key] ?? ''}');
    if (value != null) return value;
  }
  return fallback;
}

double? _d(Object? value) => double.tryParse('${value ?? ''}');

class BusLine {
  const BusLine({
    required this.name,
    required this.direction,
    required this.destination,
    this.beginTime = '',
    this.endTime = '',
    this.fare = '',
    this.mileage = '',
    this.remark = '',
    this.summary = '',
  });
  factory BusLine.fromJson(Map<String, dynamic> j) => BusLine(
    name: _s(j, ['lineName', 'routeName', 'name'], '未知线路'),
    direction: _s(j, ['upperOrDown', 'uod', 'direction'], '1'),
    destination: _s(j, ['to', 'endStation', 'endName']),
    beginTime: _s(j, ['beginTime', 'startTime']),
    endTime: _s(j, ['endTime', 'lastTime']),
    fare: _s(j, ['price', 'ticketPrice', 'fare']),
    mileage: _s(j, ['mileage', 'length']),
    remark: _s(j, ['remark', 'memo']),
    summary: _s(j, ['summary', 'lineDesc']),
  );
  final String name,
      direction,
      destination,
      beginTime,
      endTime,
      fare,
      mileage,
      remark,
      summary;
  String get id => '$name-$direction';
  String get displayName => destination.isEmpty ? name : '$name->$destination';
}

class RouteStop {
  const RouteStop({required this.order, required this.name, this.position});
  factory RouteStop.fromJson(Map<String, dynamic> j, int index) {
    final lat = _d(_s(j, ['station_lat', 'lat', 'latitude']));
    final lon = _d(_s(j, ['station_lon', 'lon', 'lng', 'longitude']));
    return RouteStop(
      order: _i(j, ['stationOrder', 'order'], index + 1),
      name: _s(j, ['showName', 'stationName', 'name'], '站点'),
      position: lat == null || lon == null ? null : LatLng(lat, lon),
    );
  }
  final int order;
  final String name;
  final LatLng? position;
}

class NearbyStop {
  const NearbyStop({required this.name, required this.distance, this.position});
  factory NearbyStop.fromJson(Map<String, dynamic> j) {
    final lat = _d(_s(j, ['lat', 'latitude']));
    final lon = _d(_s(j, ['lon', 'lng', 'longitude']));
    return NearbyStop(
      name: _s(j, ['name', 'stationName'], '未知站点'),
      distance: _s(j, ['dis', 'distance']),
      position: lat == null || lon == null ? null : LatLng(lat, lon),
    );
  }
  final String name, distance;
  final LatLng? position;
}

class LiveBus {
  const LiveBus({
    required this.number,
    required this.stationOrder,
    this.position,
    this.distance = '',
    this.speed = '',
    this.arriveText = '',
    this.fittedIndex = -1,
  });
  factory LiveBus.fromJson(Map<String, dynamic> j, int index) {
    final merged = <String, dynamic>{...j};
    for (final key in ['gps', 'location', 'position', 'vehicle']) {
      if (j[key] is Map) {
        merged.addAll(Map<String, dynamic>.from(j[key] as Map));
      }
    }
    final lat = _d(_s(merged, ['bus_lat', 'lat', 'latitude', 'gpsLat', 'y']));
    final lon = _d(
      _s(merged, ['bus_lng', 'lon', 'lng', 'longitude', 'gpsLng', 'x']),
    );
    return LiveBus(
      number: _s(merged, [
        'busNumber',
        'busName',
        'busno',
        'busNo',
        'vehicleNo',
        'carNo',
        'name',
      ], '车辆 ${index + 1}'),
      stationOrder: _i(merged, [
        'stationOrder',
        'stationIndex',
        'stationNum',
        'order',
        'seq',
      ]),
      position: lat == null || lon == null ? null : LatLng(lat, lon),
      distance: _s(merged, ['dis', 'distance', 'distanceToStation']),
      speed: _s(merged, ['speed', 'velocity']),
      arriveText: _s(merged, ['arrivalTime', 'arriveTime', 'eta', 'time']),
      fittedIndex: _i(merged, ['nihePointIndex'], -1),
    );
  }
  final String number, distance, speed, arriveText;
  final int stationOrder, fittedIndex;
  final LatLng? position;
}

class RouteBundle {
  const RouteBundle({
    required this.stops,
    required this.geometry,
    required this.routeId,
  });
  final List<RouteStop> stops;
  final List<LatLng> geometry;
  final String routeId;
}

class RealtimeData {
  const RealtimeData({required this.buses, required this.planTime});
  final List<LiveBus> buses;
  final String planTime;
}
