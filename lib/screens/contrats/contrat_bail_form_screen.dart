import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/contrat_bail.dart';
import '../../models/logement.dart';
import '../../services/contrat_bail_service.dart';
import '../../services/locataire_service.dart';
import '../../widgets/primary_button.dart';
import 'contrat_bail_detail_screen.dart';

/// Formulaire de création / édition d'un contrat de bail. Conditionne les
/// champs visibles selon le type de bail sélectionné.
class ContratBailFormScreen extends StatefulWidget {
  final Logement logement;
  final ContratBail? existing;
  const ContratBailFormScreen({
    super.key,
    required this.logement,
    this.existing,
  });

  @override
  State<ContratBailFormScreen> createState() =>
      _ContratBailFormScreenState();
}

class _ContratBailFormScreenState extends State<ContratBailFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late BailType _type;
  late DateTime _dateDebut;
  late TextEditingController _dureeMois;
  late TextEditingController _loyerHC;
  late TextEditingController _charges;
  late TextEditingController _depot;
  late TextEditingController _jourEcheance;
  late TextEditingController _rib;
  late TextEditingController _notes;
  late TextEditingController _justifMobilite;
  late TextEditingController _noteAnimaux;
  ModePaiement _modePaiement = ModePaiement.virement;

  bool _revisionIRL = true;
  bool _nonFumeur = false;
  bool _animaux = false;
  bool _solidariteColo = true;
  bool _chargesIncluses = false;

  final Set<String> _selectedLocataireIds = {};
  String? _referentColo;

  /// Équipements bail meublé : map(label → coché).
  late Map<String, bool> _equipements;

  static const List<String> _equipementsMeublesObligatoires = [
    'Literie (lit + matelas)',
    'Table et sièges',
    'Étagères de rangement',
    'Luminaires',
    'Plaques de cuisson',
    'Four ou micro-ondes',
    'Réfrigérateur + congélateur',
    'Ustensiles de cuisine',
    'Évier avec robinetterie',
    'Volets ou rideaux occultants (chambre)',
  ];
  static const List<String> _equipementsMeublesOptionnels = [
    'Lave-vaisselle',
    'Machine à laver',
    'Sèche-linge',
    'Aspirateur',
    'Télévision',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? BailType.vide;
    _dateDebut = e?.dateDebut ?? DateTime.now();
    _dureeMois = TextEditingController(
        text: '${e?.dureeMois ?? _type.dureeDefautMois}');
    _loyerHC = TextEditingController(
        text: e == null
            ? widget.logement.loyerHC.toStringAsFixed(2)
            : e.loyerHC.toStringAsFixed(2));
    _charges = TextEditingController(
        text: e == null
            ? widget.logement.charges.toStringAsFixed(2)
            : e.charges.toStringAsFixed(2));
    final defaultDepot = e?.depotGarantie ??
        widget.logement.loyerHC * _type.plafondDepotMois;
    _depot = TextEditingController(text: defaultDepot.toStringAsFixed(2));
    _jourEcheance =
        TextEditingController(text: '${e?.jourEcheance ?? 5}');
    _rib = TextEditingController(text: e?.rib ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _justifMobilite =
        TextEditingController(text: e?.justificatifMobilite ?? '');
    _noteAnimaux = TextEditingController(text: e?.noteAnimaux ?? '');
    _modePaiement = e?.modePaiement ?? ModePaiement.virement;
    _revisionIRL = e?.revisionAnnuelleIRL ?? true;
    _nonFumeur = e?.nonFumeur ?? false;
    _animaux = e?.animauxAutorises ?? false;
    _solidariteColo = e?.clauseSolidariteColo ?? true;
    _chargesIncluses = e?.chargesIncluses ?? false;
    if (e != null) _selectedLocataireIds.addAll(e.locataireIds);
    _referentColo = e?.referentColocataireId;

    _equipements = <String, bool>{
      for (final eq in _equipementsMeublesObligatoires) eq: true,
      for (final eq in _equipementsMeublesOptionnels) eq: false,
    };
    if (e != null) {
      _equipements.addAll(e.equipementsMeuble);
    }
  }

  @override
  void dispose() {
    _dureeMois.dispose();
    _loyerHC.dispose();
    _charges.dispose();
    _depot.dispose();
    _jourEcheance.dispose();
    _rib.dispose();
    _notes.dispose();
    _justifMobilite.dispose();
    _noteAnimaux.dispose();
    super.dispose();
  }

  void _onTypeChanged(BailType v) {
    setState(() {
      _type = v;
      _dureeMois.text = '${v.dureeDefautMois}';
      // Ajuste le dépôt au plafond légal du nouveau type.
      final loyer = double.tryParse(_loyerHC.text.replaceAll(',', '.')) ?? 0;
      _depot.text = (loyer * v.plafondDepotMois).toStringAsFixed(2);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateDebut,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 20),
    );
    if (picked != null) setState(() => _dateDebut = picked);
  }

  Future<void> _save({required bool openDetail}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocataireIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionne au moins un locataire')),
      );
      return;
    }
    final svc = context.read<ContratBailService>();
    final dureeMois = int.tryParse(_dureeMois.text) ?? _type.dureeDefautMois;
    final dateFin = DateTime(
      _dateDebut.year + ((_dateDebut.month - 1 + dureeMois) ~/ 12),
      ((_dateDebut.month - 1 + dureeMois) % 12) + 1,
      _dateDebut.day,
    );
    final loyer = double.parse(_loyerHC.text.replaceAll(',', '.'));
    final charges = double.parse(_charges.text.replaceAll(',', '.'));
    final depot = double.parse(_depot.text.replaceAll(',', '.'));
    final jour = int.tryParse(_jourEcheance.text) ?? 5;

    final existing = widget.existing;
    final contrat = existing ??
        ContratBail.create(
          type: _type,
          logementId: widget.logement.id,
          locataireIds: _selectedLocataireIds.toList(),
          adresseLogement:
              '${widget.logement.adresse}, ${widget.logement.codePostal} ${widget.logement.ville}',
          surfaceM2: widget.logement.surface,
          nbPieces: widget.logement.nbPieces,
          dateDebut: _dateDebut,
          loyerHC: loyer,
          charges: charges,
          depotGarantie: depot,
          modePaiement: _modePaiement,
          jourEcheance: jour,
          rib: _rib.text.trim().isEmpty ? null : _rib.text.trim(),
        );
    contrat.type = _type;
    contrat.locataireIds = _selectedLocataireIds.toList();
    contrat.referentColocataireId = _referentColo;
    contrat.adresseLogement =
        '${widget.logement.adresse}, ${widget.logement.codePostal} ${widget.logement.ville}';
    contrat.surfaceM2 = widget.logement.surface;
    contrat.nbPieces = widget.logement.nbPieces;
    contrat.dateDebut = _dateDebut;
    contrat.dureeMois = dureeMois;
    contrat.dateFin = dateFin;
    contrat.preavisBailleurMois = _type.preavisBailleurMois;
    contrat.preavisLocataireMois = _type.preavisLocataireMois;
    contrat.renouvellementTacite = _type.renouvellementTaciteParDefaut;
    contrat.loyerHC = loyer;
    contrat.charges = charges;
    contrat.modePaiement = _modePaiement;
    contrat.rib = _rib.text.trim().isEmpty ? null : _rib.text.trim();
    contrat.jourEcheance = jour;
    contrat.depotGarantie = depot;
    contrat.revisionAnnuelleIRL = _revisionIRL;
    contrat.nonFumeur = _nonFumeur;
    contrat.animauxAutorises = _animaux;
    contrat.noteAnimaux =
        _noteAnimaux.text.trim().isEmpty ? null : _noteAnimaux.text.trim();
    contrat.clauseSolidariteColo = _solidariteColo;
    contrat.equipementsMeuble = Map<String, bool>.from(_equipements);
    contrat.chargesIncluses = _chargesIncluses;
    contrat.justificatifMobilite =
        _justifMobilite.text.trim().isEmpty ? null : _justifMobilite.text.trim();
    contrat.notes = _notes.text.trim();

    await svc.save(contrat);
    if (!mounted) return;
    if (openDetail) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ContratBailDetailScreen(bailId: contrat.id),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locataires = context.watch<LocataireService>().all
        .where((l) => l.logementIds.contains(widget.logement.id))
        .toList();
    final dateFmt = DateFormat('dd MMMM yyyy', 'fr_FR');
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Modifier le bail' : 'Nouveau bail'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Section('Type de bail'),
            DropdownButtonFormField<BailType>(
              initialValue: _type,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
              items: BailType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _onTypeChanged(v);
              },
            ),
            const SizedBox(height: 16),
            _Section('Locataire(s)'),
            if (locataires.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Aucun locataire rattaché à ce logement. Va dans Mes '
                  'locataires pour en ajouter, puis reviens créer le bail.',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
              for (final l in locataires)
                CheckboxListTile(
                  value: _selectedLocataireIds.contains(l.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedLocataireIds.add(l.id);
                    } else {
                      _selectedLocataireIds.remove(l.id);
                      if (_referentColo == l.id) _referentColo = null;
                    }
                  }),
                  title: Text(l.fullName),
                  subtitle: Text(l.email),
                  contentPadding: EdgeInsets.zero,
                ),
            if (_type == BailType.colocation &&
                _selectedLocataireIds.length > 1) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _referentColo,
                decoration: const InputDecoration(
                  labelText: 'Référent colocataire (optionnel)',
                  prefixIcon: Icon(Icons.star_outline),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Aucun')),
                  ...locataires
                      .where((l) => _selectedLocataireIds.contains(l.id))
                      .map(
                        (l) => DropdownMenuItem<String?>(
                          value: l.id,
                          child: Text(l.fullName),
                        ),
                      ),
                ],
                onChanged: (v) => setState(() => _referentColo = v),
              ),
            ],
            const SizedBox(height: 16),
            _Section('Durée'),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date d\'effet *',
                  prefixIcon: Icon(Icons.event_outlined),
                ),
                child: Text(dateFmt.format(_dateDebut)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dureeMois,
              decoration: const InputDecoration(
                labelText: 'Durée (mois) *',
                helperText: 'Vide : 36 · Meublé : 12 · Saisonnier : ≤ 3 · '
                    'Mobilité : 1 à 10',
                helperMaxLines: 2,
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            _Section('Loyer et charges'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _loyerHC,
                    decoration: const InputDecoration(
                      labelText: 'Loyer HC *',
                      suffixText: '€',
                      prefixIcon: Icon(Icons.euro),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _charges,
                    decoration: const InputDecoration(
                      labelText: 'Charges *',
                      suffixText: '€',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ModePaiement>(
              initialValue: _modePaiement,
              decoration: const InputDecoration(
                labelText: 'Mode de paiement',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: ModePaiement.values
                  .map((m) =>
                      DropdownMenuItem(value: m, child: Text(m.label)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _modePaiement = v ?? _modePaiement),
            ),
            if (_modePaiement == ModePaiement.virement ||
                _modePaiement == ModePaiement.prelevement) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _rib,
                decoration: const InputDecoration(
                  labelText: 'RIB du bailleur (IBAN)',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _jourEcheance,
              decoration: const InputDecoration(
                labelText: 'Jour d\'échéance (1-31)',
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _depot,
              decoration: InputDecoration(
                labelText: 'Dépôt de garantie *',
                helperText:
                    'Plafond légal : ${_type.plafondDepotMois} mois de loyer HC.',
                suffixText: '€',
                prefixIcon: const Icon(Icons.savings_outlined),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            _Section('Clauses spécifiques'),
            CheckboxListTile(
              value: _revisionIRL,
              onChanged: (v) =>
                  setState(() => _revisionIRL = v ?? _revisionIRL),
              title: const Text('Révision annuelle selon l\'IRL'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _nonFumeur,
              onChanged: (v) => setState(() => _nonFumeur = v ?? _nonFumeur),
              title: const Text('Logement non-fumeur'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _animaux,
              onChanged: (v) => setState(() => _animaux = v ?? _animaux),
              title: const Text('Animaux domestiques autorisés'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_animaux)
              TextFormField(
                controller: _noteAnimaux,
                decoration: const InputDecoration(
                  labelText: 'Conditions sur les animaux',
                ),
              ),
            if (_type == BailType.colocation) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _solidariteColo,
                onChanged: (v) =>
                    setState(() => _solidariteColo = v ?? _solidariteColo),
                title: const Text('Clause de solidarité entre colocataires'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (_type == BailType.saisonnier) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _chargesIncluses,
                onChanged: (v) =>
                    setState(() => _chargesIncluses = v ?? _chargesIncluses),
                title:
                    const Text('Charges incluses dans le loyer (saisonnier)'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (_type == BailType.mobilite) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _justifMobilite,
                decoration: const InputDecoration(
                  labelText: 'Justificatif de mobilité',
                  helperText: 'Ex : étudiant, mission temporaire, formation…',
                  prefixIcon: Icon(Icons.work_history_outlined),
                ),
              ),
            ],
            if (_type == BailType.meuble) ...[
              const SizedBox(height: 16),
              _Section('Équipements obligatoires (décret n°2015-981)'),
              for (final eq in _equipementsMeublesObligatoires)
                CheckboxListTile(
                  value: _equipements[eq] ?? false,
                  onChanged: (v) =>
                      setState(() => _equipements[eq] = v ?? false),
                  title: Text(eq),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              const SizedBox(height: 8),
              _Section('Équipements optionnels'),
              for (final eq in _equipementsMeublesOptionnels)
                CheckboxListTile(
                  value: _equipements[eq] ?? false,
                  onChanged: (v) =>
                      setState(() => _equipements[eq] = v ?? false),
                  title: Text(eq),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
            const SizedBox(height: 16),
            _Section('Notes additionnelles'),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                helperText: 'Apparaîtra dans les mentions légales du PDF.',
              ),
              minLines: 2,
              maxLines: 6,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Enregistrer et ouvrir',
              icon: Icons.check_circle_outline,
              onPressed: () => _save(openDetail: true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _save(openDetail: false),
              child: const Text('Enregistrer et fermer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
