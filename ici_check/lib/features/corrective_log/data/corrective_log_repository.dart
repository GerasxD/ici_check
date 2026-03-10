import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ici_check/features/corrective_log/data/corrective_item_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:uuid/uuid.dart';

class CorrectiveLogRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> _itemsRef(String policyId) {
    return _db
        .collection('corrective_logs')
        .doc(policyId)
        .collection('items');
  }

  // ═══════════════════════════════════════════════════════════════════
  // STREAM — Escucha en tiempo real todos los correctivos de una póliza
  // ═══════════════════════════════════════════════════════════════════
  Stream<List<CorrectiveItemModel>> getItemsStream(String policyId) {
    return _itemsRef(policyId)
        .orderBy('detectionDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return CorrectiveItemModel.fromMap(data);
      }).toList();
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // SAVE — Guardar/Actualizar un item
  // ═══════════════════════════════════════════════════════════════════
  Future<void> saveItem(CorrectiveItemModel item) async {
    try {
      _itemsRef(item.policyId).doc(item.id).set(
            item.toMap(),
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('Error guardando correctivo: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // DELETE — Eliminar un item
  // ═══════════════════════════════════════════════════════════════════
  Future<void> deleteItem(String policyId, String itemId) async {
    try {
      await _itemsRef(policyId).doc(itemId).delete();
    } catch (e) {
      debugPrint('Error eliminando correctivo: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // SYNC — Escanea TODOS los reportes de la póliza y crea correctivos
  //        para cada NOK que no tenga un registro existente.
  //
  // Se ejecuta al abrir la pantalla de Bitácora.
  // Es idempotente: no duplica items gracias al uniqueKey.
  // ═══════════════════════════════════════════════════════════════════
  Future<int> syncFromReports({
    required PolicyModel policy,
    required List<DeviceModel> deviceDefinitions,
  }) async {
    try {
      // 1. Obtener todos los reportes de la póliza
      final reportsSnapshot = await _db
          .collection('reports')
          .where('policyId', isEqualTo: policy.id)
          .get();

      if (reportsSnapshot.docs.isEmpty) return 0;

      // 2. Obtener correctivos existentes para chequear duplicados
      final existingSnapshot = await _itemsRef(policy.id).get();
      final existingKeys = <String>{};
      for (final doc in existingSnapshot.docs) {
        final key = doc.data()['uniqueKey'] as String?;
        if (key != null) existingKeys.add(key);
      }

      // 3. Mapas de referencia
      final defMap = <String, DeviceModel>{};
      for (final def in deviceDefinitions) {
        defMap[def.id] = def;
      }
      final actNameMap = <String, String>{};
      for (final def in deviceDefinitions) {
        for (final act in def.activities) {
          actNameMap[act.id] = act.name;
        }
      }

      // Mapa de policyDevices por instanceId (para encontrar definitionId)
      final policyDevMap = <String, PolicyDevice>{};
      for (final pd in policy.devices) {
        policyDevMap[pd.instanceId] = pd;
      }

      int newItemsCount = 0;
      final batch = _db.batch();

      // 4. Escanear cada reporte
      for (final reportDoc in reportsSnapshot.docs) {
        final reportData = reportDoc.data();
        final reportId = reportDoc.id;
        final dateStr = reportData['dateStr'] as String? ?? '';
        final entries = reportData['entries'] as List<dynamic>? ?? [];

        // Solo procesar reportes que fueron iniciados
        final startTime = reportData['startTime'] as String?;
        if (startTime == null || startTime.isEmpty) continue;

        DateTime? serviceDate;
        try {
          serviceDate = (reportData['serviceDate'] as Timestamp?)?.toDate();
        } catch (_) {}

        for (final entryMap in entries) {
          final entry = entryMap as Map<String, dynamic>;
          final instanceId = entry['instanceId'] as String? ?? '';
          final customId = entry['customId'] as String? ?? '';
          final area = entry['area'] as String? ?? '';
          final results = entry['results'] as Map<String, dynamic>? ?? {};
          final activityData =
              entry['activityData'] as Map<String, dynamic>? ?? {};

          // Encontrar el PolicyDevice para este entry
          String baseInstanceId = instanceId;
          final lastUnderscore = instanceId.lastIndexOf('_');
          if (lastUnderscore != -1) {
            final suffix = instanceId.substring(lastUnderscore + 1);
            if (int.tryParse(suffix) != null) {
              baseInstanceId = instanceId.substring(0, lastUnderscore);
            }
          }

          final policyDev = policyDevMap[baseInstanceId];
          final defId = policyDev?.definitionId ?? '';
          final def = defMap[defId];
          final defName = def?.name ?? 'Desconocido';

          for (final actEntry in results.entries) {
            final actId = actEntry.key;
            final value = actEntry.value;

            // Solo nos interesan los NOK
            if (value != 'NOK') continue;

            final uniqueKey = '${dateStr}_${instanceId}_$actId';

            // Ya existe → saltar
            if (existingKeys.contains(uniqueKey)) continue;

            // Extraer observación y fotos de activityData si existen
            String problemDesc = '';
            List<String> problemPhotos = [];

            final actData = activityData[actId] as Map<String, dynamic>?;
            if (actData != null) {
              problemDesc = actData['observations'] as String? ?? '';
              problemPhotos =
                  List<String>.from(actData['photoUrls'] as List? ?? []);
            }

            // Si no hay observación en activityData, usar la del entry
            if (problemDesc.isEmpty) {
              problemDesc = entry['observations'] as String? ?? '';
            }

            // Si no hay fotos en activityData, usar las del entry
            if (problemPhotos.isEmpty) {
              problemPhotos =
                  List<String>.from(entry['photoUrls'] as List? ?? []);
            }

            // Crear el correctivo
            final itemId = _uuid.v4();
            final item = CorrectiveItemModel(
              id: itemId,
              policyId: policy.id,
              reportId: reportId,
              reportDateStr: dateStr,
              deviceInstanceId: instanceId,
              deviceCustomId: customId,
              deviceArea: area,
              deviceDefId: defId,
              deviceDefName: defName,
              activityId: actId,
              activityName: actNameMap[actId] ?? actId,
              detectionDate: serviceDate ?? DateTime.now(),
              problemDescription: problemDesc,
              problemPhotoUrls: problemPhotos,
              level: AttentionLevel.B, // Default
              status: CorrectiveStatus.PENDING,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

            batch.set(
              _itemsRef(policy.id).doc(itemId),
              item.toMap(),
            );

            existingKeys.add(uniqueKey);
            newItemsCount++;
          }
        }
      }

      if (newItemsCount > 0) {
        await batch.commit();
        debugPrint(
            '✅ Sync correctivos: $newItemsCount nuevos items creados');
      }

      return newItemsCount;
    } catch (e) {
      debugPrint('❌ Error en syncFromReports: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // MANUAL ADD — Agregar un correctivo manual (no vinculado a reporte)
  // ═══════════════════════════════════════════════════════════════════
  Future<CorrectiveItemModel> addManualItem({
    required String policyId,
    required String area,
    required String problemDescription,
    required AttentionLevel level,
    List<String> photoUrls = const [],
  }) async {
    final itemId = _uuid.v4();
    final item = CorrectiveItemModel(
      id: itemId,
      policyId: policyId,
      reportId: 'MANUAL',
      reportDateStr: 'MANUAL',
      deviceInstanceId: '',
      deviceCustomId: '',
      deviceArea: area,
      deviceDefId: '',
      deviceDefName: '',
      activityId: '',
      activityName: '',
      detectionDate: DateTime.now(),
      problemDescription: problemDescription,
      problemPhotoUrls: photoUrls,
      level: level,
      status: CorrectiveStatus.PENDING,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await saveItem(item);
    return item;
  }

  // ═══════════════════════════════════════════════════════════════════
  // STATS — Contadores rápidos para mostrar en el cronograma
  // ═══════════════════════════════════════════════════════════════════
  Future<({int total, int pending, int corrected})> getStats(
      String policyId) async {
    try {
      final snapshot = await _itemsRef(policyId).get();
      int total = snapshot.docs.length;
      int corrected = 0;

      for (final doc in snapshot.docs) {
        if (doc.data()['status'] == 'CORRECTED') corrected++;
      }

      return (total: total, pending: total - corrected, corrected: corrected);
    } catch (e) {
      return (total: 0, pending: 0, corrected: 0);
    }
  }
}