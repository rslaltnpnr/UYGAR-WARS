import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/pairing_uri.dart';
import '../theme/app_colors.dart';

/// Masaüstü uygulamasının "Uzaktan Kumanda" penceresindeki QR kodu
/// kamerayla tarayan tam ekran sayfa. İlk geçerli (bkz. parsePairingUri)
/// karede sonucu Navigator.pop() ile geri döndürür - sayaç yerine tek
/// seferlik bir bayrakla (_handled) korunur, aksi halde art arda gelen
/// kamera karelerinde aynı kod birden fazla kez işlenip birden fazla
/// pop() denemesi (ve hataya) yol açabilir.
class QrPairingScannerScreen extends StatefulWidget {
  const QrPairingScannerScreen({super.key});

  @override
  State<QrPairingScannerScreen> createState() =>
      _QrPairingScannerScreenState();
}

class _QrPairingScannerScreenState extends State<QrPairingScannerScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final info = parsePairingUri(raw);
      if (info != null) {
        _handled = true;
        Navigator.of(context).pop(info);
        return;
      }
    }
    if (mounted) {
      setState(() => _error = 'Bu bir bilgisayar eşleştirme kodu değil.');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('QR Kodu Tarayın'),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.panelTranslucent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.error),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
