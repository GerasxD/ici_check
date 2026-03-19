import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:ici_check/features/reports/services/offline_photo_queue.dart';
import 'package:ici_check/features/reports/services/photo_storage_service.dart';

class PhotoSyncService {
  final PhotoStorageService _photoService = PhotoStorageService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // ignore: unused_field
  final FirebaseStorage _storage = FirebaseStorage.instance;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;
  Timer? _retryTimer;

  static const int maxRetries = 5;

  void Function(int remaining, int total)? onProgress;
  void Function()? onSyncComplete;

  // ★ Singleton para que funcione tanto desde main.dart como desde el screen
  static final PhotoSyncService _instance = PhotoSyncService._internal();
  factory PhotoSyncService() => _instance;
  PhotoSyncService._internal();

  /// Iniciar escucha. Se puede llamar múltiples veces (es idempotente).
  void startListening() {
    _connectivitySub?.cancel();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = !results.contains(ConnectivityResult.none);

      if (hasConnection && !_isSyncing) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 3), () {
          syncPendingPhotos();
        });
      }
    });

    // ★ FIX APP CLOSE: Intentar sync al iniciar (fotos de sesión anterior)
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isSyncing) syncPendingPhotos();
    });

    debugPrint('🔔 PhotoSyncService: escucha iniciada');
  }

  void stopListening() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
  }

  Future<void> syncPendingPhotos() async {
    if (_isSyncing) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    _isSyncing = true;

    try {
      final pending = await OfflinePhotoQueue.getPending();
      if (pending.isEmpty) {
        _isSyncing = false;
        return;
      }

      final eligible = pending.where((p) => p.retryCount < maxRetries).toList();
      if (eligible.isEmpty) {
        _isSyncing = false;
        return;
      }

      final total = eligible.length;
      debugPrint('📤 Sincronizando $total fotos pendientes...');

      int successCount = 0;

      // ★ FIX DUPLICADOS: UNA por UNA, secuencial
      for (int i = 0; i < eligible.length; i++) {
        final conn = await Connectivity().checkConnectivity();
        if (conn.contains(ConnectivityResult.none)) {
          debugPrint('📡 Conexión perdida, pausando...');
          break;
        }

        final success = await _syncSinglePhoto(eligible[i]);
        if (success) successCount++;

        onProgress?.call(total - (i + 1), total);

        if (i < eligible.length - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }

      if (successCount > 0) {
        onSyncComplete?.call();
      }
      debugPrint('✅ Sync completado: $successCount/$total fotos');
    } catch (e) {
      debugPrint('❌ Error en sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _syncSinglePhoto(PendingPhoto photo) async {
    try {
      final file = File(photo.localPath);
      if (!await file.exists()) {
        await OfflinePhotoQueue.dequeue(photo.localPath);
        return true;
      }

      // ══════════════════════════════════════════════════════
      // ★ FIX DUPLICADOS: Si ya subimos esta foto, NO re-subir
      // ══════════════════════════════════════════════════════
      String remoteUrl;
      if (photo.remoteUrl != null && photo.remoteUrl!.isNotEmpty) {
        // Ya se subió antes pero falló el update de Firestore → reusar URL
        remoteUrl = photo.remoteUrl!;
        debugPrint('♻️ Reutilizando URL ya subida');
      } else {
        // Primera vez → subir a Storage
        final bytes = await file.readAsBytes();
        remoteUrl = await _photoService.uploadPhoto(
          photoBytes: bytes,
          reportId: photo.reportId,
          deviceInstanceId: photo.deviceInstanceId,
          activityId: photo.activityId,
        );
        // ★ Guardar URL remota en la cola para no re-subir en reintentos
        await OfflinePhotoQueue.updateRemoteUrl(photo.localPath, remoteUrl);
      }

      // Reemplazar URL en Firestore
      final localUrl = 'local://${photo.localPath}';
      final updateSuccess = await _replacePhotoUrlInReport(
        reportId: photo.reportId,
        deviceInstanceId: photo.deviceInstanceId,
        activityId: photo.activityId,
        oldUrl: localUrl,
        newUrl: remoteUrl,
      );

      if (updateSuccess) {
        await OfflinePhotoQueue.dequeue(photo.localPath);
        debugPrint('✅ Foto sincronizada: ${photo.deviceInstanceId}');
        return true;
      } else {
        await OfflinePhotoQueue.incrementRetry(photo.localPath);
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sincronizando foto: $e');
      await OfflinePhotoQueue.incrementRetry(photo.localPath);
      return false;
    }
  }

  Future<bool> _replacePhotoUrlInReport({
    required String reportId,
    required String deviceInstanceId,
    String? activityId,
    required String oldUrl,
    required String newUrl,
  }) async {
    try {
      // Buscar por campos
      final parts = reportId.split('_');
      final dateStr = parts.last;
      final policyId = reportId.substring(0, reportId.length - dateStr.length - 1);

      final query = await _db
          .collection('reports')
          .where('policyId', isEqualTo: policyId)
          .where('dateStr', isEqualTo: dateStr)
          .limit(1)
          .get();

      DocumentReference? docRef;

      if (query.docs.isNotEmpty) {
        docRef = query.docs.first.reference;
      } else {
        final directSnap = await _db.collection('reports').doc(reportId).get();
        if (directSnap.exists) {
          docRef = directSnap.reference;
        }
      }

      if (docRef == null) {
        debugPrint('⚠️ Documento no encontrado: $reportId');
        return false;
      }

      return await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(docRef!);
        if (!snap.exists) return false;

        final data = snap.data() as Map<String, dynamic>;
        final entries = List<Map<String, dynamic>>.from(
          (data['entries'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );

        bool modified = false;

        for (int i = 0; i < entries.length; i++) {
          final entry = entries[i];
          if (entry['instanceId'] != deviceInstanceId) continue;

          if (activityId != null) {
            final activityData = entry['activityData'] as Map<String, dynamic>? ?? {};
            final actData = activityData[activityId] as Map<String, dynamic>?;

            if (actData != null) {
              final photos = List<String>.from(actData['photoUrls'] ?? []);

              // ★ FIX: Evitar duplicados
              if (photos.contains(newUrl)) {
                // Ya está → solo limpiar la local
                photos.remove(oldUrl);
              } else {
                final idx = photos.indexOf(oldUrl);
                if (idx != -1) {
                  photos[idx] = newUrl;
                } else {
                  photos.add(newUrl);
                }
              }

              // Limpiar locales residuales de esta foto
              photos.removeWhere((u) => u == oldUrl);

              final updatedActData = Map<String, dynamic>.from(actData);
              updatedActData['photoUrls'] = photos;
              final updatedActivityData = Map<String, dynamic>.from(activityData);
              updatedActivityData[activityId] = updatedActData;
              entries[i] = Map<String, dynamic>.from(entry)
                ..['activityData'] = updatedActivityData;
              modified = true;
            } else {
              final updatedActivityData = Map<String, dynamic>.from(
                entry['activityData'] as Map<String, dynamic>? ?? {},
              );
              updatedActivityData[activityId] = {
                'photoUrls': [newUrl],
                'observations': '',
              };
              entries[i] = Map<String, dynamic>.from(entry)
                ..['activityData'] = updatedActivityData;
              modified = true;
            }
          } else {
            final photos = List<String>.from(entry['photoUrls'] ?? []);

            if (photos.contains(newUrl)) {
              photos.remove(oldUrl);
            } else {
              final idx = photos.indexOf(oldUrl);
              if (idx != -1) {
                photos[idx] = newUrl;
              } else {
                photos.add(newUrl);
              }
            }

            photos.removeWhere((u) => u == oldUrl);

            entries[i] = Map<String, dynamic>.from(entry)..['photoUrls'] = photos;
            modified = true;
          }

          break;
        }

        if (modified) {
          tx.update(docRef, {'entries': entries});
          return true;
        }

        return false;
      });
    } catch (e) {
      debugPrint('❌ Error en _replacePhotoUrlInReport: $e');
      return false;
    }
  }

  bool get isSyncing => _isSyncing;
}