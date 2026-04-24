import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/user_role.dart';
import '../../services/user_service.dart';
import '../../widgets/immutable_badge.dart';
import '../backup/backup_screen.dart';
import '../documents/documents_screen.dart';
import '../etat_des_lieux/etat_des_lieux_list_screen.dart';
import '../locataires/locataire_list_screen.dart';
import '../logements/logement_list_screen.dart';
import '../quittances/quittance_list_screen.dart';
import '../share/received_bundle_list_screen.dart';
import '../share/share_with_tenant_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserService>().current;
    if (profile == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Bonjour, ${profile.firstName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mon profil',
            onPressed: () => _showProfile(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          profile.role == UserRole.proprietaire
                              ? Icons.key_rounded
                              : Icons.home_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          profile.role.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile.fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: profile.role == UserRole.proprietaire
                    ? const _ProprietaireSections()
                    : const _LocataireSections(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProfile(BuildContext context) {
    final profile = context.read<UserService>().current!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Text(
                  'Mon profil',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 10),
                ImmutableBadge(),
              ],
            ),
            const SizedBox(height: 16),
            _InfoLine(label: 'Rôle', value: profile.role.label),
            _InfoLine(label: 'Prénom', value: profile.firstName),
            _InfoLine(label: 'Nom', value: profile.lastName),
            _InfoLine(label: 'Email', value: profile.email),
            _InfoLine(
              label: 'Créé le',
              value: profile.createdAt.toLocal().toString().split('.').first,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ces informations sont figées et apparaissent sur tous '
              'vos documents légaux.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProprietaireSections extends StatelessWidget {
  const _ProprietaireSections();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SectionTile(
          icon: Icons.apartment_rounded,
          title: 'Mes logements',
          subtitle: 'Ajouter, modifier ou supprimer un bien',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LogementListScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.people_alt_outlined,
          title: 'Mes locataires',
          subtitle: 'Gérer les locataires associés',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LocataireListScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.assignment_outlined,
          title: 'États des lieux',
          subtitle: 'Créer et consulter vos états des lieux',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EtatDesLieuxListScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.receipt_long_outlined,
          title: 'Quittances de loyer',
          subtitle: 'Générer des quittances conformes loi ALUR',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const QuittanceListScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.folder_open_outlined,
          title: 'Mes documents',
          subtitle: 'Retrouver et partager tous vos PDF',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DocumentsScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.bluetooth_searching,
          title: 'Partager avec un locataire',
          subtitle: 'Transfert local chiffré (Bluetooth / AirDrop / Nearby)',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ShareWithTenantScreen(),
            ),
          ),
        ),
        _SectionTile(
          icon: Icons.shield_outlined,
          title: 'Sauvegarde & restauration',
          subtitle: 'Export chiffré de toutes vos données',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BackupScreen()),
          ),
        ),
      ],
    );
  }
}

class _LocataireSections extends StatelessWidget {
  const _LocataireSections();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SectionTile(
          icon: Icons.assignment_outlined,
          title: 'Mes états des lieux',
          subtitle: 'Consulter mes états des lieux',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EtatDesLieuxListScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.receipt_long_outlined,
          title: 'Mes quittances',
          subtitle: 'Consulter mes quittances',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const QuittanceListScreen()),
          ),
        ),
        _SectionTile(
          icon: Icons.inbox_outlined,
          title: 'Documents reçus',
          subtitle: 'Consulter les partages de mon propriétaire',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ReceivedBundleListScreen(),
            ),
          ),
        ),
        _SectionTile(
          icon: Icons.shield_outlined,
          title: 'Sauvegarde & restauration',
          subtitle: 'Export chiffré de toutes mes données',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BackupScreen()),
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
