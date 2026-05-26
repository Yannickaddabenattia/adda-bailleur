import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_card.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../locataires/locataire_form_screen.dart';
import 'logement_detail_screen.dart';
import 'logement_form_screen.dart';

enum _LogementFilter { tous, occupes, vacants }

class LogementListScreen extends StatefulWidget {
  const LogementListScreen({super.key});

  @override
  State<LogementListScreen> createState() => _LogementListScreenState();
}

class _LogementListScreenState extends State<LogementListScreen> {
  _LogementFilter _filter = _LogementFilter.tous;

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>();
    final quittances = context.watch<QuittanceService>();
    final money =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 0);

    final occupiedIds = <String>{
      for (final l in locataires.all) ...l.logementIds,
    };
    final occupedCount =
        logements.where((l) => occupiedIds.contains(l.id)).length;
    final vacantCount = logements.length - occupedCount;
    final totalSurface = logements.fold<double>(0, (s, l) => s + l.surface);

    final now = DateTime.now();
    final percusMois = quittances.all
        .where((q) => q.periodYear == now.year && q.periodMonth == now.month)
        .fold<double>(0, (s, q) => s + q.total);
    final aLouer = logements
        .where((l) => !occupiedIds.contains(l.id))
        .fold<double>(0, (s, l) => s + l.loyerTTC);

    final filtered = logements.where((l) {
      switch (_filter) {
        case _LogementFilter.tous:
          return true;
        case _LogementFilter.occupes:
          return occupiedIds.contains(l.id);
        case _LogementFilter.vacants:
          return !occupiedIds.contains(l.id);
      }
    }).toList();

    final subtitle = vacantCount > 0
        ? '${logements.length} bien${logements.length > 1 ? 's' : ''} · $vacantCount vacant${vacantCount > 1 ? 's' : ''}'
        : '${logements.length} bien${logements.length > 1 ? 's' : ''}';

    return Scaffold(
      body: logements.isEmpty
          ? Column(
              children: [
                _Hero(title: 'Mes logements', subtitle: 'Aucun bien'),
                Expanded(child: _EmptyState(onAdd: _openForm)),
              ],
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _Hero(title: 'Mes logements', subtitle: subtitle),
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _StatsStrip(
                      surface: totalSurface.toStringAsFixed(0),
                      percus: money.format(percusMois),
                      aLouer: money.format(aLouer),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: _FilterPills(
                    filter: _filter,
                    counts: [
                      logements.length,
                      occupedCount,
                      vacantCount,
                    ],
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                ),
                const SizedBox(height: 16),
                ...filtered.map(
                  (l) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: _LogementCard(
                      logement: l,
                      locataires: locataires.byLogement(l.id),
                      isOccupied: occupiedIds.contains(l.id),
                      now: now,
                      money: money,
                      hasQuittanceThisMonth: (locataireId) =>
                          quittances.exists(
                        locataireId: locataireId,
                        year: now.year,
                        month: now.month,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _openForm() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LogementFormScreen()),
    );
  }
}

class _Hero extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Hero({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1B3A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 10,
        16,
        56,
      ),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.chevron_left,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'serif',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          _CircleButton(
            icon: Icons.tune_rounded,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final String surface;
  final String percus;
  final String aLouer;
  const _StatsStrip({
    required this.surface,
    required this.percus,
    required this.aLouer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: context.isDark ? 0.4 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'SURFACE',
              value: surface,
              suffix: 'm²',
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _Stat(
              label: 'PERÇUS',
              value: percus,
              valueColor: AppColors.success,
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _Stat(
              label: 'À LOUER',
              value: aLouer,
              valueColor: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      width: 1,
      color: context.dividerColor,
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final Color? valueColor;
  const _Stat({
    required this.label,
    required this.value,
    this.suffix,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor ?? context.textPrimaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'serif',
            ),
            children: [
              if (suffix != null)
                TextSpan(
                  text: ' $suffix',
                  style: TextStyle(
                    color: context.textSecondaryColor,
                    fontSize: 12,
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

class _FilterPills extends StatelessWidget {
  final _LogementFilter filter;
  final List<int> counts;
  final ValueChanged<_LogementFilter> onChanged;
  const _FilterPills({
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Pill(
            label: 'Tous · ${counts[0]}',
            selected: filter == _LogementFilter.tous,
            onTap: () => onChanged(_LogementFilter.tous),
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'Occupés · ${counts[1]}',
            selected: filter == _LogementFilter.occupes,
            dotColor: AppColors.success,
            onTap: () => onChanged(_LogementFilter.occupes),
          ),
          const SizedBox(width: 8),
          _Pill(
            label: 'Vacants · ${counts[2]}',
            selected: filter == _LogementFilter.vacants,
            dotColor: AppColors.accent,
            onTap: () => onChanged(_LogementFilter.vacants),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? dotColor;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? const Color(0xFF0F1B3A)
        : context.surfaceColor;
    final fg = selected ? Colors.white : context.textPrimaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: selected ? null : Border.all(color: context.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogementCard extends StatelessWidget {
  final Logement logement;
  final List<Locataire> locataires;
  final bool isOccupied;
  final DateTime now;
  final NumberFormat money;
  final bool Function(String locataireId) hasQuittanceThisMonth;

  const _LogementCard({
    required this.logement,
    required this.locataires,
    required this.isOccupied,
    required this.now,
    required this.money,
    required this.hasQuittanceThisMonth,
  });

  @override
  Widget build(BuildContext context) {
    final iconBg = isOccupied
        ? AppColors.primary.withValues(alpha: 0.10)
        : AppColors.accent.withValues(alpha: 0.15);
    final iconColor = isOccupied ? AppColors.primary : AppColors.accent;
    final cardBorder = isOccupied
        ? context.dividerColor
        : AppColors.accent.withValues(alpha: 0.4);
    final cardBg = isOccupied
        ? context.surfaceColor
        : (context.isDark
            ? const Color(0xFF2C2210)
            : const Color(0xFFFFFAEC));
    final accentColor = isOccupied ? AppColors.primary : AppColors.accent;

    return HoverCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LogementDetailScreen(logementId: logement.id),
        ),
      ),
      accent: accentColor,
      borderRadius: BorderRadius.circular(20),
      background: cardBg,
      borderColor: cardBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.home_outlined,
                      color: iconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                logement.libelle,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'serif',
                                  color: context.textPrimaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(occupied: isOccupied),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${logement.adresse} · ${logement.codePostal}',
                          style: TextStyle(
                            color: context.textSecondaryColor,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              color: context.textPrimaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              TextSpan(
                                text: '${logement.surface.toStringAsFixed(0)} m²',
                              ),
                              TextSpan(
                                text: '  ·  ',
                                style: TextStyle(
                                  color: context.textSecondaryColor,
                                ),
                              ),
                              TextSpan(text: '${logement.nbPieces} pièces'),
                              TextSpan(
                                text: '  ·  ',
                                style: TextStyle(
                                  color: context.textSecondaryColor,
                                ),
                              ),
                              TextSpan(
                                  text:
                                      '${money.format(logement.loyerTTC)}/mois'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cardBorder),
            if (isOccupied)
              ...locataires.map(
                (loc) => _OccupiedFooter(
                  locataire: loc,
                  upToDate: hasQuittanceThisMonth(loc.id),
                ),
              )
            else
              _VacantFooter(
                logement: logement,
                now: now,
              ),
          ],
        ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool occupied;
  const _StatusBadge({required this.occupied});

  @override
  Widget build(BuildContext context) {
    final color = occupied ? AppColors.success : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            occupied ? 'OCCUPÉ' : 'VACANT',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OccupiedFooter extends StatelessWidget {
  final Locataire locataire;
  final bool upToDate;

  const _OccupiedFooter({
    required this.locataire,
    required this.upToDate,
  });

  @override
  Widget build(BuildContext context) {
    final since = locataire.dateEntree;
    final sinceLabel = since != null
        ? 'depuis ${DateFormat('MMM yyyy', 'fr_FR').format(since)}'
        : '';
    final initials =
        '${locataire.firstName.isNotEmpty ? locataire.firstName[0] : ''}${locataire.lastName.isNotEmpty ? locataire.lastName[0] : ''}'
            .toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '${locataire.firstName} ${locataire.lastName}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: context.textPrimaryColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sinceLabel.isNotEmpty)
                  Text(
                    '  ·  $sinceLabel',
                    style: TextStyle(
                      color: context.textSecondaryColor,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          _StatusPill(
            icon: upToDate ? Icons.check_rounded : Icons.access_time_rounded,
            label: upToDate ? 'à jour' : 'à générer',
            color: upToDate ? AppColors.success : AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _VacantFooter extends StatelessWidget {
  final Logement logement;
  final DateTime now;

  const _VacantFooter({required this.logement, required this.now});

  @override
  Widget build(BuildContext context) {
    final days = now.difference(logement.createdAt.toLocal()).inDays;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded,
              color: AppColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              days <= 0
                  ? 'Disponible'
                  : 'Disponible depuis $days jour${days > 1 ? 's' : ''}',
              style: TextStyle(
                color: context.textPrimaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _AddTenantButton(logementId: logement.id),
        ],
      ),
    );
  }
}

class _AddTenantButton extends StatelessWidget {
  final String logementId;
  const _AddTenantButton({required this.logementId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              LocataireFormScreen(preselectedLogementId: logementId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Locataire',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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
            Icon(Icons.home_outlined,
                size: 72,
                color: context.textSecondaryColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Aucun logement',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ajoutez votre premier bien pour commencer.',
              style: TextStyle(color: context.textSecondaryColor),
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
