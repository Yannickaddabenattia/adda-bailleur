import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'services/etat_des_lieux_service.dart';
import 'services/locataire_service.dart';
import 'services/logement_service.dart';
import 'services/quittance_service.dart';
import 'services/tenant_share_service.dart';
import 'services/user_service.dart';

class AddaLocationApp extends StatelessWidget {
  const AddaLocationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserService()),
        ChangeNotifierProvider(create: (_) => LogementService()),
        ChangeNotifierProvider(create: (_) => LocataireService()),
        ChangeNotifierProvider(create: (_) => EtatDesLieuxService()),
        ChangeNotifierProvider(create: (_) => QuittanceService()),
        ChangeNotifierProvider(create: (_) => TenantShareService()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fr', 'FR'),
          Locale('en', 'US'),
        ],
        locale: const Locale('fr', 'FR'),
        home: const SplashScreen(),
      ),
    );
  }
}
