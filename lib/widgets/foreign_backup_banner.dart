import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../services/auto_backup_service.dart';

/// Bannière affichée quand une sauvegarde plus récente provenant d'un AUTRE
/// appareil est détectée sur le dossier partagé. Propose une fusion en 1 tap.
///
/// Invisible (`SizedBox.shrink`) tant qu'aucune donnée étrangère n'est en
/// attente. À placer en tête de l'accueil et de l'écran de sauvegarde.
class ForeignBackupBanner extends StatefulWidget {
  const ForeignBackupBanner({super.key});

  @override
  State<ForeignBackupBanner> createState() => _ForeignBackupBannerState();
}

class _ForeignBackupBannerState extends State<ForeignBackupBanner> {
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    final r = await context.read<AutoBackupService>().importForeignBackup();
    if (!mounted) return;
    setState(() => _busy = false);
    final msg = r.didBackup
        ? 'Données de l\'autre appareil fusionnées.'
        : (r.errorMessage != null
            ? 'Échec de l\'import : ${r.errorMessage}'
            : 'Rien à importer.');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<AutoBackupService>().pendingForeign;
    if (pending == null) return const SizedBox.shrink();
    final fmt = DateFormat('dd MMM yyyy à HH:mm', 'fr_FR');
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_download_outlined,
              color: AppColors.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Données d\'un autre appareil',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  'Sauvegarde du ${fmt.format(pending.dateTime)} détectée sur '
                  'le dossier partagé.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _import,
            child: Text(_busy ? '…' : 'Importer'),
          ),
        ],
      ),
    );
  }
}
