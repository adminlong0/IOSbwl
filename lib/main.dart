import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const LiquidNotesApp());
}

class LiquidNotesApp extends StatelessWidget {
  const LiquidNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: '备忘录',
      debugShowCheckedModeBanner: false,
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.systemYellow,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
      ),
      home: NotesHomePage(),
    );
  }
}

class Note {
  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.isFavorite = false,
    this.reminderAt,
  });

  final String id;
  String title;
  String body;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;
  bool isFavorite;
  DateTime? reminderAt;

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      isPinned: json['isPinned'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      'isFavorite': isFavorite,
      'reminderAt': reminderAt?.toIso8601String(),
    };
  }
}

class NotesStore {
  static const _storageKey = 'liquid_notes_items_v2';

  Future<List<Note>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      return _seedNotes();
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => Note.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(notes.map((note) => note.toJson()).toList()),
    );
  }

  List<Note> _seedNotes() {
    final now = DateTime.now();
    return [
      Note(
        id: 'welcome',
        title: '今天的想法',
        body: '用系统控件写下事情本身。需要安排时间时，可以把备忘录加入日历、提醒事项或通知。',
        createdAt: now,
        updatedAt: now,
        isPinned: true,
      ),
      Note(
        id: 'native',
        title: 'Apple 风格重构',
        body: '界面采用 Large Title、分组列表、底部操作表和系统色，尽量让体验接近第一方 iOS 应用。',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      ),
    ];
  }
}

class AppleServices {
  AppleServices._();

  static const _channel = MethodChannel('liquid_notes/apple_services');

  static Future<String> createCalendarEvent(Note note) async {
    final start =
        note.reminderAt ?? DateTime.now().add(const Duration(hours: 1));
    final result = await _channel.invokeMethod<String>('createCalendarEvent', {
      'title': note.title,
      'body': note.body,
      'start': start.toIso8601String(),
      'end': start.add(const Duration(minutes: 30)).toIso8601String(),
    });
    return result ?? '已加入日历';
  }

  static Future<String> createReminder(Note note) async {
    final due = note.reminderAt ?? DateTime.now().add(const Duration(hours: 1));
    final result = await _channel.invokeMethod<String>('createReminder', {
      'title': note.title,
      'body': note.body,
      'due': due.toIso8601String(),
    });
    return result ?? '已加入提醒事项';
  }

  static Future<String> scheduleNotification(Note note) async {
    final fireAt =
        note.reminderAt ?? DateTime.now().add(const Duration(minutes: 5));
    final result = await _channel.invokeMethod<String>('scheduleNotification', {
      'id': note.id,
      'title': note.title,
      'body': note.body,
      'fireAt': fireAt.toIso8601String(),
    });
    return result ?? '通知已安排';
  }

  static Future<String> startLiveActivity(Note note) async {
    final result = await _channel.invokeMethod<String>('startLiveActivity', {
      'title': note.title,
      'body': note.body,
    });
    return result ?? '实时活动已启动';
  }

  static Future<String> endLiveActivity() async {
    final result = await _channel.invokeMethod<String>('endLiveActivity');
    return result ?? '实时活动已结束';
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final _store = NotesStore();
  final _searchController = TextEditingController();
  final List<Note> _notes = [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final notes = await _store.load();
    setState(() {
      _notes
        ..clear()
        ..addAll(notes);
      _isLoading = false;
    });
  }

  Future<void> _persist() => _store.save(_notes);

  List<Note> get _visibleNotes {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? [..._notes]
        : _notes.where((note) {
            return note.title.toLowerCase().contains(query) ||
                note.body.toLowerCase().contains(query);
          }).toList();

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  Future<void> _openEditor([Note? note]) async {
    final result = await Navigator.of(context).push<Note?>(
      CupertinoPageRoute(builder: (_) => NoteEditorPage(note: note)),
    );
    if (result == null) {
      return;
    }

    setState(() {
      final index = _notes.indexWhere((item) => item.id == result.id);
      if (index == -1) {
        _notes.add(result);
      } else {
        _notes[index] = result;
      }
    });
    await _persist();
  }

  Future<void> _delete(Note note) async {
    setState(() => _notes.removeWhere((item) => item.id == note.id));
    await _persist();
  }

  Future<void> _togglePin(Note note) async {
    setState(() => note.isPinned = !note.isPinned);
    await _persist();
  }

  Future<void> _toggleFavorite(Note note) async {
    setState(() => note.isFavorite = !note.isFavorite);
    await _persist();
  }

  Future<void> _showNoteActions(Note note) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => NoteActionSheet(
        note: note,
        onCalendar: () => _runAppleService(
          context,
          () => AppleServices.createCalendarEvent(note),
        ),
        onReminder: () =>
            _runAppleService(context, () => AppleServices.createReminder(note)),
        onNotification: () => _runAppleService(
          context,
          () => AppleServices.scheduleNotification(note),
        ),
        onLiveActivity: () => _runAppleService(
          context,
          () => AppleServices.startLiveActivity(note),
        ),
        onEndLiveActivity: () =>
            _runAppleService(context, AppleServices.endLiveActivity),
      ),
    );
  }

  Future<void> _runAppleService(
    BuildContext sheetContext,
    Future<String> Function() action,
  ) async {
    Navigator.of(sheetContext).pop();
    try {
      final message = await action();
      if (mounted) {
        _showStatus(message);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showStatus(error.message ?? '系统服务暂不可用');
      }
    }
  }

  void _showStatus(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('完成'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('备忘录'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _openEditor(),
              child: const Icon(CupertinoIcons.square_pencil),
            ),
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              sliver: SliverList.list(
                children: [
                  CupertinoSearchTextField(
                    controller: _searchController,
                    placeholder: '搜索',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 18),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: CupertinoActivityIndicator(),
                    )
                  else if (_visibleNotes.isEmpty)
                    EmptyNotesView(onCreate: () => _openEditor())
                  else ...[
                    NotesSummary(notes: _notes),
                    const SizedBox(height: 18),
                    NotesSection(
                      title: _query.isEmpty ? '全部' : '搜索结果',
                      notes: _visibleNotes,
                      onOpen: _openEditor,
                      onPin: _togglePin,
                      onFavorite: _toggleFavorite,
                      onDelete: _delete,
                      onMore: _showNoteActions,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NotesSummary extends StatelessWidget {
  const NotesSummary({required this.notes, super.key});

  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    final pinned = notes.where((note) => note.isPinned).length;
    final reminders = notes.where((note) => note.reminderAt != null).length;

    return Row(
      children: [
        Expanded(
          child: SummaryTile(
            value: notes.length.toString(),
            label: '备忘录',
            icon: CupertinoIcons.doc_text,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SummaryTile(
            value: pinned.toString(),
            label: '置顶',
            icon: CupertinoIcons.pin,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SummaryTile(
            value: reminders.toString(),
            label: '提醒',
            icon: CupertinoIcons.bell,
          ),
        ),
      ],
    );
  }
}

class SummaryTile extends StatelessWidget {
  const SummaryTile({
    required this.value,
    required this.label,
    required this.icon,
    super.key,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: CupertinoColors.systemGrey),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotesSection extends StatelessWidget {
  const NotesSection({
    required this.title,
    required this.notes,
    required this.onOpen,
    required this.onPin,
    required this.onFavorite,
    required this.onDelete,
    required this.onMore,
    super.key,
  });

  final String title;
  final List<Note> notes;
  final ValueChanged<Note> onOpen;
  final ValueChanged<Note> onPin;
  final ValueChanged<Note> onFavorite;
  final ValueChanged<Note> onDelete;
  final ValueChanged<Note> onMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: CupertinoColors.secondaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground,
            ),
            child: Column(
              children: [
                for (var index = 0; index < notes.length; index++) ...[
                  NoteRow(
                    note: notes[index],
                    onOpen: () => onOpen(notes[index]),
                    onPin: () => onPin(notes[index]),
                    onFavorite: () => onFavorite(notes[index]),
                    onDelete: () => onDelete(notes[index]),
                    onMore: () => onMore(notes[index]),
                  ),
                  if (index != notes.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 58),
                      child: Separator(),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class NoteRow extends StatelessWidget {
  const NoteRow({
    required this.note,
    required this.onOpen,
    required this.onPin,
    required this.onFavorite,
    required this.onDelete,
    required this.onMore,
    super.key,
  });

  final Note note;
  final VoidCallback onOpen;
  final VoidCallback onPin;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return CupertinoContextMenu(
      actions: [
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.of(context).pop();
            onPin();
          },
          trailingIcon: note.isPinned
              ? CupertinoIcons.pin_slash
              : CupertinoIcons.pin,
          child: Text(note.isPinned ? '取消置顶' : '置顶'),
        ),
        CupertinoContextMenuAction(
          onPressed: () {
            Navigator.of(context).pop();
            onFavorite();
          },
          trailingIcon: note.isFavorite
              ? CupertinoIcons.star_slash
              : CupertinoIcons.star,
          child: Text(note.isFavorite ? '取消收藏' : '收藏'),
        ),
        CupertinoContextMenuAction(
          isDestructiveAction: true,
          onPressed: () {
            Navigator.of(context).pop();
            onDelete();
          },
          trailingIcon: CupertinoIcons.delete,
          child: const Text('删除'),
        ),
      ],
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              NoteGlyph(isPinned: note.isPinned, isFavorite: note.isFavorite),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CupertinoColors.label,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (note.reminderAt != null)
                          const Icon(
                            CupertinoIcons.bell_fill,
                            size: 14,
                            color: CupertinoColors.systemOrange,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      previewText(note),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatDate(note.updatedAt),
                      style: const TextStyle(
                        color: CupertinoColors.tertiaryLabel,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: onMore,
                child: const Icon(CupertinoIcons.ellipsis_circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteGlyph extends StatelessWidget {
  const NoteGlyph({
    required this.isPinned,
    required this.isFavorite,
    super.key,
  });

  final bool isPinned;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    final icon = isPinned
        ? CupertinoIcons.pin_fill
        : isFavorite
        ? CupertinoIcons.star_fill
        : CupertinoIcons.doc_text_fill;
    final color = isPinned
        ? CupertinoColors.systemYellow
        : isFavorite
        ? CupertinoColors.systemOrange
        : CupertinoColors.systemGrey3;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.note});

  final Note? note;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late bool _isPinned;
  late bool _isFavorite;
  DateTime? _reminderAt;

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _bodyController = TextEditingController(text: widget.note?.body ?? '');
    _isPinned = widget.note?.isPinned ?? false;
    _isFavorite = widget.note?.isFavorite ?? false;
    _reminderAt = widget.note?.reminderAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) {
      Navigator.of(context).pop();
      return;
    }

    final now = DateTime.now();
    final existing = widget.note;
    Navigator.of(context).pop(
      Note(
        id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim().isEmpty
            ? '无标题'
            : _titleController.text.trim(),
        body: _bodyController.text.trim(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        isPinned: _isPinned,
        isFavorite: _isFavorite,
        reminderAt: _reminderAt,
      ),
    );
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    var selected = _reminderAt ?? now.add(const Duration(hours: 1));
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    CupertinoButton(
                      child: const Text('清除'),
                      onPressed: () {
                        setState(() => _reminderAt = null);
                        Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
                    CupertinoButton(
                      child: const Text('完成'),
                      onPressed: () {
                        setState(() => _reminderAt = selected);
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: selected,
                  minimumDate: now,
                  onDateTimeChanged: (value) => selected = value,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.note == null ? '新建备忘录' : '编辑备忘录'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: const Text('完成'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: CupertinoColors.secondarySystemGroupedBackground,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  child: Column(
                    children: [
                      CupertinoTextField.borderless(
                        controller: _titleController,
                        onChanged: (_) => setState(() {}),
                        placeholder: '标题',
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: CupertinoColors.label,
                        ),
                      ),
                      const Separator(),
                      CupertinoTextField.borderless(
                        controller: _bodyController,
                        onChanged: (_) => setState(() {}),
                        placeholder: '备忘录',
                        minLines: 12,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.42,
                          color: CupertinoColors.label,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            CupertinoListSection.insetGrouped(
              margin: EdgeInsets.zero,
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.pin),
                  title: const Text('置顶'),
                  trailing: CupertinoSwitch(
                    value: _isPinned,
                    onChanged: (value) => setState(() => _isPinned = value),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.star),
                  title: const Text('收藏'),
                  trailing: CupertinoSwitch(
                    value: _isFavorite,
                    onChanged: (value) => setState(() => _isFavorite = value),
                  ),
                ),
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.bell),
                  title: const Text('提醒时间'),
                  subtitle: Text(
                    _reminderAt == null ? '未设置' : formatDate(_reminderAt!),
                  ),
                  trailing: const CupertinoListTileChevron(),
                  onTap: _pickReminder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NoteActionSheet extends StatelessWidget {
  const NoteActionSheet({
    required this.note,
    required this.onCalendar,
    required this.onReminder,
    required this.onNotification,
    required this.onLiveActivity,
    required this.onEndLiveActivity,
    super.key,
  });

  final Note note;
  final VoidCallback onCalendar;
  final VoidCallback onReminder;
  final VoidCallback onNotification;
  final VoidCallback onLiveActivity;
  final VoidCallback onEndLiveActivity;

  @override
  Widget build(BuildContext context) {
    return CupertinoActionSheet(
      title: Text(note.title),
      message: const Text('使用 iOS 系统服务处理这条备忘录'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: onCalendar,
          child: const Text('加入苹果日历'),
        ),
        CupertinoActionSheetAction(
          onPressed: onReminder,
          child: const Text('加入提醒事项'),
        ),
        CupertinoActionSheetAction(
          onPressed: onNotification,
          child: const Text('发送消息通知'),
        ),
        CupertinoActionSheetAction(
          onPressed: onLiveActivity,
          child: const Text('开始实时活动'),
        ),
        CupertinoActionSheetAction(
          onPressed: onEndLiveActivity,
          child: const Text('结束实时活动'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    );
  }
}

class EmptyNotesView extends StatelessWidget {
  const EmptyNotesView({required this.onCreate, super.key});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.doc_text_search,
            size: 44,
            color: CupertinoColors.systemGrey2,
          ),
          const SizedBox(height: 14),
          const Text(
            '没有备忘录',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            '新建一条，把下一件事写下来。',
            style: TextStyle(color: CupertinoColors.secondaryLabel),
          ),
          const SizedBox(height: 18),
          CupertinoButton.filled(
            onPressed: onCreate,
            child: const Text('新建备忘录'),
          ),
        ],
      ),
    );
  }
}

class Separator extends StatelessWidget {
  const Separator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

String previewText(Note note) {
  final body = note.body.trim();
  if (body.isEmpty) {
    return '空白备忘录';
  }
  return body.replaceAll(RegExp(r'\s+'), ' ');
}

String formatDate(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  if (date == today) {
    return '今天 ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }
  return '${value.month}月${value.day}日 ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String twoDigits(int value) => value.toString().padLeft(2, '0');
