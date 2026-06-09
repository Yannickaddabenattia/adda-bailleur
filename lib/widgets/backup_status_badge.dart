import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../screens/backup/auto_backup_settings_screen.dart';
import '../services/auto_backup_service.dart';

/// Petit indicateur cloud à placer dans la barre d'en-tête.
///
/// Couleur en fonction du `AutoBackupState` :
/// - Désactivé → gris
/// - À jour → vert
/// - Dirty (en attente debounce) → ambre
/// - En cours → bleu
/// - Erreur → rouge
///
/// Tap → ouvre [AutoBackupSettingsScreen].
class BackupStatusBadge extends StatelessWidget {
  final EdgeInsets padding;
  const BackupStatusBadge({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<AutoBackupService>();
    final state = svc.state;
    IconData icon;
    Color color;
    String tooltip;
    switch (state) {
      case AutoBackupState.disabled:
        icon = Icons.cloud_off_outlined;
        color = Colors.grey;
        tooltip = 'Sauvegarde auto désactivée';
        break;
      case AutoBackupState.upToDate:
        icon = Icons.cloud_done_outlined;
        color = Colors.green;
        tooltip = 'Sauvegarde à jour';
        break;
      case AutoBackupState.dirty:
        icon = Icons.cloud_queue_outlined;
        color = Colors.amber.shade700;
        tooltip = 'Modifications en attente de sauvegarde';
        break;
      case AutoBackupState.inProgress:
        icon = Icons.cloud_upload_outlined;
        color = AppColors.primary;
        tooltip = 'Sauvegarde en cours…';
        break;
      case AutoBackupState.error:
        icon = Icons.cloud_off;
        color = Colors.red;
        tooltip = svc.lastError ?? 'Erreur de sauvegarde';
        break;
    }
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AutoBackupSettingsScreen(),
          ),
        ),
        radius: 22,
        child: Padding(
          padding: padding,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}
