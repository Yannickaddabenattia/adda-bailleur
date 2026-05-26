import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/user_service.dart';
import '../backup/backup_screen.dart';
import '../etat_des_lieux/etat_des_lieux_list_screen.dart';
import '../quittances/quittance_list_screen.dart';
import '../share/received_bundle_list_screen.dart';

class LocataireHomeScreen extends StatelessWidget {
  const LocataireHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserService>().current;
    if (profile == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(title: Text('Bonjour, ${profile.firstName}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              _Tile(
                icon: Icons.assignment_outlined,
                title: 'Mes états des lieux',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EtatDesLieuxListScreen(),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.receipt_long_outlined,
                title: 'Mes quittances',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QuittanceListScreen()),
                ),
              ),
              _Tile(
                icon: Icons.inbox_outlined,
                title: 'Documents reçus',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ReceivedBundleListScreen(),
                  ),
                ),
              ),
              _Tile(
                icon: Icons.shield_outlined,
                title: 'Sauvegarde & restauration',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BackupScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.dividerColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: context.textSecondaryColor),
            ],
          ),
        ),
      ),
    );
  }
}
