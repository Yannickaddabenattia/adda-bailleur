import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';

import '../../core/pdf/etat_des_lieux_pdf.dart';
import '../../core/theme/app_theme.dart';
import '../../models/etat_des_lieux.dart';
import '../../services/etat_des_lieux_service.dart';
import '../../services/locataire_service.dart';
import '../../services/logement_service.dart';
import '../../services/plan_logement_service.dart';
import '../../services/user_service.dart';
import '../../widgets/primary_button.dart';
import 'etat_des_lieux_detail_screen.dart';

/// Flow de signature locataire en deux temps :
///
/// 1. Signature manuscrite + accord explicite.
/// 2. Le propriétaire envoie par email au locataire le PDF de l'EDL signé
///    (signature propriétaire + signature locataire). Le locataire le
///    transfère ensuite au propriétaire avec la mention « Bon pour accord » :
///    le forward conserve le PDF en pièce jointe et l'envoi depuis l'adresse
///    personnelle du locataire fait foi.
class LocataireSignatureScreen extends StatefulWidget {
  final String edlId;
  const LocataireSignatureScreen({super.key, required this.edlId});

  @override
  State<LocataireSignatureScreen> createState() =>
      _LocataireSignatureScreenState();
}

class _LocataireSignatureScreenState extends State<LocataireSignatureScreen> {
  late SignatureController _controller;
  bool _agreed = false;
  bool _emailSent = false;
  bool _busy = false;
  String? _error;
  int _step = 0; // 0 = signature, 1 = envoi PDF
  Uint8List? _signaturePngBytes;

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

  Future<void> _goToShareStep() async {
    if (_controller.isEmpty || !_agreed) return;
    final png = await _controller.toPngBytes();
    if (png == null) return;
    setState(() {
      _signaturePngBytes = png;
      _step = 1;
    });
  }

  Future<void> _sharePdfToLocataire() async {
    if (_signaturePngBytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final edl = context.read<EtatDesLieuxService>().byId(widget.edlId);
      final bailleur = context.read<UserService>().current;
      if (edl == null || bailleur == null) {
        setState(() => _busy = false);
        return;
      }
      final locataire =
          context.read<LocataireService>().byId(edl.locataireId);
      final logement =
          context.read<LogementService>().byId(edl.logementId);
      if (locataire == null || logement == null) {
        setState(() => _busy = false);
        return;
      }

      // Override temporaire de l'EDL en mémoire pour générer un PDF qui
      // montre les deux signatures *sans* persister la finalisation. La
      // persistance n'a lieu qu'au clic « Finaliser ».
      final origSig = edl.locataireSignaturePng;
      final origAt = edl.locataireSignatureAt;
      final origStatus = edl.status;
      final origHash = edl.integrityHash;
      edl.locataireSignaturePng = base64Encode(_signaturePngBytes!);
      edl.locataireSignatureAt = DateTime.now().toUtc();
      edl.status = EtatDesLieuxStatus.finalise;
      edl.integrityHash = edl.computeIntegrityHash();
      final plans = context
          .read<PlanLogementService>()
          .byLogement(edl.logementId);
      final wallPhotos = plans
          .expand((plan) => plan.wallPhotos)
          .where((w) => w.etatId == edl.id)
          .toList();
      try {
        final doc = await EtatDesLieuxPdfBuilder.build(
          edl: edl,
          bailleur: bailleur,
          logement: logement,
          locataire: locataire,
          wallPhotos: wallPhotos,
          plans: plans,
        );
        final bytes = await doc.save();
        final tempDir = await getTemporaryDirectory();
        if (!await tempDir.exists()) {
          await tempDir.create(recursive: true);
        }
        final file = File('${tempDir.path}/edl_${edl.id}.pdf');
        await file.writeAsBytes(bytes, flush: true);
        final subject = 'EDL ${edl.titre} — à valider par bon pour accord';
        final body = 'Bonjour ${locataire.firstName},\n\n'
            'Veuillez trouver ci-joint l\'état des lieux signé. Pour valider '
            'votre accord, transférez (forward) ce message à '
            '${bailleur.email} avec la mention « Bon pour accord » dans le '
            'corps du message.\n\n'
            'Identifiant : ${edl.id}\n'
            'Empreinte : ${edl.computePreSignatureHash().substring(0, 16).toUpperCase()}';
        if (Platform.isMacOS) {
          // macOS : NSSharingService.composeEmail (sandbox OK) ouvre Mail.app
          // directement avec destinataire / sujet / corps / pièce jointe.
          const channel = MethodChannel('adda_location/mail');
          await channel.invokeMethod<void>('composeEmail', {
            'to': locataire.email,
            'subject': subject,
            'body': body,
            'attachmentPath': file.path,
          });
        } else {
          final box = context.findRenderObject() as RenderBox?;
          final origin = box != null && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : const Rect.fromLTWH(0, 0, 1, 1);
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/pdf')],
            subject: subject,
            text: body,
            sharePositionOrigin: origin,
          );
        }
        if (mounted) setState(() => _emailSent = true);
      } finally {
        edl.locataireSignaturePng = origSig;
        edl.locataireSignatureAt = origAt;
        edl.status = origStatus;
        edl.integrityHash = origHash;
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finalize() async {
    if (!_emailSent || _signaturePngBytes == null) return;
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
      await service.signAsLocataire(
        edl,
        signaturePngBase64: base64Encode(_signaturePngBytes!),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => EtatDesLieuxDetailScreen(edlId: widget.edlId),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0
            ? 'Signature locataire — 1/2'
            : 'Bon pour accord — 2/2'),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy ? null : () => setState(() => _step = 0),
              )
            : null,
        actions: _step == 0
            ? [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Effacer',
                  onPressed: () => _controller.clear(),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _step == 0 ? _buildSignatureStep() : _buildShareStep(),
        ),
      ),
    );
  }

  Widget _buildSignatureStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.35),
            ),
          ),
          child: const Text(
            'Étape 1 — Le locataire signe ci-dessous, puis cliquez sur '
            'Suivant pour la confirmation par email.',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
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
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Je reconnais avoir pris connaissance de l\'état des '
            'lieux et l\'accepte sans réserve.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: 'Suivant',
          icon: Icons.arrow_forward,
          onPressed: _agreed ? _goToShareStep : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) =>
                    EtatDesLieuxDetailScreen(edlId: widget.edlId),
              ),
              (route) => route.isFirst,
            );
          },
          child: const Text('Plus tard'),
        ),
      ],
    );
  }

  Widget _buildShareStep() {
    final edl = context.watch<EtatDesLieuxService>().byId(widget.edlId);
    final bailleur = context.watch<UserService>().current;
    final locataire = edl == null
        ? null
        : context.watch<LocataireService>().byId(edl.locataireId);
    if (edl == null || bailleur == null || locataire == null) {
      return const Center(child: Text('Données manquantes.'));
    }
    final shortHash =
        edl.computePreSignatureHash().substring(0, 16).toUpperCase();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              'Étape 2 — Envoyez le PDF de l\'EDL signé à ${locataire.firstName} '
              'par email. Demandez-lui ensuite de **transférer (forward)** '
              'cet email à votre adresse (${bailleur.email}) en ajoutant '
              '« Bon pour accord » dans le corps. Le forward conserve le PDF '
              'en pièce jointe et l\'envoi depuis son adresse personnelle '
              'fait foi.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _emailRow(
            label: 'Adresse du locataire',
            email: locataire.email.isEmpty
                ? '(non renseignée)'
                : locataire.email,
            copyable: locataire.email.isNotEmpty,
          ),
          const SizedBox(height: 8),
          _emailRow(
            label: 'À retourner à',
            email: bailleur.email,
            copyable: true,
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Empreinte : $shortHash',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Envoyer le PDF par email',
            icon: Icons.attach_email_outlined,
            loading: _busy,
            onPressed: _busy ? null : _sharePdfToLocataire,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _emailSent,
            onChanged: _busy
                ? null
                : (v) => setState(() => _emailSent = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'PDF envoyé au locataire (le bon pour accord retournera par '
              'forward avec le PDF en pièce jointe).',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Finaliser l\'état des lieux',
            icon: Icons.verified_outlined,
            loading: _busy,
            onPressed: _emailSent ? _finalize : null,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) =>
                            EtatDesLieuxDetailScreen(edlId: widget.edlId),
                      ),
                      (route) => route.isFirst,
                    );
                  },
            child: const Text('Plus tard'),
          ),
        ],
      ),
    );
  }

  Widget _emailRow({
    required String label,
    required String email,
    required bool copyable,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (copyable)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copier',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: email));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Adresse copiée'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
      ],
    );
  }
}
