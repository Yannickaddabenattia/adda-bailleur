import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_role.dart';
import '../../services/incoming_file_handler.dart';
import '../../services/user_service.dart';
import '../onboarding/user_info_screen.dart';
import '../shell/main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final userService = context.read<UserService>();
    try {
      await userService.load();
    } catch (e) {
      if (!mounted) return;
      _showIntegrityError(e.toString());
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) {
          if (!userService.hasProfile) {
            return const UserInfoScreen(role: UserRole.proprietaire);
          }
          return const MainShell();
        },
      ),
    );
    // Les fichiers reçus de l'extérieur ne sont poussés qu'une fois le splash
    // terminé, sinon `pushReplacement` les écraserait.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => IncomingFileHandler.instance.markReady());
  }

  void _showIntegrityError(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Erreur d\'intégrité'),
        content: Text(
          'Les données locales semblent avoir été altérées.\n\n$message',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final service = context.read<UserService>();
              await service.factoryReset();
              if (!mounted) return;
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      const UserInfoScreen(role: UserRole.proprietaire),
                ),
              );
            },
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 240,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
