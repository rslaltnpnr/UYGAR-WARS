import 'package:flutter/material.dart';

import '../models/remote_profile.dart';
import '../services/automation_rules.dart';
import '../services/remote_control_service.dart';

/// Bilgisayarda tanimli otomasyon kurallarini (bkz. masaustu uygulamasinin
/// "Otomasyon Kurallari" penceresi) salt-okunur olarak listeler - kurallar
/// yalnizca masaustunde olusturulup duzenlenebilir, telefon /automation
/// uc noktasindan mevcut listeyi ceker ve gosterir; boylece uzaktayken bile
/// hangi kurallarin aktif oldugunu gorebilirsiniz.
class AutomationRulesScreen extends StatefulWidget {
  final RemoteControlService remoteService;
  final RemoteProfile profile;
  final void Function(String fingerprint) onFingerprintUpdated;

  const AutomationRulesScreen({
    super.key,
    required this.remoteService,
    required this.profile,
    required this.onFingerprintUpdated,
  });

  @override
  State<AutomationRulesScreen> createState() => _AutomationRulesScreenState();
}

class _AutomationRulesScreenState extends State<AutomationRulesScreen> {
  List<Map<String, dynamic>>? _rules;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.remoteService.fetchAutomationRules(
        ip: widget.profile.ip,
        port: widget.profile.port,
        pin: widget.profile.pin,
        pinnedFingerprint: widget.profile.certFingerprint,
      );
      widget.onFingerprintUpdated(result.fingerprint);
      if (!mounted) return;
      setState(() {
        _rules = result.rules;
        _loading = false;
      });
    } on RemoteControlException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Otomasyon Kurallari'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final rules = _rules ?? [];
    if (rules.isEmpty) {
      return const Center(child: Text('Bilgisayarda tanimli kural yok.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rules.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final rule = rules[index];
        final enabled = rule['enabled'] as bool? ?? true;
        return ListTile(
          leading: Icon(
            enabled ? Icons.rule : Icons.rule_folder_outlined,
            color: enabled ? null : Theme.of(context).disabledColor,
          ),
          title: Text(describeAutomationRule(rule)),
        );
      },
    );
  }
}
