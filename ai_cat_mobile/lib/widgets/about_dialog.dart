import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// "Hakkında": surum numarasi ve proje deposu linkini gosteren basit bir
/// bilgi penceresi.
class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key});

  static const _repoUrl = 'https://github.com/rslaltnpnr/UYGAR-WARS';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.panel,
      title: Text('Hakkında', style: TextStyle(color: colors.textPrimary)),
      content: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version ?? '...';
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI Kedi Asistanı',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text('Sürüm $version', style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 12),
              Text(
                'Google Gemini destekli, uygulama ekranında gezinen bir '
                'kedi asistanı.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(_repoUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'GitHub deposu',
                  style: TextStyle(
                    color: colors.accent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}
