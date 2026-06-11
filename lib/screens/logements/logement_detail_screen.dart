import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/country.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/plan_logement.dart';
import '../../models/quittance.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/plan_logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/revision_loyer_service.dart';
import '../locataires/colocataires_edit_screen.dart';
import '../locataires/locataire_detail_screen.dart';
import 'logement_form_screen.dart';
import 'plans/logement_plans_screen.dart';
import 'exterior_walls_screen.dart';
import '../contrats/contrat_bail_list_screen.dart';
import '../contrats/placeholders_recap_screen.dart';
import '../diagnostics/diagnostic_list_screen.dart';
import '../../services/contrat_bail_service.dart';
import '../../services/diagnostic_service.dart';
import 'revisions/revisions_loyer_screen.dart';
import '../finance/bilan_logement_screen.dart';
import '../finance/foreign_fiscalite_screen.dart';

class LogementDetailScreen extends StatelessWidget {
  final String logementId;
  const LogementDetailScreen({super.key, required this.logementId});

  static const _bg = Color(0xFFEFF1F7);
  static const _ink = Color(0xFF1F1F2E);
  static const _muted = Color(0xFF8A8AA0);
  static const _hairline = Color(0xFFE3E5EE);
  static const _surface = Colors.white;

  static const _purple = Color(0xFF7C3AED);
  static const _purpleLight = Color(0xFFA78BFA);
  static const _greenDark = Color(0xFF059669);
  static const _blue = Color(0xFF3B82F6);
  static const _red = Color(0xFFEF4444);

  static const _heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6D5CD6),
      Color(0xFF9C44C7),
      Color(0xFFE65A8A),
      Color(0xFFFF8E63),
    ],
    stops: [0, 0.45, 0.78, 1],
  );

  @override
  Widget build(BuildContext context) {
    final logement = context.watch<LogementService>().byId(logementId);
    if (logement == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Logement introuvable.')),
      );
    }
    final locataires =
        context.watch<LocataireService>().byLogement(logementId);
    final plans =
        context.watch<PlanLogementService>().byLogement(logementId);
    final quittances =
        context.watch<QuittanceService>().forLogement(logementId);
    final revisionsCount =
        context.watch<RevisionLoyerService>().forLogement(logementId).length;

    final money = NumberFormat.currency(
        locale: 'fr_FR', symbol: '€', decimalDigits: 0);
    final money2 = NumberFormat.currency(
        locale: 'fr_FR', symbol: '€', decimalDigits: 2);

    final actifs =
        locataires.where((l) => !l.isArchived && !l.isFutur).toList();
    final futurs = locataires.where((l) => l.isFutur).toList();
    final actuels = [...actifs, ...futurs];

    final now = DateTime.now();
    final upToDate = actifs.isNotEmpty &&
        actifs.every((l) => quittances.any((q) =>
            q.locataireId == l.id &&
            q.periodYear == now.year &&
            q.periodMonth == now.month));

    final depuisDates = actuels
        .map((l) => l.dateEntree)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final depuisLabel = depuisDates.isEmpty
        ? null
        : DateFormat('MM/yyyy', 'fr_FR').format(depuisDates.first);

    final capacity = math.max(1, logement.nbPieces - 1);
    final occupants = actuels.length;

    final caracCount = 5;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _GradientHeader(
            title: logement.libelle,
            subtitle: 'FICHE BIEN · ADDA',
            onEdit: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LogementFormScreen(logement: logement),
              ),
            ),
            onDelete: () => _confirmDelete(context, logement),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Transform.translate(
                offset: const Offset(0, -8),
                child: _HeroCard(
                  logement: logement,
                  isOccupied: actifs.isNotEmpty,
                  upToDate: upToDate,
                  depuisLabel: depuisLabel,
                  occupants: occupants,
                  capacity: capacity,
                  money: money,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SectionHeaderRow(
                color: _blue,
                title: 'CARACTÉRISTIQUES',
                count: caracCount,
                trailing: 'Données contractuelles',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _CaracteristiquesGrid(
                logement: logement,
                money: money2,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _RevisionBanner(
                count: revisionsCount,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        RevisionsLoyerScreen(logementId: logementId),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _RevenuesCard(
                logement: logement,
                quittances: quittances,
                money: money,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _BilanAccessTile(logementId: logementId),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _SectionHeaderRow(
                color: const Color(0xFF06B6D4),
                title: 'PLANS & SURFACES',
                count: plans.length,
                trailing: 'Architectures du logement',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PlansSection(
                plans: plans,
                onManage: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        LogementPlansScreen(logementId: logementId),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ExteriorWallsScreen(logement: logement),
                  ),
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.house_outlined,
                            color: Color(0xFF06B6D4)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Photos murs / façades extérieurs',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text(
                              'Façade, pignon, toiture, cour, jardin — '
                              'horodatées',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Builder(builder: (context) {
              final bails = context
                  .watch<ContratBailService>()
                  .forLogement(logementId);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SectionHeaderRow(
                  color: const Color(0xFF7C3AED),
                  title: 'CONTRATS DE BAIL',
                  count: bails.length,
                  trailing: 'Vide / meublé / colo / saisonnier / mobilité',
                ),
              );
            }),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _BailsSection(
                logement: logement,
                onManage: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ContratBailListScreen(logement: logement),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Builder(builder: (context) {
              final ds = context
                  .watch<DiagnosticService>()
                  .forLogement(logementId);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _SectionHeaderRow(
                  color: const Color(0xFF0EA5E9),
                  title: 'DIAGNOSTICS',
                  count: ds.length,
                  trailing: 'DPE, ERP, plomb, électrique, gaz…',
                ),
              );
            }),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _DiagnosticsSection(
                logement: logement,
                onManage: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        DiagnosticListScreen(logement: logement),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _LocatairesSectionHeader(
                count: actifs.length,
                upToDate: upToDate,
              ),
            ),
          ),
          SliverList.builder(
            itemCount: actuels.length,
            itemBuilder: (ctx, i) {
              final loc = actuels[i];
              final loyer = logement.loyerTTC;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _LocataireDetailCard(
                  locataire: loc,
                  loyerTTC: loyer,
                  isUpToDate: actifs.contains(loc) &&
                      quittances.any((q) =>
                          q.locataireId == loc.id &&
                          q.periodYear == now.year &&
                          q.periodMonth == now.month),
                  gradientIndex: i,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          LocataireDetailScreen(locataireId: loc.id),
                    ),
                  ),
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _GradientButton(
                      colors: const [
                        Color(0xFFFF8E63),
                        Color(0xFFE65A8A),
                        Color(0xFF9C44C7),
                      ],
                      icon: Icons.person_add_alt_1,
                      label: 'Modifier les locataires',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CoLocatairesEditScreen(
                            logementId: logementId,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GradientButton(
                      colors: const [
                        Color(0xFF34D399),
                        Color(0xFF059669),
                      ],
                      icon: Icons.add,
                      label: 'Ajouter un co-locataire',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CoLocatairesEditScreen(
                            logementId: logementId,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (AppConstants.multiPaysActif &&
              logement.country != Country.france)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    _GradientButton(
                      colors: const [Color(0xFF6366F1), Color(0xFF3B82F6)],
                      icon: Icons.public,
                      label:
                          'Fiscalité ${logement.country.label} (estimation)',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ForeignFiscaliteScreen(
                            logement: logement,
                            year: DateTime.now().year,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _GradientButton(
                      colors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                      icon: Icons.gavel_outlined,
                      label: 'Modèles de documents — points à valider',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaceholdersRecapScreen(
                            country: logement.country,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 24 + MediaQuery.of(context).viewPadding.bottom,
            ),
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
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  HEADER
// ────────────────────────────────────────────────────────────────────────────

class _GradientHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _GradientHeader({
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(gradient: LogementDetailScreen._heroGradient),
        padding: EdgeInsets.fromLTRB(12, top + 8, 12, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GlassIcon(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _GlassIcon(icon: Icons.edit_outlined, onTap: onEdit),
            const SizedBox(width: 8),
            _GlassIcon(icon: Icons.delete_outline, onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  HERO CARD
// ────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final Logement logement;
  final bool isOccupied;
  final bool upToDate;
  final String? depuisLabel;
  final int occupants;
  final int capacity;
  final NumberFormat money;

  const _HeroCard({
    required this.logement,
    required this.isOccupied,
    required this.upToDate,
    required this.depuisLabel,
    required this.occupants,
    required this.capacity,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LogementDetailScreen._heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9C44C7).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _HouseIllustration(type: logement.type)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(
                icon: _typeIcon(logement.type),
                label: logement.type.label.toUpperCase(),
              ),
              _HeroPill(
                dot: true,
                dotColor: isOccupied
                    ? const Color(0xFF34D399)
                    : Colors.white.withValues(alpha: 0.6),
                label: isOccupied
                    ? (upToDate
                        ? 'OCCUPÉE · BAIL À JOUR'
                        : 'OCCUPÉE · EN ATTENTE')
                    : 'VACANT',
              ),
              if (depuisLabel != null)
                _HeroPill(
                  icon: Icons.calendar_today_outlined,
                  label: 'DEPUIS $depuisLabel',
                ),
            ],
          ),
          const SizedBox(height: 14),
          _BigSerifTitle(text: logement.libelle),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${logement.adresse} · ${logement.codePostal} ${logement.ville.toUpperCase()}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'SURFACE',
                  value: logement.surface.toStringAsFixed(0),
                  suffix: 'm²',
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'PIÈCES',
                  value: logement.nbPieces.toString(),
                  suffix: 'P',
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'LOYER TTC',
                  value: logement.loyerTTC.toStringAsFixed(0),
                  suffix: '€',
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: 'LOCATAIRE',
                  value: occupants.toString().padLeft(2, '0'),
                  suffix: '/ ${capacity}P',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _typeIcon(LogementType t) {
    switch (t) {
      case LogementType.maison:
        return Icons.home_outlined;
      case LogementType.appartement:
        return Icons.apartment_rounded;
      case LogementType.studio:
        return Icons.weekend_outlined;
      case LogementType.garage:
        return Icons.garage_outlined;
      case LogementType.parking:
        return Icons.local_parking_rounded;
      case LogementType.box:
        return Icons.inventory_2_outlined;
      case LogementType.localCommercial:
        return Icons.storefront_outlined;
      case LogementType.autre:
        return Icons.location_city_outlined;
    }
  }
}

class _HouseIllustration extends StatelessWidget {
  final LogementType type;
  const _HouseIllustration({required this.type});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 4,
            right: 22,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD86B),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 30,
            child: _Cloud(),
          ),
          Center(
            child: Icon(
              type == LogementType.maison
                  ? Icons.cottage
                  : type == LogementType.appartement
                      ? Icons.apartment_rounded
                      : type == LogementType.studio
                          ? Icons.weekend
                          : Icons.location_city,
              size: 78,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cloud extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData? icon;
  final bool dot;
  final Color? dotColor;
  final String label;
  const _HeroPill({
    this.icon,
    this.dot = false,
    this.dotColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor ?? const Color(0xFF34D399),
                shape: BoxShape.circle,
              ),
            )
          else if (icon != null)
            Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigSerifTitle extends StatelessWidget {
  final String text;
  const _BigSerifTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    final words = text.trim().split(RegExp(r'\s+'));
    final lastTwo = words.length >= 2 ? words.sublist(words.length - 2) : <String>[];
    final head = words.length >= 2
        ? words.sublist(0, words.length - 2).join(' ')
        : text;
    final italic = lastTwo.join(' ');
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'serif',
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
        children: [
          if (head.isNotEmpty) TextSpan(text: head),
          if (head.isNotEmpty && italic.isNotEmpty) const TextSpan(text: ' '),
          if (italic.isNotEmpty)
            TextSpan(
              text: italic,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            text: value,
            style: const TextStyle(
              fontFamily: 'serif',
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
            children: [
              TextSpan(
                text: suffix,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  SECTION HEADER
// ────────────────────────────────────────────────────────────────────────────

class _SectionHeaderRow extends StatelessWidget {
  final Color color;
  final String title;
  final int count;
  final String? trailing;
  const _SectionHeaderRow({
    required this.color,
    required this.title,
    required this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: LogementDetailScreen._ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: LogementDetailScreen._hairline),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: LogementDetailScreen._muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: LogementDetailScreen._muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  CARACTÉRISTIQUES GRID
// ────────────────────────────────────────────────────────────────────────────

class _CaracteristiquesGrid extends StatelessWidget {
  final Logement logement;
  final NumberFormat money;
  const _CaracteristiquesGrid({required this.logement, required this.money});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CharCard(
                icon: Icons.dashboard_outlined,
                iconBg: const Color(0xFFE0EAFF),
                iconFg: LogementDetailScreen._blue,
                value: logement.surface.toStringAsFixed(0),
                suffix: 'm²',
                label: 'SURFACE',
                bigColor: LogementDetailScreen._blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CharCard(
                icon: Icons.grid_view_rounded,
                iconBg: const Color(0xFFEDE6FF),
                iconFg: LogementDetailScreen._purple,
                value: logement.nbPieces.toString(),
                suffix: 'pièces',
                label: 'COMPOSITION',
                bigColor: LogementDetailScreen._purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _CharCard(
                icon: Icons.attach_money,
                iconBg: const Color(0xFFD7F1E2),
                iconFg: LogementDetailScreen._greenDark,
                value: logement.loyerHC.toStringAsFixed(0),
                suffix: '€',
                label: 'LOYER HC',
                bigColor: LogementDetailScreen._greenDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CharCard(
                icon: Icons.access_time_rounded,
                iconBg: const Color(0xFFFCE3C7),
                iconFg: const Color(0xFFC66E1A),
                value: logement.charges.toStringAsFixed(0),
                suffix: '€',
                label: 'CHARGES',
                bigColor: const Color(0xFFC66E1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _CharCard(
          icon: Icons.check_rounded,
          iconBg: LogementDetailScreen._purple,
          iconFg: Colors.white,
          value: logement.loyerTTC.toStringAsFixed(0),
          suffix: '€',
          label: 'LOYER TTC / MOIS',
          bigColor: LogementDetailScreen._purple,
          highlight: true,
        ),
      ],
    );
  }
}

class _CharCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String value;
  final String suffix;
  final String label;
  final Color bigColor;
  final bool highlight;
  const _CharCard({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.value,
    required this.suffix,
    required this.label,
    required this.bigColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFFEDE6FF)
            : LogementDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LogementDetailScreen._hairline),
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
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconFg, size: 20),
              ),
              const Spacer(),
              if (highlight)
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: bigColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              text: value,
              style: TextStyle(
                fontFamily: 'serif',
                color: bigColor,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
              children: [
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    color: bigColor.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: LogementDetailScreen._muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  RÉVISION BANNER
// ────────────────────────────────────────────────────────────────────────────

class _RevisionBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _RevisionBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = DateTime(now.year + 1, now.month);
    final nextLabel = DateFormat('MM/yyyy', 'fr_FR').format(next);
    final hasRevisions = count > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: LogementDetailScreen._surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LogementDetailScreen._hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFDE5C0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.access_time_rounded,
                  color: Color(0xFFC66E1A), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRevisions
                        ? '$count révision${count > 1 ? 's' : ''} de loyer'
                        : 'Aucune révision de loyer programmée',
                    style: const TextStyle(
                      color: LogementDetailScreen._ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Indice de Référence des Loyers (IRL) · prochaine révision possible en $nextLabel',
                    style: const TextStyle(
                      color: LogementDetailScreen._muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: const [
                Text(
                  'Configurer',
                  style: TextStyle(
                    color: LogementDetailScreen._purple,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 2),
                Icon(Icons.chevron_right,
                    size: 18, color: LogementDetailScreen._purple),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  REVENUS + OCCUPATION
// ────────────────────────────────────────────────────────────────────────────

class _RevenuesCard extends StatelessWidget {
  final Logement logement;
  final List<Quittance> quittances;
  final NumberFormat money;
  const _RevenuesCard({
    required this.logement,
    required this.quittances,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstThisMonth = DateTime(now.year, now.month);
    final last12Start = DateTime(now.year, now.month - 11);
    final last24Start = DateTime(now.year, now.month - 23);

    double sumBetween(DateTime startInc, DateTime endExclusive) {
      return quittances.where((q) {
        final d = DateTime(q.periodYear, q.periodMonth);
        return !d.isBefore(startInc) && d.isBefore(endExclusive);
      }).fold<double>(0, (s, q) => s + q.loyerHC + q.charges);
    }

    final endNext = DateTime(now.year, now.month + 1);
    final revenu12 = sumBetween(last12Start, endNext);
    final revenuPrev12 = sumBetween(last24Start, last12Start);
    final delta = revenu12 - revenuPrev12;
    final monthsCovered12 = quittances.where((q) {
      final d = DateTime(q.periodYear, q.periodMonth);
      return !d.isBefore(last12Start) && d.isBefore(endNext);
    }).map((q) => '${q.periodYear}-${q.periodMonth}').toSet().length;

    final series = List<double>.generate(12, (i) {
      final m = DateTime(now.year, now.month - 11 + i);
      return quittances
          .where((q) => q.periodYear == m.year && q.periodMonth == m.month)
          .fold<double>(0, (s, q) => s + q.loyerHC + q.charges);
    });

    final acquisition = logement.createdAt.toLocal();
    final monthsElapsed = math.max(
      1,
      (firstThisMonth.year - acquisition.year) * 12 +
          (firstThisMonth.month - acquisition.month) +
          1,
    );
    final monthsOccupied = quittances
        .map((q) => '${q.periodYear}-${q.periodMonth}')
        .toSet()
        .length;
    final occupationPct =
        ((monthsOccupied / monthsElapsed) * 100).clamp(0, 100).round();
    final vacant = math.max(0, monthsElapsed - monthsOccupied);

    final perfLabel = occupationPct >= 90
        ? 'très bonne performance'
        : occupationPct >= 75
            ? 'bonne performance'
            : occupationPct >= 50
                ? 'performance correcte'
                : 'performance à améliorer';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: LogementDetailScreen._surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LogementDetailScreen._hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.attach_money,
                  color: LogementDetailScreen._greenDark, size: 18),
              SizedBox(width: 6),
              Text(
                'REVENUS ENCAISSÉS · 12 DERNIERS MOIS',
                style: TextStyle(
                  color: LogementDetailScreen._muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              text: NumberFormat.decimalPattern('fr_FR').format(revenu12.round()),
              style: const TextStyle(
                fontFamily: 'serif',
                color: LogementDetailScreen._greenDark,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
              children: const [
                TextSpan(
                  text: '€',
                  style: TextStyle(
                    color: LogementDetailScreen._greenDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: LogementDetailScreen._muted,
                fontSize: 12,
              ),
              children: [
                const TextSpan(text: 'Soit '),
                TextSpan(
                  text:
                      '${delta >= 0 ? '+' : ''}${money.format(delta)} vs N-1',
                  style: TextStyle(
                    color: delta >= 0
                        ? LogementDetailScreen._greenDark
                        : LogementDetailScreen._red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text:
                      ' · $monthsCovered12 mois plein${monthsCovered12 > 1 ? 's' : ''} encaissé${monthsCovered12 > 1 ? 's' : ''}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: revenu12 == 0
                ? _EmptyChart()
                : CustomPaint(
                    painter: _AreaSparklinePainter(
                      values: series,
                      color: LogementDetailScreen._greenDark,
                    ),
                    size: Size.infinite,
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: LogementDetailScreen._hairline,
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              Icon(Icons.layers_outlined,
                  color: LogementDetailScreen._purple, size: 18),
              SizedBox(width: 6),
              Text(
                "TAUX D'OCCUPATION · DEPUIS ACQUISITION",
                style: TextStyle(
                  color: LogementDetailScreen._muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              text: occupationPct.toString(),
              style: const TextStyle(
                fontFamily: 'serif',
                color: LogementDetailScreen._purple,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
              children: const [
                TextSpan(
                  text: '%',
                  style: TextStyle(
                    color: LogementDetailScreen._purple,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: LogementDetailScreen._muted,
                fontSize: 12,
              ),
              children: [
                const TextSpan(text: 'Vacant '),
                TextSpan(
                  text: '$vacant mois',
                  style: const TextStyle(
                    color: LogementDetailScreen._purple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: ' sur les $monthsElapsed derniers · $perfLabel'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Container(
                  height: 8,
                  color: const Color(0xFFEDE6FF),
                ),
                FractionallySizedBox(
                  widthFactor: occupationPct / 100,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          LogementDetailScreen._purpleLight,
                          LogementDetailScreen._purple,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Acquisition · ${DateFormat('MM/yyyy', 'fr_FR').format(acquisition)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: LogementDetailScreen._muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                "Aujourd'hui",
                style: TextStyle(
                  fontSize: 11,
                  color: LogementDetailScreen._muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Aucune quittance encaissée sur la période',
        style: TextStyle(
          color: LogementDetailScreen._muted.withValues(alpha: 0.7),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _AreaSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _AreaSparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(0, math.max);
    final minV = values.fold<double>(double.infinity, math.min);
    final range = (maxV - minV).abs();
    final scale = range == 0 ? 0.0 : 1.0 / range;
    final n = values.length;
    final dx = size.width / (n - 1).clamp(1, 999);
    final pad = 6.0;
    final h = size.height - pad * 2;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          i * dx,
          range == 0
              ? size.height / 2
              : size.height - pad - (values[i] - minV) * scale * h,
        ),
    ];

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final cp1 = Offset((p0.dx + p1.dx) / 2, p0.dy);
      final cp2 = Offset((p0.dx + p1.dx) / 2, p1.dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.32),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(pts.last, 4, dotPaint);
    canvas.drawCircle(
      pts.last,
      6,
      Paint()..color = color.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _AreaSparklinePainter old) =>
      old.values != values || old.color != color;
}

// ────────────────────────────────────────────────────────────────────────────
//  PLANS
// ────────────────────────────────────────────────────────────────────────────

class _PlansSection extends StatelessWidget {
  final List<PlanLogement> plans;
  final VoidCallback onManage;
  const _PlansSection({required this.plans, required this.onManage});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              ...plans.map((p) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _PlanThumbnail(plan: p, onTap: onManage),
                  )),
              _AddPlanCard(onTap: onManage),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onManage,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: LogementDetailScreen._surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LogementDetailScreen._hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7F1E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder_outlined,
                      color: Color(0xFF059669), size: 18),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Gérer les plans & documents',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: LogementDetailScreen._ink,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: LogementDetailScreen._muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanThumbnail extends StatelessWidget {
  final PlanLogement plan;
  final VoidCallback onTap;
  const _PlanThumbnail({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 170,
        child: Container(
          decoration: BoxDecoration(
            color: LogementDetailScreen._surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: LogementDetailScreen._hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF34D399), Color(0xFF6BCEFF)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Container(
                  height: 95,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7F1E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _MiniPlanPainter(plan: plan),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'serif',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: LogementDetailScreen._ink,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: LogementDetailScreen._muted, size: 18),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _kindLabel(plan),
                      style: const TextStyle(
                        fontSize: 11,
                        color: LogementDetailScreen._muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _kindLabel(PlanLogement p) {
    final rooms = p.rooms.length;
    switch (p.kind) {
      case PlanKind.niveau:
        return rooms > 0 ? '$rooms pièce${rooms > 1 ? 's' : ''}' : 'Niveau';
      case PlanKind.dependance:
        return 'Dépendance';
      case PlanKind.terrain:
        return 'Terrain';
    }
  }
}

/// Rendu miniature d'un plan dans la card de la section « Plans & surfaces ».
/// Affiche les pièces effectivement dessinées (rectangles ou polygones) avec
/// leur couleur, ajustées et centrées dans la zone disponible. Si le plan est
/// vide ou n'est qu'une image importée, retombe sur un pictogramme stylisé.
class _MiniPlanPainter extends CustomPainter {
  final PlanLogement plan;

  _MiniPlanPainter({required this.plan});

  /// Palette des couleurs de pièce — doit rester en cohérence avec
  /// `_DrawerViewState._colors` de l'éditeur de plans.
  static const List<Color> _roomColors = [
    Color(0xFFBFDBFE),
    Color(0xFFFECACA),
    Color(0xFFFEF3C7),
    Color(0xFFD9F99D),
    Color(0xFFC7D2FE),
    Color(0xFFFBCFE8),
    Color(0xFFA7F3D0),
    Color(0xFFE2E8F0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rooms = plan.rooms;
    if (rooms.isEmpty) {
      _paintPlaceholder(canvas, size);
      return;
    }

    // Bbox de toutes les pièces (coords normalisées 0..1).
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final r in rooms) {
      final corners = _corners(r);
      for (final c in corners) {
        if (c.dx < minX) minX = c.dx;
        if (c.dy < minY) minY = c.dy;
        if (c.dx > maxX) maxX = c.dx;
        if (c.dy > maxY) maxY = c.dy;
      }
    }
    final bbW = (maxX - minX).clamp(0.001, 1.0);
    final bbH = (maxY - minY).clamp(0.001, 1.0);

    // Ajuste l'échelle pour rentrer dans la zone avec un peu de padding,
    // centré et en conservant le ratio.
    const padding = 6.0;
    final availW = size.width - padding * 2;
    final availH = size.height - padding * 2;
    final scale = math.min(availW / bbW, availH / bbH);
    final renderW = bbW * scale;
    final renderH = bbH * scale;
    final offsetX = (size.width - renderW) / 2;
    final offsetY = (size.height - renderH) / 2;

    Offset toPx(double nx, double ny) => Offset(
          offsetX + (nx - minX) * scale,
          offsetY + (ny - minY) * scale,
        );

    final borderPaint = Paint()
      ..color = const Color(0xFF334155).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final r in rooms) {
      final fillPaint = Paint()
        ..color = _roomColors[r.colorIndex % _roomColors.length]
            .withValues(alpha: 0.92)
        ..style = PaintingStyle.fill;

      if (r.isPolygon && r.vertices != null) {
        final v = r.vertices!;
        final path = Path();
        for (var i = 0; i < v.length; i += 2) {
          final p = toPx(v[i], v[i + 1]);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        path.close();
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, borderPaint);
      } else {
        final tl = toPx(r.x, r.y);
        final br = toPx(r.x + r.width, r.y + r.height);
        final rect = Rect.fromPoints(tl, br);
        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  /// Pictogramme de secours quand le plan n'a aucune pièce dessinée.
  void _paintPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF059669).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final rect = Rect.fromLTWH(pad, pad, w, h);
    canvas.drawRect(rect, paint);
    canvas.drawLine(
      Offset(pad + w * 0.55, pad),
      Offset(pad + w * 0.55, pad + h * 0.55),
      paint,
    );
    canvas.drawLine(
      Offset(pad, pad + h * 0.55),
      Offset(pad + w * 0.55, pad + h * 0.55),
      paint,
    );
    if (plan.hasImage) {
      final iconPaint = Paint()
        ..color = const Color(0xFF059669).withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2 + 4),
        4,
        iconPaint,
      );
    }
  }

  List<Offset> _corners(RoomShape r) {
    if (r.isPolygon && r.vertices != null) {
      final v = r.vertices!;
      return [
        for (var i = 0; i < v.length; i += 2) Offset(v[i], v[i + 1]),
      ];
    }
    return [
      Offset(r.x, r.y),
      Offset(r.x + r.width, r.y),
      Offset(r.x + r.width, r.y + r.height),
      Offset(r.x, r.y + r.height),
    ];
  }

  @override
  bool shouldRepaint(covariant _MiniPlanPainter old) =>
      !identical(old.plan, plan) ||
      old.plan.rooms.length != plan.rooms.length;
}

class _AddPlanCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPlanCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 170,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: LogementDetailScreen._hairline,
            radius: 18,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 95,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.add,
                        color: LogementDetailScreen._muted, size: 32),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Ajouter',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'étage, sous-sol, jardin…',
                  style: TextStyle(
                    fontSize: 11,
                    color: LogementDetailScreen._muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        dashed.addPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          Offset.zero,
        );
        d += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ────────────────────────────────────────────────────────────────────────────
//  LOCATAIRES
// ────────────────────────────────────────────────────────────────────────────

class _LocatairesSectionHeader extends StatelessWidget {
  final int count;
  final bool upToDate;
  const _LocatairesSectionHeader({
    required this.count,
    required this.upToDate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 16,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE65A8A), Color(0xFFFF8E63)],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'LOCATAIRES',
          style: TextStyle(
            color: LogementDetailScreen._ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: LogementDetailScreen._hairline),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: LogementDetailScreen._muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        const Spacer(),
        Text(
          count == 0
              ? 'Aucun occupant'
              : '${upToDate ? 'Bail signé' : 'Bail à vérifier'} · $count occupant${count > 1 ? 's' : ''}',
          style: const TextStyle(
            color: LogementDetailScreen._muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LocataireDetailCard extends StatelessWidget {
  final Locataire locataire;
  final double loyerTTC;
  final bool isUpToDate;
  final int gradientIndex;
  final VoidCallback onTap;

  const _LocataireDetailCard({
    required this.locataire,
    required this.loyerTTC,
    required this.isUpToDate,
    required this.gradientIndex,
    required this.onTap,
  });

  static const _gradients = <List<Color>>[
    [Color(0xFFE07AB5), Color(0xFFE89460)],
    [Color(0xFF6FB1FF), Color(0xFFB46BFF)],
    [Color(0xFF5BB9C4), Color(0xFF7C5BC4)],
    [Color(0xFF6BD2A1), Color(0xFF3F8F6B)],
    [Color(0xFFFFB070), Color(0xFFE0608B)],
    [Color(0xFFA98EFF), Color(0xFF6B46FF)],
  ];

  @override
  Widget build(BuildContext context) {
    final gradient = _gradients[gradientIndex % _gradients.length];
    final money = NumberFormat.currency(
        locale: 'fr_FR', symbol: '€', decimalDigits: 0);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: LogementDetailScreen._surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LogementDetailScreen._hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradient,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _SquareAvatar(
                gradient: gradient,
                letter: locataire.firstName.isNotEmpty
                    ? locataire.firstName[0]
                    : '?',
                isFutur: locataire.isFutur,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _NameWithSurname(
                            firstName: locataire.firstName,
                            lastName: locataire.lastName,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (locataire.isFutur)
                          _MiniPill(
                            text: 'NOUVEAU',
                            color: const Color(0xFFC66E1A),
                            bg: const Color(0xFFFCE3C7),
                          )
                        else
                          _MiniPill(
                            text: isUpToDate
                                ? 'BAIL À JOUR'
                                : 'BAIL À VÉRIFIER',
                            color: isUpToDate
                                ? const Color(0xFF1B7B4D)
                                : const Color(0xFFC66E1A),
                            bg: isUpToDate
                                ? const Color(0xFFD7F1E2)
                                : const Color(0xFFFCE3C7),
                            dot: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.mail_outline,
                            size: 13, color: LogementDetailScreen._muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locataire.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: LogementDetailScreen._muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 12, color: LogementDetailScreen._muted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _depuisLabel(locataire),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: LogementDetailScreen._muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money.format(loyerTTC),
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: LogementDetailScreen._ink,
                    ),
                  ),
                  const Text(
                    '/ mois TTC',
                    style: TextStyle(
                      fontSize: 11,
                      color: LogementDetailScreen._muted,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right,
                  color: LogementDetailScreen._muted),
            ),
          ],
        ),
      ),
    );
  }

  String _depuisLabel(Locataire l) {
    if (l.isFutur && l.dateEntree != null) {
      final delta = l.dateEntree!.difference(DateTime.now()).inDays;
      return 'Entrée prévue le ${DateFormat('dd/MM/yyyy', 'fr_FR').format(l.dateEntree!)} · dans $delta jours';
    }
    if (l.dateEntree == null) return 'Date d\'entrée non renseignée';
    final months = (DateTime.now().year - l.dateEntree!.year) * 12 +
        DateTime.now().month -
        l.dateEntree!.month;
    final years = months ~/ 12;
    final restMonths = months % 12;
    final parts = <String>[];
    if (years > 0) parts.add('$years an${years > 1 ? 's' : ''}');
    if (restMonths > 0) parts.add('$restMonths mois');
    final dur = parts.isEmpty ? 'ce mois-ci' : parts.join(' ');
    return 'Depuis le ${DateFormat('dd/MM/yyyy', 'fr_FR').format(l.dateEntree!)} · $dur';
  }
}

class _NameWithSurname extends StatelessWidget {
  final String firstName;
  final String lastName;
  const _NameWithSurname({required this.firstName, required this.lastName});

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          color: LogementDetailScreen._ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: firstName),
          const TextSpan(text: ' '),
          TextSpan(
            text: lastName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SquareAvatar extends StatelessWidget {
  final List<Color> gradient;
  final String letter;
  final bool isFutur;
  const _SquareAvatar({
    required this.gradient,
    required this.letter,
    required this.isFutur,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            letter.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'serif',
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isFutur
                  ? const Color(0xFFC66E1A)
                  : const Color(0xFF34D399),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  final bool dot;
  const _MiniPill({
    required this.text,
    required this.color,
    required this.bg,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  GRADIENT BUTTON
// ────────────────────────────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final List<Color> colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GradientButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section "Contrats de bail" dans la fiche logement. Affiche un résumé
/// (compteur + bouton Gérer) qui ouvre `ContratBailListScreen`.
class _BailsSection extends StatelessWidget {
  final Logement logement;
  final VoidCallback onManage;
  const _BailsSection({required this.logement, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final bails = context.watch<ContratBailService>().forLogement(logement.id);
    final active = context
        .watch<ContratBailService>()
        .activeForLogement(logement.id);
    return InkWell(
      onTap: onManage,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_outlined,
                  color: Color(0xFF7C3AED)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bails.isEmpty
                        ? 'Aucun bail créé'
                        : '${bails.length} bail${bails.length > 1 ? "s" : ""}'
                            ' au total',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active != null
                        ? '${active.type.label} en cours · ${active.reference}'
                        : 'Crée un nouveau contrat (vide / meublé / colo / saisonnier / mobilité)',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  final Logement logement;
  final VoidCallback onManage;
  const _DiagnosticsSection({required this.logement, required this.onManage});

  @override
  Widget build(BuildContext context) {
    final ds = context.watch<DiagnosticService>().forLogement(logement.id);
    final expired = ds.where((d) => d.estExpire).length;
    return InkWell(
      onTap: onManage,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.fact_check_outlined,
                  color: Color(0xFF0EA5E9)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ds.isEmpty
                        ? 'Aucun diagnostic'
                        : '${ds.length} diagnostic${ds.length > 1 ? "s" : ""}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expired > 0
                        ? '⚠ $expired diagnostic${expired > 1 ? "s" : ""} expiré${expired > 1 ? "s" : ""}'
                        : 'DPE, ERP, plomb, électrique, gaz, assainissement…',
                    style: TextStyle(
                      fontSize: 12,
                      color: expired > 0
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF64748B),
                      fontWeight:
                          expired > 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _BilanAccessTile extends StatelessWidget {
  final String logementId;
  const _BilanAccessTile({required this.logementId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BilanLogementScreen(logementId: logementId),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.insights_outlined,
                  color: Color(0xFF059669)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bilan depuis acquisition',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Loyers, dépenses, crédits cumulés + rentabilité brute',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}
