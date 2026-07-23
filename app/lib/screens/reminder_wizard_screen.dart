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

/// Yeni hatırlatma eklemek için adım adım kurulum akışı.
///
/// Her ekranda tek bir soru sorulur; yazı ve dokunma alanları bilinçli olarak
/// büyük tutulmuştur. Mevcut bir kaydı düzenlemek için tek sayfalık
/// `ReminderFormScreen` kullanılır — küçük bir düzeltme için altı adım
/// gezdirmek gerekmesin diye.
class ReminderWizardScreen extends StatefulWidget {
  const ReminderWizardScreen({super.key});

  @override
  State<ReminderWizardScreen> createState() => _ReminderWizardScreenState();
}

class _ReminderWizardScreenState extends State<ReminderWizardScreen> {
  static const _stepCount = 6;
  static const _leadOptions = [0, 1, 3, 7, 15, 30, 60, 90];

  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountController = TextEditingController();

  int _step = 0;
  ReminderCategory? _category;
  RepeatInterval? _repeat;

  /// Takvimde baştan bir gün seçili görünür; aksi hâlde kullanıcı seçili bir
  /// tarihe bakarken "Devam et" kapalı kalır ve neden ilerleyemediğini anlamaz.
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  Set<int> _leadDays = {};
  List<String> _photoNames = [];

  /// Bildirim saati. null ise kullanıcı dokunmamıştır ve ayarlardaki
  /// varsayılan saat kullanılır — sihirbazı bir adım daha uzatmamak için
  /// saat seçimi bilinçli olarak isteğe bağlıdır.
  TimeOfDay? _notifyTime;

  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- gezinme

  /// Bulunulan adım tamamlandı mı? İleri butonu buna göre etkinleşir.
  bool get _canGoForward {
    switch (_step) {
      case 0:
        return _category != null;
      case 1:
        return _titleController.text.trim().isNotEmpty;
      case 3:
        return _repeat != null;
      case 4:
        // Sürekli hatırlatmada "kaç gün önce" sorulmaz; adım yalnızca saat
        // seçimini içerir ve boş bırakılabilir.
        return (_repeat?.isContinuous ?? false) || _leadDays.isNotEmpty;
      default:
        return true;
    }
  }

  void _goForward() {
    FocusScope.of(context).unfocus();
    if (_step == _stepCount - 1) {
      _save();
      return;
    }
    setState(() => _step++);
  }

  void _goBack() {
    FocusScope.of(context).unfocus();
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step--);
  }

  /// Kategori seçilince akışı beklemeden ilerletir: yaşlı kullanıcılar için
  /// "seç, sonra ayrıca İleri'ye bas" iki adımlı bir yük oluşturuyor.
  void _selectCategory(ReminderCategory category) {
    setState(() {
      _category = category;
      _repeat = category.defaultRepeat;
      _leadDays = category.defaultLeadDays.toSet();
      _step = 1;
    });
  }

  // ----------------------------------------------------------------- kayıt

  Future<void> _save() async {
    final category = _category;
    if (category == null) return;
    final dueDate = _dueDate;

    setState(() => _saving = true);
    final store = context.read<ReminderStore>();
    final settings = context.read<SettingsStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Sürekli hatırlatmada "kaç gün önce" sorulmaz; bildirim aralık bazlı
    // kurulduğu için değer kullanılmaz ama alan boş bırakılmaz.
    final leads = (_repeat?.isContinuous ?? false)
        ? const [0]
        : (_leadDays.toList()..sort((a, b) => b.compareTo(a)));
    final reminder = Reminder.create(
      categoryId: category.id,
      title: _titleController.text.trim(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      leadDays: leads,
      // Saat seçilmediyse ayarlardaki varsayılan geçerli olur.
      notifyHour: (_notifyTime ?? settings.defaultNotifyTime).hour,
      notifyMinute: (_notifyTime ?? settings.defaultNotifyTime).minute,
      repeat: _repeat ?? RepeatInterval.none,
      amount: _parseAmount(_amountController.text),
      photoPaths: _photoNames,
    );

    try {
      await NotificationService.instance.requestPermissions();
      await store.add(reminder);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('"${reminder.title}" kaydedildi.')),
      );
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

  // ------------------------------------------------------------------ arayüz

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Adım ${_step + 1} / $_stepCount'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            tooltip: _step == 0 ? 'Vazgeç' : 'Önceki adım',
            onPressed: _saving ? null : _goBack,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: LinearProgressIndicator(
              value: (_step + 1) / _stepCount,
              minHeight: 6,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  // Her adım kendi kaydırma konumunu alır; aksi hâlde önceki
                  // adımın kaydırması korunur ve yeni sorunun başlığı
                  // ekranın dışında kalır.
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: _buildStep(),
                ),
              ),
              _BottomBar(
                isLastStep: _step == _stepCount - 1,
                enabled: _canGoForward && !_saving,
                saving: _saving,
                // Kategori adımında seçim zaten ilerletir; buton kalabalık yapar.
                showForward: _step != 0,
                onForward: _goForward,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _categoryStep();
      case 1:
        return _titleStep();
      case 2:
        return _dateStep();
      case 3:
        return _repeatStep();
      case 4:
        return _leadStep();
      default:
        return _extrasStep();
    }
  }

  // --------------------------------------------------------------- adım 1

  Widget _categoryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('Ne hatırlatalım?'),
        const _Hint('Listeden birine dokunun.'),
        const SizedBox(height: 20),
        for (final category in ReminderCategory.all) ...[
          _BigTile(
            icon: category.icon,
            iconColor: category.color,
            label: category.label,
            selected: category.id == _category?.id,
            onTap: () => _selectCategory(category),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // --------------------------------------------------------------- adım 2

  Widget _titleStep() {
    final category = _category!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Question('Bu ${category.label.toLowerCase()} için bir isim yazın'),
        const _Hint('Bildirimde bu ismi göreceksiniz.'),
        const SizedBox(height: 20),
        TextField(
          controller: _titleController,
          autofocus: false,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 22),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: category.hint,
            hintStyle: const TextStyle(fontSize: 19),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          ),
        ),
        if (category.suggestions.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _Hint('Ya da hazır olanlardan seçin:'),
          const SizedBox(height: 12),
          for (final suggestion in category.suggestions) ...[
            _BigTile(
              icon: Icons.add,
              iconColor: Theme.of(context).colorScheme.primary,
              label: suggestion,
              selected: _titleController.text.trim() == suggestion,
              onTap: () {
                setState(() {
                  _titleController.text = suggestion;
                  _titleController.selection = TextSelection.collapsed(
                    offset: suggestion.length,
                  );
                });
              },
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  // --------------------------------------------------------------- adım 3

  Widget _dateStep() {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('Son tarih ne zaman?'),
        const _Hint('Takvimden günü seçin.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _QuickDateChip(
              label: '1 ay sonra',
              onTap: () => setState(
                () => _dueDate = DateTime(now.year, now.month + 1, now.day),
              ),
            ),
            _QuickDateChip(
              label: '3 ay sonra',
              onTap: () => setState(
                () => _dueDate = DateTime(now.year, now.month + 3, now.day),
              ),
            ),
            _QuickDateChip(
              label: '1 yıl sonra',
              onTap: () => setState(
                () => _dueDate = DateTime(now.year + 1, now.month, now.day),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: CalendarDatePicker(
            // Hızlı seçim butonları tarihi değiştirdiğinde takvimin o aya
            // atlaması için takvimi yeniden kurar.
            key: ValueKey(_dueDate),
            initialDate: _dueDate,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 25),
            onDateChanged: (date) => setState(() => _dueDate = date),
          ),
        ),
        const SizedBox(height: 16),
        _SelectionSummary(
          icon: Icons.event_available_outlined,
          text: DateFormat('d MMMM yyyy, EEEE', 'tr_TR').format(_dueDate),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- adım 4

  Widget _repeatStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('Bu her seferinde tekrar ediyor mu?'),
        const _Hint(
          'Tekrar eden bir ödemeyse, siz "ödendi" dedikçe tarih kendiliğinden '
          'sonraki döneme geçer.',
        ),
        const SizedBox(height: 20),
        for (final option in RepeatInterval.values) ...[
          _BigTile(
            icon: switch (option) {
              RepeatInterval.none => Icons.looks_one_outlined,
              RepeatInterval.hourly => Icons.hourglass_bottom_outlined,
              RepeatInterval.daily => Icons.today_outlined,
              RepeatInterval.weekly => Icons.date_range_outlined,
              _ => Icons.repeat,
            },
            iconColor: Theme.of(context).colorScheme.primary,
            label: option == RepeatInterval.none
                ? 'Sadece bir kez'
                : option.label,
            selected: _repeat == option,
            onTap: () => setState(() => _repeat = option),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // --------------------------------------------------------------- adım 5

  Widget _leadStep() {
    final defaultTime = context.watch<SettingsStore>().defaultNotifyTime;
    final effectiveTime = _notifyTime ?? defaultTime;
    final repeat = _repeat ?? RepeatInterval.none;

    // Saat başı tekrarda ne "kaç gün önce" ne de sabit bir saat anlamlıdır:
    // bildirim aralık bazlı kurulur.
    if (repeat == RepeatInterval.hourly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Question('Saat başı hatırlatılacak'),
          const _Hint(
            'Bu hatırlatma her saat tekrar edecek. İlk bildirim kaydettikten '
            'bir saat sonra gelir ve siz durdurana kadar sürer.',
          ),
          const SizedBox(height: 20),
          _BigTile(
            icon: Icons.hourglass_bottom_outlined,
            iconColor: Theme.of(context).colorScheme.primary,
            label: 'Her saat başı',
            selected: true,
            onTap: () {},
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!repeat.isContinuous) ...[
          const _Question('Kaç gün önce haber verelim?'),
          const _Hint(
            'Birden fazla seçebilirsiniz. Yalnızca seçtiğiniz günlerde bildirim '
            'gönderilir.',
          ),
          const SizedBox(height: 20),
          for (final option in _leadOptions) ...[
            _BigTile(
              icon: _leadDays.contains(option)
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              iconColor: Theme.of(context).colorScheme.primary,
              label: option == 0 ? 'Son gün' : '$option gün önce',
              selected: _leadDays.contains(option),
              onTap: () => setState(() {
                if (!_leadDays.remove(option)) _leadDays.add(option);
              }),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 22),
        ] else ...[
          _Question(
            repeat == RepeatInterval.daily
                ? 'Her gün saat kaçta?'
                : 'Her hafta saat kaçta?',
          ),
          const _Hint(
            'Bu hatırlatma siz durdurana kadar tekrar edecek.',
          ),
          const SizedBox(height: 20),
        ],
        if (!repeat.isContinuous)
          _FieldLabel('Saat kaçta?', icon: Icons.schedule_outlined),
        _Hint(
          _notifyTime == null
              ? 'Ayarlardaki varsayılan saat kullanılacak. Değiştirmek için '
                    'dokunun.'
              : 'Bu hatırlatma için özel saat seçildi.',
        ),
        const SizedBox(height: 12),
        _BigTile(
          icon: Icons.access_time,
          iconColor: Theme.of(context).colorScheme.primary,
          label: effectiveTime.format(context),
          selected: _notifyTime != null,
          onTap: _pickNotifyTime,
        ),
      ],
    );
  }

  Future<void> _pickNotifyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _notifyTime ?? context.read<SettingsStore>().defaultNotifyTime,
      helpText: 'Bildirim saati',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null) setState(() => _notifyTime = picked);
  }

  // --------------------------------------------------------------- adım 6

  Widget _extrasStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Question('İsterseniz ekleyin'),
        const _Hint('Bunlar zorunlu değil. Doğrudan kaydedebilirsiniz.'),
        const SizedBox(height: 24),
        _FieldLabel('Tutar', icon: Icons.payments_outlined),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(
            hintText: 'Örn. 1.250,00',
            suffixText: '₺',
            contentPadding:
                EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          ),
        ),
        const SizedBox(height: 26),
        _FieldLabel('Belge fotoğrafı', icon: Icons.photo_camera_outlined),
        const _Hint(
          'Faturanın veya garanti belgesinin fotoğrafını çekip saklayabilirsiniz.',
        ),
        const SizedBox(height: 12),
        PhotoGalleryField(
          large: true,
          photoNames: _photoNames,
          onChanged: (names) => setState(() => _photoNames = names),
        ),
        const SizedBox(height: 26),
        _FieldLabel('Not', icon: Icons.notes_outlined),
        TextField(
          controller: _noteController,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 18),
          decoration: const InputDecoration(
            hintText: 'Poliçe numarası, kurum adı, IBAN…',
            contentPadding:
                EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          ),
        ),
        const SizedBox(height: 28),
        _Summary(
          category: _category!,
          title: _titleController.text.trim(),
          dueDate: _dueDate,
          repeat: _repeat ?? RepeatInterval.none,
          leadDays: _leadDays.toList()..sort((a, b) => b.compareTo(a)),
          notifyTime:
              _notifyTime ?? context.watch<SettingsStore>().defaultNotifyTime,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ ortak parçalar

class _Question extends StatelessWidget {
  const _Question(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Yüksek, tek satırlık, kolay dokunulur seçim kutusu.
class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? iconColor.withValues(alpha: 0.14)
          : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? iconColor : scheme.outlineVariant,
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 30, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 26, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 17)),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 26, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Son adımda kaydetmeden önce gösterilen özet.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.category,
    required this.title,
    required this.dueDate,
    required this.repeat,
    required this.leadDays,
    required this.notifyTime,
  });

  final ReminderCategory category;
  final String title;
  final DateTime dueDate;
  final RepeatInterval repeat;
  final List<int> leadDays;
  final TimeOfDay notifyTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leadText = leadDays
        .map((d) => d == 0 ? 'son gün' : '$d gün önce')
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category.icon, size: 26, color: category.color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.isEmpty ? category.label : title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!repeat.isContinuous)
            _SummaryRow(
              label: 'Son tarih',
              value: DateFormat('d MMMM yyyy', 'tr_TR').format(dueDate),
            ),
          _SummaryRow(
            label: 'Tekrar',
            value: repeat == RepeatInterval.none ? 'Sadece bir kez' : repeat.label,
          ),
          if (!repeat.isContinuous)
            _SummaryRow(label: 'Bildirim', value: leadText),
          if (repeat != RepeatInterval.hourly)
            _SummaryRow(label: 'Saat', value: notifyTime.format(context)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isLastStep,
    required this.enabled,
    required this.saving,
    required this.showForward,
    required this.onForward,
  });

  final bool isLastStep;
  final bool enabled;
  final bool saving;
  final bool showForward;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    if (!showForward) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: FilledButton(
        onPressed: enabled ? onForward : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        child: saving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Text(isLastStep ? 'Kaydet' : 'Devam et'),
      ),
    );
  }
}
