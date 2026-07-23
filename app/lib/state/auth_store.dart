import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_client.dart';

/// Sunucu adresi. Sürüm derlemesinde değiştirmek için:
///   flutter build apk --dart-define=API_BASE_URL=https://...
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://vaktinde.devposs.com',
);

/// Oturum durumu ve token saklama.
///
/// Tokenlar `shared_preferences` yerine güvenli depoda tutulur: Android'de
/// Keystore, iOS'ta Keychain. Yedeklemelere düz metin olarak sızmazlar.
class AuthStore extends ChangeNotifier {
  AuthStore({ApiClient? api, FlutterSecureStorage? storage})
    : api = api ?? ApiClient(baseUrl: apiBaseUrl),
      _storage = storage ?? const FlutterSecureStorage() {
    this.api.onTokensChanged = _persist;
    this.api.onSessionExpired = () {
      // Yenileme tokeni de geçersizse kullanıcı düşürülür.
      signOut();
    };
  }

  static const _keyAccess = 'auth_access_token';
  static const _keyRefresh = 'auth_refresh_token';
  static const _keyEmail = 'auth_email';

  /// Statik olarak premium sayılan hesaplar (geliştirici / test).
  ///
  /// Bu hesaplar App Store aboneliği satın almadan premium olur; premium'a
  /// bağlı özellikleri (bulut yedekleme, sınırsız hatırlatma, reklamsız)
  /// yayın öncesi test etmek içindir. E-postalar küçük harfle yazılmalı;
  /// karşılaştırma normalize edilmiş [_email] ile yapılır.
  static const _premiumEmails = {'keremkarakoc.dev@gmail.com'};

  final ApiClient api;
  final FlutterSecureStorage _storage;

  String? _email;
  bool _isLoading = true;
  bool _busy = false;

  String? get email => _email;
  bool get isSignedIn => _email != null && api.hasSession;
  bool get isLoading => _isLoading;
  bool get isBusy => _busy;

  /// Oturumdaki hesap statik premium listesinde mi?
  bool get isPremiumAccount =>
      _email != null && _premiumEmails.contains(_email);

  /// Statik premium bir hesap giriş yaptığında ya da açılışta böyle bir oturum
  /// bulunduğunda çağrılır; premium bayrağını açmak için [SettingsStore] buna
  /// bağlanır.
  void Function()? onPremiumAccountDetected;

  Future<void> load() async {
    try {
      final access = await _storage.read(key: _keyAccess);
      final refresh = await _storage.read(key: _keyRefresh);
      _email = await _storage.read(key: _keyEmail);
      if (refresh != null) api.setTokens(access, refresh);
    } catch (e) {
      // Güvenli depo okunamazsa (ör. cihaz kilidi sıfırlandı) oturumsuz
      // başlarız; uygulama çevrimdışı olarak çalışmaya devam eder.
      debugPrint('Oturum okunamadı: $e');
    }
    if (isPremiumAccount) onPremiumAccountDetected?.call();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persist(String access, String refresh) async {
    await _storage.write(key: _keyAccess, value: access);
    await _storage.write(key: _keyRefresh, value: refresh);
  }

  Future<void> register(String email, String password) =>
      _authenticate(email, () => api.register(email, password));

  Future<void> signIn(String email, String password) =>
      _authenticate(email, () => api.login(email, password));

  Future<void> _authenticate(
    String email,
    Future<void> Function() action,
  ) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
      _email = email.trim().toLowerCase();
      await _storage.write(key: _keyEmail, value: _email);
      if (isPremiumAccount) onPremiumAccountDetected?.call();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Hesabı sunucudan siler ve yerel oturumu kapatır.
  ///
  /// Cihazdaki hatırlatmalar bu işlemle silinmez; kullanıcı yalnızca bulut
  /// hesabından çıkmış olur. Yerel verileri silmek ayrı bir seçenektir
  /// (Ayarlar → Tüm verileri sil).
  Future<void> deleteAccount(String password) async {
    _busy = true;
    notifyListeners();
    try {
      await api.deleteAccount(password);
      await signOut();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    api.clear();
    _email = null;
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
    await _storage.delete(key: _keyEmail);
    notifyListeners();
  }
}
