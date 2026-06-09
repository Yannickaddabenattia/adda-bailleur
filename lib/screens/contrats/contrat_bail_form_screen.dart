import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/bail_template.dart';
import '../../models/clause.dart';
import '../../models/contrat_bail.dart';
import '../../models/garant.dart';
import '../../models/logement.dart';
import '../../services/bail_template_service.dart';
import '../../services/contrat_bail_service.dart';
import '../../services/locataire_service.dart';
import '../../widgets/primary_button.dart';
import 'contrat_bail_detail_screen.dart';

/// Formulaire de création / édition d'un contrat de bail. Conditionne les
/// champs visibles selon le type de bail sélectionné.
///
/// Lorsque [template] est fourni (sélection depuis la galerie), les valeurs
/// par défaut sont pré-remplies depuis le template : type, durée, dépôt,
/// préavis, équipements meublé, clauses pré-cochées.
class ContratBailFormScreen extends StatefulWidget {
  final Logement logement;
  final ContratBail? existing;
  final BailTemplate? template;
  const ContratBailFormScreen({
    super.key,
    required this.logement,
    this.existing,
    this.template,
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
  late TextEditingController _restitutionDepot;
  late TextEditingController _description;
  late TextEditingController _bailleurAdresse;
  late TextEditingController _bailleurTel;
  late TextEditingController _bailleurRaisonSociale;
  late TextEditingController _bailleurSiret;
  late TextEditingController _bailleurRepresentant;
  bool _bailleurEstSociete = false;
  final List<Garant> _garants = [];
  final Set<String> _activeCatalogIds = {};
  final List<Clause> _customClauses = [];
  String? _assuranceFilePath;
  final List<String> _annexes = [];
  ModePaiement _modePaiement = ModePaiement.virement;

  bool _revisionIRL = true;
  bool _nonFumeur = false;
  bool _animaux = false;
  bool _solidariteColo = true;
  bool _chargesIncluses = false;
  bool _attestationAssurance = false;
  bool _mentionEDL = false;
  bool _termeEchu = false;

  final Set<String> _selectedLocataireIds = {};
  String? _referentColo;
  String? _templateSourceId;
  DateTime? _templateAppliqueLe;

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
    _restitutionDepot =
        TextEditingController(text: e?.modalitesRestitutionDepot ?? '');
    _description =
        TextEditingController(text: e?.descriptionLogement ?? '');
    _bailleurAdresse = TextEditingController(text: e?.bailleurAdresse ?? '');
    _bailleurTel = TextEditingController(text: e?.bailleurTelephone ?? '');
    _bailleurRaisonSociale =
        TextEditingController(text: e?.bailleurRaisonSociale ?? '');
    _bailleurSiret = TextEditingController(text: e?.bailleurSiret ?? '');
    _bailleurRepresentant =
        TextEditingController(text: e?.bailleurRepresentant ?? '');
    _bailleurEstSociete = e?.bailleurEstSociete ?? false;
    if (e != null) {
      _garants.addAll(e.garants);
      for (final c in e.clauses) {
        if (c.isCustom) {
          _customClauses.add(c.copy());
        } else {
          _activeCatalogIds.add(c.id);
        }
      }
    }
    _attestationAssurance = e?.attestationAssurance ?? false;
    _mentionEDL = e?.mentionEtatDesLieux ?? false;
    _termeEchu = e?.paiementTermeEchu ?? false;
    _assuranceFilePath = e?.assuranceFilePath;
    if (e != null) _annexes.addAll(e.annexesOptionnelles);
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
      _templateSourceId = e.templateSourceId;
      _templateAppliqueLe = e.templateAppliqueLe;
    }

    // Pré-remplissage à partir d'un template (uniquement en création, pas en édition).
    final t = widget.template;
    if (e == null && t != null) {
      _type = t.typeBail;
      _dureeMois.text = '${t.dureeDefautMois}';
      final loyer = widget.logement.loyerHC;
      final depot = t.depotInterdit ? 0.0 : loyer * t.depotMultiplicateurLoyer;
      _depot.text = depot.toStringAsFixed(2);
      _justifMobilite.text = t.justificatifMobiliteRequis ? '' : '';
      // Clauses pré-cochées du template
      _activeCatalogIds.addAll(t.clausesPreCochees);
      for (final c in t.clausesPersoIncluses) {
        _customClauses.add(c.copy());
      }
      // Équipements meublé du template.
      // Note : les obligatoires sont déjà cochés par défaut à l'init (cf.
      // _equipements ci-dessus) ; ce mapping ne sert qu'à reporter des valeurs
      // explicites du template. Les libellés DOIVENT correspondre exactement
      // aux clés de _equipements, sinon le report est silencieusement ignoré.
      if (t.equipementsMeubleDefauts != null) {
        // Mapping clés sémantiques → libellés français du form
        const keyToLabel = {
          'literie': 'Literie (lit + matelas)',
          'volets_rideaux': 'Volets ou rideaux occultants (chambre)',
          'plaques_cuisson': 'Plaques de cuisson',
          'four_micro_ondes': 'Four ou micro-ondes',
          'refrigerateur': 'Réfrigérateur + congélateur',
          'congelateur': 'Réfrigérateur + congélateur',
          'vaisselle': 'Vaisselle nécessaire à la prise des repas',
          'ustensiles_cuisine': 'Ustensiles de cuisine',
          'table_sieges': 'Table et sièges',
          'luminaires': 'Luminaires',
          'menage': 'Matériel d\'entretien ménager adapté',
        };
        for (final entry in t.equipementsMeubleDefauts!.entries) {
          final lbl = keyToLabel[entry.key];
          if (lbl != null && _equipements.containsKey(lbl)) {
            _equipements[lbl] = entry.value;
          }
        }
      }
      _templateSourceId = t.id;
      _templateAppliqueLe = DateTime.now().toUtc();
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
    _restitutionDepot.dispose();
    _description.dispose();
    _bailleurAdresse.dispose();
    _bailleurTel.dispose();
    _bailleurRaisonSociale.dispose();
    _bailleurSiret.dispose();
    _bailleurRepresentant.dispose();
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

  /// Sélectionne un fichier et le copie dans le sandbox de l'app. Retourne le
  /// chemin local de la copie, ou null si annulé.
  Future<String?> _pickAttachment() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.single.path == null) return null;
    final src = File(r.files.single.path!);
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/contrats_bail/annexes');
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dest = File('${dir.path}/${stamp}_${r.files.single.name}');
    await src.copy(dest.path);
    return dest.path;
  }

  /// Ouvre un dialogue pour créer ou éditer un garant.
  Future<void> _editGarant(Garant? existing) async {
    final prenom = TextEditingController(text: existing?.prenom ?? '');
    final nom = TextEditingController(text: existing?.nom ?? '');
    final adresse = TextEditingController(text: existing?.adresse ?? '');
    final tel = TextEditingController(text: existing?.telephone ?? '');
    final email = TextEditingController(text: existing?.email ?? '');
    final revenus = TextEditingController(
      text: existing?.revenusMensuels != null
          ? existing!.revenusMensuels!.toStringAsFixed(0)
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nouveau garant' : 'Modifier le garant'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: prenom,
                  decoration: const InputDecoration(labelText: 'Prénom')),
              TextField(
                  controller: nom,
                  decoration: const InputDecoration(labelText: 'Nom')),
              TextField(
                  controller: adresse,
                  decoration: const InputDecoration(labelText: 'Adresse')),
              TextField(
                  controller: tel,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                  keyboardType: TextInputType.phone),
              TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress),
              TextField(
                  controller: revenus,
                  decoration: const InputDecoration(
                      labelText: 'Revenus mensuels (€)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    if (prenom.text.trim().isEmpty && nom.text.trim().isEmpty) return;
    final rev = double.tryParse(revenus.text.replaceAll(',', '.'));
    setState(() {
      if (existing == null) {
        _garants.add(Garant.create(
          nom: nom.text,
          prenom: prenom.text,
          adresse: adresse.text,
          telephone: tel.text,
          email: email.text,
          revenusMensuels: rev,
        ));
      } else {
        existing.nom = nom.text.trim().toUpperCase();
        existing.prenom = prenom.text.trim();
        existing.adresse =
            adresse.text.trim().isEmpty ? null : adresse.text.trim();
        existing.telephone =
            tel.text.trim().isEmpty ? null : tel.text.trim();
        existing.email = email.text.trim().isEmpty
            ? null
            : email.text.trim().toLowerCase();
        existing.revenusMensuels = rev;
      }
    });
  }

  /// Section de catalogue pour une catégorie de clauses (cases à cocher).
  Widget _catalogCategorySection(ClauseCategorie cat) {
    final clauses =
        ClauseCatalogue.standard.where((c) => c.categorie == cat).toList();
    if (clauses.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            cat.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        for (final c in clauses)
          CheckboxListTile(
            value: _activeCatalogIds.contains(c.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _activeCatalogIds.add(c.id);
              } else {
                _activeCatalogIds.remove(c.id);
              }
            }),
            title: Text(c.titre),
            subtitle: Text(c.contenu,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            contentPadding: EdgeInsets.zero,
            dense: true,
            isThreeLine: true,
          ),
      ],
    );
  }

  /// Ouvre un dialogue pour créer ou éditer une clause personnalisée.
  Future<void> _editCustomClause(Clause? existing) async {
    final titre = TextEditingController(text: existing?.titre ?? '');
    final contenu = TextEditingController(text: existing?.contenu ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(existing == null ? 'Nouvelle clause' : 'Modifier la clause'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: titre,
                  decoration: const InputDecoration(labelText: 'Titre')),
              const SizedBox(height: 8),
              TextField(
                controller: contenu,
                decoration: const InputDecoration(labelText: 'Contenu'),
                minLines: 3,
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return;
    if (titre.text.trim().isEmpty && contenu.text.trim().isEmpty) return;
    setState(() {
      if (existing == null) {
        _customClauses
            .add(Clause.custom(titre: titre.text, contenu: contenu.text));
      } else {
        existing.titre = titre.text.trim();
        existing.contenu = contenu.text.trim();
      }
    });
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
    final loyer = double.tryParse(_loyerHC.text.replaceAll(',', '.')) ?? 0;
    final charges = double.tryParse(_charges.text.replaceAll(',', '.')) ?? 0;
    final depot = double.tryParse(_depot.text.replaceAll(',', '.')) ?? 0;
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
    contrat.attestationAssurance = _attestationAssurance;
    contrat.paiementTermeEchu = _termeEchu;
    contrat.assuranceFilePath = _assuranceFilePath;
    contrat.annexesOptionnelles = List<String>.from(_annexes);
    contrat.mentionEtatDesLieux = _mentionEDL;
    contrat.modalitesRestitutionDepot = _restitutionDepot.text.trim().isEmpty
        ? null
        : _restitutionDepot.text.trim();
    contrat.descriptionLogement =
        _description.text.trim().isEmpty ? null : _description.text.trim();
    String? optText(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    contrat.bailleurAdresse = optText(_bailleurAdresse);
    contrat.bailleurTelephone = optText(_bailleurTel);
    contrat.bailleurEstSociete = _bailleurEstSociete;
    contrat.bailleurRaisonSociale = optText(_bailleurRaisonSociale);
    contrat.bailleurSiret = optText(_bailleurSiret);
    contrat.bailleurRepresentant = optText(_bailleurRepresentant);
    contrat.garants = List<Garant>.from(_garants);
    final catalogActives = ClauseCatalogue.standard
        .where((c) => _activeCatalogIds.contains(c.id))
        .map((c) => c.copy()..active = true)
        .toList();
    contrat.clauses = [...catalogActives, ..._customClauses];
    contrat.notes = _notes.text.trim();
    contrat.templateSourceId = _templateSourceId;
    contrat.templateAppliqueLe = _templateAppliqueLe;

    await svc.save(contrat);
    if (_templateSourceId != null) {
      try {
        await context.read<BailTemplateService>().incrementUsage(_templateSourceId!);
      } catch (_) {
        // pas critique : ignore silencieusement les erreurs de comptage
      }
    }
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
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_templateSourceId != null)
              _TemplateBanner(templateId: _templateSourceId!),
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
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Durée en mois requise (> 0)';
                return null;
              },
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
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (n == null || n <= 0) return 'Loyer > 0 requis';
                      return null;
                    },
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
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (n == null || n < 0) return 'Charges ≥ 0 requises';
                      return null;
                    },
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
                labelText: 'Jour d\'échéance (1-28) *',
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 28) {
                  return 'Jour entre 1 et 28';
                }
                return null;
              },
            ),
            CheckboxListTile(
              value: _termeEchu,
              onChanged: (v) => setState(() => _termeEchu = v ?? _termeEchu),
              title: const Text('Loyer payable à terme échu'),
              subtitle: const Text(
                  'En fin de période (sinon : d\'avance / à échoir).'),
              contentPadding: EdgeInsets.zero,
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
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null || n < 0) return 'Dépôt ≥ 0 requis';
                final loyer =
                    double.tryParse(_loyerHC.text.replaceAll(',', '.')) ?? 0;
                final plafond = loyer * _type.plafondDepotMois;
                if (loyer > 0 && n > plafond + 0.01) {
                  return 'Max ${_type.plafondDepotMois} mois de loyer '
                      '(${plafond.toStringAsFixed(2)} €)';
                }
                return null;
              },
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
            _Section('Bailleur'),
            SwitchListTile(
              value: _bailleurEstSociete,
              onChanged: (v) => setState(() => _bailleurEstSociete = v),
              title: const Text('Bailleur = société (SCI, SARL…)'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_bailleurEstSociete) ...[
              TextFormField(
                controller: _bailleurRaisonSociale,
                decoration: const InputDecoration(
                  labelText: 'Raison sociale *',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bailleurSiret,
                decoration: const InputDecoration(
                  labelText: 'SIRET *',
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bailleurRepresentant,
                decoration: const InputDecoration(
                  labelText: 'Représentant légal',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _bailleurAdresse,
              decoration: const InputDecoration(
                labelText: 'Adresse du bailleur',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              minLines: 1,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bailleurTel,
              decoration: const InputDecoration(
                labelText: 'Téléphone du bailleur',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _Section('Garants / cautions'),
            for (final g in _garants)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(g.fullName),
                  subtitle: Text(
                    [
                      if (g.revenusMensuels != null)
                        '${g.revenusMensuels!.toStringAsFixed(0)} €/mois',
                      if (g.email != null) g.email!,
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _garants.remove(g)),
                  ),
                  onTap: () => _editGarant(g),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _editGarant(null),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un garant'),
            ),
            const SizedBox(height: 16),
            _Section('Clauses du bail'),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Coche les clauses à inclure, ou ajoute les tiennes.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            for (final cat in ClauseCategorie.values
                .where((c) => c != ClauseCategorie.personnalisee))
              _catalogCategorySection(cat),
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 2),
              child: Text(
                'CLAUSES PERSONNALISÉES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            for (final c in _customClauses)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(c.titre.isEmpty ? '(Sans titre)' : c.titre),
                  subtitle: Text(c.contenu,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _customClauses.remove(c)),
                  ),
                  onTap: () => _editCustomClause(c),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _editCustomClause(null),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une clause personnalisée'),
            ),
            const SizedBox(height: 16),
            _Section('Logement & obligations'),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description du logement',
                helperText: 'Ex : T3 avec balcon, cuisine équipée…',
                prefixIcon: Icon(Icons.home_outlined),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _mentionEDL,
              onChanged: (v) => setState(() => _mentionEDL = v ?? _mentionEDL),
              title: const Text('État des lieux d\'entrée réalisé ou prévu'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _attestationAssurance,
              onChanged: (v) => setState(
                  () => _attestationAssurance = v ?? _attestationAssurance),
              title: const Text('Attestation d\'assurance habitation fournie'),
              subtitle: const Text('Obligatoire pour générer le bail.'),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text(
                _assuranceFilePath == null
                    ? 'Joindre l\'attestation (fichier)'
                    : _assuranceFilePath!.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _assuranceFilePath == null
                  ? const Icon(Icons.upload_file)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          setState(() => _assuranceFilePath = null),
                    ),
              onTap: () async {
                final p = await _pickAttachment();
                if (p != null) setState(() => _assuranceFilePath = p);
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _restitutionDepot,
              decoration: const InputDecoration(
                labelText: 'Modalités de restitution du dépôt',
                helperText:
                    'Ex : sous 1 mois après l\'état des lieux de sortie.',
                prefixIcon: Icon(Icons.assignment_return_outlined),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _Section('Pièces jointes optionnelles'),
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Règlement de copropriété, photos, plan, assurance bailleur…',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            for (final a in _annexes)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(a.split('/').last,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _annexes.remove(a)),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await _pickAttachment();
                if (p != null) setState(() => _annexes.add(p));
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une pièce jointe'),
            ),
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

/// Bandeau d'information « Basé sur le modèle X » en haut du form bail.
/// Affiché uniquement quand un template a été appliqué.
class _TemplateBanner extends StatelessWidget {
  final String templateId;
  const _TemplateBanner({required this.templateId});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BailTemplateService>();
    final t = svc.byId(templateId);
    final nom = t?.nom ?? 'Modèle personnalisé';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.bookmark_added_outlined,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Basé sur le modèle',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                ),
                Text(
                  nom,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
