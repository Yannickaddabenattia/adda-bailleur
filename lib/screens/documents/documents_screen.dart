import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/quittance.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../etat_des_lieux/etat_des_lieux_detail_screen.dart';
import '../quittances/quittance_detail_screen.dart';

enum _DocKind { quittance, edl }

enum _DocFilter {
  tous('Tous'),
  quittances('Quittances'),
  edl('États des lieux');

  final String label;
  const _DocFilter(this.label);
}

/// Entrée unifiée pour l'affichage dans la liste.
class _DocEntry {
  final _DocKind kind;
  final String id;
  final DateTime date;
  final String title;
  final String subtitle;
  final String logementId;
  final String locataireId;
  final int year;
  final bool finalized;
  final String? amount;
  final IconData icon;

  _DocEntry({
    required this.kind,
    required this.id,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.logementId,
    required this.locataireId,
    required this.year,
    required this.finalized,
    required this.amount,
    required this.icon,
  });
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  _DocFilter _kindFilter = _DocFilter.tous;
  String? _logementId;
  String? _locataireId;
  int? _year;

  @override
  Widget build(BuildContext context) {
    final quittances = context.watch<QuittanceService>().all;
    final edls = context.watch<EtatDesLieuxService>().all;
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;

    final entries = _buildEntries(
      quittances: quittances,
      edls: edls,
      logements: logements,
      locataires: locataires,
    );
    final years = _collectYears(entries);
    final filtered = _applyFilters(entries);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes documents')),
      body: Column(
        children: [
          _Filters(
            kind: _kindFilter,
            logementId: _logementId,
            locataireId: _locataireId,
            year: _year,
            logements: logements,
            locataires: locataires,
            years: years,
            onKindChanged: (v) => setState(() => _kindFilter = v),
            onLogementChanged: (v) => setState(() => _logementId = v),
            onLocataireChanged: (v) => setState(() => _locataireId = v),
            onYearChanged: (v) => setState(() => _year = v),
            onReset: _resetFilters,
          ),
          if (filtered.isEmpty)
            const Expanded(child: _Empty())
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) => _DocCard(entry: filtered[i]),
              ),
            ),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _kindFilter = _DocFilter.tous;
      _logementId = null;
      _locataireId = null;
      _year = null;
    });
  }

  List<_DocEntry> _buildEntries({
    required List<Quittance> quittances,
    required List<EtatDesLieux> edls,
    required List<Logement> logements,
    required List<Locataire> locataires,
  }) {
    final logementById = {for (final l in logements) l.id: l};
    final locataireById = {for (final l in locataires) l.id: l};
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    final entries = <_DocEntry>[];

    for (final q in quittances) {
      final loc = logementById[q.logementId];
      final ten = locataireById[q.locataireId];
      entries.add(
        _DocEntry(
          kind: _DocKind.quittance,
          id: q.id,
          date: DateTime(q.periodYear, q.periodMonth, 1),
          title: 'Quittance ${_capitalize(q.periodLabel)}',
          subtitle: [
            ten?.fullName ?? 'Locataire supprimé',
            loc?.libelle ?? 'Logement supprimé',
          ].join(' · '),
          logementId: q.logementId,
          locataireId: q.locataireId,
          year: q.periodYear,
          finalized: true,
          amount: money.format(q.total),
          icon: Icons.receipt_long_outlined,
        ),
      );
    }

    for (final e in edls) {
      final loc = logementById[e.logementId];
      final ten = locataireById[e.locataireId];
      entries.add(
        _DocEntry(
          kind: _DocKind.edl,
          id: e.id,
          date: e.date,
          title: e.titre,
          subtitle: [
            ten?.fullName ?? 'Locataire supprimé',
            loc?.libelle ?? 'Logement supprimé',
          ].join(' · '),
          logementId: e.logementId,
          locataireId: e.locataireId,
          year: e.date.year,
          finalized: e.isFinalized,
          amount: null,
          icon: e.type == EtatDesLieuxType.entree
              ? Icons.login_rounded
              : Icons.logout_rounded,
        ),
      );
    }

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  List<_DocEntry> _applyFilters(List<_DocEntry> entries) {
    return entries.where((e) {
      if (_kindFilter == _DocFilter.quittances && e.kind != _DocKind.quittance) {
        return false;
      }
      if (_kindFilter == _DocFilter.edl && e.kind != _DocKind.edl) {
        return false;
      }
      if (_logementId != null && e.logementId != _logementId) return false;
      if (_locataireId != null && e.locataireId != _locataireId) return false;
      if (_year != null && e.year != _year) return false;
      return true;
    }).toList();
  }

  List<int> _collectYears(List<_DocEntry> entries) {
    final set = <int>{for (final e in entries) e.year};
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Filters extends StatelessWidget {
  final _DocFilter kind;
  final String? logementId;
  final String? locataireId;
  final int? year;
  final List<Logement> logements;
  final List<Locataire> locataires;
  final List<int> years;
  final ValueChanged<_DocFilter> onKindChanged;
  final ValueChanged<String?> onLogementChanged;
  final ValueChanged<String?> onLocataireChanged;
  final ValueChanged<int?> onYearChanged;
  final VoidCallback onReset;

  const _Filters({
    required this.kind,
    required this.logementId,
    required this.locataireId,
    required this.year,
    required this.logements,
    required this.locataires,
    required this.years,
    required this.onKindChanged,
    required this.onLogementChanged,
    required this.onLocataireChanged,
    required this.onYearChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = kind != _DocFilter.tous ||
        logementId != null ||
        locataireId != null ||
        year != null;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _DocFilter.values) ...[
                  ChoiceChip(
                    label: Text(f.label),
                    selected: kind == f,
                    onSelected: (_) => onKindChanged(f),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DropdownFilter<String?>(
                  label: 'Logement',
                  value: logementId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous les logements'),
                    ),
                    ...logements.map(
                      (l) => DropdownMenuItem<String?>(
                        value: l.id,
                        child: Text(
                          l.libelle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onLogementChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DropdownFilter<String?>(
                  label: 'Locataire',
                  value: locataireId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous les locataires'),
                    ),
                    ...locataires.map(
                      (l) => DropdownMenuItem<String?>(
                        value: l.id,
                        child: Text(
                          l.fullName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onLocataireChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DropdownFilter<int?>(
                  label: 'Année',
                  value: year,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Toutes les années'),
                    ),
                    ...years.map(
                      (y) => DropdownMenuItem<int?>(
                        value: y,
                        child: Text(y.toString()),
                      ),
                    ),
                  ],
                  onChanged: onYearChanged,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: hasActiveFilter ? onReset : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Réinitialiser'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DropdownFilter<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownFilter({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _DocCard extends StatelessWidget {
  final _DocEntry entry;
  const _DocCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(entry.icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        df.format(entry.date),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (entry.kind == _DocKind.edl) _StatusBadge(entry: entry),
                    ],
                  ),
                ],
              ),
            ),
            if (entry.amount != null) ...[
              const SizedBox(width: 8),
              Text(
                entry.amount!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    switch (entry.kind) {
      case _DocKind.quittance:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuittanceDetailScreen(quittanceId: entry.id),
          ),
        );
      case _DocKind.edl:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EtatDesLieuxDetailScreen(edlId: entry.id),
          ),
        );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final _DocEntry entry;
  const _StatusBadge({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.finalized ? AppColors.success : AppColors.accent;
    final label = entry.finalized ? 'Finalisé' : 'En cours';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 72,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucun document',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vos quittances et états des lieux apparaîtront ici. '
              'Ajustez les filtres pour affiner la recherche.',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
