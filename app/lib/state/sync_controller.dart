import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/sync_service.dart';
import 'auth_store.dart';
import 'reminder_store.dart';

/// Senkronizasyonu arayüze bağlar: ne zaman çalışacağına karar verir ve
/// sonucunu gösterilebilir bir duruma çevirir.
///
/// Senkronizasyon hiçbir zaman kullanıcıyı bekletmez. Başarısız olursa
/// uygulama yerel veriyle çalışmaya devam eder; bir sonraki fırsatta
/// yeniden denenir.
class SyncController extends ChangeNotifier {
  SyncController({required AuthStore auth})
      : _auth = auth,
        _sync = SyncService(api: auth.api) {
    _auth.addListener(_onAuthChanged);
  }

  final AuthStore _auth;
  final SyncService _sync;

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
    // Oturum zaten açıksa açılışta bir tur senkronize et.
    if (_auth.isSignedIn) unawaited(sync());
  }

  void _onAuthChanged() {
    final signedIn = _auth.isSignedIn;
    if (signedIn && !_wasSignedIn) {
      // Yeni giriş: sunucudaki her şey çekilsin.
      unawaited(sync());
    } else if (!signedIn && _wasSignedIn) {
      // Çıkış: bir sonraki girişte baştan çekilsin diye imleç sıfırlanır.
      unawaited(SyncService.resetCursor());
      _state = SyncState.idle;
      _lastSuccess = null;
      notifyListeners();
    }
    _wasSignedIn = signedIn;
  }

  Future<SyncState> sync() async {
    if (!_auth.isSignedIn || _state == SyncState.running) return _state;

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
    super.dispose();
  }
}
