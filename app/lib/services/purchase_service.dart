import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Premium aboneliğinin satın alınması ve geri yüklenmesi.
///
/// Abonelik durumu cihazda [SettingsStore] içinde saklanır; mağaza her
/// açılışta geçmiş satın alımları bildirdiği için uygulama açıldığında durum
/// kendiliğinden tazelenir.
///
/// **Sunucu doğrulaması yok.** Makbuz sunucuda doğrulanmadığı sürece kararlı
/// bir kullanıcı premium'u taklit edebilir. Bu uygulama için kabul edilebilir
/// bir risk: premium yalnızca kayıt sınırını ve reklamları etkiliyor, sunucu
/// tarafında ayrıcalıklı bir kaynak tüketmiyor. Yedekleme kotası gibi gerçek
/// maliyeti olan bir ayrıcalık eklenirse makbuz backend'de doğrulanmalıdır.
class PurchaseService {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  /// App Store Connect'te tanımlanan abonelik ürün kimliği.
  ///
  /// Bu kimlik mağazadaki ürünle birebir aynı olmalıdır; farklıysa ürün
  /// listesi boş döner ve satın alma ekranı fiyat gösteremez.
  static const yearlyProductId = 'com.vaktinde.app.premium.yearly';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// Premium durumu değiştiğinde çağrılır (satın alma ya da geri yükleme).
  void Function(bool isPremium)? onPremiumChanged;

  ProductDetails? _yearly;
  ProductDetails? get yearlyProduct => _yearly;

  bool _available = false;
  bool get storeAvailable => _available;

  Future<void> init() async {
    _available = await _iap.isAvailable();
    if (!_available) return;

    _subscription ??= _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object e) => debugPrint('Satın alma akışı hatası: $e'),
    );

    final response = await _iap.queryProductDetails({yearlyProductId});
    if (response.productDetails.isNotEmpty) {
      _yearly = response.productDetails.first;
    } else {
      // Ürün bulunamadı: App Store Connect'te tanımlı değil, henüz
      // onaylanmamış ya da "Paid Applications" sözleşmesi imzalanmamış.
      debugPrint(
        'Premium ürünü bulunamadı: ${response.notFoundIDs}. '
        'App Store Connect ürün tanımını ve sözleşme durumunu kontrol edin.',
      );
    }
  }

  /// Yıllık aboneliği satın alma akışını başlatır.
  ///
  /// Sonuç anında dönmez; mağaza akışı [onPremiumChanged] ile bildirilir.
  Future<bool> buyYearly() async {
    final product = _yearly;
    if (product == null) return false;
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Önceki satın alımları geri yükler. Apple bunu ekranda sunmayı zorunlu
  /// tutuyor: cihaz değiştiren kullanıcı tekrar ödemek zorunda kalmamalı.
  Future<void> restore() => _iap.restorePurchases();

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.productID == yearlyProductId) {
            onPremiumChanged?.call(true);
          }
        case PurchaseStatus.error:
          debugPrint('Satın alma hatası: ${purchase.error}');
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }

      // Tamamlanmayan işlem mağaza kuyruğunda kalır ve her açılışta tekrar
      // bildirilir; bu yüzden her durumda kapatılması gerekir.
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
