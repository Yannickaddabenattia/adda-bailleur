import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon_3d.dart';
import '../../services/theme_service.dart';
import '../../services/user_service.dart';
import '../backup/backup_screen.dart';
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
                secondary: const Icon(
                  Icons.nightlight_round,
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
                leading: const AppIcon3D(name: 'icon-cloud-sync', size: 34),
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
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String fullName;
  final String role;
  const _ProfileCard({
    required this.fullName,
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
