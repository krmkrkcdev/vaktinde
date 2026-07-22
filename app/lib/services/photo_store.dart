import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Belge fotoğraflarını (fatura, garanti belgesi) uygulamanın kendi
/// dizininde saklar.
///
/// Veritabanında yalnızca dosya **adı** tutulur; mutlak yol her erişimde
/// yeniden çözülür. iOS'ta uygulama dizininin mutlak yolu her güncellemede
/// değiştiği için mutlak yol saklamak kayıpla sonuçlanırdı.
class PhotoStore {
  PhotoStore._();

  static final PhotoStore instance = PhotoStore._();

  static const _folder = 'belgeler';

  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

  Directory? _cachedDir;

  Future<Directory> _directory() async {
    if (_cachedDir != null) return _cachedDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _cachedDir = dir;
  }

  /// Kayıtlı bir fotoğrafın tam yolu.
  Future<String> resolve(String fileName) async {
    final dir = await _directory();
    return p.join(dir.path, fileName);
  }

  /// Kamerayı açar ve çekilen fotoğrafı saklar. Kullanıcı vazgeçerse `null`.
  Future<String?> captureFromCamera() =>
      _pickAndStore(() => _picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 2000,
            imageQuality: 85,
          ));

  /// Galeriden birden fazla fotoğraf seçtirir ve hepsini saklar.
  Future<List<String>> pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(
        maxWidth: 2000,
        imageQuality: 85,
      );
      final stored = <String>[];
      for (final file in files) {
        stored.add(await _store(file));
      }
      return stored;
    } catch (e) {
      debugPrint('Galeriden fotoğraf seçilemedi: $e');
      return const [];
    }
  }

  Future<String?> _pickAndStore(Future<XFile?> Function() pick) async {
    try {
      final file = await pick();
      if (file == null) return null;
      return _store(file);
    } catch (e) {
      debugPrint('Fotoğraf alınamadı: $e');
      return null;
    }
  }

  Future<String> _store(XFile file) async {
    final dir = await _directory();
    final extension = p.extension(file.path).isEmpty
        ? '.jpg'
        : p.extension(file.path).toLowerCase();
    // Dosya adına gömülen UUID aynı zamanda sunucudaki fotoğraf kimliğidir.
    // Böylece yerel dosya ile uzak kayıt arasında ayrı bir eşleme tablosu
    // tutmaya gerek kalmaz. Bkz. SyncService.photoIdFromFileName.
    final name = 'belge_${_uuid.v4()}$extension';
    final target = File(p.join(dir.path, name));
    await target.writeAsBytes(await file.readAsBytes(), flush: true);
    return name;
  }

  /// Tek bir fotoğrafı diskten siler. Dosya yoksa sessizce geçer.
  Future<void> delete(String fileName) async {
    try {
      final file = File(await resolve(fileName));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Fotoğraf silinemedi ($fileName): $e');
    }
  }

  Future<void> deleteAll(Iterable<String> fileNames) async {
    for (final name in fileNames) {
      await delete(name);
    }
  }

  /// Hiçbir hatırlatmaya bağlı olmayan dosyaları temizler.
  ///
  /// Sihirbaz yarıda bırakıldığında veya bir kayıt uygulama kapanırken
  /// silindiğinde artık dosya kalabilir.
  Future<void> pruneOrphans(Set<String> referenced) async {
    try {
      final dir = await _directory();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (!referenced.contains(p.basename(entity.path))) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('Artık fotoğraflar temizlenemedi: $e');
    }
  }
}
