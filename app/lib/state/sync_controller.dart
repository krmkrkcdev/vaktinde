import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/sync_service.dart';
import 'auth_store.dart';
import 'reminder_store.dart';
import 'settings_store.dart';

/// Senkronizasyonu arayüze bağlar: ne zaman çalışacağına karar verir ve
/// sonucunu gösterilebilir bir duruma çevirir.
///
/// Senkronizasyon hiçbir zaman kullanıcıyı bekletmez. Başarısız olursa
/// uygulama yerel veriyle çalışmaya devam eder; bir sonraki fırsatta
/// yeniden denenir.
class SyncController extends ChangeNotifier {
  SyncController({required AuthStore auth, required SettingsStore settings})
    : _auth = auth,
      _settings = settings,
      _sync = SyncService(api: auth.api) {
    _auth.addListener(_onAuthChanged);
    // Premium'a geçildiğinde birikmiş yerel değişiklikler yüklensin;
    // premium bırakılırsa senkronizasyon durur.
    _settings.addListener(_onAuthChanged);
  }

  final AuthStore _auth;
  final SettingsStore _settings;
  final SyncService _sync;

  /// Bulut yedekleme premium bir özelliktir. Hem giriş yapılmış hem de premium
  /// olunmalı; ikisinden biri eksikse senkronizasyon çalışmaz.
  bool get _canSync => _auth.isSignedIn && _settings.isPremium;

  ReminderStore? _reminders;
  SyncState _state = SyncState.idle;
  DateTime? _lastSuccess;
  bool _wasSignedIn = false;

  SyncState get state => _state;
  DateTime? get lastSuccess => _lastSuccess;
  bool get isRunning => _state == SyncState.running;

  void attach(ReminderStore reminders) {
    if (_reminders != null) return;
    _reminders = reminders;
    // Oturum açık VE premium ise açılışta bir tur senkronize et.
    if (_canSync) unawaited(sync());
  }

  void _onAuthChanged() {
    final canSync = _canSync;
    if (canSync && !_wasSignedIn) {
      // Yeni giriş ya da premium'a geçiş: sunucudaki her şey çekilsin.
      unawaited(sync());
    } else if (!canSync && _wasSignedIn) {
      // Çıkış: bir sonraki girişte baştan çekilsin diye imleç sıfırlanır.
      unawaited(SyncService.resetCursor());
      _state = SyncState.idle;
      _lastSuccess = null;
      notifyListeners();
    }
    _wasSignedIn = canSync;
  }

  Future<SyncState> sync() async {
    if (!_canSync || _state == SyncState.running) return _state;

    _state = SyncState.running;
    notifyListeners();

    final result = await _sync.run();

    if (result == SyncState.idle) {
      _lastSuccess = DateTime.now();
      await _reminders?.reloadAfterSync();
    }

    _state = result;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _settings.removeListener(_onAuthChanged);
    super.dispose();
  }
}
