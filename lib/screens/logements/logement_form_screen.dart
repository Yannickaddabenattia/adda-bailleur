import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../models/country.dart';
import '../../models/logement.dart';
import '../../models/sci.dart';
import '../../services/fiscalite_service.dart';
import '../../services/logement_service.dart';
import '../../services/sci_service.dart';
import '../../widgets/primary_button.dart';
import 'widgets/country_section.dart';

class LogementFormScreen extends StatefulWidget {
  final Logement? logement;
  const LogementFormScreen({super.key, this.logement});

  @override
  State<LogementFormScreen> createState() => _LogementFormScreenState();
}

class _LogementFormScreenState extends State<LogementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _libelle;
  late TextEditingController _adresse;
  late TextEditingController _codePostal;
  late TextEditingController _ville;
  late TextEditingController _surface;
  late TextEditingController _nbPieces;
  late TextEditingController _loyerHC;
  late TextEditingController _charges;
  late TextEditingController _equipements;
  late TextEditingController _notes;
  late TextEditingController _prixRevient;
  late TextEditingController _amortissementAnnuel;
  late TextEditingController _anneeConstruction;
  late LogementType _type;
  late StatutFiscal _statutFiscal;
  late RegimeFiscal _regimeFiscal;
  late DispositifFiscal _dispositif;
  DateTime? _dateAcquisition;
  DateTime? _dateDebutDispositif;
  DateTime? _dateFinDispositif;
  late int _dureeEngagement;
  String? _sciId;
  DateTime? _datePermis;
  DateTime? _dateElec;
  DateTime? _dateGaz;
  TypeAssainissement _assainissement = TypeAssainissement.inconnu;
  bool _zoneTermites = false;
  RegimeLmnp _regimeLmnp = RegimeLmnp.microBIC;
  bool _enRenovationEnergetique = false;
  DpeClasse? _dpeClasse;
  bool _saving = false;

  // ─── Multi-pays (visible si AppConstants.multiPaysActif) ──────────────────
  late Country _country;
  BeRegion? _beRegion;
  ChCanton? _chCanton;
  late TextEditingController _revenuCadastral;
  late TextEditingController _precompteImmo;
  late TextEditingController _valeurFiscale;
  late TextEditingController _tauxFoncierPourMille;
  late TextEditingController _tauxReferenceContrat;

  bool get _isEdit => widget.logement != null;

  @override
  void initState() {
    super.initState();
    final l = widget.logement;
    _libelle = TextEditingController(text: l?.libelle ?? '');
    _adresse = TextEditingController(text: l?.adresse ?? '');
    _codePostal = TextEditingController(text: l?.codePostal ?? '');
    _ville = TextEditingController(text: l?.ville ?? '');
    _surface = TextEditingController(
        text: l == null ? '' : l.surface.toStringAsFixed(0));
    _nbPieces =
        TextEditingController(text: l == null ? '' : l.nbPieces.toString());
    _loyerHC = TextEditingController(
        text: l == null ? '' : l.loyerHC.toStringAsFixed(2));
    _charges = TextEditingController(
        text: l == null ? '' : l.charges.toStringAsFixed(2));
    _equipements =
        TextEditingController(text: l?.equipements.join(', ') ?? '');
    _notes = TextEditingController(text: l?.notes ?? '');
    _prixRevient = TextEditingController(
        text: l == null || l.prixRevient == 0
            ? ''
            : l.prixRevient.toStringAsFixed(0));
    _amortissementAnnuel = TextEditingController(
        text: l == null || l.amortissementAnnuel == 0
            ? ''
            : l.amortissementAnnuel.toStringAsFixed(2));
    _type = l?.type ?? LogementType.appartement;
    _statutFiscal = l?.statutFiscal ?? StatutFiscal.locationNue;
    _regimeFiscal = l?.regimeFiscal ?? RegimeFiscal.reel;
    _dispositif = l?.dispositif ?? DispositifFiscal.aucun;
    _dateAcquisition = l?.dateAcquisition;
    _dateDebutDispositif = l?.dateDebutDispositif;
    _dateFinDispositif = l?.dateFinDispositif;
    _dureeEngagement = l?.dureeEngagementAnnees ?? 9;
    _sciId = l?.sciId;
    _anneeConstruction =
        TextEditingController(text: l?.anneeConstruction?.toString() ?? '');
    _datePermis = l?.datePermisConstruire;
    _dateElec = l?.dateInstallationElectrique;
    _dateGaz = l?.dateInstallationGaz;
    _assainissement = l?.typeAssainissement ?? TypeAssainissement.inconnu;
    _zoneTermites = l?.zoneTermites ?? false;
    _regimeLmnp = l?.regimeLmnp ?? RegimeLmnp.microBIC;
    _enRenovationEnergetique = l?.enRenovationEnergetique ?? false;
    _dpeClasse = l?.dpeClasse;
    _country = l?.country ?? Country.france;
    _beRegion = l?.beRegion;
    _chCanton = l?.chCanton;
    _revenuCadastral = TextEditingController(text: _numStr(l?.revenuCadastral));
    _precompteImmo =
        TextEditingController(text: _numStr(l?.precompteImmobilierAnnuel));
    _valeurFiscale = TextEditingController(text: _numStr(l?.valeurFiscale));
    _tauxFoncierPourMille =
        TextEditingController(text: _numStr(l?.tauxImpotFoncierPourMille));
    _tauxReferenceContrat = TextEditingController(
        text: _numStr(l?.tauxReferenceContrat == null
            ? null
            : l!.tauxReferenceContrat! * 100)); // stocké en fraction, saisi en %
  }

  static String _numStr(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  }

  /// Parse un champ numérique nullable (virgule décimale tolérée).
  double? _d(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  @override
  void dispose() {
    _libelle.dispose();
    _adresse.dispose();
    _codePostal.dispose();
    _ville.dispose();
    _surface.dispose();
    _nbPieces.dispose();
    _loyerHC.dispose();
    _charges.dispose();
    _equipements.dispose();
    _notes.dispose();
    _prixRevient.dispose();
    _amortissementAnnuel.dispose();
    _anneeConstruction.dispose();
    _revenuCadastral.dispose();
    _precompteImmo.dispose();
    _valeurFiscale.dispose();
    _tauxFoncierPourMille.dispose();
    _tauxReferenceContrat.dispose();
    super.dispose();
  }

  /// Applique les champs multi-pays à [l] (pays, région/canton, devise, valeurs
  /// spécifiques BE/CH). Sans effet fonctionnel tant que `multiPaysActif` est
  /// `false` : le pays reste France / EUR par défaut.
  void _applyCountryFields(Logement l) {
    l.country = _country;
    l.beRegion = _country == Country.belgique ? _beRegion : null;
    l.chCanton = _country == Country.suisse ? _chCanton : null;
    l.currencyCode = _country.defaultCurrency;
    l.revenuCadastral = _country == Country.belgique ? _d(_revenuCadastral) : null;
    l.precompteImmobilierAnnuel =
        _country == Country.belgique ? _d(_precompteImmo) : null;
    l.valeurFiscale = _country == Country.suisse ? _d(_valeurFiscale) : null;
    l.tauxImpotFoncierPourMille =
        _country == Country.suisse ? _d(_tauxFoncierPourMille) : null;
    // Taux de référence saisi en % → stocké en fraction (1,50 % → 0,015).
    final tauxRefPct = _country == Country.suisse ? _d(_tauxReferenceContrat) : null;
    l.tauxReferenceContrat = tauxRefPct == null ? null : tauxRefPct / 100;
  }

  Future<DateTime?> _pickDiagDate(DateTime? current) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      locale: const Locale('fr', 'FR'),
    );
  }

  Widget _diagDateField({
    required String label,
    String? helper,
    required DateTime? date,
    required void Function(DateTime) onPicked,
    required VoidCallback onClear,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final d = await _pickDiagDate(date);
        if (d != null) onPicked(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: date == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          date == null
              ? 'Non renseignée'
              : '${date.day.toString().padLeft(2, '0')}/'
                  '${date.month.toString().padLeft(2, '0')}/${date.year}',
        ),
      ),
    );
  }

  Future<void> _pickDateAcquisition() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateAcquisition ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2014, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Date d\'acquisition',
    );
    if (picked != null) {
      setState(() => _dateAcquisition = picked);
    }
  }

  Future<void> _pickDateDebutDispositif() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dateDebutDispositif ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(now.year + 20, 12, 31),
      helpText: 'Début du dispositif',
    );
    if (picked != null) {
      setState(() => _dateDebutDispositif = picked);
    }
  }

  Future<void> _pickDateFinDispositif() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFinDispositif ??
          (_dateDebutDispositif != null
              ? DateTime(_dateDebutDispositif!.year + 9,
                  _dateDebutDispositif!.month, _dateDebutDispositif!.day)
              : DateTime(now.year + 9, now.month, now.day)),
      firstDate: _dateDebutDispositif ?? DateTime(2000, 1, 1),
      lastDate: DateTime(now.year + 50, 12, 31),
      helpText: 'Fin du dispositif',
    );
    if (picked != null) {
      setState(() => _dateFinDispositif = picked);
    }
  }

  List<String> _parseEquipements(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dispositif.isPinelDenormandie && _dateAcquisition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date d\'acquisition requise')),
      );
      return;
    }
    if (_dispositif.isBorloo &&
        (_dateDebutDispositif == null || _dateFinDispositif == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Borloo Ancien : dates de début et fin requises')),
      );
      return;
    }
    if (_dateDebutDispositif != null &&
        _dateFinDispositif != null &&
        _dateFinDispositif!.isBefore(_dateDebutDispositif!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'La date de fin doit être après la date de début')),
      );
      return;
    }
    setState(() => _saving = true);

    final service = context.read<LogementService>();
    try {
      if (_isEdit) {
        final l = widget.logement!;
        l.libelle = _libelle.text.trim();
        l.adresse = _adresse.text.trim();
        l.codePostal = _codePostal.text.trim();
        l.ville = _ville.text.trim();
        l.type = _type;
        l.surface = double.parse(_surface.text.replaceAll(',', '.'));
        l.nbPieces = int.parse(_nbPieces.text);
        l.loyerHC = double.parse(_loyerHC.text.replaceAll(',', '.'));
        l.charges = double.parse(_charges.text.replaceAll(',', '.'));
        l.equipements = _parseEquipements(_equipements.text);
        l.notes = _notes.text.trim();
        l.statutFiscal = _statutFiscal;
        l.regimeFiscal = _regimeFiscal;
        l.dispositif = _dispositif;
        l.dateAcquisition = _dateAcquisition;
        l.dureeEngagementAnnees = _dureeEngagement;
        l.prixRevient = _prixRevient.text.trim().isEmpty
            ? 0
            : double.parse(_prixRevient.text.replaceAll(',', '.'));
        l.sciId = _statutFiscal == StatutFiscal.sci ? _sciId : null;
        l.amortissementAnnuel = _amortissementAnnuel.text.trim().isEmpty
            ? 0
            : double.parse(_amortissementAnnuel.text.replaceAll(',', '.'));
        l.dateDebutDispositif =
            _dispositif == DispositifFiscal.aucun ? null : _dateDebutDispositif;
        l.dateFinDispositif =
            _dispositif == DispositifFiscal.aucun ? null : _dateFinDispositif;
        l.anneeConstruction = int.tryParse(_anneeConstruction.text.trim());
        l.datePermisConstruire = _datePermis;
        l.dateInstallationElectrique = _dateElec;
        l.dateInstallationGaz = _dateGaz;
        l.typeAssainissement = _assainissement;
        l.zoneTermites = _zoneTermites;
        l.regimeLmnp = _regimeLmnp;
        l.enRenovationEnergetique = _enRenovationEnergetique;
        l.dpeClasse = _dpeClasse;
        _applyCountryFields(l);
        await service.update(l);
      } else {
        final logement = Logement.create(
          libelle: _libelle.text,
          adresse: _adresse.text,
          codePostal: _codePostal.text,
          ville: _ville.text,
          type: _type,
          surface: double.parse(_surface.text.replaceAll(',', '.')),
          nbPieces: int.parse(_nbPieces.text),
          loyerHC: double.parse(_loyerHC.text.replaceAll(',', '.')),
          charges: double.parse(_charges.text.replaceAll(',', '.')),
          equipements: _parseEquipements(_equipements.text),
          notes: _notes.text,
          statutFiscal: _statutFiscal,
          regimeFiscal: _regimeFiscal,
          dispositif: _dispositif,
          dateAcquisition: _dateAcquisition,
          dureeEngagementAnnees: _dureeEngagement,
          prixRevient: _prixRevient.text.trim().isEmpty
              ? 0
              : double.parse(_prixRevient.text.replaceAll(',', '.')),
        );
        logement.sciId = _statutFiscal == StatutFiscal.sci ? _sciId : null;
        logement.amortissementAnnuel =
            _amortissementAnnuel.text.trim().isEmpty
                ? 0
                : double.parse(_amortissementAnnuel.text.replaceAll(',', '.'));
        logement.dateDebutDispositif =
            _dispositif == DispositifFiscal.aucun ? null : _dateDebutDispositif;
        logement.dateFinDispositif =
            _dispositif == DispositifFiscal.aucun ? null : _dateFinDispositif;
        logement.anneeConstruction =
            int.tryParse(_anneeConstruction.text.trim());
        logement.datePermisConstruire = _datePermis;
        logement.dateInstallationElectrique = _dateElec;
        logement.dateInstallationGaz = _dateGaz;
        logement.typeAssainissement = _assainissement;
        logement.zoneTermites = _zoneTermites;
        logement.regimeLmnp = _regimeLmnp;
        logement.enRenovationEnergetique = _enRenovationEnergetique;
        logement.dpeClasse = _dpeClasse;
        _applyCountryFields(logement);
        await service.add(logement);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier le logement' : 'Nouveau logement'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (AppConstants.multiPaysActif) ...[
                _Section(title: 'Localisation fiscale'),
                const SizedBox(height: 8),
                CountrySection(
                  country: _country,
                  beRegion: _beRegion,
                  chCanton: _chCanton,
                  revenuCadastral: _revenuCadastral,
                  precompteImmo: _precompteImmo,
                  valeurFiscale: _valeurFiscale,
                  tauxFoncierPourMille: _tauxFoncierPourMille,
                  tauxReferenceContrat: _tauxReferenceContrat,
                  onCountry: (c) => setState(() => _country = c),
                  onRegion: (r) => setState(() => _beRegion = r),
                  onCanton: (c) => setState(() => _chCanton = c),
                ),
                const SizedBox(height: 24),
              ],
              _Section(title: 'Identification'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _libelle,
                decoration: const InputDecoration(
                  labelText: 'Libellé *',
                  hintText: 'Ex: Appartement République',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Libellé requis' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LogementType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Type *',
                  prefixIcon: Icon(Icons.home_work_outlined),
                ),
                items: LogementType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 20),
              _Section(title: 'Adresse'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _adresse,
                decoration: const InputDecoration(
                  labelText: 'Adresse *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v?.trim().length ?? 0) < 3 ? 'Adresse requise' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      controller: _codePostal,
                      decoration: const InputDecoration(
                        labelText: 'CP *',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      validator: (v) =>
                          (v?.length ?? 0) != 5 ? 'CP sur 5 chiffres' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _ville,
                      decoration: const InputDecoration(
                        labelText: 'Ville *',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v?.trim().length ?? 0) < 2
                          ? 'Ville requise'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(title: 'Caractéristiques'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _surface,
                      decoration: const InputDecoration(
                        labelText: 'Surface (m²) *',
                        prefixIcon: Icon(Icons.square_foot),
                      ),
                      keyboardType: TextInputType.number,
                      validator: _numberValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nbPieces,
                      decoration: const InputDecoration(
                        labelText: 'Pièces *',
                        prefixIcon: Icon(Icons.door_front_door_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _numberValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(title: 'Diagnostics — caractéristiques'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _anneeConstruction,
                decoration: const InputDecoration(
                  labelText: 'Année de construction',
                  helperText: 'Plomb obligatoire si avant 1949.',
                  prefixIcon: Icon(Icons.foundation_outlined),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              _diagDateField(
                label: 'Permis de construire',
                helper: 'Amiante obligatoire si avant juillet 1997.',
                date: _datePermis,
                onPicked: (d) => setState(() => _datePermis = d),
                onClear: () => setState(() => _datePermis = null),
              ),
              const SizedBox(height: 12),
              _diagDateField(
                label: 'Installation électrique',
                helper: 'Diagnostic élec si plus de 15 ans.',
                date: _dateElec,
                onPicked: (d) => setState(() => _dateElec = d),
                onClear: () => setState(() => _dateElec = null),
              ),
              const SizedBox(height: 12),
              _diagDateField(
                label: 'Installation de gaz',
                helper: 'Diagnostic gaz si plus de 15 ans.',
                date: _dateGaz,
                onPicked: (d) => setState(() => _dateGaz = d),
                onClear: () => setState(() => _dateGaz = null),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TypeAssainissement>(
                initialValue: _assainissement,
                decoration: const InputDecoration(
                  labelText: 'Assainissement',
                  prefixIcon: Icon(Icons.water_drop_outlined),
                ),
                items: TypeAssainissement.values
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _assainissement = v ?? _assainissement),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DpeClasse?>(
                initialValue: _dpeClasse,
                decoration: const InputDecoration(
                  labelText: 'Classe DPE',
                  helperText:
                      'F/G : gel des loyers · classe G interdite à la location dès 2025',
                  prefixIcon: Icon(Icons.bolt_outlined),
                ),
                items: [
                  const DropdownMenuItem<DpeClasse?>(
                    value: null,
                    child: Text('Non renseignée'),
                  ),
                  for (final c in DpeClasse.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _dpeClasse = v),
              ),
              SwitchListTile(
                value: _zoneTermites,
                onChanged: (v) => setState(() => _zoneTermites = v),
                title: const Text('Zone à risque termites'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              _Section(title: 'Loyer'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _loyerHC,
                      decoration: const InputDecoration(
                        labelText: 'Loyer HC *',
                        suffixText: '€',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _numberValidator,
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
                      keyboardType: TextInputType.number,
                      validator: _numberValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(title: 'Fiscalité'),
              const SizedBox(height: 8),
              DropdownButtonFormField<StatutFiscal>(
                initialValue: _statutFiscal,
                decoration: const InputDecoration(
                  labelText: 'Statut fiscal',
                  prefixIcon: Icon(Icons.calculate_outlined),
                ),
                items: StatutFiscal.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _statutFiscal = v ?? _statutFiscal),
              ),
              if (_statutFiscal == StatutFiscal.locationNue) ...[
                const SizedBox(height: 12),
                _RegimeAutoInfo(statut: _statutFiscal),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rénovation énergétique en cours'),
                  subtitle: const Text(
                    'Déficit foncier renforcé à 21 400 € (DPE E/F/G → A/B/C/D).',
                  ),
                  value: _enRenovationEnergetique,
                  onChanged: (v) =>
                      setState(() => _enRenovationEnergetique = v),
                ),
              ],
              if (_statutFiscal == StatutFiscal.lmnp ||
                  _statutFiscal == StatutFiscal.lmp ||
                  _statutFiscal == StatutFiscal.viagerLmnp) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<RegimeLmnp>(
                  decoration: const InputDecoration(
                    labelText: 'Régime LMNP / LMP',
                  ),
                  initialValue: _regimeLmnp,
                  items: RegimeLmnp.values
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r.label),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _regimeLmnp = v ?? _regimeLmnp),
                ),
                const SizedBox(height: 12),
                _RegimeAutoInfo(statut: _statutFiscal),
              ],
              if (_statutFiscal == StatutFiscal.sci) ...[
                const SizedBox(height: 12),
                _SciSelector(
                  selectedSciId: _sciId,
                  onChanged: (id) => setState(() => _sciId = id),
                ),
                Builder(builder: (ctx) {
                  final sci = ctx.watch<SCIService>().byId(_sciId);
                  if (sci == null) return const SizedBox.shrink();
                  final year = DateTime.now().year;
                  final regimeAnneeCourante = sci.regimeForYear(year);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      _RegimeAutoInfo(
                          statut: _statutFiscal,
                          sciRegime: regimeAnneeCourante),
                      if (regimeAnneeCourante == SCIRegime.is_) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _amortissementAnnuel,
                          decoration: const InputDecoration(
                            labelText: 'Amortissement annuel',
                            helperText:
                                'Bâti uniquement, hors terrain. Déductible '
                                'du bénéfice IS de la SCI.',
                            helperMaxLines: 2,
                            suffixText: '€',
                            prefixIcon: Icon(Icons.trending_down_outlined),
                          ),
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                        ),
                      ],
                    ],
                  );
                }),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<DispositifFiscal>(
                initialValue: _dispositif,
                decoration: const InputDecoration(
                  labelText: 'Dispositif de défiscalisation',
                  prefixIcon: Icon(Icons.discount_outlined),
                ),
                items: DispositifFiscal.values
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.label),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _dispositif = v ?? _dispositif),
              ),
              if (_dispositif.isBorloo) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Abattement Borloo : '
                          '${(_dispositif.tauxAbattementBorloo * 100).toStringAsFixed(0)} % '
                          'sur les recettes brutes de ce logement, appliqué '
                          'avant déduction des charges. Force le régime réel.',
                          style: const TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_dispositif != DispositifFiscal.aucun) ...[
                const SizedBox(height: 12),
                _DateRangePickers(
                  required: _dispositif.isBorloo,
                  dateDebut: _dateDebutDispositif,
                  dateFin: _dateFinDispositif,
                  onPickDebut: _pickDateDebutDispositif,
                  onPickFin: _pickDateFinDispositif,
                  onClear: () => setState(() {
                    _dateDebutDispositif = null;
                    _dateFinDispositif = null;
                  }),
                ),
              ],
              if (_dispositif.isPinelDenormandie) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDateAcquisition,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date d\'acquisition *',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(
                      _dateAcquisition == null
                          ? 'Sélectionner…'
                          : '${_dateAcquisition!.day.toString().padLeft(2, '0')}/'
                              '${_dateAcquisition!.month.toString().padLeft(2, '0')}/'
                              '${_dateAcquisition!.year}',
                      style: TextStyle(
                        color: _dateAcquisition == null
                            ? AppColors.textSecondary
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _dureeEngagement,
                  decoration: const InputDecoration(
                    labelText: 'Durée d\'engagement',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 6, child: Text('6 ans')),
                    DropdownMenuItem(value: 9, child: Text('9 ans')),
                    DropdownMenuItem(value: 12, child: Text('12 ans')),
                  ],
                  onChanged: (v) =>
                      setState(() => _dureeEngagement = v ?? _dureeEngagement),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prixRevient,
                  decoration: const InputDecoration(
                    labelText: 'Prix de revient *',
                    helperText:
                        'Plafonné automatiquement à 300 000 € et 5 500 €/m².',
                    suffixText: '€',
                    prefixIcon: Icon(Icons.euro_outlined),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Prix de revient requis';
                    }
                    final p = double.tryParse(v.replaceAll(',', '.'));
                    if (p == null || p <= 0) return 'Montant invalide';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 20),
              _Section(title: 'Optionnel'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _equipements,
                decoration: const InputDecoration(
                  labelText: 'Équipements (séparés par des virgules)',
                  hintText: 'Chauffage, Balcon, Parking',
                  prefixIcon: Icon(Icons.checklist_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: _isEdit ? 'Enregistrer' : 'Créer le logement',
                icon: Icons.check,
                loading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Requis';
    final parsed = double.tryParse(v.replaceAll(',', '.'));
    if (parsed == null) return 'Nombre invalide';
    if (parsed < 0) return 'Doit être positif';
    return null;
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// Bandeau informatif affichant le régime fiscal auto-détecté pour le foyer
/// (location nue → micro-foncier / réel selon recettes 15 000 € ; LMNP →
/// micro-BIC 50 %). Le calcul est fait sur l'année en cours pour donner un
/// aperçu en temps réel.
class _RegimeAutoInfo extends StatelessWidget {
  final StatutFiscal statut;
  final SCIRegime? sciRegime;
  const _RegimeAutoInfo({required this.statut, this.sciRegime});

  @override
  Widget build(BuildContext context) {
    final fisc = context.watch<FiscaliteService>();
    final year = DateTime.now().year;

    final String label;
    final String detail;
    final IconData icon;
    final Color color;

    if (statut == StatutFiscal.locationNue) {
      final regime = fisc.regimeNuApplique(year);
      final eligible = fisc.eligibleMicroFoncier(year);
      if (regime == RegimeFiscal.microFoncier) {
        label = 'Régime auto : Micro-foncier (abattement 30 %)';
        detail = 'Recettes foyer ≤ 15 000 € et aucun Pinel/Denormandie '
            'sur les logements nus → micro-foncier appliqué.';
        icon = Icons.auto_awesome;
        color = AppColors.success;
      } else {
        label = 'Régime auto : Réel';
        detail = eligible
            ? 'Régime réel appliqué (par défaut).'
            : 'Régime réel obligatoire : recettes > 15 000 € OU un logement '
                'nu est sous Pinel/Denormandie OU une SCI est présente.';
        icon = Icons.balance;
        color = AppColors.primary;
      }
    } else if (statut == StatutFiscal.lmnp) {
      label = 'Régime auto : Micro-BIC (abattement 50 %)';
      detail = 'Location meublée non pro. Limite 77 700 €/an avant '
          'basculement obligatoire au BIC réel (non géré pour l\'instant).';
      icon = Icons.auto_awesome;
      color = AppColors.success;
    } else if (statut == StatutFiscal.sci) {
      if (sciRegime == SCIRegime.is_) {
        label = 'SCI à l\'IS : impôt sociétés séparé';
        detail =
            'Ce logement est détenu par une SCI à l\'IS. Le bénéfice de la '
            'SCI est imposé à l\'IS (15 % jusqu\'à 42 500 €, 25 % au-delà). '
            'Les dividendes distribués sont soumis au PFU 30 % côté '
            'associés. Ce bien est exclu du calcul foncier du foyer.';
        icon = Icons.business_outlined;
        color = AppColors.accent;
      } else {
        label = 'SCI à l\'IR : transparente fiscalement';
        detail =
            'Le revenu de ce logement est intégré à la déclaration foncière '
            'personnelle (régime réel imposé : le micro-foncier n\'est pas '
            'ouvert aux SCI dans cette app).';
        icon = Icons.business_outlined;
        color = AppColors.primary;
      }
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
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

/// Deux date pickers côte à côte (« Du » / « Au ») pour borner la période
/// d'application d'un dispositif fiscal. [required] est utilisé pour
/// indiquer à l'utilisateur que les dates sont obligatoires (cas Borloo).
class _DateRangePickers extends StatelessWidget {
  final bool required;
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final VoidCallback onPickDebut;
  final VoidCallback onPickFin;
  final VoidCallback onClear;

  const _DateRangePickers({
    required this.required,
    required this.dateDebut,
    required this.dateFin,
    required this.onPickDebut,
    required this.onPickFin,
    required this.onClear,
  });

  String _fmt(DateTime? d) {
    if (d == null) return 'Sélectionner…';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final suffix = required ? ' *' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            'Période de validité du dispositif',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPickDebut,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Du$suffix',
                    prefixIcon: const Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    _fmt(dateDebut),
                    style: TextStyle(
                      color: dateDebut == null
                          ? AppColors.textSecondary
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onPickFin,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Au$suffix',
                    prefixIcon: const Icon(Icons.event_busy_outlined),
                  ),
                  child: Text(
                    _fmt(dateFin),
                    style: TextStyle(
                      color: dateFin == null
                          ? AppColors.textSecondary
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!required && (dateDebut != null || dateFin != null))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Effacer les dates'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 28),
              ),
            ),
          ),
      ],
    );
  }
}

/// Dropdown pour rattacher le logement à une SCI existante. Affiche une
/// CTA discrète si aucune SCI n'est encore créée — l'utilisateur reste
/// libre de quitter le formulaire pour aller en créer une.
class _SciSelector extends StatelessWidget {
  final String? selectedSciId;
  final ValueChanged<String?> onChanged;
  const _SciSelector({
    required this.selectedSciId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scis = context.watch<SCIService>().all;
    if (scis.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.accent, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aucune SCI créée. Va dans Fiscalité → icône SCI pour en '
                'ajouter une, puis reviens ici sélectionner.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    return DropdownButtonFormField<String?>(
      initialValue: scis.any((s) => s.id == selectedSciId) ? selectedSciId : null,
      decoration: const InputDecoration(
        labelText: 'Société de détention (SCI)',
        prefixIcon: Icon(Icons.business_outlined),
      ),
      items: scis
          .map(
            (s) => DropdownMenuItem<String?>(
              value: s.id,
              child: Text('${s.nom} · ${s.regime.label}'),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
