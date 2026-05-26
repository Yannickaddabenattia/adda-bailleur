import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/credit_immobilier.dart';

/// Tableau d'amortissement façon document financier — couverture synthétique
/// puis échéances groupées par année avec en-tête en dégradé.
class CreditAmortizationScreen extends StatelessWidget {
  final CreditImmobilier credit;
  const CreditAmortizationScreen({super.key, required this.credit});

  // Palette éditoriale crème — accents colorés par catégorie.
  static const Color _bg = Color(0xFFF5F2E8);
  static const Color _surface = Color(0xFFFAF7EE);
  static const Color _ink = Color(0xFF1F1F1F);
  static const Color _muted = Color(0xFF8A8678);
  static const Color _hairline = Color(0xFFE0DAC9);

  static const Color _capitalGreen = Color(0xFF4EA77E);
  static const Color _capitalGreenDark = Color(0xFF2E7B5C);
  static const Color _interetsOrange = Color(0xFFD4651E);
  static const Color _assurancePurple = Color(0xFF7C3AED);
  static const Color _gold = Color(0xFFC19A2C);

  // Dégradés de bandeau année (3 alternances, comme dans la maquette).
  static const List<List<Color>> _yearGradients = [
    [Color(0xFFD4651E), Color(0xFFE89858)],
    [Color(0xFF3E8E64), Color(0xFF5CB28F)],
    [Color(0xFF6B47D4), Color(0xFF8A6FE8)],
  ];

  static const List<Color> _yearDots = [
    Color(0xFFE89858),
    Color(0xFFCBE9D8),
    Color(0xFFCFC0F0),
  ];

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final compact = NumberFormat('#,##0', 'fr_FR');
    final monthShort = DateFormat('MM / yyyy', 'fr_FR');

    final dureeAns = credit.dureeMois ~/ 12;
    final dureeMoisRest = credit.dureeMois % 12;
    final dureeText = dureeMoisRest == 0
        ? dureeAns.toString()
        : (credit.dureeMois / 12).toStringAsFixed(1);

    final totalCapital = credit.capitalEmprunte;
    final totalInterets = credit.totalInterets.clamp(0, double.infinity).toDouble();
    final totalAssurance = credit.totalAssurance;
    final totalARembourser = totalCapital + totalInterets + totalAssurance;
    final pctCapital = totalARembourser == 0 ? 0.0 : totalCapital / totalARembourser;
    final pctInterets =
        totalARembourser == 0 ? 0.0 : totalInterets / totalARembourser;
    final pctAssurance =
        totalARembourser == 0 ? 0.0 : totalAssurance / totalARembourser;

    final years = _groupByYear(credit);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text(
          'Tableau d\'amortissement',
          style: TextStyle(
            fontSize: 15,
            fontFamily: 'serif',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
          primary: true,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocumentHeader(
                subtitle:
                    'Décomposition mensuelle du remboursement — capital, intérêts & assurance.',
              ),
              const SizedBox(height: 24),

              // ---- Cartes synthèse + donut ----
              LayoutBuilder(
                builder: (ctx, c) {
                  final wide = c.maxWidth >= 720;
                  final cardsCol = Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: 'Capital emprunté',
                              accent: _capitalGreen,
                              value: _bigEuros(credit.capitalEmprunte, compact),
                              caption: '— montant initial',
                              valueColor: _ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              label: 'Durée',
                              accent: _interetsOrange,
                              value: '$dureeText\u00A0ans',
                              valueIsCompact: true,
                              caption:
                                  '— ${credit.dureeMois} mensualités',
                              valueColor: _ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: 'Taux nominal',
                              accent: _gold,
                              value:
                                  '${credit.tauxAnnuel.toString().replaceAll('.', ',')}\u00A0%',
                              valueIsCompact: true,
                              caption: '— hors assurance',
                              valueColor: _ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              label: 'Mensualité totale',
                              accent: _assurancePurple,
                              value: _bigEuros(credit.mensualiteTotale, money),
                              valueIsCompact: true,
                              caption: '— assurance comprise',
                              valueColor: _ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                  final donutCard = _DonutCard(
                    pctCapital: pctCapital,
                    pctInterets: pctInterets,
                    pctAssurance: pctAssurance,
                    totalARembourser: totalARembourser,
                    money: money,
                    dureeAns: dureeAns,
                  );

                  if (wide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cardsCol),
                          const SizedBox(width: 12),
                          Expanded(child: donutCard),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      cardsCol,
                      const SizedBox(height: 12),
                      donutCard,
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // ---- Barre empilée ----
              _StackedBarBlock(
                capital: totalCapital,
                interets: totalInterets,
                assurance: totalAssurance,
                money: money,
              ),

              const SizedBox(height: 24),

              // ---- Tableaux par année ----
              if (years.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _hairline),
                  ),
                  child: Text(
                    'Aucune échéance à afficher (durée=${credit.dureeMois} mois, '
                    'début=${credit.dateDebut.toIso8601String().substring(0, 10)}).',
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontStyle: FontStyle.italic,
                      color: _muted,
                    ),
                  ),
                )
              else
                for (var i = 0; i < years.length; i++) ...[
                  _YearBlock(
                    index: i,
                    year: years[i],
                    totalCapitalAllYears: totalCapital,
                    gradient: _yearGradients[i % _yearGradients.length],
                    rowDot: _yearDots[i % _yearDots.length],
                    money: money,
                    monthShort: monthShort,
                  ),
                  if (i < years.length - 1) const SizedBox(height: 18),
                ],
            ],
          ),
        ),
        ),
      ),
    );
  }

  static String _bigEuros(double v, NumberFormat fmt) {
    final formatted = NumberFormat('#,##0', 'fr_FR').format(v);
    return '$formatted\u00A0€';
  }

  static List<_YearGroup> _groupByYear(CreditImmobilier credit) {
    final map = <int, _YearGroup>{};
    final echeances = credit.echeances();
    for (var i = 0; i < echeances.length; i++) {
      final echeance = echeances[i];
      final dec = credit.decomposerMois(echeance);
      final group = map.putIfAbsent(
        echeance.year,
        () => _YearGroup(year: echeance.year),
      );
      group.rows.add(_AmortRow(
        numero: i + 1,
        echeance: echeance,
        capital: dec.capital,
        interets: dec.interets,
        assurance: dec.assurance,
        capitalRestantDu: dec.crd < 0 ? 0 : dec.crd,
        postRachat: dec.postRachat,
      ));
      group.totalCapital += dec.capital;
      group.totalInterets += dec.interets;
      group.totalAssurance += dec.assurance;
      if (dec.postRachat) group.hasPostRachat = true;
      if (!dec.postRachat) group.hasPreRachat = true;
    }
    final list = map.values.toList()..sort((a, b) => a.year.compareTo(b.year));
    return list;
  }
}

// ============================================================================
//                                ENTÊTE DOC
// ============================================================================

class _DocumentHeader extends StatelessWidget {
  final String subtitle;
  const _DocumentHeader({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _Dash(),
            const SizedBox(width: 8),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: CreditAmortizationScreen._capitalGreenDark,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'DOCUMENT FINANCIER',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 3,
                color: CreditAmortizationScreen._capitalGreenDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: CreditAmortizationScreen._capitalGreenDark,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const _Dash(),
          ],
        ),
        const SizedBox(height: 10),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Tableau ',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 36,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: CreditAmortizationScreen._ink,
                ),
              ),
              TextSpan(
                text: 'd\'amortissement',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 36,
                  height: 1.1,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                  color: CreditAmortizationScreen._capitalGreenDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'serif',
            fontStyle: FontStyle.italic,
            fontSize: 13,
            color: CreditAmortizationScreen._muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 1,
      color: CreditAmortizationScreen._capitalGreenDark,
    );
  }
}

// ============================================================================
//                              CARTES SYNTHÈSE
// ============================================================================

class _SummaryCard extends StatelessWidget {
  final String label;
  final Color accent;
  final String value;
  final String caption;
  final Color valueColor;
  final bool valueIsCompact;
  const _SummaryCard({
    required this.label,
    required this.accent,
    required this.value,
    required this.caption,
    required this.valueColor,
    this.valueIsCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CreditAmortizationScreen._surface,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 8),
                _SummaryValue(
                  value: value,
                  color: valueColor,
                  compact: valueIsCompact,
                ),
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 10,
                    color: CreditAmortizationScreen._muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String value;
  final Color color;
  final bool compact;
  const _SummaryValue({
    required this.value,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final parts = _splitUnit(value);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(
          parts.number,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: compact ? 26 : 32,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: color,
          ),
        ),
        if (parts.unit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 3, bottom: 3),
            child: Text(
              parts.unit,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }

  static ({String number, String unit}) _splitUnit(String v) {
    if (v.endsWith('€')) {
      return (number: v.substring(0, v.length - 1).trimRight(), unit: '€');
    }
    if (v.contains('%')) {
      final i = v.indexOf('%');
      return (number: v.substring(0, i).trimRight(), unit: '%');
    }
    if (v.toLowerCase().contains('ans')) {
      final i = v.toLowerCase().indexOf('ans');
      return (number: v.substring(0, i).trimRight(), unit: 'ans');
    }
    return (number: v, unit: '');
  }
}

// ============================================================================
//                                DONUT CARD
// ============================================================================

class _DonutCard extends StatelessWidget {
  final double pctCapital;
  final double pctInterets;
  final double pctAssurance;
  final double totalARembourser;
  final NumberFormat money;
  final int dureeAns;

  const _DonutCard({
    required this.pctCapital,
    required this.pctInterets,
    required this.pctAssurance,
    required this.totalARembourser,
    required this.money,
    required this.dureeAns,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CreditAmortizationScreen._surface,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
              gradient: LinearGradient(
                colors: [
                  CreditAmortizationScreen._capitalGreen,
                  CreditAmortizationScreen._interetsOrange,
                  CreditAmortizationScreen._assurancePurple,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'COÛT TOTAL — RÉPARTITION',
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                          color: CreditAmortizationScreen._muted,
                        ),
                      ),
                    ),
                    Text(
                      'sur $dureeAns ans',
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: CreditAmortizationScreen._muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: _DonutChart(
                        pctCapital: pctCapital,
                        pctInterets: pctInterets,
                        pctAssurance: pctAssurance,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendRow(
                            color: CreditAmortizationScreen._capitalGreen,
                            label: 'Capital',
                            value: '${_pct(pctCapital)} %',
                          ),
                          const SizedBox(height: 8),
                          _LegendRow(
                            color: CreditAmortizationScreen._interetsOrange,
                            label: 'Intérêts',
                            value: '${_pct(pctInterets)} %',
                          ),
                          const SizedBox(height: 8),
                          _LegendRow(
                            color: CreditAmortizationScreen._assurancePurple,
                            label: 'Assurance',
                            value: '${_pct(pctAssurance)} %',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _DottedDivider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TOTAL À REMBOURSER',
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                          color: CreditAmortizationScreen._muted,
                        ),
                      ),
                    ),
                    Text(
                      CreditAmortizationScreen._bigEuros(
                          totalARembourser, money),
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: CreditAmortizationScreen._ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _pct(double v) {
    final pct = v * 100;
    if (pct >= 10) return pct.toStringAsFixed(0).replaceAll('.', ',');
    return pct.toStringAsFixed(1).replaceAll('.', ',');
  }
}

class _DonutChart extends StatelessWidget {
  final double pctCapital;
  final double pctInterets;
  final double pctAssurance;
  const _DonutChart({
    required this.pctCapital,
    required this.pctInterets,
    required this.pctAssurance,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[];
    void addSec(double v, Color c) {
      if (v <= 0) return;
      sections.add(
        PieChartSectionData(
          value: v * 100,
          color: c,
          showTitle: false,
          radius: 18,
        ),
      );
    }

    addSec(pctCapital, CreditAmortizationScreen._capitalGreen);
    addSec(pctInterets, CreditAmortizationScreen._interetsOrange);
    addSec(pctAssurance, CreditAmortizationScreen._assurancePurple);

    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 32,
        sectionsSpace: 2,
        startDegreeOffset: -90,
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 13,
              color: CreditAmortizationScreen._ink,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CreditAmortizationScreen._ink,
          ),
        ),
      ],
    );
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        const dashWidth = 4.0;
        const dashSpace = 4.0;
        final count = (c.maxWidth / (dashWidth + dashSpace)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              count,
              (_) => SizedBox(
                width: dashWidth,
                height: 1,
                child: const ColoredBox(
                  color: CreditAmortizationScreen._hairline,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
//                              BARRE EMPILÉE
// ============================================================================

class _StackedBarBlock extends StatelessWidget {
  final double capital;
  final double interets;
  final double assurance;
  final NumberFormat money;
  const _StackedBarBlock({
    required this.capital,
    required this.interets,
    required this.assurance,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final total = capital + interets + assurance;
    final cHors = interets + assurance;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: CreditAmortizationScreen._surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: CreditAmortizationScreen._hairline,
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Répartition du remboursement total',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CreditAmortizationScreen._ink,
                  ),
                ),
              ),
              Text(
                'Coût hors capital · ',
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: CreditAmortizationScreen._muted,
                ),
              ),
              Text(
                CreditAmortizationScreen._bigEuros(cHors, money),
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: CreditAmortizationScreen._ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  if (total > 0)
                    Expanded(
                      flex: (capital / total * 1000).round(),
                      child: _BarSegment(
                        color: CreditAmortizationScreen._capitalGreen,
                        text:
                            'Capital · ${CreditAmortizationScreen._bigEuros(capital, money)}',
                      ),
                    ),
                  if (total > 0 && interets > 0)
                    Expanded(
                      flex: (interets / total * 1000).round(),
                      child: _BarSegment(
                        color: CreditAmortizationScreen._interetsOrange,
                        text:
                            'Intérêts · ${CreditAmortizationScreen._bigEuros(interets, money)}',
                      ),
                    ),
                  if (total > 0 && assurance > 0)
                    Expanded(
                      flex: (assurance / total * 1000).round(),
                      child: _BarSegment(
                        color: CreditAmortizationScreen._assurancePurple,
                        text: 'Ass.',
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

class _BarSegment extends StatelessWidget {
  final Color color;
  final String text;
  const _BarSegment({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: const TextStyle(
          fontFamily: 'serif',
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ============================================================================
//                              BLOC ANNÉE
// ============================================================================

class _YearBlock extends StatelessWidget {
  final int index;
  final _YearGroup year;
  final double totalCapitalAllYears;
  final List<Color> gradient;
  final Color rowDot;
  final NumberFormat money;
  final DateFormat monthShort;
  const _YearBlock({
    required this.index,
    required this.year,
    required this.totalCapitalAllYears,
    required this.gradient,
    required this.rowDot,
    required this.money,
    required this.monthShort,
  });

  @override
  Widget build(BuildContext context) {
    final n = (index + 1).toString().padLeft(2, '0');
    return Container(
      decoration: BoxDecoration(
        color: CreditAmortizationScreen._surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: CreditAmortizationScreen._hairline,
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bandeau dégradé
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5)),
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Text(
                  '§ $n',
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${year.year}',
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${year.rows.length.toString().padLeft(2, '0')} ÉCHÉANCES',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                _YearTotal(
                    label: 'CAPITAL',
                    value: CreditAmortizationScreen._bigEuros(
                        year.totalCapital, money)),
                const SizedBox(width: 14),
                _YearTotal(
                    label: 'INTÉRÊTS',
                    value: CreditAmortizationScreen._bigEuros(
                        year.totalInterets, money)),
                const SizedBox(width: 14),
                _YearTotal(
                    label: 'ASSURANCE',
                    value: CreditAmortizationScreen._bigEuros(
                        year.totalAssurance, money)),
              ],
            ),
          ),
          // En-tête colonnes
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: const _ColumnsHeader(),
          ),
          // Lignes
          for (var i = 0; i < year.rows.length; i++) ...[
            if (i > 0 &&
                year.rows[i].postRachat &&
                !year.rows[i - 1].postRachat)
              const _RachatSeparator(),
            _AmortRowTile(
              dot: year.rows[i].postRachat
                  ? const Color(0xFF7C3AED)
                  : rowDot,
              row: year.rows[i],
              totalCapitalAllYears: totalCapitalAllYears,
              money: money,
              monthShort: monthShort,
              isLast: i == year.rows.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _RachatSeparator extends StatelessWidget {
  const _RachatSeparator();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
            width: 0.6,
          ),
          bottom: BorderSide(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: const [
          Icon(Icons.swap_horiz_outlined,
              size: 13, color: Color(0xFF7C3AED)),
          SizedBox(width: 6),
          Text(
            'RACHAT — NOUVELLES CONDITIONS',
            style: TextStyle(
              fontSize: 9.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: Color(0xFF7C3AED),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearTotal extends StatelessWidget {
  final String label;
  final String value;
  const _YearTotal({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ColumnsHeader extends StatelessWidget {
  const _ColumnsHeader();

  @override
  Widget build(BuildContext context) {
    TextStyle s(Color c) => TextStyle(
          fontSize: 9.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: c,
        );
    return Row(
      children: [
        SizedBox(width: 38, child: Text('N°', style: s(CreditAmortizationScreen._muted))),
        SizedBox(
          width: 70,
          child: Text('ÉCHÉANCE', style: s(CreditAmortizationScreen._muted)),
        ),
        Expanded(
          flex: 18,
          child: Text(
            'CAPITAL',
            style: s(CreditAmortizationScreen._capitalGreenDark),
          ),
        ),
        Expanded(
          flex: 18,
          child: Text(
            'INTÉRÊTS',
            style: s(CreditAmortizationScreen._interetsOrange),
          ),
        ),
        Expanded(
          flex: 12,
          child: Text(
            'ASSUR.',
            style: s(CreditAmortizationScreen._assurancePurple),
          ),
        ),
        Expanded(
          flex: 22,
          child: Text(
            'CAPITAL RESTANT DÛ',
            style: s(CreditAmortizationScreen._muted),
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 22,
          child: Text(
            'PROGRESSION',
            style: s(CreditAmortizationScreen._muted),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _AmortRowTile extends StatelessWidget {
  final Color dot;
  final _AmortRow row;
  final double totalCapitalAllYears;
  final NumberFormat money;
  final DateFormat monthShort;
  final bool isLast;
  const _AmortRowTile({
    required this.dot,
    required this.row,
    required this.totalCapitalAllYears,
    required this.money,
    required this.monthShort,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalCapitalAllYears == 0
        ? 0.0
        : ((totalCapitalAllYears - row.capitalRestantDu) / totalCapitalAllYears)
            .clamp(0.0, 1.0);
    final pctText = '${(progress * 100).toStringAsFixed(1).replaceAll('.', ',')} %';

    final n = row.numero.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CreditAmortizationScreen._hairline,
            width: 0.5,
          ),
          bottom: isLast
              ? BorderSide.none
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Container(
              alignment: Alignment.center,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  n,
                  style: const TextStyle(
                    fontFamily: 'serif',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              monthShort.format(row.echeance),
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 12,
                color: CreditAmortizationScreen._ink,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              CreditAmortizationScreen._bigEuros(row.capital, money),
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CreditAmortizationScreen._capitalGreenDark,
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              CreditAmortizationScreen._bigEuros(row.interets, money),
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CreditAmortizationScreen._interetsOrange,
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: Text(
              CreditAmortizationScreen._bigEuros(row.assurance, money),
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CreditAmortizationScreen._assurancePurple,
              ),
            ),
          ),
          Expanded(
            flex: 22,
            child: Text(
              CreditAmortizationScreen._bigEuros(row.capitalRestantDu, money),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F3D62),
              ),
            ),
          ),
          Expanded(
            flex: 22,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: CreditAmortizationScreen._hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: CreditAmortizationScreen._capitalGreen,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    pctText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: CreditAmortizationScreen._capitalGreenDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//                                  DTO
// ============================================================================

class _YearGroup {
  final int year;
  final List<_AmortRow> rows = [];
  double totalCapital = 0;
  double totalInterets = 0;
  double totalAssurance = 0;
  bool hasPreRachat = false;
  bool hasPostRachat = false;
  _YearGroup({required this.year});
}

class _AmortRow {
  final int numero;
  final DateTime echeance;
  final double capital;
  final double interets;
  final double assurance;
  final double capitalRestantDu;
  final bool postRachat;
  _AmortRow({
    required this.numero,
    required this.echeance,
    required this.capital,
    required this.interets,
    required this.assurance,
    required this.capitalRestantDu,
    this.postRachat = false,
  });
}
