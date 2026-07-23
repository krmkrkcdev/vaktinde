import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import '../services/ad_service.dart';
import '../state/settings_store.dart';

/// Liste sonunda gösterilen banner reklam.
///
/// Premium kullanıcıda ve reklam yüklenemediğinde **hiç yer kaplamaz**:
/// boş bir gri kutu bırakmak, reklamın kendisinden daha rahatsız edici olur.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Premium durumu ilk karede okunabilsin diye kare sonrasına bırakılır.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (context.read<SettingsStore>().isPremium) return;

    await AdService.instance.init();
    if (!mounted) return;

    final ad = BannerAd(
      adUnitId: AdService.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _loaded = false);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Premium olunca reklam anında kaybolur (satın alma sonrası bekleme yok).
    if (context.watch<SettingsStore>().isPremium) {
      return const SizedBox.shrink();
    }

    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
          const SizedBox(height: 6),
          Text(
            'Reklamsız kullanmak için Premium',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
