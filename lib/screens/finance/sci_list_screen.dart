import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/sci.dart';
import '../../services/sci_service.dart';
import '../../widgets/primary_button.dart';

/// Écran de gestion des SCI : liste + création/édition via dialog.
/// Pour chaque SCI à l'IS, affiche le calcul IS + PFU de l'année en cours.
class SciListScreen extends StatefulWidget {
  const SciListScreen({super.key});

  @override
  State<SciListScreen> createState() => _SciListScreenState();
}

class _SciListScreenState extends State<SciListScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SCIService>();
    final scis = svc.all;
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        title: const Text('Mes SCI'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle SCI'),
      ),
      body: scis.isEmpty
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _YearStrip(
                  year: _year,
                  onPrev: () => setState(() => _year -= 1),
                  onNext: () => setState(() => _year += 1),
                ),
                const SizedBox(height: 16),
                ...scis.map(
                  (sci) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SciCard(
                      sci: sci,
                      year: _year,
                      money: money,
                      onEdit: () => _openForm(context, existing: sci),
                      onDelete: () => _confirmDelete(context, sci),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _openForm(BuildContext context, {SCI? existing}) async {
    final svc = context.read<SCIService>();
    final result = await showDialog<_SciFormResult?>(
      context: context,
      builder: (_) => _SciFormDialog(existing: existing, year: _year),
    );
    if (result == null || !mounted) return;
    if (existing == null) {
      final sci = SCI.create(nom: result.nom, regime: result.regime);
      sci.anneeBasculeIS = result.anneeBasculeIS;
      await svc.add(sci);
    } else {
      existing.nom = result.nom;
      existing.regime = result.regime;
      existing.anneeBasculeIS = result.anneeBasculeIS;
      if (existing.regime == SCIRegime.is_ && result.distribution != null) {
        existing.distributionsParAnnee[_year] = result.distribution!;
      } else if (existing.regime == SCIRegime.ir) {
        existing.distributionsParAnnee.remove(_year);
      }
      await svc.update(existing);
    }
  }

  Future<void> _confirmDelete(BuildContext context, SCI sci) async {
    final svc = context.read<SCIService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la SCI ?'),
        content: Text(
          'La SCI « ${sci.nom} » sera supprimée. Les logements rattachés '
          'seront simplement détachés (ils ne sont pas supprimés). Action '
          'irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) await svc.delete(sci.id);
  }
}

class _SciCard extends StatelessWidget {
  final SCI sci;
  final int year;
  final NumberFormat money;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SciCard({
    required this.sci,
    required this.year,
    required this.money,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SCIService>();
    final calc = svc.calculerIS(sci, year);
    final logements = svc.logementsForSci(sci.id);
    final regimeApplique = sci.regimeForYear(year);
    final isIS = regimeApplique == SCIRegime.is_;
    final color = isIS ? AppColors.accent : AppColors.primary;
    final basculeStr = sci.regime == SCIRegime.ir && sci.anneeBasculeIS != null
        ? 'IR → IS dès ${sci.anneeBasculeIS}'
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  regimeApplique.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sci.nom,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
                tooltip: 'Modifier',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                onPressed: onDelete,
                tooltip: 'Supprimer',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${logements.length} logement${logements.length > 1 ? 's' : ''} '
            'rattaché${logements.length > 1 ? 's' : ''}'
            '${basculeStr != null ? ' · $basculeStr' : ''}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (isIS && calc != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _kv(money, 'Recettes', calc.recettes),
                  _kv(money, 'Charges', -calc.charges),
                  _kv(money, 'Intérêts crédit', -calc.interets),
                  _kv(money, 'Amortissements', -calc.amortissements),
                  const Divider(height: 12),
                  _kv(money, 'Bénéfice imposable', calc.benefice,
                      bold: true),
                  _kv(money, 'IS (15 %/25 %)', calc.impotIS,
                      negative: true),
                  if (calc.distribution > 0) ...[
                    const Divider(height: 12),
                    _kv(money, 'Dividendes distribués', calc.distribution),
                    _kv(money, 'PFU 30 %',
                        calc.prelevementForfaitaireUnique,
                        negative: true),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(NumberFormat money, String label, double v,
      {bool bold = false, bool negative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            money.format(v),
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: negative
                  ? AppColors.error
                  : (bold ? AppColors.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearStrip extends StatelessWidget {
  final int year;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _YearStrip({
    required this.year,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                '$year',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_outlined,
                size: 64, color: context.dividerColor),
            const SizedBox(height: 16),
            const Text(
              'Aucune SCI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crée une SCI puis rattache tes logements depuis leur fiche.\n'
              'IR : transparente (intégré au foyer). IS : impôt société séparé.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SciFormResult {
  final String nom;
  final SCIRegime regime;
  final double? distribution;
  final int? anneeBasculeIS;
  const _SciFormResult({
    required this.nom,
    required this.regime,
    this.distribution,
    this.anneeBasculeIS,
  });
}

class _SciFormDialog extends StatefulWidget {
  final SCI? existing;
  final int year;
  const _SciFormDialog({required this.existing, required this.year});

  @override
  State<_SciFormDialog> createState() => _SciFormDialogState();
}

class _SciFormDialogState extends State<_SciFormDialog> {
  late TextEditingController _nom;
  late SCIRegime _regime;
  late TextEditingController _distribution;
  late TextEditingController _anneeBascule;

  @override
  void initState() {
    super.initState();
    _nom = TextEditingController(text: widget.existing?.nom ?? '');
    _regime = widget.existing?.regime ?? SCIRegime.ir;
    final d = widget.existing?.distributionPourAnnee(widget.year) ?? 0;
    _distribution = TextEditingController(
        text: d > 0 ? d.toStringAsFixed(2).replaceAll('.', ',') : '');
    _anneeBascule = TextEditingController(
        text: widget.existing?.anneeBasculeIS?.toString() ?? '');
  }

  @override
  void dispose() {
    _nom.dispose();
    _distribution.dispose();
    _anneeBascule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nouvelle SCI' : 'Modifier SCI'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nom,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Nom de la SCI',
                prefixIcon: Icon(Icons.business_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SCIRegime>(
              initialValue: _regime,
              decoration: const InputDecoration(
                labelText: 'Régime fiscal',
                prefixIcon: Icon(Icons.balance),
              ),
              items: SCIRegime.values
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.label),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _regime = v ?? _regime),
            ),
            if (_regime == SCIRegime.ir) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _anneeBascule,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Bascule à l\'IS à partir de l\'année (optionnel)',
                  helperText:
                      'Laisse vide si tu restes au régime IR. Sinon, indique '
                      'l\'année à partir de laquelle la SCI passera à l\'IS '
                      '(option irrévocable). Avant cette année, calcul IR ; '
                      'à partir de cette année, calcul IS.',
                  helperMaxLines: 4,
                  prefixIcon: Icon(Icons.swap_horiz),
                ),
              ),
            ],
            if (_regime == SCIRegime.is_) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _distribution,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9,.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Distribution ${widget.year} (€)',
                  helperText: 'Montant distribué aux associés cette année. '
                      'Soumis à PFU 30 %.',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.euro),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Annuler'),
        ),
        PrimaryButton(
          label: 'Enregistrer',
          onPressed: () {
            final nom = _nom.text.trim();
            if (nom.isEmpty) return;
            final dist = double.tryParse(
                  _distribution.text.replaceAll(',', '.'),
                ) ??
                0.0;
            final basculeStr = _anneeBascule.text.trim();
            final bascule = basculeStr.isEmpty
                ? null
                : int.tryParse(basculeStr);
            Navigator.of(context).pop(
              _SciFormResult(
                nom: nom,
                regime: _regime,
                distribution: _regime == SCIRegime.is_ ? dist : null,
                anneeBasculeIS:
                    _regime == SCIRegime.ir ? bascule : null,
              ),
            );
          },
        ),
      ],
    );
  }
}
