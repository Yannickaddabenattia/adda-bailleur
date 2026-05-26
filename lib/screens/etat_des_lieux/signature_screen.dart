import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import '../../core/theme/app_theme.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../widgets/primary_button.dart';
import 'locataire_signature_screen.dart';

class SignatureScreen extends StatefulWidget {
  final String edlId;
  const SignatureScreen({super.key, required this.edlId});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  late SignatureController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: AppColors.textPrimary,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.isEmpty) return;
    setState(() => _saving = true);
    final service = context.read<EtatDesLieuxService>();
    final edl = service.byId(widget.edlId);
    if (edl == null) {
      setState(() => _saving = false);
      return;
    }
    final pngBytes = await _controller.toPngBytes();
    if (pngBytes == null) {
      setState(() => _saving = false);
      return;
    }
    final base64Png = base64Encode(pngBytes);
    await service.signAsProprietaire(
      edl,
      signaturePngBase64: base64Png,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LocataireSignatureScreen(edlId: widget.edlId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signature propriétaire'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Effacer',
            onPressed: () => _controller.clear(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'Signez dans le cadre ci-dessous, puis validez.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Valider ma signature',
                icon: Icons.check_circle_outline,
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
