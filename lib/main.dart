import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_store.dart';
import 'models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  final store = AppStore();
  @override
  void initState() {
    super.initState();
    store.initialize();
  }

  @override
  Widget build(BuildContext context) => StoreScope(
    store: store,
    child: AnimatedBuilder(
      animation: store,
      builder: (_, _) => MaterialApp(
        title: 'NLBUS',
        debugShowCheckedModeBanner: false,
        themeMode: store.themeMode,
        theme: _theme(Brightness.light, store.accent),
        darkTheme: _theme(Brightness.dark, store.accent),
        home: const AppShell(),
      ),
    ),
  );
}

ThemeData _theme(Brightness brightness, Color seed) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansSC',
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface.withValues(alpha: .92),
      height: 68,
      indicatorColor: scheme.primaryContainer,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: .5,
      backgroundColor: scheme.surface.withValues(alpha: .94),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(10),
      ),
      prefixIconColor: scheme.onSurfaceVariant,
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  final pages = const [HomePage(), RoutesPage(), MapPage(), SettingsPage()];
  @override
  Widget build(BuildContext context) {
    final sideGutter = math.max(
      0.0,
      (MediaQuery.sizeOf(context).width - 720) / 2,
    );
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: IndexedStack(index: index, children: pages),
        ),
      ),
      bottomNavigationBar: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.location_on_outlined),
                selectedIcon: Icon(Icons.location_on),
                label: '主页',
              ),
              NavigationDestination(
                icon: Icon(Icons.directions_bus_outlined),
                selectedIcon: Icon(Icons.directions_bus),
                label: '路线',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: '地图',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(right: sideGutter),
        child: FloatingActionButton.small(
          onPressed: () => showModalBottomSheet(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => const QuickActions(),
          ),
          tooltip: '快捷操作',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final controller = TextEditingController();
  Timer? debounce;
  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context),
        results = store.search(controller.text);
    return Scaffold(
      appBar: AppBar(
        title: const Text('附近'),
        actions: [
          IconButton(
            onPressed: store.locate,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.locate,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索线路、站点',
                  ),
                  onChanged: (_) {
                    debounce?.cancel();
                    debounce = Timer(
                      const Duration(milliseconds: 250),
                      () => setState(() {}),
                    );
                  },
                  onSubmitted: store.rememberSearch,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              _section(
                '搜索结果',
                results.isEmpty
                    ? [
                        const EmptyBlock(
                          icon: Icons.search_off,
                          title: '没有找到匹配路线',
                          detail: '尝试输入线路编号或终点站。',
                        ),
                      ]
                    : results.map((line) => LineTile(line: line)).toList(),
              ),
            if (controller.text.isEmpty && store.searchHistory.isNotEmpty)
              _section(
                '最近搜索',
                store.searchHistory
                    .take(5)
                    .map(
                      (value) => Dismissible(
                        key: ValueKey(value),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 22),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => store.deleteSearch(value),
                        child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(value),
                          onTap: () {
                            controller.text = value;
                            setState(() {});
                            store.rememberSearch(value);
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            if (store.favoriteLines.isNotEmpty)
              _section(
                '收藏路线',
                store.favoriteLines
                    .map((e) => LineTile(line: e, pinned: true))
                    .toList(),
              ),
            _section(
              '附近站点',
              store.nearbyStops.isEmpty
                  ? [
                      EmptyBlock(
                        icon: Icons.location_off,
                        title: '暂无附近站点',
                        detail: store.error ?? '允许定位后会展示 500 米内的公交站。',
                        action: TextButton.icon(
                          onPressed: store.locate,
                          icon: const Icon(Icons.my_location),
                          label: const Text('重新定位'),
                        ),
                      ),
                    ]
                  : store.nearbyStops
                        .map(
                          (stop) => ListTile(
                            leading: const Icon(
                              Icons.directions_bus_filled_outlined,
                            ),
                            title: Text(
                              stop.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              stop.distance.isEmpty
                                  ? '500 米范围内'
                                  : '${stop.distance}m',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                _push(context, StationPage(station: stop)),
                          ),
                        )
                        .toList(),
            ),
            if (store.loading)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

SliverMainAxisGroup _section(String title, List<Widget> children) =>
    SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 7),
          sliver: SliverToBoxAdapter(
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SliverList.list(children: children),
      ],
    );

class RoutesPage extends StatelessWidget {
  const RoutesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('路线')),
      body: RefreshIndicator(
        onRefresh: store.loadLines,
        child: ListView(
          children: [
            if (store.favoriteLines.isNotEmpty) ...[
              const SectionLabel('收藏路线'),
              ...store.favoriteLines.map(
                (e) => LineTile(line: e, pinned: true),
              ),
            ],
            const SectionLabel('全部路线'),
            if (store.lines.isEmpty)
              EmptyBlock(
                icon: Icons.directions_bus,
                title: '暂无路线',
                detail: store.error ?? '下拉刷新路线列表。',
              ),
            ...store.favoriteFirst(store.lines).map((e) => LineTile(line: e)),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  BusLine? selected;
  RouteBundle? route;
  List<LiveBus> buses = [];
  bool loading = false;
  Future<void> load(BusLine line) async {
    final store = StoreScope.of(context);
    setState(() {
      selected = line;
      loading = true;
    });
    try {
      final r = await store.api.route(line, store.cityName, store.cityKey);
      final live = await store.api.realtime(
        line,
        r.stops.firstOrNull?.order ?? 1,
        store.cityName,
        store.cityKey,
      );
      if (mounted) {
        setState(() {
          route = r;
          buses = live.buses;
        });
      }
    } catch (e) {
      if (mounted) _notice(context, store.friendly(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('地图'),
        actions: [
          PopupMenuButton<BusLine>(
            tooltip: '筛选路线',
            onSelected: load,
            itemBuilder: (_) => store
                .favoriteFirst(store.lines)
                .map(
                  (line) =>
                      PopupMenuItem(value: line, child: Text(line.displayName)),
                )
                .toList(),
          ),
        ],
      ),
      body: Stack(
        children: [
          TransitMap(
            route: route,
            buses: buses,
            nearby: store.nearbyStops,
            user: store.userLocation,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 8,
            child: Material(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  selected == null
                      ? Icons.layers_outlined
                      : Icons.directions_bus,
                ),
                title: Text(selected?.displayName ?? '全部附近站点'),
                subtitle: Text(
                  selected == null
                      ? '从右上角筛选路线及实时车辆'
                      : '${route?.stops.length ?? 0} 个站点 · ${buses.length} 辆实时车辆',
                ),
              ),
            ),
          ),
          if (loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = [
      const Color(0xff20a464),
      Colors.blue,
      Colors.orange,
      Colors.pink,
      Colors.red,
      Colors.cyan,
      Colors.indigo,
      Colors.grey,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SectionLabel('外观'),
          ListTile(
            title: const Text('主题风格'),
            trailing: DropdownButton<ThemeMode>(
              value: store.themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('亮色模式')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('暗色模式')),
              ],
              onChanged: (v) {
                if (v != null) store.setTheme(v);
              },
            ),
          ),
          ListTile(
            title: const Text('主题色'),
            subtitle: Wrap(
              spacing: 10,
              children: colors
                  .map(
                    (color) => IconButton(
                      onPressed: () => store.setAccent(color),
                      tooltip: '选择主题色',
                      icon: Icon(
                        store.accent.toARGB32() == color.toARGB32()
                            ? Icons.check_circle
                            : Icons.circle,
                        color: color,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          ListTile(
            title: const Text('数据刷新间隔'),
            subtitle: Slider(
              value: store.refreshInterval,
              min: 0,
              max: 30,
              divisions: 30,
              label: store.refreshInterval == 0
                  ? '实时'
                  : '${store.refreshInterval.round()} 秒',
              onChanged: store.setRefresh,
            ),
            trailing: Text(
              store.refreshInterval == 0
                  ? '实时'
                  : '${store.refreshInterval.round()}秒',
            ),
          ),
          const SectionLabel('软件信息'),
          const ListTile(title: Text('名称'), trailing: Text('NLBUS')),
          const ListTile(title: Text('城市'), trailing: Text('莆田市')),
          const ListTile(title: Text('开发者'), trailing: Text('@奶龙')),
          const ListTile(
            title: Text('免责声明'),
            subtitle: Text('数据仅供参考，具体请以实际为准。'),
          ),
          const SectionLabel('平台'),
          ListTile(
            leading: Icon(kIsWeb ? Icons.language : Icons.android),
            title: Text(kIsWeb ? '网页版' : 'Android 版'),
            subtitle: const Text('与 iOS 版共享信息架构和实时公交协议'),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class LinePage extends StatefulWidget {
  const LinePage({super.key, required this.line, this.focusStation});
  final BusLine line;
  final String? focusStation;
  @override
  State<LinePage> createState() => _LinePageState();
}

class _LinePageState extends State<LinePage> {
  late BusLine line;
  RouteBundle? route;
  List<LiveBus> buses = [];
  List<String> timetable = [];
  int selectedOrder = 1;
  String plan = '';
  bool loading = true;
  Timer? timer;
  bool horizontal = true;
  @override
  void initState() {
    super.initState();
    line = widget.line;
    loadAll();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadAll() async {
    final store = StoreScope.of(context);
    setState(() => loading = true);
    try {
      final r = await store.api.route(line, store.cityName, store.cityKey);
      route = r;
      selectedOrder = r.stops
          .firstWhere(
            (e) => e.name == widget.focusStation,
            orElse: () =>
                _nearestUserStop(r.stops, store.userLocation) ?? r.stops.first,
          )
          .order;
      timetable = await store.api.timetable(line, r, store.cityName);
      await refresh();
      schedule();
    } catch (e) {
      if (mounted) _notice(context, store.friendly(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void schedule() {
    timer?.cancel();
    final seconds = StoreScope.of(context).refreshInterval;
    timer = Timer(
      Duration(milliseconds: seconds == 0 ? 1 : (seconds * 1000).round()),
      refresh,
    );
  }

  Future<void> refresh() async {
    final store = StoreScope.of(context);
    try {
      final live = await store.api.realtime(
        line,
        selectedOrder,
        store.cityName,
        store.cityKey,
      );
      if (mounted) {
        setState(() {
          buses = live.buses;
          plan = live.planTime;
        });
      }
    } catch (_) {}
    if (mounted) schedule();
  }

  Future<void> switchDirection() async {
    final store = StoreScope.of(context);
    final direction = line.direction == '1' ? '2' : '1';
    line = store.lines.firstWhere(
      (e) => e.name == line.name && e.direction == direction,
      orElse: () => BusLine(
        name: line.name,
        direction: direction,
        destination: line.destination,
      ),
    );
    await loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context),
        stops = route?.stops ?? [],
        target = stops.where((e) => e.order == selectedOrder).firstOrNull;
    final analyses =
        buses
            .map((bus) => (bus: bus, analysis: _analyze(bus, route, target)))
            .toList()
          ..sort((a, b) => a.analysis.sort.compareTo(b.analysis.sort));
    return Scaffold(
      appBar: AppBar(
        title: Text(line.displayName),
        actions: [
          IconButton(
            onPressed: refresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadAll,
        child: ListView(
          children: [
            if (loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '开往 ${line.destination}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: switchDirection,
                        tooltip: '切换行驶方向',
                        icon: const Icon(Icons.swap_horiz),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        avatar: Icon(
                          store.favorites.contains(line.id)
                              ? Icons.star
                              : Icons.star_outline,
                        ),
                        label: Text(
                          store.favorites.contains(line.id) ? '已收藏' : '收藏',
                        ),
                        onPressed: () => store.toggleFavorite(line),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.phone_in_talk_outlined),
                        label: const Text('路线反馈'),
                        onPressed: () => _callFeedback(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SectionLabel('运营信息'),
            if (line.beginTime.isNotEmpty || line.endTime.isNotEmpty)
              InfoLine('首末班', '${line.beginTime} - ${line.endTime}'),
            if (line.fare.isNotEmpty) InfoLine('收费信息', line.fare),
            if (plan.isNotEmpty) InfoLine('预计最近发车', plan),
            if (line.mileage.isNotEmpty) InfoLine('线路里程', line.mileage),
            const SectionLabel('到站分析'),
            if (analyses.isEmpty)
              const EmptyBlock(
                icon: Icons.directions_bus,
                title: '暂无实时车辆',
                detail: '实时数据返回后会自动更新。',
              ),
            ...analyses.map(
              (item) => ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  child: const Icon(Icons.directions_bus, size: 19),
                ),
                title: Text(
                  item.bus.number,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(item.analysis.text),
                trailing: item.bus.distance.isEmpty
                    ? const Icon(Icons.chevron_right)
                    : Text(item.bus.distance),
                onTap: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.sizeOf(context).height * .72,
                    child: TransitMap(
                      route: route,
                      buses: [item.bus],
                      nearby: const [],
                      user: null,
                      focus: item.bus.position,
                    ),
                  ),
                ),
              ),
            ),
            const SectionLabel('时刻表'),
            if (timetable.isEmpty)
              InfoLine('发车时间', plan.isEmpty ? '实时发车时间暂未返回' : plan)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: timetable.map((time) {
                    final next = _isNext(time, timetable);
                    return Semantics(
                      label: next ? '下一班，$time' : time,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: next
                              ? store.accent
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          time,
                          style: TextStyle(
                            color: next ? Colors.white : null,
                            fontWeight: next ? FontWeight.w700 : null,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SectionLabel('车辆实时地图'),
            SizedBox(
              height: 250,
              child: TransitMap(
                route: route,
                buses: buses,
                nearby: const [],
                user: null,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('使用官方网页核对实时车辆'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => launchUrl(
                Uri.parse('https://h5.mygolbs.com/?areacode=${store.cityKey}'),
                mode: LaunchMode.inAppBrowserView,
              ),
            ),
            SectionLabel(
              '站点列表',
              trailing: IconButton(
                onPressed: () => setState(() => horizontal = !horizontal),
                tooltip: '切换站点展示样式',
                icon: Icon(horizontal ? Icons.view_list : Icons.view_column),
              ),
            ),
            if (horizontal)
              SizedBox(
                height: 270,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: stops.length,
                  itemBuilder: (_, i) {
                    final stop = stops[i],
                        selected = stop.order == selectedOrder;
                    return InkWell(
                      onTap: () {
                        setState(() => selectedOrder = stop.order);
                        refresh();
                      },
                      child: SizedBox(
                        width: 34,
                        child: Column(
                          children: [
                            const SizedBox(height: 22),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  height: 3,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                Container(
                                  width: selected ? 16 : 10,
                                  height: selected ? 16 : 10,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? store.accent
                                        : Theme.of(context).colorScheme.outline,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              stop.name.characters.join('\n'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.05,
                                fontWeight: selected ? FontWeight.w700 : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${stop.order}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              ...stops.map(
                (stop) => ListTile(
                  leading: Text('${stop.order}'),
                  title: Text(
                    stop.name,
                    style: TextStyle(
                      fontWeight: stop.order == selectedOrder
                          ? FontWeight.w700
                          : null,
                    ),
                  ),
                  trailing: stop.order == selectedOrder
                      ? Icon(Icons.my_location, color: store.accent)
                      : null,
                  onTap: () {
                    setState(() => selectedOrder = stop.order);
                    refresh();
                  },
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class StationPage extends StatefulWidget {
  const StationPage({super.key, required this.station});
  final NearbyStop station;
  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  List<BusLine> lines = [];
  bool loading = true;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && lines.isEmpty) load();
  }

  Future<void> load() async {
    final store = StoreScope.of(context);
    try {
      lines = await store.api.stationLines(
        widget.station.name,
        store.cityName,
        store.cityKey,
      );
    } catch (e) {
      error = store.friendly(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.station.name)),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          children: [
            if (loading) const LinearProgressIndicator(),
            const SectionLabel('经过路线'),
            if (!loading && lines.isEmpty)
              EmptyBlock(
                icon: Icons.route,
                title: '暂无经过路线',
                detail: error ?? '该站点暂未返回线路数据。',
              ),
            ...store
                .favoriteFirst(lines)
                .map(
                  (e) => LineTile(
                    line: e,
                    pinned: store.favorites.contains(e.id),
                    focusStation: widget.station.name,
                  ),
                ),
            const SectionLabel('周边站点'),
            ...store.nearbyStops
                .where((e) => e.name != widget.station.name)
                .take(8)
                .map(
                  (e) => ListTile(
                    title: Text(e.name),
                    subtitle: Text(e.distance),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _push(context, StationPage(station: e)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class TransitMap extends StatelessWidget {
  const TransitMap({
    super.key,
    this.route,
    required this.buses,
    required this.nearby,
    required this.user,
    this.focus,
  });
  final RouteBundle? route;
  final List<LiveBus> buses;
  final List<NearbyStop> nearby;
  final LatLng? user, focus;
  @override
  Widget build(BuildContext context) {
    final positions = [
      ?focus,
      ?user,
      ...?route?.stops.map((e) => e.position).whereType<LatLng>(),
      ...nearby.map((e) => e.position).whereType<LatLng>(),
      ...buses.map((e) => e.position).whereType<LatLng>(),
    ];
    final center = positions.firstOrNull ?? const LatLng(25.431, 119.007);
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: focus != null ? 15 : 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.nailong.nlbus',
        ),
        if (route?.geometry.isNotEmpty == true)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route!.geometry,
                strokeWidth: 4,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (user != null)
              _marker(user!, Icons.my_location, '我的位置', Colors.blue),
            ...?route?.stops
                .where((e) => e.position != null)
                .map(
                  (e) => _marker(
                    e.position!,
                    Icons.circle,
                    e.name,
                    Theme.of(context).colorScheme.secondary,
                  ),
                ),
            ...nearby
                .where((e) => e.position != null)
                .map(
                  (e) => _marker(
                    e.position!,
                    Icons.location_on,
                    e.name,
                    Theme.of(context).colorScheme.secondary,
                  ),
                ),
            ...buses
                .where((e) => e.position != null)
                .map(
                  (e) => _marker(
                    e.position!,
                    Icons.directions_bus,
                    e.number,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Marker _marker(LatLng point, IconData icon, String label, Color color) =>
      Marker(
        point: point,
        width: 72,
        height: 54,
        child: Tooltip(
          message: label,
          child: Column(
            children: [
              Icon(icon, color: color, size: 25),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          const SectionLabel('快捷跳转'),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Apple 钱包'),
            subtitle: const Text('仅 iOS 设备可用'),
            onTap: () => _notice(context, 'Apple 钱包仅可在 iOS 版中打开。'),
          ),
          ListTile(
            leading: const Icon(Icons.credit_card),
            title: const Text('莆田市民卡'),
            subtitle: const Text('通过微信业务链接打开'),
            onTap: () =>
                launchUrl(Uri.parse('weixin://dl/business/?t=wsEoAa0Vyum')),
          ),
          const SectionLabel('到站与实时状态'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('到站通知'),
            subtitle: const Text('选择线路和目标站后创建提醒'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _notice(context, 'Android 通知通道将在选择具体线路后启用；网页版使用浏览器通知。'),
          ),
          ListTile(
            leading: const Icon(Icons.location_searching),
            title: const Text('实时状态监测'),
            subtitle: Text(
              store.userLocation == null ? '需要定位权限' : '定位已就绪，可与车辆位置进行匹配',
            ),
            onTap: store.locate,
          ),
        ],
      ),
    );
  }
}

class LineTile extends StatelessWidget {
  const LineTile({
    super.key,
    required this.line,
    this.pinned = false,
    this.focusStation,
  });
  final BusLine line;
  final bool pinned;
  final String? focusStation;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      pinned ? Icons.star : Icons.directions_bus,
      color: pinned ? Colors.amber : Theme.of(context).colorScheme.primary,
    ),
    title: Text(
      line.displayName,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: line.destination.isEmpty ? null : Text('开往 ${line.destination}'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        _push(context, LinePage(line: line, focusStation: focusStation)),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 8, 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label, style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
  );
}

class EmptyBlock extends StatelessWidget {
  const EmptyBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title, detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    child: Column(
      children: [
        Icon(
          icon,
          size: 38,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _Arrival {
  const _Arrival(this.text, this.sort);
  final String text;
  final int sort;
}

_Arrival _analyze(LiveBus bus, RouteBundle? route, RouteStop? target) {
  if (route == null || target == null) return const _Arrival('实时位置分析中', 9999);
  final distance = const Distance();
  RouteStop? inferred;
  if (bus.position != null) {
    var best = double.infinity;
    for (final stop in route.stops) {
      if (stop.position == null) continue;
      final value = distance(bus.position!, stop.position!);
      if (value < best) {
        best = value;
        inferred = stop;
      }
    }
  }
  inferred ??= route.stops
      .where((e) => e.order == bus.stationOrder)
      .firstOrNull;
  final order = inferred?.order ?? math.max(bus.stationOrder, 1);
  final remaining = target.order - order;
  if (remaining < 0) {
    return _Arrival(
      '已驶过当前${target.name}约${remaining.abs()}站',
      10000 + remaining.abs(),
    );
  }
  double meters = 0;
  final sequence =
      route.stops
          .where((e) => e.order >= order && e.order <= target.order)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  for (var i = 1; i < sequence.length; i++) {
    if (sequence[i - 1].position != null && sequence[i].position != null) {
      meters += distance(sequence[i - 1].position!, sequence[i].position!);
    }
  }
  if (meters < 50 && remaining > 0) meters = remaining * 450;
  final speed =
      double.tryParse(bus.speed.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 18;
  final safeSpeed = speed >= 5 && speed <= 80 ? speed : 18;
  final eta = math
      .max(1, ((meters / 1000) / safeSpeed * 60).ceil())
      .clamp(1, 99)
      .toString()
      .padLeft(2, '0');
  if (remaining == 0 && meters < 120) {
    return _Arrival('车辆正在抵达当前${target.name}(约$eta分钟)', 0);
  }
  final count = math.max(1, remaining);
  return _Arrival('距离当前${target.name}约$count站($eta分钟)', count);
}

RouteStop? _nearestUserStop(List<RouteStop> stops, LatLng? user) {
  if (user == null) return stops.firstOrNull;
  final distance = const Distance();
  RouteStop? result;
  var best = double.infinity;
  for (final stop in stops) {
    if (stop.position == null) continue;
    final value = distance(user, stop.position!);
    if (value < best) {
      best = value;
      result = stop;
    }
  }
  return result;
}

bool _isNext(String value, List<String> all) {
  int? minutes(String v) {
    final p = v.trim().split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]),
        m = int.tryParse(p[1].substring(0, math.min(2, p[1].length)));
    return h == null || m == null ? null : h * 60 + m;
  }

  final now = DateTime.now().hour * 60 + DateTime.now().minute;
  final candidates =
      all
          .map((e) => (value: e, minutes: minutes(e)))
          .where((e) => e.minutes != null && e.minutes! >= now)
          .toList()
        ..sort((a, b) => a.minutes!.compareTo(b.minutes!));
  return candidates.firstOrNull?.value == value;
}

Future<void> _callFeedback(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('联系莆田公交运营热线？'),
      content: const Text('是否拨打 0594-2296933 咨询？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('拨打'),
        ),
      ],
    ),
  );
  if (yes == true) launchUrl(Uri.parse('tel:05942296933'));
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
void _notice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
