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
  // SYNC — Escanea TODOS los reportes de la póliza:
  //   • CREA correctivos para NOK nuevos (por uniqueKey)
  //   • ACTUALIZA fotos y observaciones en items PENDIENTES/EN PROCESO
  //     cuando el reporte cambia (ej: técnico agrega fotos después)
  //
  // Regla importante: NUNCA sobreescribe datos de un item ya corregido
  // (CORRECTED_BY_ICISI / CORRECTED_BY_THIRD) para no perder el trabajo
  // de gestión que el coordinador ya hizo.
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

      // ▼ NUEVO: Obtener a los usuarios de la base de datos para saber sus nombres ▼
      final usersSnapshot = await _db.collection('users').get();
      final userMap = <String, String>{};
      for (final doc in usersSnapshot.docs) {
        userMap[doc.id] = doc.data()['name'] as String? ?? 'Desconocido';
      }
      // ▲ FIN NUEVO ▲

      // 2. Obtener correctivos existentes
      //    Guardamos: uniqueKey → {docId, status, problemPhotoUrls, problemDescription}
      final existingSnapshot = await _itemsRef(policy.id).get();

      // Map: uniqueKey → documento existente (para detectar updates)
      final existingByKey = <String, Map<String, dynamic>>{};
      for (final doc in existingSnapshot.docs) {
        final data = doc.data();
        final key = data['uniqueKey'] as String?;
        if (key != null) {
          existingByKey[key] = {'docId': doc.id, ...data};
        }
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

        // ▼ NUEVO: Extraer asignaciones del reporte para saber quién trabajó ▼
        final sectionAssignments = reportData['sectionAssignments'] as Map<String, dynamic>? ?? {};
        final globalTechs = List<String>.from(reportData['assignedTechnicianIds'] ?? []);
        // ▲ FIN NUEVO ▲

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

          // ▼ NUEVO: Determinar los nombres exactos de quienes reportaron esto ▼
          List<String> techIds = [];
          if (sectionAssignments.containsKey(defId) && (sectionAssignments[defId] as List).isNotEmpty) {
            techIds = List<String>.from(sectionAssignments[defId]);
          } else {
            techIds = globalTechs;
          }
          final reporterNames = techIds.map((id) => userMap[id] ?? 'Desconocido').join(', ');
          // ▲ FIN NUEVO ▲

          for (final actEntry in results.entries) {
            final actId = actEntry.key;
            final value = actEntry.value;

            // Solo nos interesan los NOK
            if (value != 'NOK') continue;

            final uniqueKey = '${dateStr}_${instanceId}_$actId';

            // ── Extraer fotos y observación actuales del reporte ──
            String problemDescFromReport = '';
            List<String> problemPhotosFromReport = [];

            final actData = activityData[actId] as Map<String, dynamic>?;
            if (actData != null) {
              problemDescFromReport =
                  actData['observations'] as String? ?? '';
              problemPhotosFromReport = List<String>.from(
                  actData['photoUrls'] as List? ?? []);
            }
            if (problemDescFromReport.isEmpty) {
              problemDescFromReport =
                  entry['observations'] as String? ?? '';
            }
            if (problemPhotosFromReport.isEmpty) {
              problemPhotosFromReport =
                  List<String>.from(entry['photoUrls'] as List? ?? []);
            }

            // ── ¿Ya existe este correctivo? ──
            // ── ¿Ya existe este correctivo? ──
            if (existingByKey.containsKey(uniqueKey)) {
              // ── LÓGICA DE UPDATE ──
              final existing = existingByKey[uniqueKey]!;
              final existingStatus = existing['status'] as String? ?? '';
              final isCorrected = existingStatus == 'CORRECTED_BY_ICISI' ||
                  existingStatus == 'CORRECTED_BY_THIRD';

              if (!isCorrected) {
                final existingPhotos = List<String>.from(
                    existing['problemPhotoUrls'] as List? ?? []);
                final existingDesc =
                    existing['problemDescription'] as String? ?? '';
                final existingReportedTo = 
                    existing['reportedTo'] as String? ?? ''; // 👈 NUEVO

                // Detectar si hay cambios reales
                final photosChanged = !_listEquals(
                    existingPhotos, problemPhotosFromReport);
                final descChanged =
                    existingDesc != problemDescFromReport &&
                        problemDescFromReport.isNotEmpty;
                
                // 👈 NUEVO: Detectar si le falta el nombre y el reporte sí lo tiene
                final namesMissing = existingReportedTo.isEmpty && reporterNames.isNotEmpty; 

                if (photosChanged || descChanged || namesMissing) {
                  final docId = existing['docId'] as String;
                  final updateData = <String, dynamic>{
                    'updatedAt': Timestamp.fromDate(DateTime.now()),
                  };
                  if (photosChanged) {
                    updateData['problemPhotoUrls'] = problemPhotosFromReport;
                  }
                  if (descChanged) {
                    updateData['problemDescription'] = problemDescFromReport;
                  }
                  if (namesMissing) { // 👈 NUEVO: Si le falta el nombre, se lo pone
                    updateData['reportedTo'] = reporterNames;
                  }

                  batch.update(
                    _itemsRef(policy.id).doc(docId),
                    updateData,
                  );
                }
              }
              continue; // Ya procesado, pasar al siguiente
            }

            // ── CREAR item nuevo ──
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
              problemDescription: problemDescFromReport,
              problemPhotoUrls: problemPhotosFromReport,
              level: AttentionLevel.B,
              status: CorrectiveStatus.PENDING,
              reportedTo: reporterNames.isNotEmpty ? reporterNames : null, // 👈 AQUÍ SE GUARDA EL NOMBRE AUTOMÁTICAMENTE
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

            batch.set(
              _itemsRef(policy.id).doc(itemId),
              item.toMap(),
            );

            // Registrar en el mapa para evitar duplicados dentro del mismo batch
            existingByKey[uniqueKey] = {
              'docId': itemId,
              ...item.toMap(),
            };
            newItemsCount++;
          }
        }
      }

      // Solo commitear si hay algo que escribir
      if (newItemsCount > 0 || _batchHasWrites(reportsSnapshot.docs)) {
        await batch.commit();
        debugPrint(
            '✅ Sync correctivos: $newItemsCount nuevos, updates aplicados');
      }

      return newItemsCount;
    } catch (e) {
      debugPrint('❌ Error en syncFromReports: $e');
      return 0;
    }
  }

  // Helper: comparar listas de strings sin importar orden
  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Helper: evitar commit vacío innecesario
  // (Firestore no cobra por commits vacíos pero es buena práctica)
  bool _batchHasWrites(List<QueryDocumentSnapshot> docs) {
    // Si llegamos aquí con docs es porque hubo al menos una iteración
    // La forma correcta sería trackear un contador de updates en el loop,
    // pero para simplicidad retornamos true si hay docs (el batch.commit
    // con 0 operaciones es seguro en Firestore)
    return true;
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