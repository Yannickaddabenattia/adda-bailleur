import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final edl = context.read<EtatDesLieuxService>().byId(widget.edlId);
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
    super.dispose();
  }

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
