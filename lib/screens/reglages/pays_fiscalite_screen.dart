import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/fiscalite_service.dart';

/// Réglages « Pays & fiscalité » — taux d'imposition **personnels** de
/// l'utilisateur pour la Belgique et la Suisse.
///
/// En BE/CH il n'existe pas de taux national unique sur les loyers : le calcul
/// dépend du taux marginal du contribuable. Ces valeurs alimentent les
/// estimations par bien ; sans elles, aucun montant n'est calculé.
/// Saisie en **pourcentage** (ex. 45) ; stockage en fraction (0,45).
class PaysFiscaliteScreen extends StatefulWidget {
  const PaysFiscaliteScreen({super.key});

  @override
  State<PaysFiscaliteScreen> createState() => _PaysFiscaliteScreenState();
}

class _PaysFiscaliteScreenState extends State<PaysFiscaliteScreen> {
  late TextEditingController _margBE;
  late TextEditingController _commBE;
  late TextEditingController _margCH;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<FiscaliteService>().settings;
    _margBE = TextEditingController(text: _pct(s.tauxMarginalBE));
    _commBE = TextEditingController(text: _pct(s.tauxCommunalBE));
    _margCH = TextEditingController(text: _pct(s.tauxMarginalCH));
  }

  static String _pct(double? fraction) =>
      fraction == null ? '' : (fraction * 100).toString().replaceAll('.0', '');

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t.replaceAll(',', '.'));
    return v == null ? null : v / 100;
  }

  @override
  void dispose() {
    _margBE.dispose();
    _commBE.dispose();
    _margCH.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final svc = context.read<FiscaliteService>();
    final s = svc.settings;
    s.tauxMarginalBE = _parse(_margBE);
    s.tauxCommunalBE = _parse(_commBE);
    s.tauxMarginalCH = _parse(_margCH);
    await svc.saveSettings(s);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Taux enregistrés')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pays & fiscalité')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('🇧🇪  Belgique',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _field(_margBE, 'Taux marginal IPP (%)', '25 / 40 / 45 / 50'),
          const SizedBox(height: 12),
          _field(_commBE, 'Centimes additionnels communaux (%)', 'Ex : 7'),
          const SizedBox(height: 28),
          Text('🇨🇭  Suisse', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _field(_margCH, 'Taux marginal global (%)',
              'Fédéral + cantonal + communal, ex : 30'),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: '%',
        prefixIcon: const Icon(Icons.percent),
      ),
    );
  }
}
