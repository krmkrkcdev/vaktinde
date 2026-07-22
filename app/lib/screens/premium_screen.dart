import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_store.dart';

/// Premium tanıtım ekranı.
///
/// İlk sürümde mağaza entegrasyonu yoktur; satın alma akışı eklendiğinde
/// [_buy] içindeki TODO doldurulup [SettingsStore.setPremium] satın alma
/// doğrulandıktan sonra çağrılır.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  static const _benefits = [
    (Icons.all_inclusive, 'Sınırsız hatırlatma',
        'Ücretsiz sürümdeki 10 kayıt sınırı kalkar.'),
    (Icons.cloud_upload_outlined, 'Bulut yedekleme',
        'Telefonunuzu değiştirseniz de kayıtlarınız sizinle gelir.'),
    (Icons.family_restroom_outlined, 'Aileyle paylaşma',
        'Kira, aidat, muayene gibi ortak tarihleri birlikte takip edin.'),
    (Icons.block_outlined, 'Reklamsız kullanım',
        'Hiçbir reklam gösterilmez.'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.workspace_premium,
              size: 36,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Vaktinde Premium',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Tek seferlik ödeme. Abonelik yok, yenileme yok.',
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          for (final (icon, title, description) in _benefits) ...[
            _Benefit(icon: icon, title: title, description: description),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 12),
          if (settings.isPremium)
            Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: scheme.primary),
                title: const Text('Premium etkin'),
                subtitle: const Text('Tüm özellikler açık. Teşekkürler!'),
              ),
            )
          else ...[
            FilledButton(
              onPressed: () => _buy(context),
              child: const Text('Premium\'a geç'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _restore(context),
              child: const Text('Satın alımları geri yükle'),
            ),
          ],
          if (kDebugMode) ...[
            const Divider(height: 32),
            SwitchListTile(
              title: const Text('Geliştirici: premium aç/kapa'),
              subtitle: const Text('Yalnızca debug derlemesinde görünür'),
              value: settings.isPremium,
              onChanged: settings.setPremium,
            ),
          ],
        ],
      ),
    );
  }

  void _buy(BuildContext context) {
    // TODO(iap): in_app_purchase ile tek seferlik ürünü satın al, satın alma
    // doğrulandıktan sonra context.read<SettingsStore>().setPremium(true).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Satın alma yakında: mağaza entegrasyonu hazırlanıyor.'),
      ),
    );
  }

  void _restore(BuildContext context) {
    // TODO(iap): in_app_purchase restorePurchases() çağrısı.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Geri yüklenecek satın alma bulunamadı.')),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: scheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
