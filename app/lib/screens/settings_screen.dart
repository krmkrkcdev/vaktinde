import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../state/auth_store.dart';
import '../state/reminder_store.dart';
import '../state/settings_store.dart';
import '../state/sync_controller.dart';
import '../widgets/nag_interval_selector.dart';
import 'archive_screen.dart';
import 'auth_screen.dart';
import 'premium_screen.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final store = context.watch<ReminderStore>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        // Son öğe ve açıklama metni ana ekran çubuğunun altında kalmasın.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
          const _AccountSection(),
          const Divider(height: 1),

          ListTile(
            leading: Icon(
              Icons.workspace_premium_outlined,
              color: scheme.primary,
            ),
            title: Text(
              settings.isPremium ? 'Premium etkin' : 'Premium\'a geç',
            ),
            subtitle: Text(
              settings.isPremium
                  ? 'Sınırsız hatırlatma açık'
                  : '${store.activeCount}/${SettingsStore.freeReminderLimit} '
                        'hatırlatma kullanıldı',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Varsayılan bildirim saati'),
            subtitle: const Text('Yeni hatırlatmalar bu saatle başlar'),
            trailing: Text(
              settings.defaultNotifyTime.format(context),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: settings.defaultNotifyTime,
                helpText: 'Varsayılan bildirim saati',
                cancelText: 'Vazgeç',
                confirmText: 'Seç',
              );
              if (picked != null) await settings.setDefaultNotifyTime(picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.replay),
            title: const Text('Tamamlanmazsa tekrar hatırlat'),
            subtitle: const Text('Yeni hatırlatmalar için varsayılan'),
            trailing: Text(
              NagIntervalSelector.labelFor(settings.defaultNagIntervalHours),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            onTap: () => _pickNagInterval(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Bildirim izinlerini kontrol et'),
            subtitle: const Text('Bildirim gelmiyorsa buradan izin verin'),
            onTap: () => _checkPermissions(context),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Bildirimleri yeniden planla'),
            subtitle: const Text('Tüm hatırlatmalar için bildirimler kurulur'),
            onTap: () => _reschedule(context),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Arşiv'),
            subtitle: Text('${store.archived.length} tamamlanmış hatırlatma'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ArchiveScreen())),
          ),
          const Divider(height: 1),

          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(
              'Tüm verileri sil',
              style: TextStyle(color: scheme.error),
            ),
            subtitle: const Text('Geri alınamaz'),
            onTap: () => _confirmWipe(context),
          ),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              context.watch<AuthStore>().isSignedIn
                  ? 'Hatırlatmalarınız ve belge fotoğraflarınız telefonunuzda '
                        'saklanır ve hesabınıza yedeklenir. Çıkış yaparsanız '
                        'yedekleme durur, kayıtlarınız telefonda kalır.'
                  : 'Verileriniz yalnızca bu telefonda saklanır. Giriş '
                        'yapmadığınız sürece sunucuya hiçbir bilgi gönderilmez.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Varsayılan tekrar aralığını seçtirir.
  Future<void> _pickNagInterval(
    BuildContext context,
    SettingsStore settings,
  ) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tamamlanmazsa tekrar hatırlat',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            for (final option in SettingsStore.nagIntervalOptions)
              ListTile(
                title: Text(NagIntervalSelector.labelFor(option)),
                trailing: settings.defaultNagIntervalHours == option
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await settings.setDefaultNagIntervalHours(picked);
  }

  Future<void> _checkPermissions(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await NotificationService.instance.requestPermissions();
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackDuration,
        content: Text(
          granted
              ? 'Bildirim izni verildi.'
              : 'Bildirim izni kapalı. Telefon ayarlarından açmanız gerekiyor.',
        ),
      ),
    );
  }

  Future<void> _reschedule(BuildContext context) async {
    final store = context.read<ReminderStore>();
    final messenger = ScaffoldMessenger.of(context);
    await NotificationService.instance.rescheduleAll(store.active);
    final pending = await NotificationService.instance.pending();
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackDuration,
        content: Text('${pending.length} bildirim planlandı.'),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tüm veriler silinsin mi?'),
        content: const Text(
          'Bütün hatırlatmalarınız ve bildirimleriniz kalıcı olarak silinecek. '
          'Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Hepsini sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final store = context.read<ReminderStore>();
    final messenger = ScaffoldMessenger.of(context);
    await store.deleteAll();
    messenger.showSnackBar(
      const SnackBar(
        duration: kSnackDuration,
        content: Text('Tüm veriler silindi.'),
      ),
    );
  }
}

/// Bulut yedekleme ve hesap bölümü.
///
/// Hesap açmak isteğe bağlıdır; uygulama girişsiz de tam olarak çalışır.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final sync = context.watch<SyncController>();
    final scheme = Theme.of(context).colorScheme;

    if (!auth.isSignedIn) {
      return ListTile(
        leading: Icon(Icons.cloud_off_outlined, color: scheme.onSurfaceVariant),
        title: const Text('Bulut yedekleme kapalı'),
        subtitle: const Text(
          'Giriş yapın; telefon değiştirdiğinizde kayıtlarınız geri gelsin',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
      );
    }

    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.cloud_done_outlined, color: scheme.primary),
          title: Text(auth.email ?? 'Hesabım'),
          subtitle: Text(_statusText(sync)),
        ),
        ListTile(
          leading: sync.isRunning
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.sync),
          title: const Text('Şimdi yedekle'),
          enabled: !sync.isRunning,
          onTap: () => _syncNow(context),
        ),
        ListTile(
          leading: Icon(Icons.logout, color: scheme.error),
          title: Text('Çıkış yap', style: TextStyle(color: scheme.error)),
          subtitle: const Text('Kayıtlarınız bu telefonda kalır'),
          onTap: () => _confirmSignOut(context),
        ),
        ListTile(
          leading: Icon(Icons.person_remove_outlined, color: scheme.error),
          title: Text('Hesabımı sil', style: TextStyle(color: scheme.error)),
          subtitle: const Text(
            'Buluttaki tüm verileriniz kalıcı olarak silinir',
          ),
          onTap: () => _confirmDeleteAccount(context),
        ),
      ],
    );
  }

  /// Hesap silme akışı: önce ne olacağını anlatır, sonra şifre ister.
  ///
  /// İki aşamalı olmasının sebebi işlemin geri alınamaz olması; tek dokunuşla
  /// yanlışlıkla tetiklenmemeli.
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hesabınız silinsin mi?'),
        content: const Text(
          'Buluttaki hatırlatmalarınız ve belge fotoğraflarınız kalıcı olarak '
          'silinecek. Bu işlem geri alınamaz.\n\n'
          'Bu telefondaki kayıtlarınız silinmez; onları da kaldırmak için '
          '"Tüm verileri sil" seçeneğini kullanın.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Devam et'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _PasswordPrompt(),
    );
    if (password == null || password.isEmpty || !context.mounted) return;

    final auth = context.read<AuthStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await auth.deleteAccount(password);
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackDuration,
          content: Text('Hesabınız silindi.'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(duration: kSnackDuration, content: Text(e.message)),
      );
    } on NetworkUnavailableException {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackDuration,
          content: Text(
            'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
          ),
        ),
      );
    }
  }

  static String _statusText(SyncController sync) {
    switch (sync.state) {
      case SyncState.running:
        return 'Yedekleniyor…';
      case SyncState.offline:
        return 'İnternet yok — bağlanınca yedeklenecek';
      case SyncState.failed:
        return 'Son yedekleme başarısız oldu';
      case SyncState.idle:
        final at = sync.lastSuccess;
        if (at == null) return 'Bulut yedekleme açık';
        return 'Son yedekleme: ${DateFormat('d MMM HH:mm', 'tr_TR').format(at)}';
    }
  }

  Future<void> _syncNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<SyncController>().sync();
    messenger.showSnackBar(
      SnackBar(
        duration: kSnackDuration,
        content: Text(switch (result) {
          SyncState.idle => 'Yedekleme tamamlandı.',
          SyncState.offline => 'İnternet bağlantısı yok.',
          SyncState.failed =>
            'Yedekleme başarısız oldu, sonra tekrar denenecek.',
          SyncState.running => 'Yedekleme sürüyor…',
        }),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text(
          'Hatırlatmalarınız bu telefonda kalmaya devam eder. Tekrar giriş '
          'yaptığınızda buluttaki kayıtlarınızla birleşir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<AuthStore>().signOut();
  }
}

/// Hesap silmeden önce şifreyi bir kez daha ister.
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt();

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Şifrenizi girin'),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Şifre',
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Hesabımı sil'),
        ),
      ],
    );
  }
}
