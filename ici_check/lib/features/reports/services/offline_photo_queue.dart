import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class OfflinePhotoQueue {
  static const String _queueKey = 'pending_photo_uploads_v2';
  static const String _diskUsageKey = 'offline_photo_disk_usage';

  static const int maxDiskUsageBytes = 500 * 1024 * 1024;
  static const int maxPhotoWidth = 800;
  static const int compressionQuality = 70;
  static const int thumbnailWidth = 200;
  static const int thumbnailQuality = 50;

  static Future<String?> enqueue({
    required Uint8List photoBytes,
    required String reportId,
    required String deviceInstanceId,
    required int entryIndex,
    String? activityId,
  }) async {
    try {
      final currentUsage = await getDiskUsage();
      if (currentUsage >= maxDiskUsageBytes) {
        debugPrint('⚠️ Cola offline llena ($currentUsage bytes)');
        return null;
      }

      final dir = await _getQueueDir();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final hash = deviceInstanceId.hashCode.abs();

      final compressed = await _compressForOffline(photoBytes);

      final photoFilename = '${timestamp}_$hash.jpg';
      final photoFile = File('${dir.path}/$photoFilename');
      await photoFile.writeAsBytes(compressed);

      final thumbFilename = '${timestamp}_${hash}_thumb.jpg';
      final thumbFile = File('${dir.path}/$thumbFilename');
      final thumbnail = await _generateThumbnail(compressed);
      await thumbFile.writeAsBytes(thumbnail);

      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];

      final item = jsonEncode({
        'localPath': photoFile.path,
        'thumbPath': thumbFile.path,
        'reportId': reportId,
        'deviceInstanceId': deviceInstanceId,
        'entryIndex': entryIndex,
        'activityId': activityId,
        'sizeBytes': compressed.length,
        'createdAt': DateTime.now().toIso8601String(),
        'retryCount': 0,
        'remoteUrl': null, // ★ NUEVO: se llena después de subir a Storage
      });

      queue.add(item);
      await prefs.setStringList(_queueKey, queue);
      await _addDiskUsage(compressed.length + thumbnail.length);

      debugPrint(
        '📦 Foto offline: $photoFilename '
        '(${(compressed.length / 1024).toStringAsFixed(1)}KB)',
      );

      return 'local://${photoFile.path}';
    } catch (e) {
      debugPrint('❌ Error encolando foto offline: $e');
      return null;
    }
  }

  static Future<List<PendingPhoto>> getPending() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    final List<PendingPhoto> result = [];
    for (final item in queue) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        result.add(PendingPhoto.fromMap(map));
      } catch (e) {
        debugPrint('⚠️ Item corrupto en cola: $e');
      }
    }

    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  static Future<void> dequeue(String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    int removedSize = 0;
    String? thumbPath;

    queue.removeWhere((item) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        if (map['localPath'] == localPath) {
          removedSize = map['sizeBytes'] as int? ?? 0;
          thumbPath = map['thumbPath'] as String?;
          return true;
        }
      } catch (_) {}
      return false;
    });

    await prefs.setStringList(_queueKey, queue);
    await _safeDeleteFile(localPath);
    if (thumbPath != null) await _safeDeleteFile(thumbPath!);
    if (removedSize > 0) await _subtractDiskUsage(removedSize);
  }

  // ═══════════════════════════════════════════════════════════════════
  // ★ NUEVO: Guardar la URL remota después de subir exitosamente
  //   Así si el update de Firestore falla, no re-subimos la foto.
  // ═══════════════════════════════════════════════════════════════════
  static Future<void> updateRemoteUrl(String localPath, String remoteUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    for (int i = 0; i < queue.length; i++) {
      try {
        final map = jsonDecode(queue[i]) as Map<String, dynamic>;
        if (map['localPath'] == localPath) {
          map['remoteUrl'] = remoteUrl;
          queue[i] = jsonEncode(map);
          break;
        }
      } catch (_) {}
    }

    await prefs.setStringList(_queueKey, queue);
    debugPrint('💾 remoteUrl guardada en cola para: ${localPath.split('/').last}');
  }

  static Future<void> incrementRetry(String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    for (int i = 0; i < queue.length; i++) {
      try {
        final map = jsonDecode(queue[i]) as Map<String, dynamic>;
        if (map['localPath'] == localPath) {
          map['retryCount'] = (map['retryCount'] as int? ?? 0) + 1;
          queue[i] = jsonEncode(map);
          break;
        }
      } catch (_) {}
    }

    await prefs.setStringList(_queueKey, queue);
  }

  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? []).length;
  }

  static Future<int> getDiskUsage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_diskUsageKey) ?? 0;
  }

  static String? getThumbnailPath(String localUrl) {
    if (!localUrl.startsWith('local://')) return null;
    final fullPath = localUrl.replaceFirst('local://', '');
    final dotIndex = fullPath.lastIndexOf('.');
    if (dotIndex == -1) return null;
    final withoutExt = fullPath.substring(0, dotIndex);
    return '${withoutExt}_thumb.jpg';
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    for (final item in queue) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        await _safeDeleteFile(map['localPath'] as String);
        if (map['thumbPath'] != null) {
          await _safeDeleteFile(map['thumbPath'] as String);
        }
      } catch (_) {}
    }

    await prefs.setStringList(_queueKey, []);
    await prefs.setInt(_diskUsageKey, 0);

    try {
      final dir = await _getQueueDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}

    debugPrint('🗑️ Cola offline limpiada completamente');
  }

  static Future<int> cleanOrphans() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];
    final List<String> cleaned = [];
    int removedCount = 0;

    for (final item in queue) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final file = File(map['localPath'] as String);
        if (await file.exists()) {
          cleaned.add(item);
        } else {
          removedCount++;
          if (map['thumbPath'] != null) {
            await _safeDeleteFile(map['thumbPath'] as String);
          }
        }
      } catch (_) {
        removedCount++;
      }
    }

    if (removedCount > 0) {
      await prefs.setStringList(_queueKey, cleaned);
      await _recalculateDiskUsage(cleaned);
      debugPrint('🧹 Limpiados $removedCount huérfanos');
    }

    return removedCount;
  }

  // ═══════════════════ HELPERS PRIVADOS ═══════════════════

  static Future<Uint8List> _compressForOffline(Uint8List imageBytes) async {
    try {
      return await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: maxPhotoWidth,
        quality: compressionQuality,
        format: CompressFormat.jpeg,
      );
    } catch (e) {
      debugPrint('⚠️ Compresión fallida, usando original: $e');
      return imageBytes;
    }
  }

  static Future<Uint8List> _generateThumbnail(Uint8List imageBytes) async {
    try {
      return await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: thumbnailWidth,
        quality: thumbnailQuality,
        format: CompressFormat.jpeg,
      );
    } catch (e) {
      return imageBytes;
    }
  }

  static Future<Directory> _getQueueDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final queueDir = Directory('${appDir.path}/offline_photo_queue');
    if (!await queueDir.exists()) await queueDir.create(recursive: true);
    return queueDir;
  }

  static Future<void> _safeDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _addDiskUsage(int bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_diskUsageKey) ?? 0;
    await prefs.setInt(_diskUsageKey, current + bytes);
  }

  static Future<void> _subtractDiskUsage(int bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_diskUsageKey) ?? 0;
    await prefs.setInt(_diskUsageKey, (current - bytes).clamp(0, current));
  }

  static Future<void> _recalculateDiskUsage(List<String> queue) async {
    int total = 0;
    for (final item in queue) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        total += (map['sizeBytes'] as int? ?? 0);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_diskUsageKey, total);
  }
}

class PendingPhoto {
  final String localPath;
  final String? thumbPath;
  final String reportId;
  final String deviceInstanceId;
  final int entryIndex;
  final String? activityId;
  final int sizeBytes;
  final DateTime createdAt;
  final int retryCount;
  final String? remoteUrl; // ★ NUEVO

  PendingPhoto({
    required this.localPath,
    this.thumbPath,
    required this.reportId,
    required this.deviceInstanceId,
    required this.entryIndex,
    this.activityId,
    required this.sizeBytes,
    required this.createdAt,
    required this.retryCount,
    this.remoteUrl,
  });

  factory PendingPhoto.fromMap(Map<String, dynamic> map) {
    return PendingPhoto(
      localPath: map['localPath'] as String,
      thumbPath: map['thumbPath'] as String?,
      reportId: map['reportId'] as String,
      deviceInstanceId: map['deviceInstanceId'] as String,
      entryIndex: map['entryIndex'] as int? ?? 0,
      activityId: map['activityId'] as String?,
      sizeBytes: map['sizeBytes'] as int? ?? 0,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      retryCount: map['retryCount'] as int? ?? 0,
      remoteUrl: map['remoteUrl'] as String?, // ★ NUEVO
    );
  }
}