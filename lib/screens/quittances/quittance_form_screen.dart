import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../models/logement.dart';
import '../../models/quittance.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/quittance_service.dart';
import '../../services/revision_loyer_service.dart';
import '../../widgets/primary_button.dart';
import 'quittance_detail_screen.dart';

class QuittanceFormScreen extends StatefulWidget {
  final String? initialLogementId;
  final String? initialLocataireId;
  final DateTime? initialPeriode;

  const QuittanceFormScreen({
    super.key,
    this.initialLogementId,
    this.initialLocataireId,
    this.initialPeriode,
  });

  @override
  State<QuittanceFormScreen> createState() => _QuittanceFormScreenState();
}

class _QuittanceFormScreenState extends State<QuittanceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  Logement? _logement;
  Locataire? _locataire;
  late DateTime _periode;
  DateTime _datePaiement = DateTime.now();
  final _loyerCtrl = TextEditingController();
  final _chargesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _montantPayeCtrl = TextEditingController();
  // Versements supplémentaires alloués à d'autres mois (régularisations
  // passées ou avance sur mois futurs). Clé = (year, month).
  final Map<(int year, int month), double> _versementsSupplem = {};
  bool _saving = false;
  bool _initialPrefillDone = false;
  bool _montantPayeUserEdited = false;

  // --- Mode lot ----------------------------------------------------------
  bool _batchMode = false;
  DateTime _periodeDebut =
      DateTime(DateTime.now().year, 1);
  DateTime _periodeFin =
      DateTime(DateTime.now().year, 12);
  int _jourPaiement = 5;

  @override
  void initState() {
    super.initState();
    _periode = widget.initialPeriode ??
        DateTime(DateTime.now().year, DateTime.now().month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialPrefillDone) return;
    _initialPrefillDone = true;
    if (widget.initialLogementId != null) {
      _logement =
          context.read<LogementService>().byId(widget.initialLogementId!);
    }
    if (widget.initialLocataireId != null) {
      _locataire =
          context.read<LocataireService>().byId(widget.initialLocataireId!);
    }
    if (_logement != null) {
      _applyEffectiveRent();
    }
  }

  @override
  void dispose() {
    _loyerCtrl.dispose();
    _chargesCtrl.dispose();
    _notesCtrl.dispose();
    _montantPayeCtrl.dispose();
    super.dispose();
  }

  void _applyEffectiveRent() {
    final l = _logement;
    if (l == null) return;
    final effectif = context
        .read<RevisionLoyerService>()
        .loyerEffectifAt(logement: l, date: _periode);
    _loyerCtrl.text = effectif.loyerHC.toStringAsFixed(2);
    _chargesCtrl.text = effectif.charges.toStringAsFixed(2);
    _syncMontantPayeDefault();
  }

  double _safeParse(String s) =>
      double.tryParse(s.replaceAll(',', '.').trim()) ?? 0;

  double get _totalDu => _safeParse(_loyerCtrl.text) + _safeParse(_chargesCtrl.text);

  /// Si l'utilisateur n'a pas explicitement modifié le montant payé,
  /// on le synchronise sur le total dû. Appelé après chaque changement
  /// de loyer/charges/période.
  void _syncMontantPayeDefault() {
    if (_montantPayeUserEdited) return;
    _montantPayeCtrl.text = _totalDu.toStringAsFixed(2);
  }

  Future<void> _pickPeriode() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _periode,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12),
      helpText: 'Période de la quittance',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (selected != null) {
      setState(() => _periode = DateTime(selected.year, selected.month));
      _applyEffectiveRent();
    }
  }

  Future<void> _pickPaiement() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _datePaiement,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Date de paiement',
    );
    if (selected != null) {
      setState(() => _datePaiement = selected);
    }
  }

  Future<void> _pickPeriodeBornee({required bool debut}) async {
    final now = DateTime.now();
    final initial = debut ? _periodeDebut : _periodeFin;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5, 12),
      helpText: debut ? 'Premier mois' : 'Dernier mois',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (selected != null) {
      setState(() {
        final v = DateTime(selected.year, selected.month);
        if (debut) {
          _periodeDebut = v;
          if (_periodeFin.isBefore(_periodeDebut)) _periodeFin = v;
        } else {
          _periodeFin = v;
          if (_periodeDebut.isAfter(_periodeFin)) _periodeDebut = v;
        }
      });
    }
  }

  void _setAnneeComplete(int year) {
    setState(() {
      _periodeDebut = DateTime(year, 1);
      _periodeFin = DateTime(year, 12);
    });
  }

  /// Liste des (year, month) couverts par la plage [_periodeDebut, _periodeFin].
  List<DateTime> _moisDansPlage() {
    final out = <DateTime>[];
    var cursor = DateTime(_periodeDebut.year, _periodeDebut.month);
    final end = DateTime(_periodeFin.year, _periodeFin.month);
    while (!cursor.isAfter(end)) {
      out.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return out;
  }

  ({int aCreer, int dejaExistantes}) _previewLot() {
    if (_locataire == null) return (aCreer: 0, dejaExistantes: 0);
    final service = context.read<QuittanceService>();
    int existantes = 0;
    final mois = _moisDansPlage();
    for (final m in mois) {
      if (service.exists(
          locataireId: _locataire!.id, year: m.year, month: m.month)) {
        existantes++;
      }
    }
    return (aCreer: mois.length - existantes, dejaExistantes: existantes);
  }

  Future<void> _addVersement() async {
    final picked = await _pickVersement(
      context,
      defaultMois: DateTime(_periode.year, _periode.month - 1),
    );
    if (picked == null) return;
    setState(() {
      _versementsSupplem[(picked.year, picked.month)] = picked.montant;
    });
  }

  Future<void> _submit() async {
    if (_batchMode) {
      await _submitLot();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_logement == null || _locataire == null) return;
    final service = context.read<QuittanceService>();
    if (service.exists(
      locataireId: _locataire!.id,
      year: _periode.year,
      month: _periode.month,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Une quittance existe déjà pour ce locataire sur cette période.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final montantPayeRaw = _safeParse(_montantPayeCtrl.text);
    final montantPayeFinal = _montantPayeUserEdited ? montantPayeRaw : null;
    final versementsMap = <String, double>{
      for (final e in _versementsSupplem.entries)
        if (e.value > 0)
          QuittanceService.moisKey(e.key.$1, e.key.$2): e.value,
    };
    final q = Quittance.create(
      logementId: _logement!.id,
      locataireId: _locataire!.id,
      periodYear: _periode.year,
      periodMonth: _periode.month,
      loyerHC: double.parse(_loyerCtrl.text.replaceAll(',', '.')),
      charges: double.parse(_chargesCtrl.text.replaceAll(',', '.')),
      datePaiement: _datePaiement,
      notes: _notesCtrl.text,
      montantPaye: montantPayeFinal,
      versementsSupplementaires:
          versementsMap.isEmpty ? null : versementsMap,
    );
    await service.add(q);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuittanceDetailScreen(quittanceId: q.id),
      ),
    );
  }

  Future<void> _submitLot() async {
    if (_logement == null || _locataire == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez un logement et un locataire.'),
        ),
      );
      return;
    }
    final mois = _moisDansPlage();
    if (mois.isEmpty) return;

    final service = context.read<QuittanceService>();
    final revisions = context.read<RevisionLoyerService>();

    final preview = _previewLot();
    if (preview.aCreer == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Toutes les quittances de cette période existent déjà.'),
        ),
      );
      return;
    }

    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer la création'),
        content: Text(
          'Créer ${preview.aCreer} quittance${preview.aCreer > 1 ? 's' : ''} '
          'de ${DateFormat('MMMM yyyy', 'fr_FR').format(_periodeDebut)} '
          'à ${DateFormat('MMMM yyyy', 'fr_FR').format(_periodeFin)} ?'
          '${preview.dejaExistantes > 0 ? '\n\n${preview.dejaExistantes} mois déjà existant${preview.dejaExistantes > 1 ? 's seront ignorés' : ' sera ignoré'}.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    setState(() => _saving = true);
    int crees = 0;
    int ignores = 0;
    for (final m in mois) {
      if (service.exists(
          locataireId: _locataire!.id, year: m.year, month: m.month)) {
        ignores++;
        continue;
      }
      final eff = revisions.loyerEffectifAt(logement: _logement!, date: m);
      // Date de paiement : jour choisi, borné au dernier jour du mois.
      final lastDay = DateTime(m.year, m.month + 1, 0).day;
      final day = _jourPaiement.clamp(1, lastDay);
      final dp = DateTime(m.year, m.month, day);
      final q = Quittance.create(
        logementId: _logement!.id,
        locataireId: _locataire!.id,
        periodYear: m.year,
        periodMonth: m.month,
        loyerHC: eff.loyerHC,
        charges: eff.charges,
        datePaiement: dp,
        notes: _notesCtrl.text,
      );
      await service.add(q);
      crees++;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$crees quittance${crees > 1 ? 's créées' : ' créée'}'
          '${ignores > 0 ? ', $ignores ignorée${ignores > 1 ? 's' : ''} (déjà existante${ignores > 1 ? 's' : ''})' : ''}.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final logements = context.watch<LogementService>().all;
    final locataires = context.watch<LocataireService>().all;
    final dfPeriode = DateFormat('MMMM yyyy', 'fr_FR');
    final dfDate = DateFormat('dd/MM/yyyy', 'fr_FR');
    final preview = _batchMode ? _previewLot() : null;
    final lotCount = preview?.aCreer ?? 0;
    final lotIgnores = preview?.dejaExistantes ?? 0;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title:
            Text(_batchMode ? 'Quittances en lot' : 'Nouvelle quittance'),
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
                final l = logements.firstWhere((e) => e.id == id);
                setState(() {
                  _logement = l;
                });
                _applyEffectiveRent();
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _locataire?.id,
              decoration: const InputDecoration(
                labelText: 'Locataire',
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: locataires
                  .map((l) => DropdownMenuItem(
                      value: l.id, child: Text(l.fullName)))
                  .toList(),
              validator: (v) => v == null ? 'Sélectionnez un locataire' : null,
              onChanged: (id) {
                if (id == null) return;
                setState(() {
                  _locataire = locataires.firstWhere((e) => e.id == id);
                });
              },
            ),
            const SizedBox(height: 20),
            _BatchToggle(
              value: _batchMode,
              onChanged: (v) => setState(() => _batchMode = v),
            ),
            const SizedBox(height: 16),
            if (!_batchMode) ...[
              _PickerTile(
                icon: Icons.calendar_month_outlined,
                label: 'Période',
                value:
                    '${dfPeriode.format(_periode)[0].toUpperCase()}${dfPeriode.format(_periode).substring(1)}',
                onTap: _pickPeriode,
              ),
              const SizedBox(height: 10),
              _PickerTile(
                icon: Icons.event_available_outlined,
                label: 'Date de paiement',
                value: dfDate.format(_datePaiement),
                onTap: _pickPaiement,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _loyerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Loyer hors charges (€)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validateAmount,
                onChanged: (_) => setState(_syncMontantPayeDefault),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _chargesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Charges (€)',
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validateAmount,
                onChanged: (_) => setState(_syncMontantPayeDefault),
              ),
              const SizedBox(height: 16),
              _PaiementSection(
                totalDu: _totalDu,
                montantPayeCtrl: _montantPayeCtrl,
                onMontantPayeChanged: () => setState(() {
                  _montantPayeUserEdited = true;
                }),
                versements: _versementsSupplem,
                onAddVersement: _addVersement,
                onRemoveVersement: (key) => setState(() {
                  _versementsSupplem.remove(key);
                }),
              ),
            ] else ...[
              _PickerTile(
                icon: Icons.first_page,
                label: 'Premier mois',
                value:
                    '${dfPeriode.format(_periodeDebut)[0].toUpperCase()}${dfPeriode.format(_periodeDebut).substring(1)}',
                onTap: () => _pickPeriodeBornee(debut: true),
              ),
              const SizedBox(height: 10),
              _PickerTile(
                icon: Icons.last_page,
                label: 'Dernier mois',
                value:
                    '${dfPeriode.format(_periodeFin)[0].toUpperCase()}${dfPeriode.format(_periodeFin).substring(1)}',
                onTap: () => _pickPeriodeBornee(debut: false),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PresetChip(
                    label: 'Année ${now.year}',
                    onTap: () => _setAnneeComplete(now.year),
                  ),
                  _PresetChip(
                    label: 'Année ${now.year - 1}',
                    onTap: () => _setAnneeComplete(now.year - 1),
                  ),
                  _PresetChip(
                    label: 'Année ${now.year - 2}',
                    onTap: () => _setAnneeComplete(now.year - 2),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _JourPaiementField(
                value: _jourPaiement,
                onChanged: (v) => setState(() => _jourPaiement = v),
              ),
              const SizedBox(height: 16),
              const _InfoBanner(
                text:
                    'Le loyer effectif de chaque mois est utilisé automatiquement. '
                    'Les révisions ALUR enregistrées sont appliquées mois par mois.',
              ),
              const SizedBox(height: 16),
              _LotPreview(
                aCreer: lotCount,
                dejaExistantes: lotIgnores,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: _batchMode
                    ? 'Notes (appliquées à toutes — facultatif)'
                    : 'Notes (facultatif)',
                prefixIcon: const Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: _batchMode
                  ? (lotCount > 0
                      ? 'Créer $lotCount quittance${lotCount > 1 ? 's' : ''}'
                      : 'Aucune quittance à créer')
                  : 'Créer la quittance',
              icon: Icons.check_circle_outline,
              loading: _saving,
              onPressed:
                  (_batchMode && lotCount == 0 && _locataire != null)
                      ? null
                      : _submit,
            ),
          ],
        ),
      ),
    );
  }

  String? _validateAmount(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requis';
    final parsed = double.tryParse(v.replaceAll(',', '.'));
    if (parsed == null || parsed < 0) return 'Montant invalide';
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
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.dividerColor),
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
                      style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.textSecondaryColor),
          ],
        ),
      ),
    );
  }
}

class _BatchToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _BatchToggle({required this.value, required this.onChanged});

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
          const Icon(Icons.layers_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode lot',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Plusieurs mois ou années en une fois',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.event_repeat, size: 18),
    );
  }
}

class _JourPaiementField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _JourPaiementField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Jour de paiement',
                  style: TextStyle(
                      fontSize: 12, color: context.textSecondaryColor),
                ),
                const SizedBox(height: 2),
                Text(
                  'Le $value de chaque mois',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed:
                value < 28 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.primaryLight.withValues(alpha: 0.12)
            : AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: dark ? 0.4 : 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  TextStyle(fontSize: 13, color: context.textPrimaryColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _LotPreview extends StatelessWidget {
  final int aCreer;
  final int dejaExistantes;
  const _LotPreview({required this.aCreer, required this.dejaExistantes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        children: [
          Icon(Icons.summarize_outlined,
              color: aCreer > 0 ? AppColors.success : AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$aCreer quittance${aCreer > 1 ? 's' : ''} à créer',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (dejaExistantes > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$dejaExistantes mois déjà existant${dejaExistantes > 1 ? 's seront ignorés' : ' sera ignoré'}',
                    style: TextStyle(
                        fontSize: 12, color: context.textSecondaryColor),
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

// ─────────────────────────────────────────────────────────────────────────
// Section "Paiement" du formulaire (montant payé + versements supplem)
// ─────────────────────────────────────────────────────────────────────────

class _PaiementSection extends StatelessWidget {
  final double totalDu;
  final TextEditingController montantPayeCtrl;
  final VoidCallback onMontantPayeChanged;
  final Map<(int, int), double> versements;
  final Future<void> Function() onAddVersement;
  final void Function((int, int)) onRemoveVersement;

  const _PaiementSection({
    required this.totalDu,
    required this.montantPayeCtrl,
    required this.onMontantPayeChanged,
    required this.versements,
    required this.onAddVersement,
    required this.onRemoveVersement,
  });

  static const List<String> _mois = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final montantPaye =
        double.tryParse(montantPayeCtrl.text.replaceAll(',', '.')) ?? 0;
    final restant = totalDu - montantPaye;
    final totalVersements =
        versements.values.fold<double>(0, (s, v) => s + v);
    final totalEncaisse = montantPaye + totalVersements;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_rounded, size: 18,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Paiement',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const Spacer(),
              Text(
                'Dû : ${money.format(totalDu)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: montantPayeCtrl,
            decoration: const InputDecoration(
              labelText: 'Montant encaissé ce mois (€)',
              prefixIcon: Icon(Icons.attach_money_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onMontantPayeChanged(),
          ),
          if (restant > 0.01) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Reste dû ce mois : ${money.format(restant)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ] else if (restant < -0.01) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Excédent : ${money.format(-restant)} (à allouer ci-dessous)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Versements supplémentaires (régul / avance)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textSecondaryColor,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onAddVersement,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          if (versements.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Aucun versement complémentaire.',
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondaryColor,
                ),
              ),
            )
          else
            ...versements.entries.map((e) {
              final label = '${_mois[e.key.$2 - 1]} ${e.key.$1}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 16, color: context.textSecondaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                    Text(
                      money.format(e.value),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Retirer',
                      onPressed: () => onRemoveVersement(e.key),
                    ),
                  ],
                ),
              );
            }),
          if (totalVersements > 0) ...[
            const Divider(height: 18),
            Row(
              children: [
                Text(
                  'Total encaissé via cette quittance',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
                const Spacer(),
                Text(
                  money.format(totalEncaisse),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PickedVersement {
  final int year;
  final int month;
  final double montant;
  const _PickedVersement(this.year, this.month, this.montant);
}

Future<_PickedVersement?> _pickVersement(
  BuildContext context, {
  required DateTime defaultMois,
}) async {
  DateTime mois = DateTime(defaultMois.year, defaultMois.month);
  final montantCtrl = TextEditingController();
  return showDialog<_PickedVersement>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Versement supplémentaire'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Précise le mois concerné (régularisation passée ou '
              'avance sur mois futur) et le montant alloué.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: mois,
                  firstDate: DateTime(now.year - 10),
                  lastDate: DateTime(now.year + 5, 12, 31),
                  helpText: 'Mois du versement',
                );
                if (picked == null) return;
                setLocal(() => mois = DateTime(picked.year, picked.month));
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Mois concerné',
                  prefixIcon: Icon(Icons.event_outlined),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  DateFormat('MMMM yyyy', 'fr_FR').format(mois),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montantCtrl,
              decoration: const InputDecoration(
                labelText: 'Montant (€)',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final m = double.tryParse(
                  montantCtrl.text.replaceAll(',', '.').trim());
              if (m == null || m <= 0) return;
              Navigator.of(ctx).pop(
                _PickedVersement(mois.year, mois.month, m),
              );
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    ),
  );
}
