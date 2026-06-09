import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'services/avenant_service.dart';
import 'services/auto_backup_service.dart';
import 'services/bail_template_service.dart';
import 'services/contrat_bail_service.dart';
import 'services/credit_service.dart';
import 'services/depense_service.dart';
import 'services/diagnostic_service.dart';
import 'services/rappel_service.dart';
import 'services/etat_des_lieux_service.dart';
import 'services/expense_categories_service.dart';
import 'services/fiscalite_service.dart';
import 'services/incoming_file_handler.dart';
import 'services/locataire_service.dart';
import 'services/logement_service.dart';
import 'services/plan_logement_service.dart';
import 'services/quittance_service.dart';
import 'services/received_backups_service.dart';
import 'services/revision_loyer_service.dart';
import 'services/sci_service.dart';
import 'services/tenant_share_service.dart';
import 'services/theme_service.dart';
import 'services/user_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

class AddaLocationApp extends StatefulWidget {
  const AddaLocationApp({super.key});

  @override
  State<AddaLocationApp> createState() => _AddaLocationAppState();
}

class _AddaLocationAppState extends State<AddaLocationApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      IncomingFileHandler.instance.start(rootNavigatorKey);
      // Filet de sécurité au démarrage : si une sauvegarde auto est
      // configurée et qu'aucun backup n'a été fait depuis > 24h, on
      // déclenche un check (sans bloquer le démarrage).
      _maybeAutoBackup(AutoBackupTrigger.onResume);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _maybeAutoBackup(AutoBackupTrigger.onResume);
    }
  }

  void _maybeAutoBackup(AutoBackupTrigger trigger) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final svc = Provider.of<AutoBackupService>(ctx, listen: false);
    if (!svc.isEnabled) return;
    svc.checkForForeignBackups(); // détecte les données d'un autre appareil
    final last = svc.lastBackupAt;
    final tooOld = last == null ||
        DateTime.now().difference(last).inHours >= 24;
    if (!tooOld) return;
    svc.runIfNeeded(trigger: trigger);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
        ChangeNotifierProvider(create: (_) => PlanLogementService()),
        ChangeNotifierProvider(create: (_) => ReceivedBackupsService()),
        ChangeNotifierProvider(create: (_) => DepenseService()),
        ChangeNotifierProvider(create: (_) => CreditService()),
        ChangeNotifierProvider(create: (_) => ExpenseCategoriesService()),
        ChangeNotifierProvider(create: (_) => RevisionLoyerService()),
        ChangeNotifierProvider(create: (_) => ContratBailService()),
        ChangeNotifierProvider(create: (_) => BailTemplateService()),
        ChangeNotifierProvider(create: (_) => AutoBackupService()),
        ChangeNotifierProvider(create: (_) => AvenantService()),
        ChangeNotifierProvider(create: (_) => DiagnosticService()),
        ChangeNotifierProvider(create: (_) => RappelService()),
        ChangeNotifierProvider(create: (_) => ThemeService()..load()),
        ChangeNotifierProxyProvider4<LogementService, QuittanceService,
            DepenseService, CreditService, FiscaliteService>(
          create: (ctx) => FiscaliteService(
            logementService: ctx.read<LogementService>(),
            quittanceService: ctx.read<QuittanceService>(),
            depenseService: ctx.read<DepenseService>(),
            creditService: ctx.read<CreditService>(),
          ),
          update: (_, l, q, d, c, prev) =>
              prev ??
              FiscaliteService(
                logementService: l,
                quittanceService: q,
                depenseService: d,
                creditService: c,
              ),
        ),
        ChangeNotifierProxyProvider4<LogementService, QuittanceService,
            DepenseService, CreditService, SCIService>(
          create: (ctx) => SCIService(
            ctx.read<LogementService>(),
            ctx.read<QuittanceService>(),
            ctx.read<DepenseService>(),
            ctx.read<CreditService>(),
          ),
          update: (_, l, q, d, c, prev) =>
              prev ?? SCIService(l, q, d, c),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeService.mode,
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
      ),
    );
  }
}
