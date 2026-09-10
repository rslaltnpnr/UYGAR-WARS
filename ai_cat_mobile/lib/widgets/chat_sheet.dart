import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_entry.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';

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
  late List<ChatEntry> _entries;
  XFile? _pendingImage;
  bool _busy = false;

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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xE61E1E28),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white70,
                    ),
                    tooltip: 'Gecmisi Temizle',
                    onPressed: _entries.isEmpty ? null : _clearHistory,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: _entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Henuz bir sohbet gecmisi yok.',
                          style: TextStyle(color: Colors.white38),
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
                    icon: const Icon(
                      Icons.photo_library,
                      color: Colors.white70,
                    ),
                    tooltip: 'Galeriden Sec',
                    onPressed:
                        _busy ? null : () => _pickImage(ImageSource.gallery),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white70),
                    tooltip: 'Fotograf Cek',
                    onPressed:
                        _busy ? null : () => _pickImage(ImageSource.camera),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Bir soru yaz...',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  _busy
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Color(0xFF5AAAFF),
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
          const Expanded(
            child: Text(
              'Gorsel eklendi',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white70),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sen: ${entry.question}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.isError ? "⚠" : "\u{1F431}"} ${entry.answer}',
            style: TextStyle(
              color: entry.isError ? const Color(0xFFFF8080) : Colors.white,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
