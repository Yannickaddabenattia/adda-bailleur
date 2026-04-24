import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../locataires/locataire_detail_screen.dart';
import 'logement_form_screen.dart';

class LogementDetailScreen extends StatelessWidget {
  final String logementId;
  const LogementDetailScreen({super.key, required this.logementId});

  @override
  Widget build(BuildContext context) {
    final logement = context.watch<LogementService>().byId(logementId);
    if (logement == null) {
      return const Scaffold(
        body: Center(child: Text('Logement introuvable.')),
      );
    }
    final locataires =
        context.watch<LocataireService>().byLogement(logementId);
    final currency =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: Text(logement.libelle),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LogementFormScreen(logement: logement),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, logement),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HeaderCard(logement: logement),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Caractéristiques',
            children: [
              _Row(label: 'Surface', value: '${logement.surface.toStringAsFixed(0)} m²'),
              _Row(label: 'Pièces', value: '${logement.nbPieces}'),
              _Row(label: 'Loyer HC', value: currency.format(logement.loyerHC)),
              _Row(label: 'Charges', value: currency.format(logement.charges)),
              _Row(
                label: 'Loyer TTC',
                value: currency.format(logement.loyerTTC),
                bold: true,
              ),
            ],
          ),
          if (logement.equipements.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Équipements',
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: logement.equipements
                      .map((e) => Chip(
                            label: Text(e),
                            backgroundColor: AppColors.primary
                                .withValues(alpha: 0.08),
                            side: BorderSide.none,
                          ))
                      .toList(),
                ),
              ],
            ),
          ],
          if (logement.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Notes',
              children: [Text(logement.notes)],
            ),
          ],
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Locataires (${locataires.length})',
            children: locataires.isEmpty
                ? [
                    const Text(
                      'Aucun locataire associé.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ]
                : locataires
                    .map((l) => _LocataireTile(locataire: l))
                    .toList(),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Logement logement) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce logement ?'),
        content: Text(
          'Le logement « ${logement.libelle} » sera supprimé définitivement. '
          'Les locataires associés ne seront PAS supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<LogementService>().delete(logement.id);
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

class _HeaderCard extends StatelessWidget {
  final Logement logement;
  const _HeaderCard({required this.logement});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(Icons.apartment_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                logement.type.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            logement.libelle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            logement.adresseComplete,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Row({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color:
                  bold ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocataireTile extends StatelessWidget {
  final Locataire locataire;
  const _LocataireTile({required this.locataire});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: Text(
          locataire.firstName.isNotEmpty ? locataire.firstName[0] : '?',
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(locataire.fullName),
      subtitle: Text(locataire.email),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LocataireDetailScreen(locataireId: locataire.id),
        ),
      ),
    );
  }
}
