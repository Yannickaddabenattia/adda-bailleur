import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_role.dart';
import '../../services/auto_backup_service.dart';
import '../../services/master_key_service.dart';
import '../../services/theme_service.dart';
import '../../services/user_service.dart';
import '../backup/backup_screen.dart';
import '../onboarding/user_info_screen.dart';
import '../backup/pre_update_backups_screen.dart';
import '../share/share_with_tenant_screen.dart';
import 'cloud_sync_screen.dart';
import 'confidentialite_screen.dart';
import 'pays_fiscalite_screen.dart';

class ReglagesScreen extends StatelessWidget {
  const ReglagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserService>().current;
    final themeService = context.watch<ThemeService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (profile != null)
            _ProfileCard(
              fullName: profile.fullName,
              email: profile.email,
              role: profile.role.label,
            ),
          const SizedBox(height: 20),
          _SectionLabel('APPARENCE'),
          _Card(
            children: [
              SwitchListTile(
                title: const Text('Mode sombre'),
                subtitle: Text(
                  themeService.isDark
                      ? 'Interface sombre activée'
                      : 'Interface claire',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                secondary: Icon(
                  themeService.isDark
                      ? Icons.nightlight_round
                      : Icons.wb_sunny_rounded,
                  color: AppColors.accent,
                ),
                value: themeService.isDark,
                onChanged: (_) => themeService.toggle(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('DONNÉES'),
          _Card(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined,
                    color: AppColors.success),
                title: const Text('Sauvegarde & restauration'),
                subtitle: Text(
                  'Export chiffré',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BackupScreen()),
                ),
              ),
              Divider(height: 1, color: context.dividerColor),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined,
                    color: AppColors.primary),
                title: const Text('Synchronisation cloud'),
                subtitle: Text(
                  'pCloud · Dropbox · Drive · iCloud · chiffré',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CloudSyncScreen()),
                ),
              ),
              Divider(height: 1, color: context.dividerColor),
              ListTile(
                leading: Icon(Icons.restore, color: Colors.orange.shade700),
                title: const Text('Sauvegardes de sécurité'),
                subtitle: Text(
                  'Points de restauration avant mise à jour',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PreUpdateBackupsScreen(),
                  ),
                ),
              ),
              Divider(height: 1, color: context.dividerColor),
              ListTile(
                leading: const Icon(Icons.bluetooth_searching,
                    color: AppColors.primary),
                title: const Text('Partager avec un locataire'),
                subtitle: Text(
                  'Bluetooth · AirDrop · Nearby',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ShareWithTenantScreen(),
                  ),
                ),
              ),
            ],
          ),
          if (AppConstants.multiPaysActif) ...[
            const SizedBox(height: 20),
            _SectionLabel('PAYS & FISCALITÉ'),
            _Card(
              children: [
                ListTile(
                  leading: const Icon(Icons.public, color: AppColors.primary),
                  title: const Text('Pays & fiscalité'),
                  subtitle: Text(
                    'Taux marginaux Belgique / Suisse',
                    style: TextStyle(color: context.textSecondaryColor),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PaysFiscaliteScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _SectionLabel('À PROPOS'),
          _Card(
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.success),
                title: const Text('Confidentialité'),
                subtitle: Text(
                  '100 % local · aucune donnée envoyée',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ConfidentialiteScreen(),
                  ),
                ),
              ),
              Divider(height: 1, color: context.dividerColor),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                trailing: Text(
                  AppConstants.appVersion,
                  style: TextStyle(color: context.textSecondaryColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('COMPTE'),
          _Card(
            children: [
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined,
                    color: AppColors.error),
                title: const Text(
                  'Supprimer mon compte',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Efface définitivement le profil, toutes les données et les '
                  'sauvegardes cloud',
                  style: TextStyle(color: context.textSecondaryColor),
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: AppColors.error),
                onTap: () => _confirmDeleteAccount(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Parcours de suppression de compte (Apple Guideline 5.1.1(v)) : confirmation
/// explicite → suppression irréversible → retour à l'onboarding. App
/// *local-first* : efface profil + données + mot de passe maître + sauvegardes
/// cloud accessibles (cf. [UserService.deleteAccount]).
Future<void> _confirmDeleteAccount(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer mon compte ?'),
      content: const Text(
        'Cette action est définitive et irréversible. Elle effacera :\n\n'
        '• votre profil ;\n'
        '• tous vos biens, locataires, quittances, états des lieux et '
        'documents ;\n'
        '• votre mot de passe maître ;\n'
        '• les sauvegardes chiffrées accessibles dans votre dossier cloud lié.\n\n'
        'Aucune récupération ne sera possible.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annuler'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final userService = context.read<UserService>();
  final masterKey = context.read<MasterKeyService>();
  final autoBackup = context.read<AutoBackupService>();
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);

  // Indicateur de chargement (non annulable) pendant la suppression.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await userService.deleteAccount(
      masterKey: masterKey,
      autoBackup: autoBackup,
    );
    navigator.pop(); // ferme le chargement
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const UserInfoScreen(role: UserRole.proprietaire),
      ),
      (route) => false,
    );
  } catch (e) {
    navigator.pop(); // ferme le chargement
    messenger.showSnackBar(
      SnackBar(content: Text('Échec de la suppression : $e')),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String fullName;
  final String email;
  final String role;
  const _ProfileCard({
    required this.fullName,
    required this.email,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final initials = fullName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.accent,
            child: Text(
              initials.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
      child: Text(
        label,
        style: TextStyle(
          color: context.textSecondaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(children: children),
    );
  }
}
