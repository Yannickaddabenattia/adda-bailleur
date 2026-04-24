import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/logement.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import 'logement_detail_screen.dart';
import 'logement_form_screen.dart';

class LogementListScreen extends StatelessWidget {
  const LogementListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<LogementService>();
    final logements = service.all;

    return Scaffold(
      appBar: AppBar(title: const Text('Mes logements')),
      body: logements.isEmpty
          ? _EmptyState(
              onAdd: () => _openForm(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logements.length,
              itemBuilder: (context, i) => _LogementCard(logement: logements[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _openForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogementFormScreen()),
    );
  }
}

class _LogementCard extends StatelessWidget {
  final Logement logement;
  const _LogementCard({required this.logement});

  @override
  Widget build(BuildContext context) {
    final nbLocataires =
        context.watch<LocataireService>().byLogement(logement.id).length;
    final currency =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LogementDetailScreen(logementId: logement.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
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
                    child: const Icon(Icons.apartment_rounded,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          logement.libelle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          logement.adresseComplete,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(
                    icon: Icons.home_work_outlined,
                    label: logement.type.label,
                  ),
                  _Chip(
                    icon: Icons.square_foot,
                    label: '${logement.surface.toStringAsFixed(0)} m²',
                  ),
                  _Chip(
                    icon: Icons.door_front_door_outlined,
                    label: '${logement.nbPieces} pièce(s)',
                  ),
                  _Chip(
                    icon: Icons.euro,
                    label: currency.format(logement.loyerTTC),
                  ),
                  _Chip(
                    icon: Icons.people_alt_outlined,
                    label: '$nbLocataires locataire(s)',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
            Icon(Icons.apartment_rounded,
                size: 72,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Aucun logement',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez votre premier bien pour commencer.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un logement'),
            ),
          ],
        ),
      ),
    );
  }
}
