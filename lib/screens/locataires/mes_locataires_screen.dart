import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/hover_card.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import 'locataire_detail_screen.dart';
import 'locataire_form_screen.dart';

class MesLocatairesScreen extends StatefulWidget {
  const MesLocatairesScreen({super.key});

  @override
  State<MesLocatairesScreen> createState() => _MesLocatairesScreenState();
}

enum _Tab { tous, actuels, anciens }

enum _Sort { date, alpha }

class _MesLocatairesScreenState extends State<MesLocatairesScreen> {
  static const _bg = Color(0xFFEFF1F7);
  static const _ink = Color(0xFF1F1F2E);
  static const _muted = Color(0xFF8A8AA0);
  static const _hairline = Color(0xFFE3E5EE);
  static const _purple = Color(0xFF7C3AED);
  static const _purpleSoft = Color(0xFFEDE6FF);
  static const _green = Color(0xFF1B7B4D);
  static const _greenSoft = Color(0xFFD7F1E2);
  static const _orange = Color(0xFFC66E1A);
  static const _orangeSoft = Color(0xFFFCE3C7);
  static const _addGreen1 = Color(0xFF5DBE89);
  static const _addGreen2 = Color(0xFF2E875D);
  static const _archive = Color(0xFF6E7280);
  static const _archiveSoft = Color(0xFFE3E5EE);

  static const _gradients = <List<Color>>[
    [Color(0xFF5BB9C4), Color(0xFF7C5BC4)],
    [Color(0xFFE07AB5), Color(0xFFE89460)],
    [Color(0xFF6FB1FF), Color(0xFFB46BFF)],
    [Color(0xFF6BD2A1), Color(0xFF3F8F6B)],
    [Color(0xFFFFB070), Color(0xFFE0608B)],
    [Color(0xFFA98EFF), Color(0xFF6B46FF)],
  ];

  _Tab _tab = _Tab.tous;
  _Sort _sortActuels = _Sort.date;
  _Sort _sortAnciens = _Sort.date;
  bool _expandActuels = true;
  bool _expandAnciens = true;
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Color> _gradientFor(int i) => _gradients[i % _gradients.length];

  bool _matches(Locataire l, String q) {
    if (q.isEmpty) return true;
    final t = q.toLowerCase();
    return l.fullName.toLowerCase().contains(t) ||
        l.email.toLowerCase().contains(t) ||
        (l.phone?.toLowerCase().contains(t) ?? false);
  }

  void _openCreate({bool archive = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocataireFormScreen(archiveMode: archive),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<LocataireService>();
    final logService = context.watch<LogementService>();
    final all = svc.all;
    final actuels = svc.actuels;
    final anciens = svc.anciens;
    final logements = logService.all;
    final now = DateTime.now();

    final actuelsHorsFuturs =
        actuels.where((l) => !l.isFutur).toList();
    final occupiedLogIds = actuelsHorsFuturs
        .expand((l) => l.logementIds)
        .toSet();
    final loyersMois = occupiedLogIds.fold<double>(0, (s, id) {
      final lg = logements.where((l) => l.id == id).cast<Logement?>();
      final found = lg.isEmpty ? null : lg.first;
      return s + (found?.loyerTTC ?? 0);
    });
    final occupationPct = logements.isEmpty
        ? 0
        : (occupiedLogIds.length * 100 / logements.length).round();
    final addedThisMonth = all
        .where((l) =>
            l.createdAt.year == now.year && l.createdAt.month == now.month)
        .length;
    final anciensYears = anciens
        .map((l) => l.dateSortie?.year)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    final archivesRange = anciensYears.isEmpty
        ? null
        : (anciensYears.first == anciensYears.last
            ? 'Historique ${anciensYears.first}'
            : 'Historique ${anciensYears.first}-${anciensYears.last}');

    final query = _query.text.trim();
    final filteredActuels = actuels.where((l) => _matches(l, query)).toList();
    final filteredAnciens = anciens.where((l) => _matches(l, query)).toList();

    _sortList(filteredActuels, _sortActuels, archived: false);
    _sortList(filteredAnciens, _sortAnciens, archived: true);

    final showActuels = _tab != _Tab.anciens;
    final showAnciens = _tab != _Tab.actuels;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _SliverHeader(count: all.length),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _StatsGrid(
                      stats: [
                        _StatData(
                          icon: Icons.people_alt_outlined,
                          iconBg: const Color(0xFFD9F2DD),
                          iconFg: _green,
                          mainGradient: const [
                            _green,
                            Color(0xFF5DBE89),
                          ],
                          big: actuelsHorsFuturs.length
                              .toString()
                              .padLeft(2, '0'),
                          suffix: 'actifs',
                          label: 'LOCATAIRES',
                          chip: addedThisMonth > 0
                              ? '+$addedThisMonth ce mois'
                              : null,
                          chipBg: _greenSoft,
                          chipFg: _green,
                        ),
                        _StatData(
                          icon: Icons.home_outlined,
                          iconBg: _purpleSoft,
                          iconFg: _purple,
                          mainGradient: const [
                            _purple,
                            Color(0xFFC026D3),
                          ],
                          big: occupiedLogIds.length
                              .toString()
                              .padLeft(2, '0'),
                          suffix: '/ ${logements.length.toString().padLeft(2, '0')}',
                          label: 'LOGEMENTS OCCUPÉS',
                          chip: logements.isEmpty
                              ? null
                              : '$occupationPct % occupation',
                          chipIcon: Icons.check,
                          chipBg: _greenSoft,
                          chipFg: _green,
                        ),
                        _StatData(
                          icon: Icons.attach_money_outlined,
                          iconBg: _orangeSoft,
                          iconFg: _orange,
                          mainGradient: const [
                            _orange,
                            Color(0xFFE9B45A),
                          ],
                          big: NumberFormat.decimalPattern('fr_FR')
                              .format(loyersMois.round()),
                          suffix: '€',
                          label: 'LOYERS / MOIS',
                          chip: null,
                        ),
                        _StatData(
                          icon: Icons.archive_outlined,
                          iconBg: _archiveSoft,
                          iconFg: _archive,
                          mainGradient: const [_ink, _archive],
                          big: anciens.length.toString().padLeft(2, '0'),
                          suffix: '',
                          label: 'ANCIENS LOCATAIRES',
                          chip: archivesRange,
                          chipIcon: Icons.access_time,
                          chipBg: _archiveSoft,
                          chipFg: _archive,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _SearchBar(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _Tabs(
                    current: _tab,
                    counts: {
                      _Tab.tous: all.length,
                      _Tab.actuels: actuels.length,
                      _Tab.anciens: anciens.length,
                    },
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ),
              ),
              if (showActuels && filteredActuels.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
                    child: _SectionToolbar(
                      bulletColor: _green,
                      title: 'LOCATAIRES ACTUELS',
                      count: filteredActuels.length,
                      sort: _sortActuels,
                      sortLabel: _sortActuels == _Sort.date
                          ? "date d'entrée"
                          : 'nom',
                      onToggleSort: () => setState(() {
                        _sortActuels = _sortActuels == _Sort.date
                            ? _Sort.alpha
                            : _Sort.date;
                      }),
                      expanded: _expandActuels,
                      onToggleExpand: () => setState(
                          () => _expandActuels = !_expandActuels),
                    ),
                  ),
                ),
                if (_expandActuels)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverList.builder(
                      itemCount: filteredActuels.length,
                      itemBuilder: (ctx, i) {
                        final l = filteredActuels[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ActifCard(
                            locataire: l,
                            logements: logements,
                            gradient: _gradientFor(all.indexOf(l)),
                          ),
                        );
                      },
                    ),
                  ),
              ],
              if (showActuels && showAnciens && filteredAnciens.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: _ArchivesDivider(count: anciens.length),
                  ),
                ),
              if (showAnciens && filteredAnciens.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
                    child: _SectionToolbar(
                      bulletColor: _archive,
                      title: 'ANCIENS LOCATAIRES',
                      count: filteredAnciens.length,
                      sort: _sortAnciens,
                      sortLabel: _sortAnciens == _Sort.date
                          ? 'date de sortie'
                          : 'nom',
                      onToggleSort: () => setState(() {
                        _sortAnciens = _sortAnciens == _Sort.date
                            ? _Sort.alpha
                            : _Sort.date;
                      }),
                      expanded: _expandAnciens,
                      onToggleExpand: () => setState(
                          () => _expandAnciens = !_expandAnciens),
                    ),
                  ),
                ),
                if (_expandAnciens)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverList.builder(
                      itemCount: filteredAnciens.length,
                      itemBuilder: (ctx, i) {
                        final l = filteredAnciens[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _AncienCard(
                            locataire: l,
                            logements: logements,
                          ),
                        );
                      },
                    ),
                  ),
              ],
              if (filteredActuels.isEmpty && filteredAnciens.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(
                    onAdd: () => _openCreate(),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: TextButton.icon(
                    onPressed: () => _openCreate(archive: true),
                    icon: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: _purple,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add,
                          color: Colors.white, size: 18),
                    ),
                    label: const Text(
                      "Ajouter un ancien locataire à l'historique",
                      style: TextStyle(
                        color: _purple,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 80 + MediaQuery.of(context).viewPadding.bottom,
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
            child: _AddFloatingButton(onPressed: () => _openCreate()),
          ),
        ],
      ),
    );
  }

  void _sortList(List<Locataire> list, _Sort sort, {required bool archived}) {
    list.sort((a, b) {
      if (sort == _Sort.alpha) {
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      }
      final ad = archived ? a.dateSortie : a.dateEntree;
      final bd = archived ? b.dateSortie : b.dateEntree;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return archived ? bd.compareTo(ad) : bd.compareTo(ad);
    });
  }
}

class _SliverHeader extends StatelessWidget {
  final int count;
  const _SliverHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SliverToBoxAdapter(
      child: Container(
        height: 110 + top,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7C3AED), Color(0xFFC026D3)],
          ),
        ),
        padding: EdgeInsets.fromLTRB(12, top + 8, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GlassButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Mes locataires',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _GlassButton(icon: Icons.more_vert, onTap: () {}),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _StatData {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final List<Color> mainGradient;
  final String big;
  final String suffix;
  final String label;
  final String? chip;
  final IconData? chipIcon;
  final Color? chipBg;
  final Color? chipFg;
  _StatData({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.mainGradient,
    required this.big,
    required this.suffix,
    required this.label,
    this.chip,
    this.chipIcon,
    this.chipBg,
    this.chipFg,
  });
}

class _StatsGrid extends StatelessWidget {
  final List<_StatData> stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return GridView.count(
          crossAxisCount: wide ? 4 : 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: wide ? 2.6 : 2.4,
          children: stats.map((s) => _StatCard(data: s)).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _MesLocatairesScreenState._hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: data.iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(data.icon, color: data.iconFg, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: data.big,
                        style: TextStyle(
                          color: data.mainGradient.first,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          height: 1.05,
                        ),
                      ),
                      if (data.suffix.isNotEmpty)
                        TextSpan(
                          text: ' ${data.suffix}',
                          style: TextStyle(
                            color: data.mainGradient.first
                                .withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: _MesLocatairesScreenState._muted,
                  ),
                ),
                if (data.chip != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: data.chipBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (data.chipIcon != null) ...[
                          Icon(data.chipIcon, size: 9, color: data.chipFg),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            data.chip!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: data.chipFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.search,
              color: _MesLocatairesScreenState._muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText:
                    'Rechercher un locataire (actuel ou ancien), un email…',
                hintStyle: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: _MesLocatairesScreenState._muted,
                  fontSize: 13.5,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              splashRadius: 18,
              icon: const Icon(Icons.close, size: 18),
              color: _MesLocatairesScreenState._muted,
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final _Tab current;
  final Map<_Tab, int> counts;
  final ValueChanged<_Tab> onChanged;
  const _Tabs({
    required this.current,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: _Tab.values.map((t) {
          final selected = t == current;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onChanged(t),
                borderRadius: BorderRadius.circular(10),
                hoverColor: selected
                    ? Colors.white.withValues(alpha: 0.12)
                    : _MesLocatairesScreenState._purple
                        .withValues(alpha: 0.08),
                mouseCursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: selected
                        ? _MesLocatairesScreenState._purple
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _label(t),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : _MesLocatairesScreenState._ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.22)
                            : _MesLocatairesScreenState._hairline,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${counts[t] ?? 0}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : _MesLocatairesScreenState._muted,
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(_Tab t) {
    switch (t) {
      case _Tab.tous:
        return 'Tous';
      case _Tab.actuels:
        return 'Actuels';
      case _Tab.anciens:
        return 'Anciens';
    }
  }
}

class _SectionToolbar extends StatelessWidget {
  final Color bulletColor;
  final String title;
  final int count;
  final _Sort sort;
  final String sortLabel;
  final VoidCallback onToggleSort;
  final bool expanded;
  final VoidCallback onToggleExpand;
  const _SectionToolbar({
    required this.bulletColor,
    required this.title,
    required this.count,
    required this.sort,
    required this.sortLabel,
    required this.onToggleSort,
    required this.expanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: bulletColor,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: _MesLocatairesScreenState._ink,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w700,
              color: _MesLocatairesScreenState._muted,
            ),
          ),
        ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onToggleSort,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'Trier par ',
                  style: TextStyle(
                    fontSize: 12,
                    color: _MesLocatairesScreenState._muted,
                  ),
                ),
                Text(
                  sortLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _MesLocatairesScreenState._ink,
                  ),
                ),
                const Icon(
                  Icons.expand_more,
                  size: 16,
                  color: _MesLocatairesScreenState._muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggleExpand,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _MesLocatairesScreenState._hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.expand_less,
                  size: 14,
                  color: _MesLocatairesScreenState._muted,
                ),
                const SizedBox(width: 3),
                Text(
                  expanded ? 'Replier' : 'Déplier',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _MesLocatairesScreenState._ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ArchivesDivider extends StatelessWidget {
  final int count;
  const _ArchivesDivider({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(
            color: _MesLocatairesScreenState._hairline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _MesLocatairesScreenState._hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.archive_outlined,
                  size: 14,
                  color: _MesLocatairesScreenState._archive,
                ),
                const SizedBox(width: 8),
                Text(
                  'ARCHIVES · $count ANCIENS LOCATAIRES',
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: _MesLocatairesScreenState._archive,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: _MesLocatairesScreenState._hairline,
          ),
        ),
      ],
    );
  }
}

class _SquareAvatar extends StatelessWidget {
  final String letter;
  final List<Color> gradient;
  final double size;
  final IconData? badgeIcon;
  final bool dotActive;
  const _SquareAvatar({
    required this.letter,
    required this.gradient,
    this.size = 56,
    this.badgeIcon,
    this.dotActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: gradient.last.withValues(alpha: 0.32),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.white, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.45,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          if (dotActive)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF38C172),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
          if (badgeIcon != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: _MesLocatairesScreenState._archive,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  badgeIcon,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActifCard extends StatelessWidget {
  final Locataire locataire;
  final List<Logement> logements;
  final List<Color> gradient;
  const _ActifCard({
    required this.locataire,
    required this.logements,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final first = locataire.firstName.trim();
    final last = locataire.lastName.trim().toUpperCase();
    final initial = first.isNotEmpty
        ? first[0].toUpperCase()
        : (last.isNotEmpty ? last[0] : '?');
    final logement = locataire.logementIds.isEmpty
        ? null
        : logements.where((l) => l.id == locataire.logementIds.first).cast<Logement?>().firstWhere(
              (_) => true,
              orElse: () => null,
            );
    final loyer = logement?.loyerTTC ?? 0;
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final now = DateTime.now();
    final isFuture = locataire.isFutur;
    final money = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: '€',
      decimalDigits: 0,
    );

    String dateLabel;
    if (locataire.dateEntree == null) {
      dateLabel = 'Sans date d\'entrée';
    } else if (isFuture) {
      final days =
          locataire.dateEntree!.difference(now).inDays;
      dateLabel =
          'Entrée prévue le ${df.format(locataire.dateEntree!)} · dans $days jours';
    } else {
      final months = ((now.year - locataire.dateEntree!.year) * 12 +
              now.month -
              locataire.dateEntree!.month)
          .clamp(0, 1000);
      dateLabel =
          'Locataire depuis le ${df.format(locataire.dateEntree!)} · ${months > 0 ? '$months mois' : 'ce mois-ci'}';
    }

    return HoverCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              LocataireDetailScreen(locataireId: locataire.id),
        ),
      ),
      accent: const Color(0xFF7C3AED),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isFuture
                    ? const [
                        _MesLocatairesScreenState._purple,
                        Color(0xFFC026D3),
                      ]
                    : gradient,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SquareAvatar(
                        letter: initial,
                        gradient: gradient,
                        size: 52,
                        dotActive: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: first.isEmpty
                                                  ? ''
                                                  : '$first ',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w500,
                                              ),
                                            ),
                                            TextSpan(
                                              text: last,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isFuture)
                                        _MiniPill(
                                          text: 'Nouveau',
                                          bg: _MesLocatairesScreenState
                                              ._purpleSoft,
                                          fg: _MesLocatairesScreenState
                                              ._purple,
                                          dot: true,
                                        )
                                      else
                                        _MiniPill(
                                          text: 'Bail à jour',
                                          bg: _MesLocatairesScreenState
                                              ._greenSoft,
                                          fg: _MesLocatairesScreenState
                                              ._green,
                                          dot: true,
                                        ),
                                      if (isFuture)
                                        _MiniPill(
                                          text: 'Bail signé',
                                          bg: _MesLocatairesScreenState
                                              ._greenSoft,
                                          fg: _MesLocatairesScreenState
                                              ._green,
                                          dot: true,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  _ContactRow(
                                    email: locataire.email,
                                    phone: locataire.phone,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _MesLocatairesScreenState._bg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: _MesLocatairesScreenState._muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color:
                                    _MesLocatairesScreenState._hairline,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: _BottomChip(
                                  icon: Icons.home_outlined,
                                  text: logement == null
                                      ? '—'
                                      : '${logement.libelle} · ${logement.codePostal}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: _BottomChip(
                                  icon: Icons.event_outlined,
                                  text: dateLabel,
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (loyer > 0)
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: money.format(loyer),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          fontStyle: FontStyle.italic,
                                          color: _MesLocatairesScreenState
                                              ._ink,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' / mois',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _MesLocatairesScreenState
                                              ._muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AncienCard extends StatelessWidget {
  final Locataire locataire;
  final List<Logement> logements;
  const _AncienCard({required this.locataire, required this.logements});

  @override
  Widget build(BuildContext context) {
    final first = locataire.firstName.trim();
    final last = locataire.lastName.trim().toUpperCase();
    final initial = first.isNotEmpty
        ? first[0].toUpperCase()
        : (last.isNotEmpty ? last[0] : '?');
    final logement = locataire.logementIds.isEmpty
        ? null
        : logements
            .where((l) => l.id == locataire.logementIds.first)
            .cast<Logement?>()
            .firstWhere((_) => true, orElse: () => null);
    final loyer = locataire.loyerSortie ?? logement?.loyerTTC ?? 0;
    final df = DateFormat('dd/MM/yyyy', 'fr_FR');
    final money = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: '€',
      decimalDigits: 0,
    );

    String periodLabel = '—';
    if (locataire.dateEntree != null && locataire.dateSortie != null) {
      final fmt = DateFormat('MM/yyyy', 'fr_FR');
      final months = ((locataire.dateSortie!.year - locataire.dateEntree!.year) *
                  12 +
              locataire.dateSortie!.month -
              locataire.dateEntree!.month)
          .clamp(0, 1200);
      final years = months ~/ 12;
      final remMonths = months % 12;
      String duration;
      if (years > 0 && remMonths > 0) {
        duration = '$years ans $remMonths mois';
      } else if (years > 0) {
        duration = '$years an${years > 1 ? 's' : ''}';
      } else {
        duration = '$months mois';
      }
      periodLabel =
          'Du ${fmt.format(locataire.dateEntree!)} au ${fmt.format(locataire.dateSortie!)} · $duration';
    } else if (locataire.dateSortie != null) {
      periodLabel = 'Sortie ${df.format(locataire.dateSortie!)}';
    }

    return HoverCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              LocataireDetailScreen(locataireId: locataire.id),
        ),
      ),
      accent: const Color(0xFF6E7280),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 3,
            decoration: const BoxDecoration(
              color: _MesLocatairesScreenState._archive,
            ),
          ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _SquareAvatar(
                              letter: initial,
                              gradient: const [
                                Color(0xFF8E8E9E),
                                Color(0xFF565666),
                              ],
                              size: 50,
                              badgeIcon: Icons.archive_outlined,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: first.isEmpty
                                                  ? ''
                                                  : '$first ',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w500,
                                              ),
                                            ),
                                            TextSpan(
                                              text: last,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (locataire.dateSortie != null)
                                        _MiniPill(
                                          text:
                                              'Sorti le ${df.format(locataire.dateSortie!)}',
                                          bg: _MesLocatairesScreenState
                                              ._archiveSoft,
                                          fg: _MesLocatairesScreenState
                                              ._archive,
                                          dot: true,
                                        ),
                                      if (locataire
                                          .raisonSortie.isNotEmpty)
                                        _MiniPill(
                                          text: locataire.raisonSortie,
                                          bg: _MesLocatairesScreenState
                                              ._archiveSoft,
                                          fg: _MesLocatairesScreenState
                                              ._archive,
                                          dot: true,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  _ContactRow(
                                    email: locataire.email,
                                    phone: locataire.phone,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _MesLocatairesScreenState._bg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: _MesLocatairesScreenState._muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color:
                                    _MesLocatairesScreenState._hairline,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: _BottomChip(
                                  icon: Icons.home_outlined,
                                  text: logement == null
                                      ? '—'
                                      : '${logement.libelle} · ${logement.codePostal}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: _BottomChip(
                                  icon: Icons.access_time,
                                  text: periodLabel,
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (loyer > 0)
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: money.format(loyer),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          fontStyle: FontStyle.italic,
                                          color: _MesLocatairesScreenState
                                              ._ink,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' / dernier loyer',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _MesLocatairesScreenState
                                              ._muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final bool dot;
  const _MiniPill({
    required this.text,
    required this.bg,
    required this.fg,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 5.5,
              height: 5.5,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String email;
  final String? phone;
  const _ContactRow({required this.email, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mail_outline,
              size: 14,
              color: _MesLocatairesScreenState._muted,
            ),
            const SizedBox(width: 4),
            Text(
              email,
              style: const TextStyle(
                fontSize: 12.5,
                color: _MesLocatairesScreenState._muted,
              ),
            ),
          ],
        ),
        if (phone != null && phone!.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.phone_outlined,
                size: 14,
                color: _MesLocatairesScreenState._muted,
              ),
              const SizedBox(width: 4),
              Text(
                phone!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _MesLocatairesScreenState._muted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BottomChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BottomChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _MesLocatairesScreenState._bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: _MesLocatairesScreenState._muted,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _MesLocatairesScreenState._ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFloatingButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddFloatingButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            _MesLocatairesScreenState._addGreen1,
            _MesLocatairesScreenState._addGreen2,
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: _MesLocatairesScreenState._addGreen2
                .withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 22, 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Ajouter un locataire',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 56,
              color: _MesLocatairesScreenState._muted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aucun résultat',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Aucun locataire ne correspond à ces critères.',
              style: TextStyle(color: _MesLocatairesScreenState._muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un locataire'),
            ),
          ],
        ),
      ),
    );
  }
}
