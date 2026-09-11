import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_entry.dart';
import '../services/history_service.dart';
import '../services/remote_control_service.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';

/// Kediye dokununca acilan, metin ve/veya foto ile soru sorulabilen panel.
/// Gecmis girisleri [HistoryService]'ten yuklenir; yeni sorular
/// [onAsk] araciligiyla ust widget'a (HomeScreen) devredilir - cevap
/// alindiginda ya da hata olustugunda kalici olarak orada kaydedilir.
class ChatSheet extends StatefulWidget {
  final SettingsService settings;
  final HistoryService history;
  final Future<String> Function(String question, Uint8List? imageBytes) onAsk;

  const ChatSheet({
    super.key,
    required this.settings,
    required this.history,
    required this.onAsk,
  });

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _remoteService = RemoteControlService();
  late List<ChatEntry> _entries;
  XFile? _pendingImage;
  bool _busy = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _entries = widget.history.load().reversed.toList(); // en yeni en ustte
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file != null && mounted) {
      setState(() => _pendingImage = file);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    final hasImage = _pendingImage != null;
    final question = hasImage ? '$text\n[Gorsel eklendi]' : text;

    setState(() => _busy = true);
    Uint8List? bytes;
    if (_pendingImage != null) {
      bytes = await _pendingImage!.readAsBytes();
    }

    try {
      final answer = await widget.onAsk(question, bytes);
      if (!mounted) return;
      setState(() {
        _entries.insert(
          0,
          ChatEntry(
            time: DateTime.now(),
            question: question,
            answer: answer,
            isError: false,
          ),
        );
        _controller.clear();
        _pendingImage = null;
      });
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        _entries.insert(
          0,
          ChatEntry(
            time: DateTime.now(),
            question: question,
            answer: exc.toString(),
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearHistory() {
    widget.history.clear();
    setState(() => _entries = []);
  }

  Future<void> _importFromDesktop() async {
    if (_importing) return;
    final profiles = widget.settings.remoteProfiles;
    if (profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Önce "Bilgisayarı Kumanda Et" panelinden bir bilgisayar ekleyin.',
          ),
        ),
      );
      return;
    }
    final activeId = widget.settings.activeProfileId;
    final profile = profiles.firstWhere(
      (p) => p.id == activeId,
      orElse: () => profiles.first,
    );

    setState(() => _importing = true);
    try {
      final result = await _remoteService.fetchHistory(
        ip: profile.ip,
        port: profile.port,
        pin: profile.pin,
        pinnedFingerprint: profile.certFingerprint,
      );
      widget.settings.remoteProfiles = profiles
          .map(
            (p) => p.id == profile.id
                ? p.copyWith(certFingerprint: result.fingerprint)
                : p,
          )
          .toList();

      final imported = result.entries
          .map(
            (e) => ChatEntry(
              time: DateTime.tryParse(e['time'] as String? ?? '') ??
                  DateTime.now(),
              question: e['question'] as String? ?? '',
              answer: e['answer'] as String? ?? '',
              isError: e['is_error'] as bool? ?? false,
            ),
          )
          .toList();

      String keyOf(ChatEntry e) =>
          '${e.time.toIso8601String()}|${e.question}|${e.answer}';
      final existingKeys = _entries.map(keyOf).toSet();
      var addedCount = 0;
      for (final entry in imported) {
        final key = keyOf(entry);
        if (existingKeys.contains(key)) continue;
        existingKeys.add(key);
        widget.history.add(entry);
        addedCount++;
      }

      if (!mounted) return;
      setState(() {
        _entries = widget.history.load().reversed.toList();
        _importing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$addedCount yeni kayıt içe aktarıldı.')),
      );
    } catch (exc) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exc.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.panelTranslucent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '\u{1F431} ${widget.settings.characterName}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: _importing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textSecondary,
                            ),
                          )
                        : Icon(
                            Icons.cloud_download_outlined,
                            color: colors.textSecondary,
                          ),
                    tooltip: 'Bilgisayardan Geçmişi Al',
                    onPressed: _importing ? null : _importFromDesktop,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: colors.textSecondary,
                    ),
                    tooltip: 'Gecmisi Temizle',
                    onPressed: _entries.isEmpty ? null : _clearHistory,
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Divider(color: colors.divider, height: 1),
              Expanded(
                child: _entries.isEmpty
                    ? Center(
                        child: Text(
                          'Henuz bir sohbet gecmisi yok.',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) =>
                            _EntryTile(entry: _entries[index]),
                      ),
              ),
              if (_pendingImage != null)
                _PendingImagePreview(
                  file: _pendingImage!,
                  onRemove: () => setState(() => _pendingImage = null),
                ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.photo_library,
                      color: colors.textSecondary,
                    ),
                    tooltip: 'Galeriden Sec',
                    onPressed:
                        _busy ? null : () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: Icon(Icons.camera_alt, color: colors.textSecondary),
                    tooltip: 'Fotograf Cek',
                    onPressed:
                        _busy ? null : () => _pickImage(ImageSource.camera),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Bir soru yaz...',
                        hintStyle: TextStyle(color: colors.textMuted),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  _busy
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.textSecondary,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: Icon(
                            Icons.send,
                            color: colors.accent,
                          ),
                          onPressed: _send,
                        ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PendingImagePreview extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _PendingImagePreview({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(file.path),
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Gorsel eklendi',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: context.colors.textSecondary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final ChatEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sen: ${entry.question}',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.isError ? "⚠" : "\u{1F431}"} ${entry.answer}',
            style: TextStyle(
              color: entry.isError ? colors.error : colors.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
