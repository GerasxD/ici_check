import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'report_model.dart';

class ReportsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  FirebaseFirestore get db => _db; // Exponer para PhotoSyncService
  // ignore: unused_field
  final _uuid = const Uuid();
  final Set<String> _savedReportIds = {};

  /// Determina si una actividad es acumulativa según la póliza.
  /// Ya NO depende de DeviceModel.isCumulative.
  static bool isActivityCumulative(PolicyModel policy, String definitionId, String activityId) {
    for (final dev in policy.devices) {
      if (dev.definitionId == definitionId) {
        return dev.cumulativeActivities.contains(activityId);
      }
    }
    return false;
  }

  /// Retorna true si este PolicyDevice tiene AL MENOS una actividad acumulativa.
  static bool hasAnyCumulativeActivity(PolicyDevice devInstance) {
    return devInstance.cumulativeActivities.isNotEmpty;
  }

  static String unitInstanceId(String baseInstanceId, int unitIndex) {
    if (unitIndex == 1) return baseInstanceId;
    // ✅ Optimizado: Interpolación simple sin instanciar RegExp
    return '${baseInstanceId}_$unitIndex';
  }

  // Stream<ServiceReportModel?> getReportStream(String policyId, String dateStr) {
  //   return _db
  //       .collection('reports')
  //       .where('policyId', isEqualTo: policyId)
  //       .where('dateStr', isEqualTo: dateStr)
  //       .limit(1)
  //       .snapshots()
  //       .map((snapshot) {
  //     if (snapshot.docs.isEmpty) return null;
  //     final data = snapshot.docs.first.data();
  //     data['id'] = snapshot.docs.first.id;
  //     return ServiceReportModel.fromMap(data);
  //   });
  // }

  Stream<ServiceReportModel?> getReportStream(String policyId, String dateStr) {
    return _db
        .collection('reports')
        .where('policyId', isEqualTo: policyId)
        .where('dateStr', isEqualTo: dateStr)
        .limit(1)
        .snapshots(includeMetadataChanges: true) // ★ OFFLINE FIX: emite cambios del cache
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      return ServiceReportModel.fromMap(data);
    });
  }

  Future<ServiceReportModel?> getReportOnce(String policyId, String dateStr) async {
    // ★ OFFLINE FIX: Intentar cache primero
    try {
      final cacheSnapshot = await _db
          .collection('reports')
          .where('policyId', isEqualTo: policyId)
          .where('dateStr', isEqualTo: dateStr)
          .limit(1)
          .get(const GetOptions(source: Source.cache));

      if (cacheSnapshot.docs.isNotEmpty) {
        final data = cacheSnapshot.docs.first.data();
        data['id'] = cacheSnapshot.docs.first.id;
        return ServiceReportModel.fromMap(data);
      }
    } catch (_) {
      // Cache vacío, intentar server
    }

    // Fallback al server
    try {
      final snapshot = await _db
          .collection('reports')
          .where('policyId', isEqualTo: policyId)
          .where('dateStr', isEqualTo: dateStr)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      return ServiceReportModel.fromMap(data);
    } catch (e) {
      debugPrint('Error en getReportOnce: $e');
      return null;
    }
  }

  // Future<void> saveReport(ServiceReportModel report) async {
  //   try {
  //     final data = report.toMap();
  //     final docRef = _db.collection('reports').doc(report.id);
  //     // Usamos merge: true para simplificar y evitar errores.
  //     await docRef.set(data, SetOptions(merge: true));
  //     _savedReportIds.add(report.id);
  //   } catch (e) {
  //     debugPrint('Error en saveReport: $e');
  //     rethrow;
  //   }
  // }

  Future<void> saveReport(ServiceReportModel report) async {
    try {
      final data = report.toMap();
      final docRef = _db.collection('reports').doc(report.id);
      // ★ OFFLINE FIX: Sin await → Firestore encola localmente si no hay red
      docRef.set(data, SetOptions(merge: true));
      _savedReportIds.add(report.id);
    } catch (e) {
      debugPrint('Error en saveReport: $e');
      // ★ NO rethrow → el dato queda en cache de Firestore para sync posterior
    }
  }

  /// Evita llamar report.toMap() en el main thread.
  // Future<void> saveReportRaw(String reportId, Map<String, dynamic> data) async {
  //   try {
  //     final docRef = _db.collection('reports').doc(reportId);
  //     // Usamos merge: true. Si el documento no existe, lo crea. Si existe, lo actualiza.
  //     await docRef.set(data, SetOptions(merge: true));
  //     _savedReportIds.add(reportId); // Mantenemos el registro por si acaso
  //   } catch (e) {
  //     debugPrint('Error en saveReportRaw: $e');
  //     rethrow;
  //   }
  // }

   Future<void> saveReportRaw(String reportId, Map<String, dynamic> data) async {
    try {
      final docRef = _db.collection('reports').doc(reportId);
      // ★ OFFLINE FIX: Sin await → fire-and-forget
      docRef.set(data, SetOptions(merge: true));
      _savedReportIds.add(reportId);
    } catch (e) {
      debugPrint('Error en saveReportRaw: $e');
      // ★ NO rethrow
    }
  }

  List<ReportEntry> generateEntriesForDate(
    PolicyModel policy,
    String dateStr,
    List<DeviceModel> definitions,
    bool isWeekly,
    int timeIndex, {
    Map<String, Map<String, String>> savedLocations = const {},
  }) {
    List<ReportEntry> entries = [];
    int correctedTimeIndex = timeIndex;

    if (!isWeekly && dateStr.isNotEmpty) {
      try {
        final parts = dateStr.split('-');
        if (parts.length == 2) {
          final reportYear  = int.parse(parts[0]);
          final reportMonth = int.parse(parts[1]);
          correctedTimeIndex =
              (reportYear - policy.startDate.year) * 12 +
              (reportMonth - policy.startDate.month);
        }
      } catch (e) {
        debugPrint('⚠️ Error parseando dateStr: $e');
      }
    }

    final Map<String, int> deviceCounters = {};
    final Map<String, DeviceModel> definitionsMap = {
      for (final def in definitions) def.id: def
    };
    final dummyDevice = DeviceModel(id: 'err', name: 'Unknown', description: '', activities: []);

    final Set<String> usedUids = {};

    for (final devInstance in policy.devices) {
      final def = definitionsMap[devInstance.definitionId] ?? dummyDevice;
      if (def.id == 'err') continue;
      final namePrefix = def.name.substring(0, min(3, def.name.length)).toUpperCase();

      for (int i = 1; i <= devInstance.quantity; i++) {
        String uid = unitInstanceId(devInstance.instanceId, i);

        int collisionCounter = 1;
        String baseUid = uid;
        while (usedUids.contains(uid)) {
          uid = '${baseUid}_dup$collisionCounter';
          collisionCounter++;
        }
        usedUids.add(uid);

        final Map<String, String?> activityResults = {};

        // (Lógica de frecuencias intacta)
        for (final act in def.activities) {
          if (devInstance.cumulativeActivities.contains(act.id)) continue;
          bool isDue = false;
          const double epsilon = 0.05;

          if (isWeekly) {
            if (act.frequency == Frequency.SEMANAL ||
                act.frequency == Frequency.QUINCENAL) {
              final double freqMonths = _getFrequencyVal(act.frequency);
              final int offset = devInstance.scheduleOffsets[act.id] ?? 0;
              final double adjustedTime = (timeIndex / 4.0) - offset.toDouble();
              if (adjustedTime >= -epsilon) {
                final double remainder = (adjustedTime % freqMonths).abs();
                if (remainder < epsilon || (remainder - freqMonths).abs() < epsilon) {
                  isDue = true;
                }
              }
            }
          } else {
            if (act.frequency != Frequency.SEMANAL &&
                act.frequency != Frequency.QUINCENAL &&
                act.frequency != Frequency.DIARIO) {
              final double freqMonths = _getFrequencyVal(act.frequency);
              final int offset = devInstance.scheduleOffsets[act.id] ?? 0;
              final double adjustedTime = correctedTimeIndex.toDouble() - offset.toDouble();
              if (adjustedTime >= -epsilon) {
                final double remainder = (adjustedTime % freqMonths).abs();
                if (remainder < epsilon || (remainder - freqMonths).abs() < epsilon) {
                  isDue = true;
                }
              }
            }
          }
          if (isDue) activityResults[act.id] = null;
        }

        // Incrementamos el contador SIEMPRE, para mantener la numeración interna correcta
        final int deviceIndex = (deviceCounters[devInstance.definitionId] ?? 0) + 1;
        deviceCounters[devInstance.definitionId] = deviceIndex;

        // ★ AQUÍ ESTÁ LA MAGIA DEL HISTORIAL ★
        final saved = savedLocations[uid];
        final savedCustomId = saved?['customId'] ?? '';
        final savedArea = saved?['area'] ?? '';

        // Si tenemos un ID guardado en Firebase, lo usamos. Si no, generamos el automático (ej. "EXT-1")
        final autoCustomId = savedCustomId.isNotEmpty 
            ? savedCustomId 
            : '$namePrefix-$deviceIndex';

        entries.add(ReportEntry(
          instanceId:  uid,
          deviceIndex: deviceIndex,
          customId:    autoCustomId,  // ¡ID pre-llenado!
          area:        savedArea,     // ¡Ubicación pre-llenada!
          results:     activityResults,
          observations: '',
          photoUrls: const [],
          activityData: const {},
        ));
      }
    }

    return entries;
  }

  Future<ServiceReportModel?> getOrCreateCumulativeReport({
    required PolicyModel policy,
    required List<DeviceModel> definitions,
    required Map<String, Map<String, String>> savedLocations,
  }) async {
    const String dateStr = 'CUMULATIVE';

    final existing = await getReportOnce(policy.id, dateStr);
    if (existing != null) return existing;

    // ★ CAMBIO: Verificar por póliza
    final bool hasCumulativeActivities = policy.devices.any(
      (d) => d.cumulativeActivities.isNotEmpty,
    );
    if (!hasCumulativeActivities) return null;

    final entries = _generateCumulativeEntriesPublic(
      policy: policy,
      definitions: definitions,
      savedLocations: savedLocations,
    );

    if (entries.isEmpty) return null;

    final reportId = '${policy.id}_$dateStr';
    final report = ServiceReportModel(
      id: reportId,
      policyId: policy.id,
      dateStr: dateStr,
      serviceDate: DateTime.now(),
      assignedTechnicianIds: policy.assignedUserIds,
      entries: entries,
    );

    await saveReport(report);
    return report;
  }

  List<ReportEntry> _generateCumulativeEntriesPublic({
    required PolicyModel policy,
    required List<DeviceModel> definitions,
    required Map<String, Map<String, String>> savedLocations,
  }) {
    final List<ReportEntry> entries = [];
    final Map<String, int> deviceCounters = {};
    final Map<String, DeviceModel> definitionsMap = {
      for (final def in definitions) def.id: def
    };
    final Set<String> usedUids = {};

    for (final devInstance in policy.devices) {
      // ★ CAMBIO CLAVE: Solo procesar si tiene actividades acumulativas
      if (devInstance.cumulativeActivities.isEmpty) continue;

      final def = definitionsMap[devInstance.definitionId];
      if (def == null) continue;

      final namePrefix = def.name
          .substring(0, def.name.length < 3 ? def.name.length : 3)
          .toUpperCase();

      for (int i = 1; i <= devInstance.quantity; i++) {
        String uid = unitInstanceId(devInstance.instanceId, i);

        int collisionCounter = 1;
        String baseUid = uid;
        while (usedUids.contains(uid)) {
          uid = '${baseUid}_dup$collisionCounter';
          collisionCounter++;
        }
        usedUids.add(uid);

        // ★ CAMBIO CLAVE: Solo incluir actividades que están en cumulativeActivities
        final Map<String, String?> activityResults = {};
        for (final act in def.activities) {
          if (devInstance.cumulativeActivities.contains(act.id)) {
            // También respetar excludedActivities
            if (!devInstance.excludedActivities.contains(act.id)) {
              activityResults[act.id] = null;
            }
          }
        }

        // Si no quedaron actividades, saltar esta unidad
        if (activityResults.isEmpty) continue;

        final int deviceIndex =
            (deviceCounters[devInstance.definitionId] ?? 0) + 1;
        deviceCounters[devInstance.definitionId] = deviceIndex;

        final saved = savedLocations[uid];
        final savedCustomId = saved?['customId'] ?? '';
        final savedArea = saved?['area'] ?? '';
        final autoCustomId =
            savedCustomId.isNotEmpty ? savedCustomId : '$namePrefix-$deviceIndex';

        entries.add(ReportEntry(
          instanceId: uid,
          deviceIndex: deviceIndex,
          customId: autoCustomId,
          area: savedArea,
          results: activityResults,
          observations: '',
          photoUrls: const [],
          activityData: const {},
        ));
      }
    }

    return entries;
  }

  /// Obtiene progreso global del reporte acumulativo para el cronograma.
  /// Retorna {total: N, completed: N} o null si no existe.
  Future<({int total, int completed})?> getCumulativeProgress(
    String policyId,
  ) async {
    final report = await getReportOnce(policyId, 'CUMULATIVE');
    if (report == null) return null;

    int total = 0;
    int completed = 0;

    for (final entry in report.entries) {
      for (final value in entry.results.values) {
        total++;
        if (value == 'OK' || value == 'NOK' || value == 'NA') {
          completed++;
        }
      }
    }

    return (total: total, completed: completed);
  }

  Future<ServiceReportModel?> syncCumulativeReport({
    required PolicyModel policy,
    required List<DeviceModel> definitions,
    required Map<String, Map<String, String>> savedLocations,
  }) async {
    const String dateStr = 'CUMULATIVE';

    // ★ CAMBIO: Ya no filtramos por def.isCumulative, sino por póliza
    final bool hasCumulativeActivities = policy.devices.any(
      (d) => d.cumulativeActivities.isNotEmpty,
    );

    if (!hasCumulativeActivities) return null;

    final idealEntries = _generateCumulativeEntriesPublic(
      policy: policy,
      definitions: definitions,
      savedLocations: savedLocations,
    );

    final existing = await getReportOnce(policy.id, dateStr);

    if (existing == null) {
      if (idealEntries.isEmpty) return null;

      final reportId = '${policy.id}_$dateStr';
      final report = ServiceReportModel(
        id: reportId,
        policyId: policy.id,
        dateStr: dateStr,
        serviceDate: DateTime.now(),
        assignedTechnicianIds: policy.assignedUserIds,
        entries: idealEntries,
      );
      await saveReport(report);
      return report;
    }

    final mergedEntries = mergeEntries(existing.entries, idealEntries, savedLocations);
    final bool changed = _entriesStructureChanged(existing.entries, mergedEntries);
    if (!changed) return existing;

    final updatedReport = existing.copyWith(entries: mergedEntries);
    await saveReport(updatedReport);
    return updatedReport;
  }

  bool _entriesStructureChanged(
    List<ReportEntry> oldEntries,
    List<ReportEntry> newEntries,
  ) {
    if (oldEntries.length != newEntries.length) return true;
    final oldIds = oldEntries.map((e) => e.instanceId).toSet();
    final newIds = newEntries.map((e) => e.instanceId).toSet();
    if (!oldIds.containsAll(newIds) || !newIds.containsAll(oldIds)) return true;

    for (int i = 0; i < newEntries.length; i++) {
      final newKeys = newEntries[i].results.keys.toSet();
      final oldEntry = oldEntries.firstWhere(
        (e) => e.instanceId == newEntries[i].instanceId,
        orElse: () => newEntries[i],
      );
      final oldKeys = oldEntry.results.keys.toSet();
      if (!newKeys.containsAll(oldKeys) || !oldKeys.containsAll(newKeys)) {
        return true;
      }
    }
    return false;
  }
    
  List<ReportEntry> mergeEntries(
  List<ReportEntry> existing,
  List<ReportEntry> ideal,
  Map<String, Map<String, String>> savedLocations,
  ) {
    final Map<String, ReportEntry> existingMap = {};
    for (final e in existing) {
      if (!existingMap.containsKey(e.instanceId)) {
        existingMap[e.instanceId] = e;
      }
    }

    // ★ Set de IDs ideales para saber cuáles actividades deben existir
    // ignore: unused_local_variable
    final Set<String> idealIds = ideal.map((e) => e.instanceId).toSet();
    
    // ★ Map de ideales para acceso rápido a los results esperados
    final Map<String, ReportEntry> idealMap = {};
    for (final e in ideal) {
      idealMap[e.instanceId] = e;
    }

    final List<ReportEntry> result = [];
    final Set<String> processedIds = {};

    // ─── Paso 1: Recorrer EXISTENTES (preserva el orden guardado en Firebase) ───
    for (final existingEntry in existing) {
      if (processedIds.contains(existingEntry.instanceId)) continue;
      processedIds.add(existingEntry.instanceId);

      final idealEntry = idealMap[existingEntry.instanceId];
      
      // Si ya no está en el ideal (dispositivo eliminado de póliza), lo saltamos
      if (idealEntry == null) continue;

      // Combinar resultados para no perder lo que ya se respondió
      final Map<String, String?> mergedResults = {};

      // Paso A: Agregar todas las actividades del ideal (las que "tocan" ahora)
      for (final actId in idealEntry.results.keys) {
        mergedResults[actId] = existingEntry.results.containsKey(actId)
            ? existingEntry.results[actId]
            : null;
      }

      // Paso B: Preservar actividades existentes que YA tienen respuesta
      // aunque no estén en el ideal (evita borrar respuestas guardadas)
      for (final actId in existingEntry.results.keys) {
        if (!mergedResults.containsKey(actId) &&
            existingEntry.results[actId] != null) {
          mergedResults[actId] = existingEntry.results[actId];
        }
      }

      final saved = savedLocations[existingEntry.instanceId];
      result.add(existingEntry.copyWith(
        results: mergedResults,
        customId: (saved?['customId'] ?? '').isNotEmpty
            ? saved!['customId']!
            : existingEntry.customId,
        area: (saved?['area'] ?? '').isNotEmpty
            ? saved!['area']!
            : existingEntry.area,
      ));
    }

    // ─── Paso 2: Agregar entradas nuevas del ideal que no existían ───
    for (final idealEntry in ideal) {
      if (processedIds.contains(idealEntry.instanceId)) continue;
      processedIds.add(idealEntry.instanceId);

      final saved = savedLocations[idealEntry.instanceId];
      result.add(idealEntry.copyWith(
        customId: (saved?['customId'] ?? '').isNotEmpty
            ? saved!['customId']!
            : idealEntry.customId,
        area: (saved?['area'] ?? '').isNotEmpty
            ? saved!['area']!
            : idealEntry.area,
      ));
    }

    return result;
  }

  // Future<ServiceReportModel?> getReportOnce(String policyId, String dateStr) async {
  //   final snapshot = await _db
  //       .collection('reports')
  //       .where('policyId', isEqualTo: policyId)
  //       .where('dateStr', isEqualTo: dateStr)
  //       .limit(1)
  //       .get();

  //   if (snapshot.docs.isEmpty) return null;
  //   final data = snapshot.docs.first.data();
  //   data['id'] = snapshot.docs.first.id;
  //   return ServiceReportModel.fromMap(data);
  // }

  ServiceReportModel initializeReport(
    PolicyModel policy,
    String dateStr,
    List<DeviceModel> definitions,
    bool isWeekly,
    int timeIndex, {
    Map<String, Map<String, String>> savedLocations = const {},
  }) {
    final entries = generateEntriesForDate(
      policy, dateStr, definitions, isWeekly, timeIndex,
      savedLocations: savedLocations,
    );
    debugPrint('✅ Reporte inicializado: ${entries.length} entradas para $dateStr');
    
    // ★ EL FIX: El ID del reporte DEBE ser predecible para que el servicio de locaciones coincida.
    final reportId = '${policy.id}_$dateStr';

    return ServiceReportModel(
      id:                    reportId,
      policyId:              policy.id,
      dateStr:               dateStr,
      serviceDate:           DateTime.now(),
      assignedTechnicianIds: policy.assignedUserIds,
      entries:               entries,
    );
  }

  double _getFrequencyVal(Frequency f) {
    switch (f) {
      case Frequency.MENSUAL:       return 1.0;
      case Frequency.TRIMESTRAL:    return 3.0;
      case Frequency.CUATRIMESTRAL: return 4.0;
      case Frequency.SEMESTRAL:     return 6.0;
      case Frequency.ANUAL:         return 12.0;
      case Frequency.SEMANAL:       return 0.25;
      case Frequency.QUINCENAL:     return 0.5;
      default:                      return 1.0;
    }
  }
}

