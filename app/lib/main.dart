import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'state/auth_store.dart';
import 'state/reminder_store.dart';
import 'state/settings_store.dart';
import 'state/sync_controller.dart';
import 'theme/app_theme.dart';

/// Reklam ve satın alma altyapısını arka planda hazırlar.
///
/// Satın alma durumu mağazadan gelince premium bayrağı güncellenir; böylece
/// cihaz değiştiren ya da aboneliği yenilenen kullanıcı ek bir işlem yapmadan
/// premium'a kavuşur.
Future<void> _initMonetization(SettingsStore settings) async {
  PurchaseService.instance.onPremiumChanged = settings.setPremium;
  await PurchaseService.instance.init();
  await AdService.instance.init();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Uygulama yalnızca dikey yönde tasarlandı; yatay düzen desteklenmiyor.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await initializeDateFormatting('tr_TR');
  await NotificationService.instance.init();

  final settings = SettingsStore();
  await settings.load();

  final auth = AuthStore();
  await auth.load();

  // Mağaza ve reklam SDK'ları açılışı bloklamamalı: ikisi de ağ bekler ve
  // hata verse bile uygulama tam olarak çalışmaya devam eder.
  unawaited(_initMonetization(settings));

  runApp(VaktindeApp(settings: settings, auth: auth));
}

class VaktindeApp extends StatelessWidget {
  const VaktindeApp({super.key, required this.settings, required this.auth});

  final SettingsStore settings;
  final AuthStore auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(
          create: (_) => ReminderStore(settings: settings)..load(),
        ),
        // Senkronizasyon, hatırlatma deposuna bağımlıdır: sunucudan veri
        // geldiğinde listeyi ve bildirimleri tazelemesi gerekir.
        ChangeNotifierProxyProvider<ReminderStore, SyncController>(
          create: (_) => SyncController(auth: auth),
          update: (_, reminders, controller) =>
              (controller ?? SyncController(auth: auth))..attach(reminders),
        ),
      ],
      child: MaterialApp(
        title: 'Vaktinde',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeScreen(),
      ),
    );
  }
}
