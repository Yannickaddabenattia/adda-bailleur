import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../logements/logement_detail_screen.dart';
import 'locataire_form_screen.dart';

class LocataireDetailScreen extends StatelessWidget {
  final String locataireId;
  const LocataireDetailScreen({super.key, required this.locataireId});

  @override
  Widget build(BuildContext context) {
    final locataire = context.watch<LocataireService>().byId(locataireId);
    if (locataire == null) {
      return const Scaffold(
        body: Center(child: Text('Locataire introuvable.')),
      );
    }
    final logementService = context.watch<LogementService>();
    final logements = locataire.logementIds
        .map(logementService.byId)
        .whereType<dynamic>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(locataire.fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LocataireFormScreen(locataire: locataire),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, locataire),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
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
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Text(
                    locataire.firstName.isNotEmpty
                        ? locataire.firstName[0]
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  locataire.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  locataire.email,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
                if (locataire.phone != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    locataire.phone!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LOGEMENTS ASSOCIÉS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                if (logements.isEmpty)
                  const Text(
                    'Aucun logement associé.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ...logements.map(
                    (l) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.apartment_rounded,
                          color: AppColors.primary),
                      title: Text(l.libelle),
                      subtitle: Text(
                        l.adresseComplete,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              LogementDetailScreen(logementId: l.id),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (locataire.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NOTES',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(locataire.notes),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Locataire locataire) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce locataire ?'),
        content: Text(
          '${locataire.fullName} sera supprimé définitivement. '
          'Les logements associés ne seront PAS supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<LocataireService>().delete(locataire.id);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
