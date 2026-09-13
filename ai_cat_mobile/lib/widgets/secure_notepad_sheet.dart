import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import '../models/secure_note.dart';
import '../services/secure_notepad_service.dart';
import '../theme/app_colors.dart';

enum _NotepadPhase { loading, setup, locked, unlocked }

/// "Bilgisayari Kumanda Et" panelindeki gibi asagidan acilan bir sayfa:
/// kullanicinin belirledigi bir sifreyle AES-256-GCM sifreli, yalnizca bu
/// cihazda saklanan bir not defteri (bkz. SecureNotepadService). Ilk
/// acilista sifre kurulumu istenir; sonraki acilislarda kilit sifreyle
/// acilir. Turetilen anahtar yalnizca bu widget'in omru boyunca bellekte
/// tutulur - kilitlenince (ya da sayfa kapaninca) atilir.
class SecureNotepadSheet extends StatefulWidget {
  /// Testlerin gercek 200k iterasyonlu PBKDF2 yerine hizli bir sahte
  /// servis enjekte edebilmesi icin - normal kullanimda hep null'dir.
  final SecureNotepadService? service;

  const SecureNotepadSheet({super.key, this.service});

  @override
  State<SecureNotepadSheet> createState() => _SecureNotepadSheetState();
}

class _SecureNotepadSheetState extends State<SecureNotepadSheet> {
  late final _service = widget.service ?? SecureNotepadService();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _NotepadPhase _phase = _NotepadPhase.loading;
  SecretKey? _key;
  List<SecureNote> _notes = [];
  String? _error;
  bool _busy = false;
  // null: tum notlar gosterilir. Bos oldugunda (yeni kurulan defter, hicbir
  // notta etiket yokken) filtre satiri hic gosterilmez, bu yuzden bu deger
  // her zaman gecerli bir etiket olur ya da hic secilmemis olur.
  String? _activeTagFilter;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final setUp = await _service.isSetUp();
    if (!mounted) return;
    setState(() => _phase = setUp ? _NotepadPhase.locked : _NotepadPhase.setup);
  }

  Future<void> _submitSetup() async {
    final password = _passwordController.text;
    if (password.length < 4) {
      setState(() => _error = 'Şifre en az 4 karakter olmalı.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'Şifreler eşleşmiyor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final key = await _service.setUp(password);
    if (!mounted) return;
    setState(() {
      _key = key;
      _notes = [];
      _phase = _NotepadPhase.unlocked;
      _busy = false;
      _passwordController.clear();
      _confirmController.clear();
    });
  }

  Future<void> _submitUnlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.unlock(_passwordController.text);
      if (!mounted) return;
      setState(() {
        _key = result.key;
        _notes = result.notes;
        _phase = _NotepadPhase.unlocked;
        _busy = false;
        _passwordController.clear();
      });
    } on WrongPasswordException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Yanlış şifre.';
      });
    }
  }

  void _lock() {
    setState(() {
      _key = null;
      _notes = [];
      _phase = _NotepadPhase.locked;
      _error = null;
      _passwordController.clear();
    });
  }

  Future<void> _resetNotepad() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Not Defterini Sıfırla'),
        content: const Text(
          'Şifre kriptografik olarak kurtarılamaz - devam ederseniz TÜM '
          'notlar kalıcı olarak silinir ve yeni bir şifreyle sıfırdan '
          'başlarsınız.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Notları Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.reset();
    if (!mounted) return;
    setState(() {
      _key = null;
      _notes = [];
      _phase = _NotepadPhase.setup;
      _error = null;
      _passwordController.clear();
    });
  }

  Future<void> _addOrEditNote({SecureNote? existing}) async {
    final key = _key;
    if (key == null) return;
    final titleController = TextEditingController(text: existing?.title ?? '');
    final bodyController = TextEditingController(text: existing?.body ?? '');
    final tagsController =
        TextEditingController(text: (existing?.tags ?? const []).join(', '));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Yeni Not' : 'Notu Düzenle'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Başlık'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: bodyController,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Not'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: 'Etiketler (virgülle ayırın)',
                  hintText: 'iş, önemli',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty && body.isEmpty) return;
    final tags = parseTagsInput(tagsController.text);

    final now = DateTime.now();
    setState(() {
      if (existing == null) {
        _notes = [
          ..._notes,
          SecureNote(
            id: now.millisecondsSinceEpoch.toString(),
            title: title,
            body: body,
            updatedAt: now,
            tags: tags,
          ),
        ];
      } else {
        _notes = _notes
            .map(
              (n) => n.id == existing.id
                  ? SecureNote(
                      id: n.id,
                      title: title,
                      body: body,
                      updatedAt: now,
                      tags: tags,
                    )
                  : n,
            )
            .toList();
        // Silinen bir etiket artik hicbir notta kullanilmiyor olabilir -
        // filtre gecerliligini kontrol et (bkz. _buildNotesList).
        if (_activeTagFilter != null &&
            !_notes.any((n) => n.tags.contains(_activeTagFilter))) {
          _activeTagFilter = null;
        }
      }
    });
    await _service.save(key, _notes);
  }

  Future<void> _deleteNote(SecureNote note) async {
    final key = _key;
    if (key == null) return;
    setState(() {
      _notes = _notes.where((n) => n.id != note.id).toList();
      if (_activeTagFilter != null &&
          !_notes.any((n) => n.tags.contains(_activeTagFilter))) {
        _activeTagFilter = null;
      }
    });
    await _service.save(key, _notes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.panelTranslucent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          // ListTile arka plan/ink efektlerini boyayabilmesi icin en
          // yakin Material atasina ihtiyac duyar - bu Container'in kendi
          // arka plan rengi bir DecoratedBox olarak araya girip bunu
          // gizlerdi, bu yuzden burada seffaf bir Material eklenir.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '🔒 Şifreli Not Defteri',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_phase == _NotepadPhase.unlocked) ...[
                      IconButton(
                        icon: Icon(Icons.add, color: colors.textSecondary),
                        tooltip: 'Yeni Not',
                        onPressed: () => _addOrEditNote(),
                      ),
                      IconButton(
                        icon: Icon(Icons.lock_outline,
                            color: colors.textSecondary),
                        tooltip: 'Kilitle',
                        onPressed: _lock,
                      ),
                    ],
                    IconButton(
                      icon: Icon(Icons.close, color: colors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                Divider(color: colors.divider, height: 1),
                Expanded(child: _buildBody(colors, scrollController)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(AppColors colors, ScrollController scrollController) {
    switch (_phase) {
      case _NotepadPhase.loading:
        return const Center(child: CircularProgressIndicator());
      case _NotepadPhase.setup:
        return _buildSetupForm(colors);
      case _NotepadPhase.locked:
        return _buildUnlockForm(colors);
      case _NotepadPhase.unlocked:
        return _buildNotesList(colors, scrollController);
    }
  }

  Widget _buildSetupForm(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notlarınız yalnızca bu cihazda, bu şifreyle şifreli olarak '
            'saklanır. Bu şifreyi unutursanız notlarınızı kurtarmanın bir '
            'yolu yoktur.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Yeni şifre'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Şifreyi tekrar yaz'),
            onSubmitted: (_) => _submitSetup(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _submitSetup,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Not Defterini Kur'),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockForm(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Şifre'),
            onSubmitted: (_) => _submitUnlock(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _submitUnlock,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kilidi Aç'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _resetNotepad,
            child: Text(
              'Şifremi unuttum (tüm notları sil)',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesList(AppColors colors, ScrollController scrollController) {
    if (_notes.isEmpty) {
      return Center(
        child: Text(
          'Henüz bir not yok. Eklemek için + simgesine dokunun.',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    final allTags = <String>{};
    for (final note in _notes) {
      allTags.addAll(note.tags);
    }
    final visibleNotes = _activeTagFilter == null
        ? _notes
        : _notes.where((n) => n.tags.contains(_activeTagFilter)).toList();
    final sorted = [...visibleNotes]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Column(
      children: [
        if (allTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final tag in allTags)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(tag),
                        selected: _activeTagFilter == tag,
                        onSelected: (selected) {
                          setState(
                            () => _activeTagFilter = selected ? tag : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: sorted.isEmpty
              ? Center(
                  child: Text(
                    'Bu etikette not yok.',
                    style: TextStyle(color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final note = sorted[index];
                    return ListTile(
                      title: Text(
                        note.title.isEmpty ? '(başlıksız)' : note.title,
                        style: TextStyle(color: colors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textMuted),
                          ),
                          if (note.tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                note.tags.map((t) => '#$t').join('  '),
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onTap: () => _addOrEditNote(existing: note),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: colors.textMuted),
                        tooltip: 'Notu Sil',
                        onPressed: () => _deleteNote(note),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
