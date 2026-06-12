import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/pdf/quittance_pdf.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/etat_des_lieux.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/quittance.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/plan_logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/user_service.dart';
import '../../widgets/disclaimer_dialog.dart';
import '../backup/backup_screen.dart';
import '../etat_des_lieux/etat_des_lieux_detail_screen.dart';
import '../quittances/quittance_detail_screen.dart';
import '../quittances/quittance_form_screen.dart';

enum _DocKind { quittance, edl }

enum _DocFilter {
  tous('Tous'),
  quittances('Quittances'),
  edl('États des lieux');

  final String label;
  const _DocFilter(this.label);
}

enum _SortMode {
  recent('Plus récent'),
  ancien('Plus ancien'),
  amount('Montant');

  final String label;
  const _SortMode(this.label);
}

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
  final double? amountValue;
  final String? amountLabel;
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
    required this.amountValue,
    required this.amountLabel,
    required this.icon,
  });
}

class _MissingMonth {
  final String logementId;
  final String locataireId;
  final String logementLabel;
  final int year;
  final int month;
  const _MissingMonth({
    required this.logementId,
    required this.locataireId,
    required this.logementLabel,
    required this.year,
    required this.month,
  });

  String get monthLabel {
    const mois = [
      'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
    ];
    return '${mois[month - 1]} $year';
  }
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  _DocFilter _kindFilter = _DocFilter.tous;
  _SortMode _sort = _SortMode.recent;
  String _query = '';
  late final TextEditingController _searchCtrl;
  String? _locataireFilter; // null = tous, sinon id du locataire choisi

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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

    final countsByKind = <_DocFilter, int>{
      _DocFilter.tous: entries.length,
      _DocFilter.quittances:
          entries.where((e) => e.kind == _DocKind.quittance).length,
      _DocFilter.edl: entries.where((e) => e.kind == _DocKind.edl).length,
    };

    final filtered = _applyFiltersAndSort(entries);

    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final totalEuros = filtered.fold<double>(
      0,
      (s, e) => s + (e.amountValue ?? 0),
    );

    final grouped = _groupByMonth(filtered);
    final missing = _detectMissingMonths(
      quittances: quittances,
      logements: logements,
      locataires: locataires,
    );

    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: Column(
        children: [
          _Hero(
            count: filtered.length,
            total: totalEuros,
            money: money,
            onBack: Navigator.of(context).canPop()
                ? () => Navigator.of(context).maybePop()
                : null,
            onExport: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _SearchBar(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in _DocFilter.values) ...[
                        _FilterPill(
                          label: '${f.label} · ${countsByKind[f]}',
                          icon: _filterIcon(f),
                          selected: _kindFilter == f,
                          onTap: () => setState(() => _kindFilter = f),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Filtre par locataire : "Tous" + 1 pill par locataire ayant
                // au moins 1 document. Compte les documents par locataire
                // après filtrage par type pour rester cohérent.
                Builder(builder: (_) {
                  final countsByTenant = <String, int>{};
                  for (final e in entries) {
                    if (_kindFilter == _DocFilter.quittances &&
                        e.kind != _DocKind.quittance) continue;
                    if (_kindFilter == _DocFilter.edl &&
                        e.kind != _DocKind.edl) continue;
                    countsByTenant.update(
                      e.locataireId,
                      (v) => v + 1,
                      ifAbsent: () => 1,
                    );
                  }
                  final tenantsWithDocs = locataires
                      .where((l) => countsByTenant.containsKey(l.id))
                      .toList()
                    ..sort((a, b) => a.fullName.compareTo(b.fullName));
                  return SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterPill(
                          label: 'Tous locataires · ${entries.length}',
                          icon: Icons.groups_outlined,
                          selected: _locataireFilter == null,
                          onTap: () =>
                              setState(() => _locataireFilter = null),
                        ),
                        const SizedBox(width: 8),
                        for (final l in tenantsWithDocs) ...[
                          _FilterPill(
                            label:
                                '${l.fullName} · ${countsByTenant[l.id]}',
                            icon: Icons.person_outline,
                            selected: _locataireFilter == l.id,
                            onTap: () =>
                                setState(() => _locataireFilter = l.id),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 14),
                _SortRow(
                  sort: _sort,
                  count: filtered.length,
                  onSortChanged: (s) => setState(() => _sort = s),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty) const _Empty(),
                for (final group in grouped) ...[
                  const SizedBox(height: 10),
                  _MonthHeader(label: group.label),
                  const SizedBox(height: 8),
                  for (final e in group.entries) ...[
                    _DocCard(
                      entry: e,
                      onTap: () => _open(context, e),
                      onShare: () => _share(context, e),
                      onMore: () => _more(context, e),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                if (missing != null) ...[
                  const SizedBox(height: 6),
                  _MissingBanner(
                    missing: missing,
                    onGenerate: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QuittanceFormScreen(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F1B3A),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Générer',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuittanceFormScreen()),
        ),
      ),
    );
  }

  IconData _filterIcon(_DocFilter f) {
    switch (f) {
      case _DocFilter.tous:
        return Icons.layers_outlined;
      case _DocFilter.quittances:
        return Icons.description_outlined;
      case _DocFilter.edl:
        return Icons.event_available_outlined;
    }
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
          title: 'Quittance · ${_capitalize(q.periodLabel)}',
          subtitle: [
            ten?.fullName ?? 'Locataire supprimé',
            loc?.libelle ?? 'Logement supprimé',
          ].join(' · '),
          logementId: q.logementId,
          locataireId: q.locataireId,
          year: q.periodYear,
          finalized: true,
          amountValue: q.total,
          amountLabel: money.format(q.total),
          icon: Icons.description_outlined,
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
          amountValue: null,
          amountLabel: null,
          icon: e.type == EtatDesLieuxType.entree
              ? Icons.login_rounded
              : Icons.logout_rounded,
        ),
      );
    }
    return entries;
  }

  List<_DocEntry> _applyFiltersAndSort(List<_DocEntry> entries) {
    var list = entries.where((e) {
      if (_kindFilter == _DocFilter.quittances && e.kind != _DocKind.quittance) {
        return false;
      }
      if (_kindFilter == _DocFilter.edl && e.kind != _DocKind.edl) return false;
      if (_locataireFilter != null && e.locataireId != _locataireFilter) {
        return false;
      }
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        if (!e.title.toLowerCase().contains(q) &&
            !e.subtitle.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    switch (_sort) {
      case _SortMode.recent:
        list.sort((a, b) => b.date.compareTo(a.date));
      case _SortMode.ancien:
        list.sort((a, b) => a.date.compareTo(b.date));
      case _SortMode.amount:
        list.sort(
            (a, b) => (b.amountValue ?? 0).compareTo(a.amountValue ?? 0));
    }
    return list;
  }

  List<_MonthGroup> _groupByMonth(List<_DocEntry> entries) {
    final df = DateFormat('MMMM yyyy', 'fr_FR');
    final groups = <String, _MonthGroup>{};
    for (final e in entries) {
      final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      final label = df.format(e.date).toUpperCase();
      groups.putIfAbsent(key, () => _MonthGroup(key: key, label: label));
      groups[key]!.entries.add(e);
    }
    final list = groups.values.toList();
    list.sort((a, b) => b.key.compareTo(a.key));
    if (_sort == _SortMode.ancien) list.sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  _MissingMonth? _detectMissingMonths({
    required List<Quittance> quittances,
    required List<Logement> logements,
    required List<Locataire> locataires,
  }) {
    final now = DateTime.now();
    final endYear = now.year;
    final endMonth = now.month - 1;
    final startCheckMonth = endMonth <= 0 ? null : endMonth;
    if (startCheckMonth == null) return null;

    for (var m = startCheckMonth; m >= 1; m--) {
      for (final l in logements) {
        final occupants =
            locataires.where((loc) => loc.logementIds.contains(l.id));
        for (final occ in occupants) {
          final exists = quittances.any((q) =>
              q.locataireId == occ.id &&
              q.logementId == l.id &&
              q.periodYear == endYear &&
              q.periodMonth == m);
          if (!exists) {
            return _MissingMonth(
              logementId: l.id,
              locataireId: occ.id,
              logementLabel: l.libelle,
              year: endYear,
              month: m,
            );
          }
        }
      }
    }
    return null;
  }

  void _open(BuildContext context, _DocEntry e) {
    switch (e.kind) {
      case _DocKind.quittance:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuittanceDetailScreen(quittanceId: e.id),
          ),
        );
      case _DocKind.edl:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EtatDesLieuxDetailScreen(edlId: e.id),
          ),
        );
    }
  }

  Future<void> _share(BuildContext context, _DocEntry e) async {
    if (e.kind != _DocKind.quittance) {
      _open(context, e);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final qSvc = context.read<QuittanceService>();
    final logSvc = context.read<LogementService>();
    final locSvc = context.read<LocataireService>();
    final userSvc = context.read<UserService>();
    final q = qSvc.byId(e.id);
    final l = q != null ? logSvc.byId(q.logementId) : null;
    final loc = q != null ? locSvc.byId(q.locataireId) : null;
    final bailleur = userSvc.current;
    if (q == null || l == null || loc == null || bailleur == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Données incomplètes pour le partage.')),
      );
      return;
    }
    // Avertissement juridique avant toute génération.
    if (!await DisclaimerDialog.show(context)) return;
    if (!context.mounted) return;
    final doc = await QuittancePdfBuilder.build(
      quittance: q,
      bailleur: bailleur,
      logement: l,
      locataire: loc,
      bailleurNameOverride: q.bailleurName,
      bailleurEmailOverride: q.bailleurEmail,
    );
    final filename =
        'quittance-${loc.fullName.replaceAll(' ', '-')}-${q.periodYear}-${q.periodMonth.toString().padLeft(2, '0')}.pdf';
    await Printing.sharePdf(bytes: await doc.save(), filename: filename);
  }

  void _more(BuildContext context, _DocEntry e) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Aperçu'),
              onTap: () {
                Navigator.of(context).pop();
                _open(context, e);
              },
            ),
            if (e.kind == _DocKind.quittance)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Imprimer'),
                onTap: () async {
                  Navigator.of(context).pop();
                  _open(context, e);
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager'),
              onTap: () {
                Navigator.of(context).pop();
                _share(context, e);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.error),
              title: const Text(
                'Supprimer',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _confirmDelete(context, e);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, _DocEntry e) {
    final isQuittance = e.kind == _DocKind.quittance;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isQuittance ? 'Supprimer cette quittance ?' : 'Supprimer cet EDL ?',
        ),
        content: Text(
          isQuittance
              ? 'La quittance « ${e.title} » sera supprimée définitivement.'
              : e.finalized
                  ? 'Attention : cet EDL est finalisé et co-signé. '
                      'Sa suppression est définitive et toutes ses photos seront effacées.'
                  : 'Cet état des lieux et toutes ses photos seront supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () async {
              if (isQuittance) {
                await context.read<QuittanceService>().delete(e.id);
              } else {
                final edl =
                    context.read<EtatDesLieuxService>().byId(e.id);
                if (edl != null) {
                  await context
                      .read<PlanLogementService>()
                      .deleteWallPhotosForEtat(
                        logementId: edl.logementId,
                        etatId: edl.id,
                      );
                }
                if (!ctx.mounted) return;
                await context.read<EtatDesLieuxService>().delete(e.id);
              }
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _MonthGroup {
  final String key;
  final String label;
  final List<_DocEntry> entries = [];
  _MonthGroup({required this.key, required this.label});
}

class _Hero extends StatelessWidget {
  final int count;
  final double total;
  final NumberFormat money;
  final VoidCallback? onBack;
  final VoidCallback onExport;
  const _Hero({
    required this.count,
    required this.total,
    required this.money,
    required this.onBack,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1B3A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 22),
      child: Row(
        children: [
          if (onBack != null)
            _CircleIconButton(
                icon: Icons.arrow_back_rounded, onTap: onBack!)
          else
            const SizedBox(width: 40, height: 40),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Mes documents',
                  style: TextStyle(
                    fontFamily: 'serif',
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count fichier${count > 1 ? 's' : ''} · ${money.format(total)}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _CircleIconButton(
            icon: Icons.file_download_outlined,
            onTap: onExport,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              color: context.textSecondaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: 'Rechercher un document…',
                hintStyle: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 14,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          Icon(Icons.filter_alt_outlined,
              color: context.textSecondaryColor, size: 20),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF0F1B3A) : context.surfaceColor;
    final fg = selected ? Colors.white : context.textPrimaryColor;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? Colors.transparent : context.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? Colors.white : AppColors.success, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  final _SortMode sort;
  final int count;
  final ValueChanged<_SortMode> onSortChanged;
  const _SortRow({
    required this.sort,
    required this.count,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.sort_rounded,
            size: 18, color: context.textSecondaryColor),
        const SizedBox(width: 6),
        Text(
          'Trier par : ',
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 13,
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final picked = await showModalBottomSheet<_SortMode>(
              context: context,
              backgroundColor: context.surfaceColor,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in _SortMode.values)
                      ListTile(
                        leading: Icon(
                          s == sort
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: s == sort ? AppColors.primary : null,
                        ),
                        title: Text(s.label),
                        onTap: () => Navigator.of(context).pop(s),
                      ),
                  ],
                ),
              ),
            );
            if (picked != null) onSortChanged(picked);
          },
          child: Row(
            children: [
              Text(
                sort.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.textPrimaryColor,
                  fontSize: 13,
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: context.textSecondaryColor),
            ],
          ),
        ),
        const Spacer(),
        Text(
          '$count résultat${count > 1 ? 's' : ''}',
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final String label;
  const _MonthHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 0, 0),
      child: Text(
        label,
        style: TextStyle(
          color: context.textSecondaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final _DocEntry entry;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onMore;
  const _DocCard({
    required this.entry,
    required this.onTap,
    required this.onShare,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final isQuittance = entry.kind == _DocKind.quittance;
    final df = DateFormat("'le' d MMM", 'fr_FR');
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        children: [
          HoverCard(
            onTap: onTap,
            accent: AppColors.primary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PdfThumb(label: isQuittance ? 'REÇU' : 'EDL'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              style: TextStyle(
                                fontFamily: 'serif',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimaryColor,
                                height: 1.2,
                              ),
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(entry: entry),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textPrimaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Émis ${df.format(entry.date)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.amountLabel != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      entry.amountLabel!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: context.dividerColor),
          Row(
            children: [
              Expanded(
                child: _CardAction(
                  icon: Icons.visibility_outlined,
                  label: 'Aperçu',
                  onTap: onTap,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: context.dividerColor,
              ),
              Expanded(
                child: _CardAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Partager',
                  onTap: onShare,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: context.dividerColor,
              ),
              Expanded(
                child: _CardAction(
                  icon: Icons.more_horiz_rounded,
                  label: 'Plus',
                  onTap: onMore,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PdfThumb extends StatelessWidget {
  final String label;
  const _PdfThumb({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFFCE5A8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'PDF',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8A6A1F),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A6A1F),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _DocEntry entry;
  const _StatusPill({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isQuittance = entry.kind == _DocKind.quittance;
    Color color;
    String label;
    IconData icon;
    if (isQuittance) {
      color = AppColors.success;
      label = 'PAYÉ';
      icon = Icons.check_rounded;
    } else if (entry.finalized) {
      color = AppColors.success;
      label = 'FINALISÉ';
      icon = Icons.check_rounded;
    } else {
      color = AppColors.accent;
      label = 'EN COURS';
      icon = Icons.schedule_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: context.textSecondaryColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: context.textPrimaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingBanner extends StatelessWidget {
  final _MissingMonth missing;
  final VoidCallback onGenerate;
  const _MissingBanner({required this.missing, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.schedule_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${missing.monthLabel} manquante',
                  style: const TextStyle(
                    color: Color(0xFF0F1B3A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Une quittance pour ${missing.logementLabel} n\'a pas été générée.',
                  style: const TextStyle(
                    color: Color(0xFF0F1B3A),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onGenerate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Générer',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 72,
            color: context.textSecondaryColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun document',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vos quittances et états des lieux apparaîtront ici.',
            style: TextStyle(color: context.textSecondaryColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
