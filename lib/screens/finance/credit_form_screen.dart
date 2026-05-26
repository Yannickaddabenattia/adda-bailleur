import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/credit_immobilier.dart';
import '../../models/logement.dart';
import '../../services/credit_service.dart';
import '../../services/logement_service.dart';
import '../../widgets/primary_button.dart';

class CreditFormScreen extends StatefulWidget {
  final CreditImmobilier? existing;
  final String? initialLogementId;
  const CreditFormScreen({
    super.key,
    this.existing,
    this.initialLogementId,
  });

  @override
  State<CreditFormScreen> createState() => _CreditFormScreenState();
}

enum _DureeUnit { annees, mois }

class _CreditFormScreenState extends State<CreditFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Logement? _logement;
  final _libelleCtrl = TextEditingController(text: 'Crédit principal');
  final _capitalCtrl = TextEditingController();
  final _tauxCtrl = TextEditingController();
  final _dureeCtrl = TextEditingController();
  _DureeUnit _dureeUnit = _DureeUnit.annees;
  final _mensualiteCtrl = TextEditingController();
  final _assuranceCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  DateTime _dateDebut =
      DateTime(DateTime.now().year, DateTime.now().month);
  bool _saving = false;
  bool _autoMensualite = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _libelleCtrl.text = e.libelle;
      _capitalCtrl.text = e.capitalEmprunte.toStringAsFixed(2);
      _tauxCtrl.text = e.tauxAnnuel.toString();
      if (e.dureeMois % 12 == 0) {
        _dureeUnit = _DureeUnit.annees;
        _dureeCtrl.text = (e.dureeMois ~/ 12).toString();
      } else {
        _dureeUnit = _DureeUnit.mois;
        _dureeCtrl.text = e.dureeMois.toString();
      }
      _mensualiteCtrl.text = e.mensualiteHorsAssurance.toStringAsFixed(2);
      _assuranceCtrl.text = e.assuranceMensuelle.toStringAsFixed(2);
      _notesCtrl.text = e.notes;
      _dateDebut = e.dateDebut;
      _autoMensualite = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logement == null) {
      final logements = context.read<LogementService>().all;
      final id = widget.existing?.logementId ?? widget.initialLogementId;
      if (id != null) {
        for (final l in logements) {
          if (l.id == id) {
            _logement = l;
            break;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _libelleCtrl.dispose();
    _capitalCtrl.dispose();
    _tauxCtrl.dispose();
    _dureeCtrl.dispose();
    _mensualiteCtrl.dispose();
    _assuranceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int? _parseDureeMois() {
    final raw = _dureeCtrl.text.replaceAll(',', '.').trim();
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return _dureeUnit == _DureeUnit.annees ? (v * 12).round() : v.round();
  }

  void _switchUnit(_DureeUnit next) {
    if (next == _dureeUnit) return;
    final raw = _dureeCtrl.text.replaceAll(',', '.').trim();
    final v = double.tryParse(raw);
    setState(() {
      _dureeUnit = next;
      if (v != null && v > 0) {
        if (next == _DureeUnit.mois) {
          _dureeCtrl.text = (v * 12).round().toString();
        } else {
          final years = v / 12;
          _dureeCtrl.text = years == years.roundToDouble()
              ? years.toStringAsFixed(0)
              : years.toStringAsFixed(1);
        }
      }
    });
  }

  Future<void> _pickDateDebut() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateDebut,
      firstDate: DateTime(DateTime.now().year - 30),
      lastDate: DateTime(DateTime.now().year + 30),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Date de début du crédit',
    );
    if (selected != null) {
      setState(() => _dateDebut = DateTime(selected.year, selected.month));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_logement == null) return;
    setState(() => _saving = true);
    final capital = double.parse(_capitalCtrl.text.replaceAll(',', '.'));
    final taux = double.parse(_tauxCtrl.text.replaceAll(',', '.'));
    final dureeMois = _parseDureeMois()!;
    final assurance =
        double.parse(_assuranceCtrl.text.replaceAll(',', '.'));
    double? mensualite;
    if (!_autoMensualite && _mensualiteCtrl.text.trim().isNotEmpty) {
      mensualite =
          double.parse(_mensualiteCtrl.text.replaceAll(',', '.'));
    }
    final service = context.read<CreditService>();
    if (widget.existing == null) {
      final c = CreditImmobilier.create(
        logementId: _logement!.id,
        libelle: _libelleCtrl.text,
        capitalEmprunte: capital,
        tauxAnnuel: taux,
        dateDebut: _dateDebut,
        dureeMois: dureeMois,
        mensualiteHorsAssurance: mensualite,
        assuranceMensuelle: assurance,
        notes: _notesCtrl.text,
      );
      await service.add(c);
    } else {
      final c = widget.existing!;
      c.libelle = _libelleCtrl.text.trim();
      c.capitalEmprunte = capital;
      c.tauxAnnuel = taux;
      c.dateDebut = _dateDebut;
      c.dureeMois = dureeMois;
      c.mensualiteHorsAssurance = mensualite ??
          CreditImmobilier.create(
            logementId: c.logementId,
            libelle: c.libelle,
            capitalEmprunte: capital,
            tauxAnnuel: taux,
            dateDebut: _dateDebut,
            dureeMois: dureeMois,
          ).mensualiteHorsAssurance;
      c.assuranceMensuelle = assurance;
      c.notes = _notesCtrl.text.trim();
      await service.update(c);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final dfMonth = DateFormat('MMMM yyyy', 'fr_FR');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nouveau crédit immobilier'
            : 'Modifier le crédit'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _logement?.id,
              decoration: const InputDecoration(
                labelText: 'Logement',
                prefixIcon: Icon(Icons.apartment_outlined),
              ),
              items: logements
                  .map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.libelle)))
                  .toList(),
              validator: (v) => v == null ? 'Sélectionnez un logement' : null,
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _logement = logements.firstWhere((e) => e.id == id);
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _libelleCtrl,
              decoration: const InputDecoration(
                labelText: 'Libellé',
                prefixIcon: Icon(Icons.short_text),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _capitalCtrl,
              decoration: const InputDecoration(
                labelText: 'Capital emprunté (€)',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tauxCtrl,
              decoration: const InputDecoration(
                labelText: 'Taux annuel (%)',
                prefixIcon: Icon(Icons.percent_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validatePositive,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dureeCtrl,
                    decoration: InputDecoration(
                      labelText: _dureeUnit == _DureeUnit.annees
                          ? 'Durée (années)'
                          : 'Durée (mois)',
                      prefixIcon: const Icon(Icons.timer_outlined),
                    ),
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: _dureeUnit == _DureeUnit.annees,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requis';
                      final p = double.tryParse(v.replaceAll(',', '.'));
                      if (p == null || p <= 0) return 'Valeur invalide';
                      if (_dureeUnit == _DureeUnit.mois &&
                          p != p.roundToDouble()) {
                        return 'Entier requis';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SegmentedButton<_DureeUnit>(
                    segments: const [
                      ButtonSegment(
                        value: _DureeUnit.annees,
                        label: Text('Années'),
                      ),
                      ButtonSegment(
                        value: _DureeUnit.mois,
                        label: Text('Mois'),
                      ),
                    ],
                    selected: {_dureeUnit},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _switchUnit(s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PickerTile(
              icon: Icons.event_outlined,
              label: 'Date de début',
              value:
                  '${dfMonth.format(_dateDebut)[0].toUpperCase()}${dfMonth.format(_dateDebut).substring(1)}',
              onTap: _pickDateDebut,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _autoMensualite,
              onChanged: (v) => setState(() => _autoMensualite = v),
              title: const Text('Calculer la mensualité automatiquement'),
              subtitle: const Text(
                'Désactivez pour saisir manuellement la mensualité hors assurance.',
                style: TextStyle(fontSize: 12),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            if (!_autoMensualite)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextFormField(
                  controller: _mensualiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mensualité hors assurance (€)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _autoMensualite ? null : _validatePositive,
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _assuranceCtrl,
              decoration: const InputDecoration(
                labelText: 'Assurance mensuelle (€)',
                prefixIcon: Icon(Icons.shield_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final p = double.tryParse(v.replaceAll(',', '.'));
                if (p == null || p < 0) return 'Montant invalide';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (facultatif)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: widget.existing == null
                  ? 'Créer le crédit'
                  : 'Enregistrer',
              icon: Icons.check_circle_outline,
              loading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _validatePositive(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requis';
    final p = double.tryParse(v.replaceAll(',', '.'));
    if (p == null || p <= 0) return 'Valeur invalide';
    return null;
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
