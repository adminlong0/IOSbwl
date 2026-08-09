import CoreLocation
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UIHostingController(rootView: NLBUSAppView())
    self.window = window
    window.makeKeyAndVisible()
  }
}

@MainActor
final class BusStore: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var cityName = "莆田市"
  @Published var cityDisplayName = "莆田公交"
  @Published var searchText = ""
  @Published var searchResults: [SearchItem] = []
  @Published var allLines: [BusLine] = []
  @Published var nearbyStations: [NearbyStation] = []
  @Published var nearbyVehicles: [StationVehicle] = []
  @Published var favoriteLineIDs: [String] = []
  @Published var searchHistory: [String] = []
  @Published var quickLinks: [QuickLink] = QuickLink.defaults
  @Published var themeMode: ThemeMode = .system
  @Published var accent: ThemeAccent = .putianGreen
  @Published var mapFilter = ""
  @Published var message: String?
  @Published var isLoading = false
  @Published var selectedCityKey = "pt111601"

  private let api = BusAPI()
  private var cityKey: String { selectedCityKey }
  private let locationManager = CLLocationManager()
  private var didBootstrap = false

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    loadPreferences()
  }

  func bootstrap() {
    guard !didBootstrap else { return }
    didBootstrap = true
    Task {
      await loadCity()
      await loadAllLines()
      requestNearbyStations()
    }
  }

  var favoriteLines: [BusLine] {
    favoriteLineIDs.compactMap { id in allLines.first { $0.id == id } }
  }

  var filteredLines: [BusLine] {
    let keyword = mapFilter.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else { return allLines }
    return allLines.filter { $0.name.localizedCaseInsensitiveContains(keyword) || $0.destination.localizedCaseInsensitiveContains(keyword) }
  }

  func loadCity() async {
    do {
      let payload = try await api.request(["CMD": "205", "CITYKEY": cityKey])
      if let city = payload["city"] as? [String: Any] {
        cityName = city.string("cityname", fallback: cityName)
        let showName = city.string("showName", fallback: "")
        cityDisplayName = showName.isEmpty ? "\(cityName)公交" : showName
      }
    } catch {
      message = error.localizedDescription
    }
  }

  func reloadCity() async {
    didBootstrap = true
    await loadCity()
    await loadAllLines()
    await loadNearbyStations()
  }

  func search() async {
    let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      searchResults = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "102",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "KEYWORD": keyword,
      ])
      var items: [SearchItem] = []
      for line in payload.array("buslines") {
        items.append(.line(BusLine(dictionary: line)))
      }
      for station in payload.array("busstations") {
        items.append(.station(BusStation(dictionary: station)))
      }
      if !searchHistory.contains(keyword) {
        searchHistory.insert(keyword, at: 0)
        searchHistory = Array(searchHistory.prefix(12))
      }
      searchResults = items
      savePreferences()
    } catch {
      message = error.localizedDescription
    }
  }

  func loadAllLines() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "119",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "KEY": "",
      ])
      allLines = payload.arrayAny(["buslines", "data", "list", "rows", "result"])
        .map(BusLine.init(dictionary:))
        .reduce(into: [BusLine]()) { result, line in
          if !result.contains(where: { $0.id == line.id }) { result.append(line) }
        }
    } catch {
      message = error.localizedDescription
    }
  }

  func requestNearbyStations() {
    locationManager.requestWhenInUseAuthorization()
    locationManager.requestLocation()
  }

  func loadNearbyStations(lng: String = "", lat: String = "") async {
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "106",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "LNG": lng,
        "LAT": lat,
      ])
      nearbyStations = payload.array("data")
        .map(NearbyStation.init(dictionary:))
        .filter { $0.distanceMeters == nil || ($0.distanceMeters ?? 0) <= 500 }
      await loadNearbyVehiclesPreview()
    } catch {
      message = error.localizedDescription
    }
  }

  func loadStationLines(stationName: String) async throws -> [BusLine] {
    let payload = try await api.request([
      "CMD": "115",
      "CITYNAME": cityName,
      "CITYKEY": cityKey,
      "STATIONNAME": stationName,
      "MYLAT": "",
      "MYLNG": "",
      "ALL": "1",
    ])
    return payload.array("data").map(BusLine.init(dictionary:))
  }

  func loadStops(for line: BusLine) async throws -> [RouteStop] {
    var lastError: Error?
    let directions = [line.direction, line.direction == "1" ? "0" : "1", "", "上行", "下行"]
    for direction in directions {
      do {
        let payload = try await api.request(["CMD": "103", "CITYNAME": cityName, "CITYKEY": cityKey, "LINENAME": line.name, "DIRECTION": direction])
        let rows = payload.arrayAny(["data", "list", "stations", "busstations", "stationList"])
        if !rows.isEmpty { return rows.enumerated().map { RouteStop(index: $0.offset, dictionary: $0.element) } }
      } catch { lastError = error }
    }
    throw lastError ?? BusError.invalidData
  }

  func loadRealtime(line: BusLine, stationOrder: Int) async throws -> RealtimeSnapshot {
    var lastError: Error?
    let directions = [line.direction, line.direction == "1" ? "0" : "1", "", "上行", "下行"]
    for direction in directions {
      do {
        let payload = try await api.request(["CMD": "104", "CITYNAME": cityName, "CITYKEY": cityKey, "LINENAME": line.name, "DIRECTION": direction, "STATIONORDER": "\(stationOrder)"])
        let snapshot = RealtimeSnapshot(dictionary: payload)
        if !snapshot.buses.isEmpty || !snapshot.planTime.isEmpty { return snapshot }
      } catch { lastError = error }
    }
    throw lastError ?? BusError.message("当前线路暂无实时车辆")
  }

  func loadStops(for lineName: String, direction: String) async throws -> [RouteStop] {
    let payload = try await api.request(["CMD": "103", "CITYNAME": cityName, "CITYKEY": cityKey, "LINENAME": lineName, "DIRECTION": direction])
    return payload.arrayAny(["data", "list", "stations", "busstations"]).enumerated().map { RouteStop(index: $0.offset, dictionary: $0.element) }
  }

  func toggleFavorite(_ line: BusLine) {
    if favoriteLineIDs.contains(line.id) {
      favoriteLineIDs.removeAll { $0 == line.id }
    } else {
      favoriteLineIDs.insert(line.id, at: 0)
    }
    savePreferences()
  }

  func isFavorite(_ line: BusLine) -> Bool {
    favoriteLineIDs.contains(line.id)
  }

  func applyBackup(_ backup: AppBackup) {
    favoriteLineIDs = backup.favoriteLineIDs
    searchHistory = backup.searchHistory
    themeMode = backup.themeMode
    accent = backup.accent
    quickLinks = backup.quickLinks.isEmpty ? QuickLink.defaults : backup.quickLinks
    savePreferences()
  }

  func backup() -> AppBackup {
    AppBackup(
      favoriteLineIDs: favoriteLineIDs,
      searchHistory: searchHistory,
      themeMode: themeMode,
      accent: accent,
      quickLinks: quickLinks
    )
  }

  func savePreferences() {
    let encoder = JSONEncoder()
    UserDefaults.standard.set(try? encoder.encode(favoriteLineIDs), forKey: "favoriteLineIDs")
    UserDefaults.standard.set(try? encoder.encode(searchHistory), forKey: "searchHistory")
    UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
    UserDefaults.standard.set(accent.rawValue, forKey: "accent")
    UserDefaults.standard.set(try? encoder.encode(quickLinks), forKey: "quickLinks")
  }

  private func loadPreferences() {
    let decoder = JSONDecoder()
    if let data = UserDefaults.standard.data(forKey: "favoriteLineIDs"),
       let value = try? decoder.decode([String].self, from: data) {
      favoriteLineIDs = value
    }
    if let data = UserDefaults.standard.data(forKey: "searchHistory"),
       let value = try? decoder.decode([String].self, from: data) {
      searchHistory = value
    }
    if let raw = UserDefaults.standard.string(forKey: "themeMode"),
       let value = ThemeMode(rawValue: raw) {
      themeMode = value
    }
    if let raw = UserDefaults.standard.string(forKey: "accent"),
       let value = ThemeAccent(rawValue: raw) {
      accent = value
    }
    if let data = UserDefaults.standard.data(forKey: "quickLinks"),
       let value = try? decoder.decode([QuickLink].self, from: data),
       !value.isEmpty {
      quickLinks = value
    }
  }

  private func loadNearbyVehiclesPreview() async {
    var previews: [StationVehicle] = []
    for station in nearbyStations.prefix(3) {
      guard let line = try? await loadStationLines(stationName: station.name).first else { continue }
      guard let snapshot = try? await loadRealtime(line: line, stationOrder: 1) else { continue }
      for bus in snapshot.buses.prefix(1) {
        previews.append(StationVehicle(station: station.name, line: line, bus: bus))
      }
    }
    nearbyVehicles = Array(previews.prefix(3))
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in
      await loadNearbyStations(
        lng: "\(location.coordinate.longitude)",
        lat: "\(location.coordinate.latitude)"
      )
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      await loadNearbyStations()
    }
  }
}

final class BusAPI {
  private let endpoint = URL(string: "https://h5.mygolbs.com/ApiData.do")!

  func request(_ parameters: [String: String]) async throws -> [String: Any] {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
    request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    request.setValue("https://h5.mygolbs.com/?areacode=pt111601", forHTTPHeaderField: "Referer")
    request.setValue("https://h5.mygolbs.com", forHTTPHeaderField: "Origin")
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
      forHTTPHeaderField: "User-Agent"
    )
    request.httpBody = parameters
      .map { key, value in "\(key.urlEncoded)=\(value.urlEncoded)" }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw BusError.server
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw BusError.invalidData
    }
    if object.int("status") == 1 || object["status"] == nil {
      return object
    }
    throw BusError.message(object.string("msg", fallback: "请求失败"))
  }
}

enum BusError: LocalizedError {
  case server
  case invalidData
  case message(String)

  var errorDescription: String? {
    switch self {
    case .server: return "公交服务暂时不可用"
    case .invalidData: return "无法解析公交数据"
    case .message(let text): return text
    }
  }
}

struct BusLine: Identifiable, Hashable, Codable {
  var id: String { "\(name)-\(direction)" }
  let name: String
  let direction: String
  let destination: String
  let beginTime: String
  let endTime: String
  let fare: String
  let mileage: String
  let remark: String
  let summary: String

  init(dictionary: [String: Any]) {
    name = dictionary.string("lineName", fallback: dictionary.string("routeName", fallback: dictionary.string("name", fallback: "未知线路")))
    direction = dictionary.string("upperOrDown", fallback: dictionary.string("uod", fallback: dictionary.string("direction", fallback: "1")))
    destination = dictionary.string("to", fallback: dictionary.string("endStation", fallback: dictionary.string("endName", fallback: "")))
    beginTime = dictionary.string("beginTime", fallback: dictionary.string("startTime", fallback: ""))
    endTime = dictionary.string("endTime", fallback: dictionary.string("lastTime", fallback: ""))
    fare = dictionary.string("price", fallback: dictionary.string("ticketPrice", fallback: dictionary.string("fare", fallback: "")))
    mileage = dictionary.string("mileage", fallback: dictionary.string("length", fallback: ""))
    remark = dictionary.string("remark", fallback: dictionary.string("memo", fallback: ""))
    summary = dictionary.string("summary", fallback: dictionary.string("lineDesc", fallback: ""))
  }
}

struct BusStation: Identifiable, Hashable {
  var id: String { "\(name)-\(latitude)-\(longitude)" }
  let name: String
  let latitude: String
  let longitude: String

  init(dictionary: [String: Any]) {
    name = dictionary.string("stationName", fallback: dictionary.string("name", fallback: "未知站点"))
    latitude = dictionary.string("lat", fallback: dictionary.string("latitude", fallback: ""))
    longitude = dictionary.string("lon", fallback: dictionary.string("lng", fallback: dictionary.string("longitude", fallback: "")))
  }
}

struct NearbyStation: Identifiable, Hashable, MapPointRepresentable {
  var id: String { "\(name)-\(latitude)-\(longitude)" }
  let name: String
  let distance: String
  let latitude: String
  let longitude: String

  var distanceMeters: Int? {
    Int(distance.filter { $0.isNumber })
  }

  init(dictionary: [String: Any]) {
    name = dictionary.string("name", fallback: dictionary.string("stationName", fallback: "未知站点"))
    distance = dictionary.string("dis", fallback: dictionary.string("distance", fallback: ""))
    latitude = dictionary.string("lat", fallback: dictionary.string("latitude", fallback: ""))
    longitude = dictionary.string("lon", fallback: dictionary.string("lng", fallback: dictionary.string("longitude", fallback: "")))
  }
}

struct RouteStop: Identifiable, Hashable, MapPointRepresentable {
  var id: Int { order }
  let order: Int
  let name: String
  let latitude: String
  let longitude: String

  init(index: Int, dictionary: [String: Any]) {
    order = dictionary.int("stationOrder", fallback: dictionary.int("order", fallback: index + 1))
    name = dictionary.string("stationName", fallback: dictionary.string("name", fallback: "站点"))
    latitude = dictionary.string("lat", fallback: dictionary.string("latitude", fallback: ""))
    longitude = dictionary.string("lon", fallback: dictionary.string("lng", fallback: dictionary.string("longitude", fallback: "")))
  }
}

struct LiveBus: Identifiable, Hashable, MapPointRepresentable {
  var id: String { "\(busName)-\(stationOrder)-\(distance)-\(latitude)-\(longitude)" }
  var name: String { busName }
  let busName: String
  let stationOrder: Int
  let distance: String
  let speed: String
  let latitude: String
  let longitude: String
  let arriveText: String

  init(index: Int, dictionary: [String: Any]) {
    let source = dictionary.mergedNestedObjects(keys: ["gps", "location", "position", "vehicle"])
    busName = source.stringAny(["busName", "busno", "busNo", "vehicleNo", "carNo", "name", "id"], fallback: "车辆 \(index + 1)")
    stationOrder = source.intAny(["stationOrder", "stationIndex", "stationNum", "order", "seq"], fallback: 0)
    distance = source.stringAny(["dis", "distance", "distanceToStation", "remainDistance"], fallback: "")
    speed = source.stringAny(["speed", "velocity"], fallback: "")
    latitude = source.stringAny(["lat", "latitude", "gpsLat", "y"], fallback: "")
    longitude = source.stringAny(["lon", "lng", "longitude", "gpsLng", "x"], fallback: "")
    arriveText = source.stringAny(["arrivalTime", "arriveTime", "eta", "time", "remainTime"], fallback: "")
  }
}

struct RealtimeSnapshot {
  let planTime: String
  let buses: [LiveBus]

  init(dictionary: [String: Any]) {
    let source = (dictionary["data"] as? [String: Any]) ?? dictionary
    planTime = source.stringAny(["planTime", "nextTime", "firstArriveTime", "arrivalTime"], fallback: "")
    buses = source.arrayAny(["list", "buslist", "vehicleList", "vehicles", "rows", "data"])
      .enumerated().map { LiveBus(index: $0.offset, dictionary: $0.element) }
  }
}

struct StationVehicle: Identifiable, Hashable {
  let id = UUID()
  let station: String
  let line: BusLine
  let bus: LiveBus
}

enum SearchItem: Identifiable, Hashable {
  case line(BusLine)
  case station(BusStation)

  var id: String {
    switch self {
    case .line(let line): return "line-\(line.id)"
    case .station(let station): return "station-\(station.id)"
    }
  }
}

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }
  var title: String {
    switch self {
    case .system: return "跟随系统"
    case .light: return "亮色模式"
    case .dark: return "暗色模式"
    }
  }
}

enum ThemeAccent: String, CaseIterable, Codable, Identifiable {
  case putianGreen
  case blue
  case orange
  case pink
  case graphite

  var id: String { rawValue }
  var title: String {
    switch self {
    case .putianGreen: return "公交绿"
    case .blue: return "海湾蓝"
    case .orange: return "日落橙"
    case .pink: return "荔枝粉"
    case .graphite: return "石墨灰"
    }
  }
  var color: Color {
    switch self {
    case .putianGreen: return .green
    case .blue: return .blue
    case .orange: return .orange
    case .pink: return .pink
    case .graphite: return .gray
    }
  }
}

struct QuickLink: Identifiable, Codable, Hashable {
  let id: UUID
  var title: String
  var subtitle: String
  var url: String
  var systemImage: String

  static let defaults = [
    QuickLink(id: UUID(), title: "Apple 钱包", subtitle: "打开系统钱包", url: "shoebox://", systemImage: "wallet.pass"),
    QuickLink(id: UUID(), title: "莆田市民卡", subtitle: "微信小程序：莆田市民卡", url: "weixin://dl/business/?t=vHnajJlAguq", systemImage: "creditcard"),
  ]
}

struct AppBackup: Codable {
  var favoriteLineIDs: [String]
  var searchHistory: [String]
  var themeMode: ThemeMode
  var accent: ThemeAccent
  var quickLinks: [QuickLink]
}

struct BackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var backup: AppBackup

  init(backup: AppBackup) {
    self.backup = backup
  }

  init(configuration: ReadConfiguration) throws {
    let data = configuration.file.regularFileContents ?? Data()
    backup = try JSONDecoder().decode(AppBackup.self, from: data)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let data = try JSONEncoder().encode(backup)
    return FileWrapper(regularFileWithContents: data)
  }
}

protocol MapPointRepresentable {
  var name: String { get }
  var latitude: String { get }
  var longitude: String { get }
}

extension MapPointRepresentable {
  var coordinate: CLLocationCoordinate2D? {
    guard let lat = Double(latitude), let lng = Double(longitude), lat != 0, lng != 0 else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
  }
}

struct MapPinItem: Identifiable {
  let id = UUID()
  let title: String
  let subtitle: String
  let coordinate: CLLocationCoordinate2D
  let systemImage: String
}

struct NLBUSAppView: View {
  @StateObject private var store = BusStore()
  @State private var quickSheet = false

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      TabView {
        HomeView()
          .environmentObject(store)
          .tabItem { Label("主页", systemImage: "location.fill") }
        RoutesView()
          .environmentObject(store)
          .tabItem { Label("路线", systemImage: "bus") }
        TransitMapView()
          .environmentObject(store)
          .tabItem { Label("地图", systemImage: "map") }
        SettingsView()
          .environmentObject(store)
          .tabItem { Label("设置", systemImage: "gearshape") }
      }

      Button {
        quickSheet = true
      } label: {
        Image(systemName: "plus")
          .font(.title3.weight(.semibold))
          .frame(width: 54, height: 54)
          .nlbusGlass()
          .clipShape(Circle())
          .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
      }
      .padding(.trailing, 18)
      .padding(.bottom, 72)
      .accessibilityLabel("快捷操作")
    }
    .accentColor(store.accent.color)
    .preferredColorScheme(colorScheme)
    .task { store.bootstrap() }
    .sheet(isPresented: $quickSheet) {
      QuickActionSheet()
        .environmentObject(store)
    }
    .alert("提示", isPresented: Binding(
      get: { store.message != nil },
      set: { if !$0 { store.message = nil } }
    )) {
      Button("好", role: .cancel) { store.message = nil }
    } message: {
      Text(store.message ?? "")
    }
  }

  private var colorScheme: ColorScheme? {
    switch store.themeMode {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

struct HomeView: View {
  @EnvironmentObject private var store: BusStore
  @State private var searchTask: Task<Void, Never>?

  var body: some View {
    NavigationView {
      List {
        Section {
          TextField("搜索线路、站点", text: $store.searchText)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .submitLabel(.search)
            .onChange(of: store.searchText) { _ in scheduleSearch() }
            .onSubmit { Task { await store.search() } }
        }

        if !store.searchResults.isEmpty {
          Section("搜索结果") {
            ForEach(store.searchResults) { item in
              SearchResultRow(item: item)
            }
          }
        } else if !store.searchHistory.isEmpty {
          Section("最近搜索") {
            ForEach(store.searchHistory.prefix(5), id: \.self) { keyword in
              Button {
                store.searchText = keyword
                Task { await store.search() }
              } label: {
                Label(keyword, systemImage: "clock.arrow.circlepath")
              }
            }
          }
        }

        Section {
          Button {
            store.requestNearbyStations()
          } label: {
            Label("刷新 500 米内站点", systemImage: "location.fill")
          }
        }

        Section("附近站点") {
          if store.nearbyStations.isEmpty {
            EmptyStateView(symbol: "location.slash", title: "暂无附近站点", message: "允许定位后会展示 500 米内的公交站。")
          } else {
            ForEach(store.nearbyStations) { station in
              NavigationLink(destination: StationDetailView(stationName: station.name).environmentObject(store)) {
                NearbyStationRow(station: station)
              }
            }
          }
        }

        Section("最近车辆") {
          if store.nearbyVehicles.isEmpty {
            Text("暂无车辆预览，点击站点可查看完整车辆列表。")
              .foregroundColor(.secondary)
          } else {
            ForEach(store.nearbyVehicles) { item in
              NavigationLink(destination: LineDetailView(line: item.line, focusStationName: item.station).environmentObject(store)) {
                VStack(alignment: .leading, spacing: 5) {
                  Text(item.line.name).font(.headline)
                  Text("\(item.station) · \(item.bus.busName)")
                    .foregroundColor(.secondary)
                  if !item.bus.distance.isEmpty {
                    Text(item.bus.distance)
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
                .padding(.vertical, 3)
              }
            }
          }
        }
      }
      .navigationTitle("附近")
      .refreshable { store.requestNearbyStations() }
    }
  }

  private func scheduleSearch() {
    searchTask?.cancel()
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      await store.search()
    }
  }
}

struct SearchResultRow: View {
  @EnvironmentObject private var store: BusStore
  let item: SearchItem

  var body: some View {
    switch item {
    case .line(let line):
      NavigationLink(destination: LineDetailView(line: line).environmentObject(store)) {
        LineRow(line: line)
      }
    case .station(let station):
      NavigationLink(destination: StationDetailView(stationName: station.name).environmentObject(store)) {
        Label(station.name, systemImage: "mappin.and.ellipse")
      }
    }
  }
}

struct RoutesView: View {
  @EnvironmentObject private var store: BusStore

  var body: some View {
    NavigationView {
      List {
        if !store.favoriteLines.isEmpty {
          Section("收藏路线") {
            ForEach(store.favoriteLines) { line in
              NavigationLink(destination: LineDetailView(line: line).environmentObject(store)) {
                LineRow(line: line, pinned: true)
              }
            }
          }
        }

        Section("全部路线") {
          if store.allLines.isEmpty {
            EmptyStateView(symbol: "bus", title: "暂无路线", message: "下拉刷新路线列表。")
          } else {
            ForEach(store.allLines) { line in
              NavigationLink(destination: LineDetailView(line: line).environmentObject(store)) {
                LineRow(line: line)
              }
            }
          }
        }
      }
      .navigationTitle("路线")
      .refreshable { await store.loadAllLines() }
    }
  }
}

struct LineDetailView: View {
  @EnvironmentObject private var store: BusStore
  let line: BusLine
  var focusStationName: String?
  @State private var currentLine: BusLine
  @State private var stops: [RouteStop] = []
  @State private var buses: [LiveBus] = []
  @State private var selectedOrder = 1
  @State private var planTime = ""
  @State private var sortMode: VehicleSortMode = .arrival

  init(line: BusLine, focusStationName: String? = nil) {
    self.line = line
    self.focusStationName = focusStationName
    _currentLine = State(initialValue: line)
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(currentLine.name).font(.title2.bold())
          if !currentLine.destination.isEmpty {
            Label("开往 \(currentLine.destination)", systemImage: "arrow.forward.circle")
              .foregroundColor(.secondary)
          }
          HStack {
            Button {
              store.toggleFavorite(currentLine)
            } label: {
              Label(store.isFavorite(currentLine) ? "已收藏" : "收藏", systemImage: store.isFavorite(currentLine) ? "star.fill" : "star")
            }
            Button {
              switchDirection()
            } label: {
              Label("双向切换", systemImage: "arrow.left.arrow.right")
            }
          }
          .buttonStyle(.bordered)
        }
      }

      Section("运营信息") {
        if !operationTime.isEmpty { InfoRow(title: "首末班", value: operationTime) }
        if !currentLine.fare.isEmpty { InfoRow(title: "收费信息", value: currentLine.fare) }
        if !planTime.isEmpty { InfoRow(title: "预计最近发车", value: planTime) }
        if !currentLine.mileage.isEmpty { InfoRow(title: "线路里程", value: currentLine.mileage) }
        if !currentLine.summary.isEmpty { InfoRow(title: "线路概括", value: currentLine.summary) }
        if !currentLine.remark.isEmpty { InfoRow(title: "备注", value: currentLine.remark) }
      }

      Section("到站分析") {
        Picker("排序", selection: $sortMode) {
          ForEach(VehicleSortMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        if sortedBuses.isEmpty {
          Text("暂无实时车辆数据")
            .foregroundColor(.secondary)
        } else {
          ForEach(sortedBuses) { bus in
            VehicleRow(bus: bus, selectedOrder: selectedOrder)
          }
        }
      }

      Section("时刻表") {
        Text(planTime.isEmpty ? "实时发车时间暂未返回，可下拉刷新。" : "当前最近发车：\(planTime)")
          .foregroundColor(.secondary)
      }

      Section("车辆实时地图") {
        MiniMapView(stops: stops, buses: buses)
          .frame(height: 220)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }

      Section("站点列表") {
        ForEach(stops) { stop in
          Button {
            selectedOrder = stop.order
            Task { await loadRealtime() }
          } label: {
            StopRow(stop: stop, selectedOrder: selectedOrder, hasBus: buses.contains { $0.stationOrder == stop.order })
          }
        }
      }
    }
    .navigationTitle(currentLine.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button {
        Task { await loadAll() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
    }
    .task { await loadAll() }
    .refreshable { await loadAll() }
  }

  private var operationTime: String {
    if currentLine.beginTime.isEmpty && currentLine.endTime.isEmpty { return "" }
    return "\(currentLine.beginTime) - \(currentLine.endTime)"
  }

  private var sortedBuses: [LiveBus] {
    switch sortMode {
    case .arrival:
      return buses.sorted { abs($0.stationOrder - selectedOrder) < abs($1.stationOrder - selectedOrder) }
    case .station:
      return buses.sorted { $0.stationOrder < $1.stationOrder }
    case .distance:
      return buses.sorted { $0.distance.numericValue < $1.distance.numericValue }
    }
  }

  private func switchDirection() {
    let nextDirection = currentLine.direction == "1" ? "0" : "1"
    if let match = store.allLines.first(where: { $0.name == currentLine.name && $0.direction == nextDirection }) {
      currentLine = match
    } else {
      currentLine = BusLine.synthetic(from: currentLine, direction: nextDirection)
    }
    selectedOrder = 1
    Task { await loadAll() }
  }

  private func loadAll() async {
    do {
      stops = try await store.loadStops(for: currentLine)
      if let focus = focusStationName, let matched = stops.first(where: { $0.name == focus }) {
        selectedOrder = matched.order
      } else if selectedOrder <= 0 {
        selectedOrder = stops.first?.order ?? 1
      }
      await loadRealtime()
    } catch {
      store.message = error.localizedDescription
    }
  }

  private func loadRealtime() async {
    do {
      let snapshot = try await store.loadRealtime(line: currentLine, stationOrder: selectedOrder)
      planTime = snapshot.planTime
      buses = snapshot.buses
    } catch {
      store.message = error.localizedDescription
    }
  }
}

enum VehicleSortMode: String, CaseIterable, Identifiable {
  case arrival
  case station
  case distance

  var id: String { rawValue }
  var title: String {
    switch self {
    case .arrival: return "到站"
    case .station: return "站序"
    case .distance: return "距离"
    }
  }
}

struct StationDetailView: View {
  @EnvironmentObject private var store: BusStore
  let stationName: String
  @State private var lines: [BusLine] = []
  @State private var vehicles: [StationVehicle] = []

  var body: some View {
    List {
      Section("经过线路") {
        if lines.isEmpty {
          EmptyStateView(symbol: "mappin", title: stationName, message: "暂无经过线路。")
        } else {
          ForEach(lines) { line in
            NavigationLink(destination: LineDetailView(line: line, focusStationName: stationName).environmentObject(store)) {
              LineRow(line: line)
            }
          }
        }
      }

      Section("本站车辆") {
        if vehicles.isEmpty {
          Text("暂无本站实时车辆")
            .foregroundColor(.secondary)
        } else {
          ForEach(vehicles) { item in
            VStack(alignment: .leading, spacing: 5) {
              Text(item.line.name).font(.headline)
              Text(item.bus.busName)
                .foregroundColor(.secondary)
              if !item.bus.distance.isEmpty {
                Text(item.bus.distance).font(.caption).foregroundColor(.secondary)
              }
            }
          }
        }
      }

      Section("周边站点") {
        ForEach(store.nearbyStations.filter { $0.name != stationName }.prefix(8)) { station in
          NavigationLink(destination: StationDetailView(stationName: station.name).environmentObject(store)) {
            NearbyStationRow(station: station)
          }
        }
      }
    }
    .navigationTitle(stationName)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    do {
      lines = try await store.loadStationLines(stationName: stationName)
      var nextVehicles: [StationVehicle] = []
      for line in lines.prefix(8) {
        let snapshot = try await store.loadRealtime(line: line, stationOrder: 1)
        nextVehicles.append(contentsOf: snapshot.buses.map { StationVehicle(station: stationName, line: line, bus: $0) })
      }
      vehicles = nextVehicles.sorted { $0.bus.distance.numericValue < $1.bus.distance.numericValue }
    } catch {
      store.message = error.localizedDescription
    }
  }
}

struct TransitMapView: View {
  @EnvironmentObject private var store: BusStore
  @State private var selectedLine: BusLine?
  @State private var stops: [RouteStop] = []
  @State private var buses: [LiveBus] = []

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        List {
          Section {
            TextField("筛选路线、车辆、站点", text: $store.mapFilter)
              .textInputAutocapitalization(.never)
              .disableAutocorrection(true)
          }

          Section("路线") {
            ForEach(store.filteredLines) { line in
              Button {
                selectedLine = line
                Task { await load(line: line) }
              } label: {
                LineRow(line: line)
              }
            }
          }
        }
        .frame(maxHeight: 290)

        FullMapView(stops: stops, buses: buses, nearbyStations: store.nearbyStations)
      }
      .task { await store.loadNearbyStations() }
      .navigationTitle("地图")
      .toolbar {
        Button {
          if let selectedLine {
            Task { await load(line: selectedLine) }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
  }

  private func load(line: BusLine) async {
    do {
      stops = try await store.loadStops(for: line)
      let snapshot = try await store.loadRealtime(line: line, stationOrder: stops.first?.order ?? 1)
      buses = snapshot.buses
    } catch {
      store.message = error.localizedDescription
    }
  }
}

struct SettingsView: View {
  @EnvironmentObject private var store: BusStore
  @State private var exporting = false
  @State private var importing = false

  var body: some View {
    NavigationView {
      Form {
        Section("外观") {
          Picker("主题风格", selection: $store.themeMode) {
            ForEach(ThemeMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          Picker("主题色", selection: $store.accent) {
            ForEach(ThemeAccent.allCases) { accent in
              HStack {
                Circle().fill(accent.color).frame(width: 12, height: 12)
                Text(accent.title)
              }
              .tag(accent)
            }
          }
        }
        .onChange(of: store.themeMode) { _ in store.savePreferences() }
        .onChange(of: store.accent) { _ in store.savePreferences() }

        Section("配置备份") {
          Button {
            exporting = true
          } label: {
            Label("导出本地备份", systemImage: "square.and.arrow.up")
          }
          Button {
            importing = true
          } label: {
            Label("导入恢复配置", systemImage: "square.and.arrow.down")
          }
        }

        Section("软件信息") {
          SettingsInfoRow(title: "名称", value: "NLBUS")
          Picker("城市", selection: $store.selectedCityKey) {
            Text("莆田市").tag("pt111601")
          }
          TextField("城市代码", text: $store.selectedCityKey)
            .textInputAutocapitalization(.never)
            .onSubmit { Task { await store.reloadCity() } }
          SettingsInfoRow(title: "开发者", value: "@奶龙")
          SettingsInfoRow(title: "数据来源", value: "mygolbs 实时公交接口")
        }
      }
      .navigationTitle("设置")
      .fileExporter(
        isPresented: $exporting,
        document: BackupDocument(backup: store.backup()),
        contentType: .json,
        defaultFilename: "NLBUS-Backup"
      ) { result in
        if case .failure(let error) = result {
          store.message = error.localizedDescription
        }
      }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
        do {
          let url = try result.get()
          guard url.startAccessingSecurityScopedResource() else { return }
          defer { url.stopAccessingSecurityScopedResource() }
          let data = try Data(contentsOf: url)
          let backup = try JSONDecoder().decode(AppBackup.self, from: data)
          store.applyBackup(backup)
        } catch {
          store.message = error.localizedDescription
        }
      }
    }
  }
}

struct QuickActionSheet: View {
  @EnvironmentObject private var store: BusStore
  @Environment(\.dismiss) private var dismiss
  @State private var selectedLine: BusLine?
  @State private var selectedStation = ""
  @State private var notifyMode: NotifyMode = .stations
  @State private var notifyValue = 2

  var body: some View {
    NavigationView {
      List {
        Section("快捷跳转") {
          ForEach(store.quickLinks) { link in
            Button {
              open(link.url)
            } label: {
              Label {
                VStack(alignment: .leading) {
                  Text(link.title)
                  Text(link.subtitle).font(.caption).foregroundColor(.secondary)
                }
              } icon: {
                Image(systemName: link.systemImage)
              }
            }
          }
        }

        Section("到站通知") {
          Picker("路线", selection: $selectedLine) {
            Text("选择路线").tag(Optional<BusLine>.none)
            ForEach(store.allLines) { line in
              Text(line.name).tag(Optional(line))
            }
          }
          if let selectedLine {
            StationPicker(line: selectedLine, selection: $selectedStation)
          } else {
            Text("请先选择线路").foregroundColor(.secondary)
          }
          Picker("提醒模式", selection: $notifyMode) {
            ForEach(NotifyMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          Stepper("\(notifyMode.unitPrefix)\(notifyValue)\(notifyMode.unitSuffix)", value: $notifyValue, in: 1...10)
          Button {
            scheduleNotification()
          } label: {
            Label("创建到站提醒", systemImage: "bell.badge")
          }
        }
      }
      .navigationTitle("快捷操作")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        Button("完成") { dismiss() }
      }
    }
  }

  private func open(_ raw: String) {
    guard let url = URL(string: raw) else { return }
    if raw.hasPrefix("weixin://"), !UIApplication.shared.canOpenURL(url) {
      UIApplication.shared.open(URL(string: "https://wxmpurl.cn/vHnajJlAguq")!)
    } else {
      UIApplication.shared.open(url)
    }
    dismiss()
  }

  private func scheduleNotification() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = "NLBUS 到站提醒"
      let lineName = selectedLine?.name ?? "指定车辆"
      content.body = "\(lineName) 接近 \(selectedStation.isEmpty ? "目标站点" : selectedStation)，请留意乘车。"
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
      )
      UNUserNotificationCenter.current().add(request)
    }
    store.message = "已创建本地提醒。实时轮询触发需要后台定位/推送证书，当前先以本地通知验证流程。"
    dismiss()
  }
}

struct StationPicker: View {
  @EnvironmentObject private var store: BusStore
  let line: BusLine
  @Binding var selection: String
  @State private var stops: [RouteStop] = []

  var body: some View {
    Picker("绑定站点", selection: $selection) {
      Text("选择站点").tag("")
      ForEach(stops) { stop in
        Text(stop.name).tag(stop.name)
      }
    }
    .task(id: line.id) {
      do { stops = try await store.loadStops(for: line) }
      catch { store.message = error.localizedDescription }
    }
  }
}

struct SettingsInfoRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.trailing)
    }
  }
}

enum NotifyMode: String, CaseIterable, Identifiable {
  case distance
  case stations

  var id: String { rawValue }
  var title: String { self == .distance ? "距离提醒" : "站数提醒" }
  var unitPrefix: String { self == .distance ? "离站还有 " : "离站还有 " }
  var unitSuffix: String { self == .distance ? " km" : " 站" }
}

struct FullMapView: View {
  let stops: [RouteStop]
  let buses: [LiveBus]
  let nearbyStations: [NearbyStation]
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 25.431, longitude: 119.007),
    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
  )

  var body: some View {
    Map(coordinateRegion: $region, annotationItems: pins) { item in
      MapAnnotation(coordinate: item.coordinate) {
        VStack(spacing: 2) {
          Image(systemName: item.systemImage)
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(7)
            .background(item.systemImage.contains("bus") ? Color.green : Color.blue)
            .clipShape(Circle())
          Text(item.title)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial)
            .clipShape(Capsule())
        }
      }
    }
    .onChange(of: pins.count) { _ in recenter() }
    .onAppear { recenter() }
  }

  private var pins: [MapPinItem] {
    var items: [MapPinItem] = []
    items += stops.compactMap { stop in
      guard let coordinate = stop.coordinate else { return nil }
      return MapPinItem(title: stop.name, subtitle: "\(stop.order)", coordinate: coordinate, systemImage: "mappin")
    }
    items += buses.compactMap { bus in
      guard let coordinate = bus.coordinate else { return nil }
      return MapPinItem(title: bus.busName, subtitle: bus.distance, coordinate: coordinate, systemImage: "bus.fill")
    }
    items += nearbyStations.compactMap { station in
      guard let coordinate = station.coordinate else { return nil }
      return MapPinItem(title: station.name, subtitle: station.distance, coordinate: coordinate, systemImage: "mappin.circle")
    }
    return items
  }

  private func recenter() {
    guard let first = pins.first else { return }
    region.center = first.coordinate
    region.span = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
  }
}

extension View {
  func nlbusGlass() -> some View {
    // Keep the rendering surface available on the current GitHub Xcode SDK.
    // The system material is the safe Liquid Glass fallback on iOS 18.
    self.background(.regularMaterial)
  }
}

struct MiniMapView: View {
  let stops: [RouteStop]
  let buses: [LiveBus]

  var body: some View {
    FullMapView(stops: stops, buses: buses, nearbyStations: [])
  }
}

struct LineRow: View {
  let line: BusLine
  var pinned = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: pinned ? "star.circle.fill" : "bus")
        .foregroundColor(pinned ? .yellow : .green)
        .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 4) {
        Text(line.name).font(.headline)
        if !line.destination.isEmpty {
          Text("开往 \(line.destination)").font(.subheadline).foregroundColor(.secondary)
        }
      }
    }
    .padding(.vertical, 3)
  }
}

struct NearbyStationRow: View {
  let station: NearbyStation

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(station.name).font(.headline)
      Text(station.distance.isEmpty ? "500 米范围内" : "\(station.distance)m")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 3)
  }
}

struct VehicleRow: View {
  let bus: LiveBus
  let selectedOrder: Int

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "bus.fill")
        .foregroundColor(.green)
      VStack(alignment: .leading, spacing: 4) {
        Text(bus.busName).font(.headline)
        Text(status)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      Spacer()
      if !bus.distance.isEmpty {
        Text(bus.distance)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 3)
  }

  private var status: String {
    let delta = bus.stationOrder - selectedOrder
    if delta == 0 { return "车辆在当前站附近" }
    if delta > 0 { return "已过当前站 \(delta) 站" }
    return "距离当前站约 \(abs(delta)) 站"
  }
}

struct StopRow: View {
  let stop: RouteStop
  let selectedOrder: Int
  let hasBus: Bool

  var body: some View {
    HStack(spacing: 10) {
      Text("\(stop.order)")
        .font(.caption.monospacedDigit())
        .foregroundColor(.secondary)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(stop.name)
          .font(selectedOrder == stop.order ? .headline.bold() : .body)
        if selectedOrder + 1 == stop.order {
          Text("下一站")
            .font(.caption)
            .foregroundColor(.green)
        }
      }
      Spacer()
      if hasBus {
        Image(systemName: "bus.fill").foregroundColor(.green)
      }
      if selectedOrder == stop.order {
        Image(systemName: "location.circle.fill").foregroundColor(.green)
      }
    }
    .contentShape(Rectangle())
  }
}

struct InfoRow: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.caption).foregroundColor(.secondary)
      Text(value).font(.body)
    }
    .padding(.vertical, 2)
  }
}

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 38)).foregroundColor(.secondary)
      Text(title).font(.headline)
      Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
  }
}

extension BusLine {
  static func synthetic(from line: BusLine, direction: String) -> BusLine {
    BusLine(dictionary: [
      "lineName": line.name,
      "upperOrDown": direction,
      "to": line.destination,
      "beginTime": line.beginTime,
      "endTime": line.endTime,
      "price": line.fare,
      "mileage": line.mileage,
      "remark": line.remark,
      "summary": line.summary,
    ])
  }
}

extension Dictionary where Key == String, Value == Any {
  func mergedNestedObjects(keys: [String]) -> [String: Any] {
    var result = self
    for key in keys {
      if let nested = self[key] as? [String: Any] { result.merge(nested) { current, _ in current } }
    }
    return result
  }

  func stringAny(_ keys: [String], fallback: String = "") -> String {
    for key in keys { let value = string(key); if !value.isEmpty { return value } }
    return fallback
  }

  func intAny(_ keys: [String], fallback: Int = 0) -> Int {
    for key in keys { let value = int(key); if value != 0 { return value } }
    return fallback
  }

  func arrayAny(_ keys: [String]) -> [[String: Any]] {
    for key in keys { if let value = self[key] as? [[String: Any]], !value.isEmpty { return value } }
    return []
  }

  func string(_ key: String, fallback: String = "") -> String {
    if let value = self[key] as? String { return value }
    if let value = self[key] as? NSNumber { return value.stringValue }
    if let value = self[key] { return "\(value)" }
    return fallback
  }

  func int(_ key: String, fallback: Int = 0) -> Int {
    if let value = self[key] as? Int { return value }
    if let value = self[key] as? NSNumber { return value.intValue }
    if let value = self[key] as? String, let intValue = Int(value) { return intValue }
    return fallback
  }

  func array(_ key: String) -> [[String: Any]] {
    self[key] as? [[String: Any]] ?? []
  }
}

extension String {
  var urlEncoded: String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?")
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }

  var numericValue: Int {
    Int(filter { $0.isNumber }) ?? Int.max
  }
}
