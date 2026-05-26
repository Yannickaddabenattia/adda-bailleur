import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/rappel_service.dart';

/// Écran des rappels actifs : préavis, fin de bail, régularisation des
/// charges, expiration des diagnostics. Chaque rappel peut être ajouté au
/// calendrier natif via `add_2_calendar`.
class RappelsScreen extends StatelessWidget {
  const RappelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rappels = context.watch<RappelService>().compute();
    final df = DateFormat('EEEE d MMMM yyyy', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: const Text('Rappels')),
      body: rappels.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_none_outlined,
                        size: 64, color: AppColors.textSecondary),
                    SizedBox(height: 16),
                    Text('Aucun rappel actif',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text(
                      'Les préavis, fins de bail, régularisations annuelles '
                      'et expirations de diagnostics s\'afficheront ici '
                      'automatiquement.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              itemCount: rappels.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final r = rappels[i];
                final color = _color(r);
                final icon = _icon(r);
                final daysDiff =
                    r.date.difference(DateTime.now()).inDays;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: r.severite >= 2
                          ? AppColors.error.withValues(alpha: 0.45)
                          : context.dividerColor,
                      width: r.severite >= 2 ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.titre,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  df.format(r.date),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: r.estPasse
                                        ? AppColors.error
                                        : AppColors.textSecondary,
                                    fontWeight: r.estPasse
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!r.estPasse)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                daysDiff == 0
                                    ? 'Aujourd\'hui'
                                    : 'Dans $daysDiff j',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(r.description, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _addToCalendar(context, r),
                            icon: const Icon(Icons.event_outlined, size: 16),
                            label: const Text('Ajouter au calendrier'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _addToCalendar(BuildContext context, Rappel r) async {
    final event = Event(
      title: r.titre,
      description: r.description,
      startDate: DateTime(r.date.year, r.date.month, r.date.day, 9),
      endDate: DateTime(r.date.year, r.date.month, r.date.day, 10),
    );
    final ok = await Add2Calendar.addEvent2Cal(event);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Événement ajouté au calendrier.'
            : 'Calendrier indisponible.'),
      ),
    );
  }

  Color _color(Rappel r) {
    if (r.severite >= 2) return AppColors.error;
    switch (r.kind) {
      case RappelKind.preavisBailleur:
      case RappelKind.preavisLocataire:
        return AppColors.primary;
      case RappelKind.finBail:
        return AppColors.accent;
      case RappelKind.regularisationCharges:
        return const Color(0xFF7C3AED);
      case RappelKind.diagnosticExpire:
        return AppColors.error;
      case RappelKind.diagnosticProche:
        return AppColors.accent;
    }
  }

  IconData _icon(Rappel r) {
    switch (r.kind) {
      case RappelKind.preavisBailleur:
      case RappelKind.preavisLocataire:
        return Icons.mail_outline;
      case RappelKind.finBail:
        return Icons.event_busy_outlined;
      case RappelKind.regularisationCharges:
        return Icons.receipt_long_outlined;
      case RappelKind.diagnosticExpire:
        return Icons.warning_amber_outlined;
      case RappelKind.diagnosticProche:
        return Icons.fact_check_outlined;
    }
  }
}
