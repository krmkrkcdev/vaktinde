import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Reklam kimlikleri ve gösterim kuralları.
///
/// Reklamlar yalnızca ücretsiz kullanıcılara gösterilir; premium kontrolü
/// çağıran tarafta yapılır ([SettingsStore.isPremium]).
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  /// Google'ın herkese açık test kimlikleri.
  ///
  /// Kendi kimliklerinizle çalışmak için `--dart-define` verin:
  ///   flutter build ios --dart-define=ADMOB_BANNER_IOS=ca-app-pub-...
  ///
  /// DİKKAT: Gerçek kimliklerle geliştirme yapıp kendi reklamlarınıza
  /// tıklamak AdMob hesabının kapatılmasına yol açar. Bu yüzden varsayılan
  /// bilinçli olarak test kimliğidir.
  static const _testBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/4411468910';

  static const _bannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: _testBanner,
  );
  static const _interstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
    defaultValue: _testInterstitial,
  );
  static const _bannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: _testBanner,
  );
  static const _interstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: _testInterstitial,
  );

  static String get bannerUnitId =>
      Platform.isIOS ? _bannerIos : _bannerAndroid;
  static String get interstitialUnitId =>
      Platform.isIOS ? _interstitialIos : _interstitialAndroid;

  /// Gerçek kimlikler verilmemişse test reklamı gösteriliyor demektir.
  static bool get usingTestIds => _bannerIos == _testBanner;

  bool _initialized = false;

  // ------------------------------------------------- tam ekran reklam kuralı

  /// Tam ekran reklam en fazla bu sıklıkta gösterilir.
  ///
  /// Kullanıcı arka arkaya hatırlatma tamamlarken her seferinde tam ekran
  /// reklam görmemeli; hem sayaç hem zaman aralığı bu yüzden var.
  static const _showEveryNCompletions = 4;
  static const _minGapBetweenAds = Duration(minutes: 5);

  int _completionsSinceAd = 0;
  DateTime? _lastInterstitialAt;
  InterstitialAd? _interstitial;

  Future<void> init() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    _preloadInterstitial();
  }

  void _preloadInterstitial() {
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) {
          // Reklam yüklenemezse uygulama normal çalışmaya devam eder.
          debugPrint('Tam ekran reklam yüklenemedi: ${error.message}');
          _interstitial = null;
        },
      ),
    );
  }

  /// Bir hatırlatma tamamlandığında çağrılır. Koşullar uygunsa tam ekran
  /// reklam gösterir.
  ///
  /// Bilinçli olarak yalnızca "tamamlandı" işaretlemesine bağlı: kayıt
  /// oluşturma ve düzenleme akışları kullanıcının iş yaptığı anlardır ve
  /// reklamla bölünmemelidir.
  Future<void> onReminderCompleted({required bool isPremium}) async {
    if (isPremium) return;
    await init();

    _completionsSinceAd++;
    if (_completionsSinceAd < _showEveryNCompletions) return;

    final last = _lastInterstitialAt;
    if (last != null && DateTime.now().difference(last) < _minGapBetweenAds) {
      return;
    }

    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    _completionsSinceAd = 0;
    _lastInterstitialAt = DateTime.now();
    _interstitial = null;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _preloadInterstitial();
      },
    );
    await ad.show();
  }

  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
  }
}
