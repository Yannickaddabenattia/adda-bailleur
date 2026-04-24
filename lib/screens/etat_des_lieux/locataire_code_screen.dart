import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../widgets/primary_button.dart';
import 'etat_des_lieux_detail_screen.dart';

/// Écran affichant le code temporaire que le locataire doit saisir
/// pour co-signer l'EDL et le finaliser.
class LocataireCodeScreen extends StatefulWidget {
  final String edlId;
  final String code;
  const LocataireCodeScreen({
    super.key,
    required this.edlId,
    required this.code,
  });

  @override
  State<LocataireCodeScreen> createState() => _LocataireCodeScreenState();
}

class _LocataireCodeScreenState extends State<LocataireCodeScreen> {
  final _inputCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(widget.edlId);
    if (edl == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      await service.signAsLocataire(edl, _inputCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => EtatDesLieuxDetailScreen(edlId: widget.edlId),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signature locataire')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
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
                      'Code temporaire à communiquer au locataire',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      widget.code,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copier'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.code));
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
              const SizedBox(height: 24),
              const Text(
                'Demandez au locataire de saisir le code ci-dessus '
                'pour co-signer et finaliser l\'état des lieux.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _inputCtrl,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
                decoration: InputDecoration(
                  hintText: 'CODE',
                  errorText: _error,
                ),
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[A-Za-z0-9]')),
                ],
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Finaliser l\'état des lieux',
                icon: Icons.verified_outlined,
                loading: _busy,
                onPressed: _inputCtrl.text.isEmpty ? null : _verify,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => EtatDesLieuxDetailScreen(
                                edlId: widget.edlId),
                          ),
                          (route) => route.isFirst,
                        );
                      },
                child: const Text('Je finaliserai plus tard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
