import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

/// Politique de confidentialité accessible depuis les Réglages.
///
/// Reprend la version courte de addabailleur.fr/confidentialite. Un bouton
/// renvoie vers la version complète en ligne.
class ConfidentialiteScreen extends StatelessWidget {
  const ConfidentialiteScreen({super.key});

  static final Uri _fullPolicyUrl =
      Uri.parse('https://addabailleur.fr/confidentialite.html');
  static final Uri _contactMail = Uri.parse(
    'mailto:contact@addabailleur.fr?subject=Confidentialit%C3%A9%20ADDA%20Bailleur',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _BannerCard(),
          const SizedBox(height: 20),
          _Section(
            title: '1. Aucune collecte par l\'éditeur',
            body: 'ADDA Bailleur est une application « local-first » : elle '
                'fonctionne entièrement sur votre appareil, sans serveur '
                'appartenant à l\'éditeur et sans compte utilisateur.\n\n'
                'L\'éditeur ne collecte, ne reçoit, ne stocke et ne consulte '
                'aucune de vos données. Aucune information ne transite par un '
                'serveur de l\'éditeur ni n\'est envoyée sur internet à son '
                'initiative.',
          ),
          _Section(
            title: '2. Données traitées sur votre appareil',
            body: 'L\'application enregistre localement les informations que '
                'vous saisissez :\n'
                '• vos logements (adresse, plans 2D, photos) ;\n'
                '• vos locataires et garants (identité, coordonnées) ;\n'
                '• vos baux, états des lieux, quittances et photos associées ;\n'
                '• vos loyers, charges, crédits immobiliers et paramètres '
                'fiscaux ;\n'
                '• les observations dictées à la voix lors d\'un EDL '
                '(converties en texte sur l\'appareil).',
          ),
          _Section(
            title: '3. Partage et export à votre seule initiative',
            body: 'Vous pouvez générer des documents (PDF, ZIP, .adls, .adlb) '
                'et les partager via votre messagerie ou la fenêtre de '
                'partage de votre système (pCloud, Drive, iCloud, etc.). '
                'Aucun envoi n\'a lieu sans une action explicite de votre '
                'part.',
          ),
          _Section(
            title: '4. Sécurité',
            body: 'Vos données sont conservées dans l\'espace privé de '
                'l\'application sur votre appareil. Les sauvegardes (.adlb) '
                'sont chiffrées AES-256-GCM avec la passphrase que vous '
                'choisissez.\n\n'
                'Protégez votre appareil (code, biométrie, mises à jour) et '
                'conservez vos fichiers de sauvegarde dans un endroit sûr.',
          ),
          _Section(
            title: '5. Aucun pistage, aucune publicité',
            body: 'ADDA Bailleur ne contient ni traceur, ni outil de mesure '
                'd\'audience, ni publicité, ni SDK tiers de collecte. '
                'L\'application ne crée aucun profil, ne dépose aucun cookie '
                'publicitaire et ne vend ni ne loue aucune donnée.',
          ),
          _Section(
            title: '6. RGPD : vous êtes responsable de traitement',
            body: 'Lorsque vous utilisez l\'application pour gérer des '
                'informations concernant vos locataires et garants, c\'est '
                'vous, le bailleur, qui êtes responsable de traitement au '
                'sens du RGPD.\n\n'
                'L\'éditeur n\'accède pas à ces données et n\'agit pas comme '
                'sous-traitant. Il vous appartient d\'informer vos locataires '
                'et de répondre à leurs demandes (accès, rectification, '
                'suppression) — ce que l\'application facilite puisque vous '
                'maîtrisez directement les fiches.',
          ),
          _Section(
            title: '7. Vos droits',
            body: 'Les droits RGPD (accès, rectification, effacement, '
                'limitation, opposition, portabilité) s\'exercent directement '
                'dans l\'application. Vous pouvez à tout moment consulter, '
                'modifier ou supprimer une fiche, une photo ou un document. '
                'Pour tout effacer, supprimez les données depuis '
                'l\'application ou désinstallez-la.',
          ),
          const SizedBox(height: 20),
          _ActionButton(
            icon: Icons.open_in_new_rounded,
            label: 'Voir la version complète',
            color: AppColors.primary,
            onTap: () => _open(_fullPolicyUrl),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.mail_outline_rounded,
            label: 'Contacter : contact@addabailleur.fr',
            color: AppColors.accent,
            onTap: () => _open(_contactMail),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Réclamation possible auprès de la CNIL · www.cnil.fr',
              style: TextStyle(
                fontSize: 11,
                color: context.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _BannerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock_outline_rounded,
                color: AppColors.success, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '100 % local, 100 % chiffré',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Aucune de vos données ne quitte votre appareil sans votre '
                  'action explicite.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
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

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
