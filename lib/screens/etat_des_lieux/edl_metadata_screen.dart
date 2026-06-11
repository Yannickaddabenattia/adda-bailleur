import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../widgets/primary_button.dart';

/// Saisie des métadonnées ALUR : adresse bailleur, nombre de clés et relevés
/// compteurs (gaz, eau chaude, eau froide, électricité jour/nuit).
class EdlMetadataScreen extends StatefulWidget {
  final String edlId;
  const EdlMetadataScreen({super.key, required this.edlId});

  @override
  State<EdlMetadataScreen> createState() => _EdlMetadataScreenState();
}

class _EdlMetadataScreenState extends State<EdlMetadataScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _adresse;
  late TextEditingController _cles;
  late TextEditingController _gaz;
  late TextEditingController _eauChaude;
  late TextEditingController _eauFroide;
  late TextEditingController _elecJour;
  late TextEditingController _elecNuit;
  // B1/B2 — EDL de sortie : nouvelle adresse du locataire + date de l'EDL d'entrée.
  late TextEditingController _nouvelleAdresse;
  DateTime? _dateEntree;
  bool _isSortie = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(widget.edlId);
    _adresse = TextEditingController(text: edl?.bailleurAdresse ?? '');
    _cles = TextEditingController(
      text: edl?.nombreCles?.toString() ?? '',
    );
    _gaz = TextEditingController(text: edl?.releveCompteurGaz ?? '');
    _eauChaude =
        TextEditingController(text: edl?.releveCompteurEauChaude ?? '');
    _eauFroide =
        TextEditingController(text: edl?.releveCompteurEauFroide ?? '');
    _elecJour =
        TextEditingController(text: edl?.releveCompteurElecJour ?? '');
    _elecNuit =
        TextEditingController(text: edl?.releveCompteurElecNuit ?? '');
    _isSortie = edl?.type == EtatDesLieuxType.sortie;
    _nouvelleAdresse =
        TextEditingController(text: edl?.nouvelleAdresseLocataire ?? '');
    _dateEntree = edl?.dateEtatEntree;
    // Auto-suggestion : reprend la date de l'EDL d'entrée du même logement/
    // locataire si elle n'a pas encore été saisie.
    if (_isSortie && _dateEntree == null && edl != null) {
      final entrees = service
          .byLogement(edl.logementId)
          .where((e) =>
              e.locataireId == edl.locataireId &&
              e.type == EtatDesLieuxType.entree)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (entrees.isNotEmpty) _dateEntree = entrees.first.date;
    }
  }

  @override
  void dispose() {
    _adresse.dispose();
    _cles.dispose();
    _gaz.dispose();
    _eauChaude.dispose();
    _eauFroide.dispose();
    _elecJour.dispose();
    _elecNuit.dispose();
    _nouvelleAdresse.dispose();
    super.dispose();
  }

  Future<void> _pickDateEntree() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEntree ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateEntree = picked);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String? _normString(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(widget.edlId);
    if (edl == null) {
      setState(() => _busy = false);
      return;
    }
    edl.bailleurAdresse = _normString(_adresse);
    final clesText = _cles.text.trim();
    edl.nombreCles = clesText.isEmpty ? null : int.tryParse(clesText);
    edl.releveCompteurGaz = _normString(_gaz);
    edl.releveCompteurEauChaude = _normString(_eauChaude);
    edl.releveCompteurEauFroide = _normString(_eauFroide);
    edl.releveCompteurElecJour = _normString(_elecJour);
    edl.releveCompteurElecNuit = _normString(_elecNuit);
    edl.nouvelleAdresseLocataire =
        _isSortie ? _normString(_nouvelleAdresse) : null;
    edl.dateEtatEntree = _isSortie ? _dateEntree : null;
    await service.save(edl);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final edl = context.watch<EtatDesLieuxService>().byId(widget.edlId);
    final readOnly = edl?.isFinalized ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détails et compteurs'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _Section(label: 'BAILLEUR'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _adresse,
                readOnly: readOnly,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Adresse postale complète',
                  hintText:
                      '12 rue de la Paix, 75002 Paris',
                ),
              ),
              const SizedBox(height: 24),
              if (_isSortie) ...[
                const _Section(label: 'ÉTAT DES LIEUX DE SORTIE'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nouvelleAdresse,
                  readOnly: readOnly,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nouvelle adresse du locataire',
                    hintText:
                        'Domicile ou lieu d\'hébergement après le départ',
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: readOnly ? null : _pickDateEntree,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date de l\'état des lieux d\'entrée',
                      suffixIcon: (_dateEntree == null || readOnly)
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _dateEntree = null),
                            ),
                    ),
                    child: Text(_dateEntree == null
                        ? 'Non renseignée'
                        : _fmtDate(_dateEntree!)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const _Section(label: 'CLÉS REMISES'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cles,
                readOnly: readOnly,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Nombre de clés / badges',
                  hintText: 'Ex : 3',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 0) return 'Nombre invalide';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const _Section(label: 'RELEVÉS COMPTEURS'),
              const SizedBox(height: 8),
              _MeterField(
                label: 'Gaz (m³)',
                controller: _gaz,
                readOnly: readOnly,
              ),
              const SizedBox(height: 12),
              _MeterField(
                label: 'Eau chaude (m³)',
                controller: _eauChaude,
                readOnly: readOnly,
              ),
              const SizedBox(height: 12),
              _MeterField(
                label: 'Eau froide (m³)',
                controller: _eauFroide,
                readOnly: readOnly,
              ),
              const SizedBox(height: 12),
              _MeterField(
                label: 'Électricité — heures pleines / jour (kWh)',
                controller: _elecJour,
                readOnly: readOnly,
              ),
              const SizedBox(height: 12),
              _MeterField(
                label: 'Électricité — heures creuses / nuit (kWh)',
                controller: _elecNuit,
                readOnly: readOnly,
              ),
              const SizedBox(height: 28),
              if (!readOnly)
                PrimaryButton(
                  label: 'Enregistrer',
                  icon: Icons.check,
                  loading: _busy,
                  onPressed: _busy ? null : _save,
                ),
              if (readOnly)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.divider.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'EDL finalisé — les détails ne peuvent plus être modifiés.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  const _Section({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 1,
      ),
    );
  }
}

class _MeterField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool readOnly;
  const _MeterField({
    required this.label,
    required this.controller,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
      ),
    );
  }
}
