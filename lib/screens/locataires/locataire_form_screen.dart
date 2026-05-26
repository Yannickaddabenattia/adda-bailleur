import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../widgets/primary_button.dart';

class LocataireFormScreen extends StatefulWidget {
  final Locataire? locataire;
  final String? preselectedLogementId;
  final List<String>? preselectedLogementIds;
  final bool archiveMode;

  const LocataireFormScreen({
    super.key,
    this.locataire,
    this.preselectedLogementId,
    this.preselectedLogementIds,
    this.archiveMode = false,
  });

  @override
  State<LocataireFormScreen> createState() => _LocataireFormScreenState();
}

class _LocataireFormScreenState extends State<LocataireFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstName;
  late TextEditingController _lastName;
  late TextEditingController _email;
  late TextEditingController _phone;
  late TextEditingController _notes;
  late TextEditingController _raisonSortie;
  late TextEditingController _loyerSortie;
  late TextEditingController _nouvelleAdresse;
  late TextEditingController _nouveauTelephone;
  late TextEditingController _nouvelEmail;
  late Set<String> _selectedLogementIds;
  DateTime? _dateEntree;
  DateTime? _dateSortie;
  bool _isArchive = false;
  bool _saving = false;

  static const _raisonsCourantes = <String>[
    'Déménagement',
    'Fin de bail',
    'Mutation pro',
    'Achat immobilier',
    'Expulsion',
    'Autre',
  ];

  bool get _isEdit => widget.locataire != null;

  @override
  void initState() {
    super.initState();
    final l = widget.locataire;
    _firstName = TextEditingController(text: l?.firstName ?? '');
    _lastName = TextEditingController(text: l?.lastName ?? '');
    _email = TextEditingController(text: l?.email ?? '');
    _phone = TextEditingController(text: l?.phone ?? '');
    _notes = TextEditingController(text: l?.notes ?? '');
    _raisonSortie = TextEditingController(text: l?.raisonSortie ?? '');
    _loyerSortie = TextEditingController(
      text: l?.loyerSortie != null ? l!.loyerSortie!.toStringAsFixed(2) : '',
    );
    _nouvelleAdresse = TextEditingController(text: l?.nouvelleAdresse ?? '');
    _nouveauTelephone = TextEditingController(text: l?.nouveauTelephone ?? '');
    _nouvelEmail = TextEditingController(text: l?.nouvelEmail ?? '');
    _selectedLogementIds = Set<String>.from(
      l?.logementIds ??
          (widget.preselectedLogementIds?.isNotEmpty == true
              ? widget.preselectedLogementIds!
              : (widget.preselectedLogementId != null
                  ? [widget.preselectedLogementId!]
                  : <String>[])),
    );
    _dateEntree = l?.dateEntree;
    _dateSortie = l?.dateSortie;
    _isArchive = widget.archiveMode ||
        l?.dateSortie != null ||
        l?.raisonSortie.isNotEmpty == true;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _notes.dispose();
    _raisonSortie.dispose();
    _loyerSortie.dispose();
    _nouvelleAdresse.dispose();
    _nouveauTelephone.dispose();
    _nouvelEmail.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEntree ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) setState(() => _dateEntree = picked);
  }

  Future<void> _pickDateSortie() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateSortie ?? now,
      firstDate: _dateEntree ?? DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) setState(() => _dateSortie = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final service = context.read<LocataireService>();
    final loyerSortieVal = _isArchive
        ? double.tryParse(_loyerSortie.text.replaceAll(',', '.').trim())
        : null;
    final dateSortieVal = _isArchive ? _dateSortie : null;
    final raisonSortieVal =
        _isArchive ? _raisonSortie.text.trim() : '';
    String? cleanOpt(TextEditingController c) {
      if (!_isArchive) return null;
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }
    final nouvelleAdresseVal = cleanOpt(_nouvelleAdresse);
    final nouveauTelephoneVal = cleanOpt(_nouveauTelephone);
    final nouvelEmailVal = cleanOpt(_nouvelEmail)?.toLowerCase();
    try {
      if (_isEdit) {
        final l = widget.locataire!;
        l.firstName = _firstName.text.trim();
        l.lastName = _lastName.text.trim().toUpperCase();
        l.email = _email.text.trim().toLowerCase();
        l.phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
        l.logementIds = _selectedLogementIds.toList();
        l.dateEntree = _dateEntree;
        l.notes = _notes.text.trim();
        l.dateSortie = dateSortieVal;
        l.raisonSortie = raisonSortieVal;
        l.loyerSortie = loyerSortieVal;
        l.nouvelleAdresse = nouvelleAdresseVal;
        l.nouveauTelephone = nouveauTelephoneVal;
        l.nouvelEmail = nouvelEmailVal;
        await service.update(l);
      } else {
        final locataire = Locataire.create(
          firstName: _firstName.text,
          lastName: _lastName.text,
          email: _email.text,
          phone: _phone.text,
          logementIds: _selectedLogementIds.toList(),
          dateEntree: _dateEntree,
          notes: _notes.text,
          dateSortie: dateSortieVal,
          raisonSortie: raisonSortieVal,
          loyerSortie: loyerSortieVal,
          nouvelleAdresse: nouvelleAdresseVal,
          nouveauTelephone: nouveauTelephoneVal,
          nouvelEmail: nouvelEmailVal,
        );
        await service.add(locataire);
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
    final logements = context.watch<LogementService>().all;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Modifier le locataire'
            : (widget.archiveMode
                ? 'Ajouter un ancien locataire'
                : 'Nouveau locataire')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _firstName,
                decoration: const InputDecoration(
                  labelText: 'Prénom *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Prénom requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastName,
                decoration: const InputDecoration(
                  labelText: 'Nom *',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Nom requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => EmailValidator.validate(v?.trim() ?? '')
                    ? null
                    : 'Email invalide',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date d\'entrée',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _dateEntree == null
                        ? 'Non renseignée'
                        : '${_dateEntree!.day.toString().padLeft(2, '0')}/'
                            '${_dateEntree!.month.toString().padLeft(2, '0')}/'
                            '${_dateEntree!.year}',
                    style: TextStyle(
                      color: _dateEntree == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'LOGEMENTS ASSOCIÉS',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (logements.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Text(
                    'Aucun logement disponible. Créez-en un d\'abord.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                ...logements.map(
                  (l) => CheckboxListTile(
                    value: _selectedLogementIds.contains(l.id),
                    onChanged: (checked) {
                      setState(() {
                        if (checked ?? false) {
                          _selectedLogementIds.add(l.id);
                        } else {
                          _selectedLogementIds.remove(l.id);
                        }
                      });
                    },
                    title: Text(l.libelle),
                    subtitle: Text(
                      l.adresseComplete,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isArchive,
                      onChanged: (v) => setState(() => _isArchive = v),
                      title: const Text(
                        'Locataire archivé',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _isArchive
                            ? 'Renseigne sortie + raison ci-dessous'
                            : 'Activer pour ajouter un ancien locataire',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (_isArchive) ...[
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _pickDateSortie,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date de sortie',
                            prefixIcon: Icon(Icons.event_busy_outlined),
                          ),
                          child: Text(
                            _dateSortie == null
                                ? 'Non renseignée'
                                : '${_dateSortie!.day.toString().padLeft(2, '0')}/'
                                    '${_dateSortie!.month.toString().padLeft(2, '0')}/'
                                    '${_dateSortie!.year}',
                            style: TextStyle(
                              color: _dateSortie == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownMenu<String>(
                        initialSelection: _raisonsCourantes.contains(
                                _raisonSortie.text)
                            ? _raisonSortie.text
                            : null,
                        controller: _raisonSortie,
                        label: const Text('Raison de sortie'),
                        leadingIcon: const Icon(Icons.logout_outlined),
                        expandedInsets: EdgeInsets.zero,
                        dropdownMenuEntries: _raisonsCourantes
                            .map((r) =>
                                DropdownMenuEntry(value: r, label: r))
                            .toList(),
                        onSelected: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _loyerSortie,
                        decoration: const InputDecoration(
                          labelText: 'Dernier loyer (€)',
                          prefixIcon: Icon(Icons.payments_outlined),
                          hintText: 'Snapshot au moment de la sortie',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'NOUVELLES COORDONNÉES (APRÈS DÉPART)',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nouvelleAdresse,
                        decoration: const InputDecoration(
                          labelText: 'Nouvelle adresse',
                          prefixIcon: Icon(Icons.location_on_outlined),
                          hintText: 'Adresse postale après déménagement',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nouveauTelephone,
                        decoration: const InputDecoration(
                          labelText: 'Nouveau téléphone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nouvelEmail,
                        decoration: const InputDecoration(
                          labelText: 'Nouvel email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          return EmailValidator.validate(t)
                              ? null
                              : 'Email invalide';
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
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
                label: _isEdit ? 'Enregistrer' : 'Créer le locataire',
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
}
