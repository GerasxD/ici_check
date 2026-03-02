import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:ici_check/features/reports/services/offline_photo_queue.dart';
import 'package:ici_check/features/reports/services/photo_storage_service.dart';

class PhotoSyncService {
  final PhotoStorageService _photoService = PhotoStorageService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;
  Timer? _retryTimer;

  static const int batchSize = 3;
  static const int maxRetries = 5;
  static const Duration pauseBetweenBatches = Duration(seconds: 1);

  void Function(int remaining, int total)? onProgress;
  void Function()? onSyncComplete;

  void startListening() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = !results.contains(ConnectivityResult.none);
      if (hasConnection && !_isSyncing) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 3), () {
          syncPendingPhotos();
        });
      }
    });
  }

  void stopListening() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
  }

  Future<void> syncPendingPhotos() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pending = await OfflinePhotoQueue.getPending();
      if (pending.isEmpty) {
        _isSyncing = false;
        return;
      }

      final eligible = pending.where((p) => p.retryCount < maxRetries).toList();
      if (eligible.isEmpty) {
        debugPrint('⚠️ Todas las fotos pendientes excedieron max retries');
        _isSyncing = false;
        return;
      }

      final total = eligible.length;
      debugPrint('📤 Sincronizando $total fotos pendientes...');

      int processed = 0;

      for (int i = 0; i < eligible.length; i += batchSize) {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) {
          debugPrint('📡 Conexión perdida durante sync, pausando...');
          break;
        }

        final batchEnd = min(i + batchSize, eligible.length);
        final batch = eligible.sublist(i, batchEnd);

        await Future.wait(
          batch.map((photo) => _syncSinglePhoto(photo)),
        );

        processed += batch.length;
        onProgress?.call(total - processed, total);

        if (batchEnd < eligible.length) {
          await Future.delayed(pauseBetweenBatches);
        }
      }

      onSyncComplete?.call();
      debugPrint('✅ Sync completado: $processed/$total fotos');
    } catch (e) {
      debugPrint('❌ Error en sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncSinglePhoto(PendingPhoto photo) async {
    try {
      final file = File(photo.localPath);
      if (!await file.exists()) {
        await OfflinePhotoQueue.dequeue(photo.localPath);
        return;
      }

      final bytes = await file.readAsBytes();

      final remoteUrl = await _photoService.uploadPhoto(
        photoBytes: bytes,
        reportId: photo.reportId,
        deviceInstanceId: photo.deviceInstanceId,
        activityId: photo.activityId,
      );

      final localUrl = 'local://${photo.localPath}';
      await _replacePhotoUrlInReport(
        reportId: photo.reportId,
        deviceInstanceId: photo.deviceInstanceId,
        activityId: photo.activityId,
        oldUrl: localUrl,
        newUrl: remoteUrl,
      );

      await OfflinePhotoQueue.dequeue(photo.localPath);
      debugPrint('✅ Foto sincronizada: ${photo.deviceInstanceId}');
    } catch (e) {
      debugPrint('❌ Error sincronizando foto: $e');
      await OfflinePhotoQueue.incrementRetry(photo.localPath);
    }
  }

  Future<void> _replacePhotoUrlInReport({
    required String reportId,
    required String deviceInstanceId,
    String? activityId,
    required String oldUrl,
    required String newUrl,
  }) async {
    try {
      final doc = await _db.collection('reports').doc(reportId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final entries = data['entries'] as List<dynamic>? ?? [];
      bool modified = false;

      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i] as Map<String, dynamic>;
        if (entry['instanceId'] != deviceInstanceId) continue;

        if (activityId != null) {
          final activityData =
              entry['activityData'] as Map<String, dynamic>? ?? {};
          final actData =
              activityData[activityId] as Map<String, dynamic>?;
          if (actData != null) {
            final photos = List<String>.from(actData['photoUrls'] ?? []);
            final idx = photos.indexOf(oldUrl);
            if (idx != -1) {
              photos[idx] = newUrl;
              actData['photoUrls'] = photos;
              modified = true;
            }
          }
        } else {
          final photos = List<String>.from(entry['photoUrls'] ?? []);
          final idx = photos.indexOf(oldUrl);
          if (idx != -1) {
            photos[idx] = newUrl;
            entry['photoUrls'] = photos;
            modified = true;
          }
        }
      }

      if (modified) {
        await doc.reference.update({'entries': entries});
      }
    } catch (e) {
      debugPrint('Error reemplazando URL: $e');
    }
  }

  bool get isSyncing => _isSyncing;
}