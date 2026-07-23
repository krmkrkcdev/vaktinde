import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/payment_totals.dart';
import '../models/reminder.dart';
import '../models/repeat_interval.dart';
import '../state/reminder_store.dart';
import '../state/settings_store.dart';
import '../widgets/reminder_card.dart';
import 'premium_screen.dart';
import 'reminder_form_screen.dart';
import 'reminder_wizard_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ReminderStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vaktinde'),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Yeni hatırlatma'),
      ),
      body: store.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _Body(reminders: store.active),
    );
  }

  /// Yeni kayıt adım adım sihirbazla, düzenleme tek sayfalık formla açılır.
  static Future<void> _openForm(
    BuildContext context, [
    Reminder? existing,
  ]) async {
    final store = context.read<ReminderStore>();

    if (existing == null && !store.canAddReminder) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => existing == null
            ? const ReminderWizardScreen()
            : ReminderFormScreen(existing: existing),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.reminders});

  final List<Reminder> reminders;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) return const _EmptyState();

    final groups = _groupByUrgency(reminders);

    return ListView(
      // Alt boşluk: genişletilmiş FAB (~72) + güvenli alan; son kart FAB'ın
      // ya da ana ekran çubuğunun altında kalmasın.
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        88 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        const _QuotaBanner(),
        const SizedBox(height: 12),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Row(
              children: [
                Text(
                  group.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${group.items.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          for (final reminder in group.items) ...[
            ReminderCard(
              reminder: reminder,
              onTap: () => HomeScreen._openForm(context, reminder),
              onComplete: () => _complete(context, reminder),
            ),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 8),
        _TotalsCard(reminders: reminders),
      ],
    );
  }

  Future<void> _complete(BuildContext context, Reminder reminder) async {
    final store = context.read<ReminderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final previous = await store.markCompleted(reminder);

    final message = reminder.repeat == RepeatInterval.none
        ? '"${reminder.title}" arşivlendi.'
        : '"${reminder.title}" sonraki döneme taşındı.';

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackDuration,
        content: Text(message),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => store.undoCompleted(previous),
        ),
      ),
    );
  }

  static List<_Group> _groupByUrgency(List<Reminder> reminders) {
    final overdue = <Reminder>[];
    final thisWeek = <Reminder>[];
    final thisMonth = <Reminder>[];
    final later = <Reminder>[];

    for (final r in reminders) {
      final d = r.daysRemaining;
      if (d < 0) {
        overdue.add(r);
      } else if (d <= 7) {
        thisWeek.add(r);
      } else if (d <= 30) {
        thisMonth.add(r);
      } else {
        later.add(r);
      }
    }

    return [
      if (overdue.isNotEmpty) _Group('GECİKMİŞ', overdue),
      if (thisWeek.isNotEmpty) _Group('BU HAFTA', thisWeek),
      if (thisMonth.isNotEmpty) _Group('BU AY', thisMonth),
      if (later.isNotEmpty) _Group('DAHA SONRA', later),
    ];
  }
}

class _Group {
  const _Group(this.title, this.items);
  final String title;
  final List<Reminder> items;
}

/// Ücretsiz sürümde kalan hak; premiumda gizlenir.
class _QuotaBanner extends StatelessWidget {
  const _QuotaBanner();

  @override
  Widget build(BuildContext context) {
    final remaining = context.watch<ReminderStore>().remainingFreeSlots;
    if (remaining == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final isLow = remaining <= 2;

    return Material(
      color: isLow
          ? scheme.errorContainer.withValues(alpha: 0.5)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isLow ? Icons.info_outline : Icons.workspace_premium_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'Ücretsiz hakkınız doldu. Sınırsız hatırlatma için Premium.'
                      : '$remaining ücretsiz hatırlatma hakkınız kaldı',
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Küçük ekran ya da büyük yazı tipi ölçeğinde içerik sığmayınca taşma
    // yerine kaydırılabilsin; normalde dikeyde ortalı kalır.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  size: 40,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Hiçbir şeyi kaçırmayın',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Muayene, sigorta, kira, fatura, aidat, abonelik ve garanti '
                'tarihlerinizi ekleyin. Tarih yaklaşınca sizi uyaralım.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => HomeScreen._openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('İlk hatırlatmanı ekle'),
              ),
              const SizedBox(height: 12),
              Text(
                'Ücretsiz sürümde ${SettingsStore.freeReminderLimit} hatırlatma',
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Düzenli ödemelerin özeti.
///
/// İki bölüm gösterir: aynı sıklıktaki ödemelerin kendi içindeki toplamı
/// (kullanıcının kafasındaki gerçek rakam) ve hepsinin tek ölçüye indirilmiş
/// hâli ("toplamda ayda ne kadar gidiyor?").
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.reminders});

  final List<Reminder> reminders;

  @override
  Widget build(BuildContext context) {
    final totals = PaymentTotals.from(reminders);
    if (totals.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Düzenli ödemelerim',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          for (final entry in totals.byInterval.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key.label,
                      style: const TextStyle(fontSize: 14.5),
                    ),
                  ),
                  Text(
                    money.format(entry.value),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

          Divider(height: 24, color: scheme.outlineVariant),

          Text(
            'Hepsi birlikte',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _TotalColumn(label: 'Günlük', value: money.format(totals.daily)),
              _TotalColumn(
                label: 'Haftalık',
                value: money.format(totals.weekly),
              ),
              _TotalColumn(label: 'Aylık', value: money.format(totals.monthly)),
              _TotalColumn(label: 'Yıllık', value: money.format(totals.yearly)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${totals.countedReminders} tekrar eden ödeme hesaba katıldı. '
            'Tek seferlik kayıtlar dahil değildir.',
            style: TextStyle(fontSize: 12, color: scheme.outline, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _TotalColumn extends StatelessWidget {
  const _TotalColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
