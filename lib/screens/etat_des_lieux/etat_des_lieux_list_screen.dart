import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import 'etat_des_lieux_detail_screen.dart';
import 'etat_des_lieux_wizard_screen.dart';

class EtatDesLieuxListScreen extends StatelessWidget {
  const EtatDesLieuxListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<EtatDesLieuxService>().all;

    return Scaffold(
      appBar: AppBar(title: const Text('États des lieux')),
      body: items.isEmpty
          ? _EmptyState(onAdd: () => _startNew(context))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _EdlCard(edl: items[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startNew(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _startNew(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EtatDesLieuxWizardScreen()),
    );
  }
}

class _EdlCard extends StatelessWidget {
  final EtatDesLieux edl;
  const _EdlCard({required this.edl});

  @override
  Widget build(BuildContext context) {
    final logement = context.watch<LogementService>().byId(edl.logementId);
    final locataire = context.watch<LocataireService>().byId(edl.locataireId);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EtatDesLieuxDetailScreen(edlId: edl.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    edl.type == EtatDesLieuxType.entree
                        ? Icons.login_rounded
                        : Icons.logout_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        edl.titre,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${logement?.libelle ?? '(logement supprimé)'} — ${locataire?.fullName ?? '(locataire supprimé)'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: edl.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final EtatDesLieuxStatus status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case EtatDesLieuxStatus.brouillon:
        return AppColors.textSecondary;
      case EtatDesLieuxStatus.enAttenteSignatureLocataire:
        return AppColors.accent;
      case EtatDesLieuxStatus.finalise:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Aucun état des lieux',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Créez un EDL d\'entrée ou de sortie pour commencer.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Nouvel état des lieux'),
            ),
          ],
        ),
      ),
    );
  }
}
