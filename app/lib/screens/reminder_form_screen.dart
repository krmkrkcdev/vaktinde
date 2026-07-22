import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../models/reminder_category.dart';
import '../models/repeat_interval.dart';
import '../services/notification_service.dart';
import '../state/reminder_store.dart';
import '../state/settings_store.dart';
import '../widgets/photo_gallery_field.dart';
import 'premium_screen.dart';

/// Kategori seç → başlık yaz → tarih belirle → kaç gün önce → kaydet.
class ReminderFormScreen extends StatefulWidget {
  const ReminderFormScreen({super.key, this.existing});

  final Reminder? existing;

  @override
  State<ReminderFormScreen> createState() => _ReminderFormScreenState();
}

class _ReminderFormScreenState extends State<ReminderFormScreen> {
  static const _leadOptions = [0, 1, 3, 7, 15, 30, 60, 90];

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountController = TextEditingController();

  late ReminderCategory _category;
  late DateTime _dueDate;
  late Set<int> _leadDays;
  late TimeOfDay _notifyTime;
  late RepeatInterval _repeat;
  late List<String> _photoNames;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final defaultTime = context.read<SettingsStore>().defaultNotifyTime;

    if (existing != null) {
      _category = existing.category;
      _dueDate = existing.dueDate;
      _leadDays = existing.leadDays.toSet();
      _notifyTime = TimeOfDay(
        hour: existing.notifyHour,
        minute: existing.notifyMinute,
      );
      _repeat = existing.repeat;
      _photoNames = [...existing.photoPaths];
      _titleController.text = existing.title;
      _noteController.text = existing.note ?? '';
      if (existing.amount != null) {
        _amountController.text =
            existing.amount!.toStringAsFixed(existing.amount! % 1 == 0 ? 0 : 2);
      }
    } else {
      _category = ReminderCategory.all.first;
      _dueDate = DateTime.now().add(const Duration(days: 30));
      _leadDays = _category.defaultLeadDays.toSet();
      _notifyTime = defaultTime;
      _repeat = _category.defaultRepeat;
      _photoNames = [];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _selectCategory(ReminderCategory category) {
    setState(() {
      final wasDefaultLeads =
          _setEquals(_leadDays, _category.defaultLeadDays.toSet());
      final wasDefaultRepeat = _repeat == _category.defaultRepeat;
      _category = category;
      // Kullanıcı elle değiştirmediyse yeni kategorinin önerilerini uygula.
      if (wasDefaultLeads) _leadDays = category.defaultLeadDays.toSet();
      if (wasDefaultRepeat) _repeat = category.defaultRepeat;
    });
  }

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.every(b.contains);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 25),
      helpText: 'Son tarihi seçin',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _notifyTime,
      helpText: 'Bildirim saati',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null) setState(() => _notifyTime = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_leadDays.isEmpty) {
      _snack('En az bir hatırlatma zamanı seçin.');
      return;
    }

    setState(() => _saving = true);
    final store = context.read<ReminderStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final leads = _leadDays.toList()..sort((a, b) => b.compareTo(a));
    final note = _noteController.text.trim();
    final amount = _parseAmount(_amountController.text);
    final dueDate = DateTime(_dueDate.year, _dueDate.month, _dueDate.day);
    final existing = widget.existing;

    // Düzenlemede copyWith kullanılır: uuid ve createdAt korunur, updatedAt
    // otomatik tazelenir. Yeni kayıtta bu ekran kullanılmaz (sihirbaz var)
    // ama tamlık için desteklenir.
    final reminder = existing != null
        ? existing.copyWith(
            categoryId: _category.id,
            title: _titleController.text.trim(),
            note: note.isEmpty ? null : note,
            clearNote: note.isEmpty,
            dueDate: dueDate,
            leadDays: leads,
            notifyHour: _notifyTime.hour,
            notifyMinute: _notifyTime.minute,
            repeat: _repeat,
            amount: amount,
            clearAmount: amount == null,
            photoPaths: _photoNames,
          )
        : Reminder.create(
            categoryId: _category.id,
            title: _titleController.text.trim(),
            note: note.isEmpty ? null : note,
            dueDate: dueDate,
            leadDays: leads,
            notifyHour: _notifyTime.hour,
            notifyMinute: _notifyTime.minute,
            repeat: _repeat,
            amount: amount,
            photoPaths: _photoNames,
          );

    try {
      await NotificationService.instance.requestPermissions();
      if (_isEditing) {
        await store.update(reminder);
      } else {
        await store.add(reminder);
      }
      navigator.pop();
    } on ReminderLimitException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  static double? _parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll('.', '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete() async {
    final reminder = widget.existing;
    if (reminder == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hatırlatma silinsin mi?'),
        content: Text('"${reminder.title}" ve bildirimleri kaldırılacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final store = context.read<ReminderStore>();
    final navigator = Navigator.of(context);
    await store.delete(reminder);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Hatırlatmayı düzenle' : 'Yeni hatırlatma'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const _SectionLabel('Kategori'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in ReminderCategory.all)
                  ChoiceChip(
                    selected: category.id == _category.id,
                    onSelected: (_) => _selectCategory(category),
                    avatar: Icon(
                      category.icon,
                      size: 18,
                      color: category.id == _category.id
                          ? category.color
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(category.label),
                    showCheckmark: false,
                    selectedColor: category.color.withValues(alpha: 0.14),
                  ),
              ],
            ),

            const _SectionLabel('Başlık'),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _category.hint,
                prefixIcon: const Icon(Icons.title),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Başlık gerekli' : null,
            ),

            const _SectionLabel('Son tarih'),
            _TappableField(
              icon: Icons.event_outlined,
              label: DateFormat('d MMMM yyyy, EEEE', 'tr_TR').format(_dueDate),
              trailing: _remainingLabel(),
              onTap: _pickDate,
            ),

            const _SectionLabel('Kaç gün önce hatırlatılsın?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _leadOptions)
                  FilterChip(
                    selected: _leadDays.contains(option),
                    label: Text(option == 0 ? 'Aynı gün' : '$option gün önce'),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _leadDays.add(option);
                      } else {
                        _leadDays.remove(option);
                      }
                    }),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Birden fazla seçebilirsiniz. Yalnızca seçtiğiniz günlerde '
                'bildirim gönderilir.',
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
            ),

            const _SectionLabel('Bildirim saati'),
            _TappableField(
              icon: Icons.schedule_outlined,
              label: _notifyTime.format(context),
              onTap: _pickTime,
            ),

            const _SectionLabel('Tekrar'),
            SegmentedButton<RepeatInterval>(
              segments: [
                for (final r in RepeatInterval.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_repeat},
              onSelectionChanged: (selection) =>
                  setState(() => _repeat = selection.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),

            const _SectionLabel('Tutar (isteğe bağlı)'),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                hintText: 'Örn. 1.250,00',
                prefixIcon: Icon(Icons.payments_outlined),
                suffixText: '₺',
              ),
            ),

            const _SectionLabel('Belge fotoğrafları (isteğe bağlı)'),
            PhotoGalleryField(
              photoNames: _photoNames,
              onChanged: (names) => setState(() => _photoNames = names),
            ),

            const _SectionLabel('Not (isteğe bağlı)'),
            TextFormField(
              controller: _noteController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Poliçe numarası, kurum adı, IBAN…',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Değişiklikleri kaydet' : 'Hatırlatmayı kaydet'),
        ),
      ),
    );
  }

  String _remainingLabel() {
    final today = DateTime.now();
    final days = DateTime(_dueDate.year, _dueDate.month, _dueDate.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days < 0) return '${-days} gün geçti';
    if (days == 0) return 'Bugün';
    return '$days gün';
  }

}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TappableField extends StatelessWidget {
  const _TappableField({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(prefixIcon: Icon(icon)),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15.5))),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
