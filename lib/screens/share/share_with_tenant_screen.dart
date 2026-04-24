import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../models/locataire.dart';
import '../../services/locataire_service.dart';
import '../../services/tenant_share_service.dart';
import '../../widgets/primary_button.dart';

class ShareWithTenantScreen extends StatefulWidget {
  const ShareWithTenantScreen({super.key});

  @override
  State<ShareWithTenantScreen> createState() => _ShareWithTenantScreenState();
}

class _ShareWithTenantScreenState extends State<ShareWithTenantScreen> {
  Locataire? _selected;
  bool _busy = false;
  TenantShareResult? _result;

  Future<void> _generate() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    try {
      final result = await context
          .read<TenantShareService>()
          .createShareForLocataire(locataire: _selected!);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_result == null) return;
    await Share.shareXFiles(
      [
        XFile(
          _result!.file.path,
          mimeType: 'application/octet-stream',
        ),
      ],
      subject: 'Partage Adda Location',
      text:
          'Documents locatifs pour ${_result!.locataireName}. '
          'Ouvrir dans Adda Location et saisir le code communiqué oralement.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final locataires = context.watch<LocataireService>().all;
    return Scaffold(
      appBar: AppBar(title: const Text('Partager avec un locataire')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _result == null
              ? _step1(locataires)
              : _step2(),
        ),
      ),
    );
  }

  Widget _step1(List<Locataire> locataires) {
    if (locataires.isEmpty) {
      return const Center(
        child: Text(
          'Aucun locataire enregistré.\nAjoutez d\'abord un locataire.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView(
      children: [
        const _InfoBanner(),
        const SizedBox(height: 16),
        const Text(
          'Sélectionner le locataire destinataire :',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...locataires.map(
          (l) => RadioListTile<String>(
            title: Text(l.fullName),
            subtitle: Text(l.email,
                style: const TextStyle(fontSize: 12)),
            value: l.id,
            // ignore: deprecated_member_use
            groupValue: _selected?.id,
            // ignore: deprecated_member_use
            onChanged: (id) {
              if (id == null) return;
              setState(() => _selected = l);
            },
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Générer le partage',
          icon: Icons.ios_share,
          loading: _busy,
          onPressed: _selected == null ? null : _generate,
        ),
      ],
    );
  }

  Widget _step2() {
    final r = _result!;
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Partage prêt pour ${r.locataireName} : '
                  '${r.edlCount} EDL, ${r.quittanceCount} quittance(s).',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              const Text(
                'CODE À COMMUNIQUER AU LOCATAIRE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                r.code,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copier le code'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copié'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '1. Envoyez le fichier au locataire via AirDrop, Nearby Share, '
          'Bluetooth, Mail ou Messages.\n'
          '2. Communiquez-lui le code oralement ou par un canal séparé.\n'
          '3. Il pourra l\'importer dans son application.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Envoyer le fichier',
          icon: Icons.ios_share,
          onPressed: _share,
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bluetooth_searching, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Le partage est chiffré localement. Il peut être transféré par '
              'Bluetooth, AirDrop, Nearby Share, email ou messagerie — le '
              'code à 8 caractères est indispensable pour le déchiffrer.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
