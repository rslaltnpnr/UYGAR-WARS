import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uygulama kilidi acikken acilista (ve arka plandan donuste) gosterilen
/// tam ekran PIN girisi - bkz. SettingsService.appLockEnabled ve
/// main.dart'taki _AppLockGate. [expectedPin] dogru girilince
/// [onUnlocked] cagrilir; bu ekran kendi basina navigasyon yapmaz, sadece
/// dogrulamayi bildirir.
class AppLockScreen extends StatefulWidget {
  final String expectedPin;
  final VoidCallback onUnlocked;

  const AppLockScreen({
    super.key,
    required this.expectedPin,
    required this.onUnlocked,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text == widget.expectedPin) {
      widget.onUnlocked();
      return;
    }
    setState(() => _error = 'Yanlış PIN.');
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Uygulama Kilitli',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'PIN'),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Kilidi Aç'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
