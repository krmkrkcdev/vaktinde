import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/reminder_store.dart';
import 'premium_screen.dart';

/// Tamamlanmış / arşivlenmiş hatırlatmalar.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final archived = context.watch<ReminderStore>().archived;

    return Scaffold(
      appBar: AppBar(title: const Text('Arşiv')),
      body: archived.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Tamamladığınız hatırlatmalar burada birikir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.separated(
              // Alt güvenli alan: son satır ana ekran çubuğunun altında kalmasın.
              padding: EdgeInsets.only(
                top: 8,
                bottom: 8 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: archived.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reminder = archived[index];
                return ListTile(
                  leading: Icon(
                    reminder.category.icon,
                    color: reminder.category.color,
                  ),
                  title: Text(reminder.title),
                  subtitle: Text(
                    '${reminder.category.label} · '
                    '${DateFormat('d MMMM yyyy', 'tr_TR').format(reminder.dueDate)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => value == 'restore'
                        ? _restore(context, reminder)
                        : _delete(context, reminder),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'restore', child: Text('Geri al')),
                      PopupMenuItem(value: 'delete', child: Text('Kalıcı sil')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _restore(BuildContext context, Reminder reminder) async {
    final store = context.read<ReminderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await store.restore(reminder);
      messenger.showSnackBar(
        SnackBar(content: Text('"${reminder.title}" listeye geri alındı.')),
      );
    } on ReminderLimitException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Ücretsiz sürümde en fazla ${e.limit} hatırlatma.'),
          action: SnackBarAction(
            label: 'Premium',
            onPressed: () => navigator.push(
              MaterialPageRoute(builder: (_) => const PremiumScreen()),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, Reminder reminder) async {
    await context.read<ReminderStore>().delete(reminder);
  }
}
