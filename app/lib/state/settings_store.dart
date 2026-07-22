import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcı tercihleri ve premium durumu.
///
/// Premium şu an yalnızca yerel bir bayraktır. Mağaza satın alma entegrasyonu
/// (in_app_purchase) eklendiğinde [setPremium] satın alma doğrulandığında
/// çağrılacak tek nokta olarak kalır.
class SettingsStore extends ChangeNotifier {
  static const _keyPremium = 'is_premium';
  static const _keyNotifyHour = 'default_notify_hour';
  static const _keyNotifyMinute = 'default_notify_minute';
  static const _keyOnboarded = 'has_onboarded';

  /// Ücretsiz sürümdeki aktif hatırlatma üst sınırı.
  static const freeReminderLimit = 10;

  SharedPreferences? _prefs;

  bool _isPremium = false;
  bool _hasOnboarded = false;
  TimeOfDay _defaultNotifyTime = const TimeOfDay(hour: 9, minute: 0);

  bool get isPremium => _isPremium;
  bool get hasOnboarded => _hasOnboarded;
  TimeOfDay get defaultNotifyTime => _defaultNotifyTime;

  Future<void> load() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    _isPremium = prefs.getBool(_keyPremium) ?? false;
    _hasOnboarded = prefs.getBool(_keyOnboarded) ?? false;
    _defaultNotifyTime = TimeOfDay(
      hour: prefs.getInt(_keyNotifyHour) ?? 9,
      minute: prefs.getInt(_keyNotifyMinute) ?? 0,
    );
    notifyListeners();
  }

  Future<void> setPremium(bool value) async {
    if (_isPremium == value) return;
    _isPremium = value;
    await _prefs?.setBool(_keyPremium, value);
    notifyListeners();
  }

  Future<void> setDefaultNotifyTime(TimeOfDay time) async {
    _defaultNotifyTime = time;
    await _prefs?.setInt(_keyNotifyHour, time.hour);
    await _prefs?.setInt(_keyNotifyMinute, time.minute);
    notifyListeners();
  }

  Future<void> markOnboarded() async {
    if (_hasOnboarded) return;
    _hasOnboarded = true;
    await _prefs?.setBool(_keyOnboarded, true);
    notifyListeners();
  }
}
