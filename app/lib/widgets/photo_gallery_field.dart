import 'dart:io';

import 'package:flutter/material.dart';

import '../services/photo_store.dart';
import '../theme/app_theme.dart';

/// Belge fotoğraflarını ekleme/görüntüleme/silme alanı.
///
/// Fotoğrafları diske yazma işini [PhotoStore] yapar; bu bileşen yalnızca
/// dosya adlarının listesini yönetir ve değişikliği [onChanged] ile bildirir.
class PhotoGalleryField extends StatelessWidget {
  const PhotoGalleryField({
    super.key,
    required this.photoNames,
    required this.onChanged,
    this.large = false,
  });

  final List<String> photoNames;
  final ValueChanged<List<String>> onChanged;

  /// Sihirbazda daha büyük dokunma alanları kullanılır.
  final bool large;

  double get _tileSize => large ? 108 : 88;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.photo_camera_outlined,
                label: 'Fotoğraf çek',
                large: large,
                onPressed: () => _capture(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                icon: Icons.photo_library_outlined,
                label: 'Galeriden seç',
                large: large,
                onPressed: () => _pick(context),
              ),
            ),
          ],
        ),
        if (photoNames.isNotEmpty) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: _tileSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photoNames.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _Thumbnail(
                fileName: photoNames[index],
                size: _tileSize,
                onOpen: () => _open(context, index),
                onRemove: () => _remove(index),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${photoNames.length} belge eklendi',
            style: TextStyle(
              fontSize: large ? 15 : 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _capture(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await PhotoStore.instance.captureFromCamera();
    if (name == null) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackDuration,
          content: Text('Fotoğraf eklenmedi.'),
        ),
      );
      return;
    }
    onChanged([...photoNames, name]);
  }

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final names = await PhotoStore.instance.pickFromGallery();
    if (names.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          duration: kSnackDuration,
          content: Text('Fotoğraf eklenmedi.'),
        ),
      );
      return;
    }
    onChanged([...photoNames, ...names]);
  }

  void _remove(int index) {
    final next = [...photoNames]..removeAt(index);
    onChanged(next);
  }

  Future<void> _open(BuildContext context, int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _PhotoViewer(photoNames: photoNames, initialIndex: index),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.large,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool large;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: large ? 24 : 20),
      label: Text(
        label,
        style: TextStyle(fontSize: large ? 16 : 14),
        textAlign: TextAlign.center,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(large ? 64 : 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.fileName,
    required this.size,
    required this.onOpen,
    required this.onRemove,
  });

  final String fileName;
  final double size;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _PhotoImage(fileName: fileName, fit: BoxFit.cover),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpen,
              ),
            ),
          ),
          // Dokunma hedefi 44×44 (HIG alt sınırı); görünür rozet küçük kalır
          // ama basılabilir alan karonun köşesini tümüyle kaplar.
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.close, size: 17, color: scheme.error),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dosya adını tam yola çözüp görseli yükler.
class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.fileName, required this.fit});

  final String fileName;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: PhotoStore.instance.resolve(fileName),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null) {
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const SizedBox.expand(),
          );
        }
        return Image.file(
          File(path),
          fit: fit,
          errorBuilder: (context, _, _) => ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        );
      },
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photoNames, required this.initialIndex});

  final List<String> photoNames;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.photoNames.length}',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photoNames.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: _PhotoImage(
              fileName: widget.photoNames[index],
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
