import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const LiquidNotesApp());
}

class LiquidNotesApp extends StatelessWidget {
  const LiquidNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'Liquid Notes',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: Color(0xFF0E7AFE),
        scaffoldBackgroundColor: Color(0xFFF7F5EF),
        textTheme: CupertinoTextThemeData(
          navLargeTitleTextStyle: TextStyle(
            color: Color(0xFF191916),
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      home: const NotesHomePage(),
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
    this.color = 0xFFFFD966,
  });

  final String id;
  String title;
  String body;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;
  bool isFavorite;
  int color;

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
      color: json['color'] as int? ?? 0xFFFFD966,
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
      'color': color,
    };
  }
}

class NotesStore {
  static const _storageKey = 'liquid_notes_items';

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
        title: '今天的灵感',
        body: '把零碎想法先记下来，再慢慢整理。轻点右下角可以新建备忘录。',
        createdAt: now,
        updatedAt: now,
        isPinned: true,
        color: 0xFFFFD166,
      ),
      Note(
        id: 'glass',
        title: '液态玻璃设计',
        body: '半透明层、背景模糊、柔和边缘和浮动控制，让界面像贴在内容上方的玻璃。',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        color: 0xFF8EECF5,
      ),
    ];
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

  Future<void> _persist() async {
    await _store.save(_notes);
  }

  List<Note> get _visibleNotes {
    final lowerQuery = _query.trim().toLowerCase();
    final filtered = lowerQuery.isEmpty
        ? _notes
        : _notes.where((note) {
            return note.title.toLowerCase().contains(lowerQuery) ||
                note.body.toLowerCase().contains(lowerQuery);
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          const LiquidBackground(),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '备忘录',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF191916),
                          ),
                        ),
                        const SizedBox(height: 14),
                        LiquidSearchField(
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                else if (_visibleNotes.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyNotesView(onCreate: () => _openEditor()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 118),
                    sliver: SliverList.separated(
                      itemBuilder: (context, index) {
                        final note = _visibleNotes[index];
                        return NoteCard(
                          note: note,
                          onTap: () => _openEditor(note),
                          onPin: () => _togglePin(note),
                          onFavorite: () => _toggleFavorite(note),
                          onDelete: () => _delete(note),
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemCount: _visibleNotes.length,
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: LiquidToolbar(
              count: _notes.length,
              onCreate: () => _openEditor(),
            ),
          ),
        ],
      ),
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
  late int _color;
  late bool _isPinned;
  late bool _isFavorite;

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _bodyController = TextEditingController(text: widget.note?.body ?? '');
    _color = widget.note?.color ?? 0xFFFFD166;
    _isPinned = widget.note?.isPinned ?? false;
    _isFavorite = widget.note?.isFavorite ?? false;
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
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          const LiquidBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: CupertinoIcons.chevron_left,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      GlassIconButton(
                        icon: _isPinned
                            ? CupertinoIcons.pin_fill
                            : CupertinoIcons.pin,
                        onPressed: () => setState(() => _isPinned = !_isPinned),
                      ),
                      const SizedBox(width: 10),
                      GlassIconButton(
                        icon: _isFavorite
                            ? CupertinoIcons.star_fill
                            : CupertinoIcons.star,
                        onPressed: () =>
                            setState(() => _isFavorite = !_isFavorite),
                      ),
                      const SizedBox(width: 10),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        color: const Color(0xFF191916),
                        borderRadius: BorderRadius.circular(22),
                        onPressed: _save,
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: Container(
                          decoration: liquidDecoration(
                            tint: Color(_color).withValues(alpha: 0.22),
                            radius: 30,
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ColorPicker(
                                selected: _color,
                                onChanged: (value) =>
                                    setState(() => _color = value),
                              ),
                              const SizedBox(height: 12),
                              CupertinoTextField.borderless(
                                controller: _titleController,
                                onChanged: (_) => setState(() {}),
                                placeholder: '标题',
                                maxLines: null,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF191916),
                                ),
                              ),
                              const SizedBox(height: 10),
                              CupertinoTextField.borderless(
                                controller: _bodyController,
                                onChanged: (_) => setState(() {}),
                                placeholder: '开始记录...',
                                minLines: 14,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.45,
                                  color: Color(0xFF2D2B27),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.onTap,
    required this.onPin,
    required this.onFavorite,
    required this.onDelete,
    super.key,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D4F),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(CupertinoIcons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: liquidDecoration(
                tint: Color(note.color).withValues(alpha: 0.24),
                radius: 28,
              ),
              padding: const EdgeInsets.all(18),
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
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF191916),
                          ),
                        ),
                      ),
                      if (note.isPinned)
                        const Icon(CupertinoIcons.pin_fill, size: 17),
                      if (note.isFavorite) ...[
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.star_fill, size: 17),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    note.body.isEmpty ? '空白备忘录' : note.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      color: const Color(0xFF2D2B27).withValues(alpha: 0.76),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        formatDate(note.updatedAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(
                            0xFF2D2B27,
                          ).withValues(alpha: 0.58),
                        ),
                      ),
                      const Spacer(),
                      MiniAction(icon: CupertinoIcons.pin, onPressed: onPin),
                      const SizedBox(width: 8),
                      MiniAction(
                        icon: CupertinoIcons.star,
                        onPressed: onFavorite,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LiquidToolbar extends StatelessWidget {
  const LiquidToolbar({required this.count, required this.onCreate, super.key});

  final int count;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: liquidDecoration(
            tint: Colors.white.withValues(alpha: 0.28),
            radius: 30,
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
          child: Row(
            children: [
              Text(
                '$count 条备忘录',
                style: const TextStyle(
                  color: Color(0xFF191916),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              CupertinoButton(
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF191916),
                borderRadius: BorderRadius.circular(22),
                onPressed: onCreate,
                child: const Icon(
                  CupertinoIcons.square_pencil,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LiquidSearchField extends StatelessWidget {
  const LiquidSearchField({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: liquidDecoration(
            tint: Colors.white.withValues(alpha: 0.32),
            radius: 22,
          ),
          child: CupertinoSearchTextField(
            controller: controller,
            onChanged: onChanged,
            placeholder: '搜索标题或内容',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            backgroundColor: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    );
  }
}

class EmptyNotesView extends StatelessWidget {
  const EmptyNotesView({required this.onCreate, super.key});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CupertinoButton(
        onPressed: onCreate,
        child: const Text('新建第一条备忘录'),
      ),
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  static const colors = [
    0xFFFFD166,
    0xFF8EECF5,
    0xFFA3E635,
    0xFFFF8FAB,
    0xFFCDB4DB,
  ];

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: colors.map((color) {
        final isSelected = color == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () => onChanged(color),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF191916) : Colors.white,
                  width: isSelected ? 3 : 1.5,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.34),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
            ),
            child: Icon(icon, color: const Color(0xFF191916), size: 21),
          ),
        ),
      ),
    );
  }
}

class MiniAction extends StatelessWidget {
  const MiniAction({required this.icon, required this.onPressed, super.key});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      onPressed: onPressed,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.38),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.56)),
        ),
        child: Icon(icon, color: const Color(0xFF191916), size: 17),
      ),
    );
  }
}

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF9F3DC),
            Color(0xFFE7F7F7),
            Color(0xFFF8EDF1),
            Color(0xFFF5F4EF),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _LiquidBackgroundPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LiquidBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xFFFFD166).withValues(alpha: 0.28);
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.16),
      120,
      paint,
    );
    paint.color = const Color(0xFF8EECF5).withValues(alpha: 0.30);
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.28),
      150,
      paint,
    );
    paint.color = const Color(0xFFFF8FAB).withValues(alpha: 0.22);
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.82),
      180,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

BoxDecoration liquidDecoration({required Color tint, required double radius}) {
  return BoxDecoration(
    color: tint,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.58), width: 1.2),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF4B4B4B).withValues(alpha: 0.10),
        blurRadius: 28,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.58),
        blurRadius: 6,
        offset: const Offset(-2, -2),
      ),
    ],
  );
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
