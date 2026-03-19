import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
    return '${baseInstanceId}_$unitIndex';
  }

  Stream<ServiceReportModel?> getReportStream(String policyId, String dateStr) {
    return _db
        .collection('reports')
        .where('policyId', isEqualTo: policyId)
        .where('dateStr', isEqualTo: dateStr)
        .limit(1)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      return ServiceReportModel.fromMap(data);
    });
  }

  Future<ServiceReportModel?> getReportOnce(String policyId, String dateStr) async {
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
    } catch (_) {}

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

  Future<void> saveReport(ServiceReportModel report) async {
    try {
      final data = report.toMap();
      final docRef = _db.collection('reports').doc(report.id);
      docRef.set(data, SetOptions(merge: true));
      _savedReportIds.add(report.id);
    } catch (e) {
      debugPrint('Error en saveReport: $e');
    }
  }

  Future<void> saveReportRaw(String reportId, Map<String, dynamic> data) async {
    try {
      final docRef = _db.collection('reports').doc(reportId);
      docRef.set(data, SetOptions(merge: true));
      _savedReportIds.add(reportId);
    } catch (e) {
      debugPrint('Error en saveReportRaw: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // ★ MERGE FIX DEFINITIVO: saveReportMerged
  //
  //   RETORNA:
  //     true  → Se guardó exitosamente en el SERVIDOR (Transaction OK)
  //     false → NO se pudo guardar en servidor (offline u otro error)
  //
  //   CLAVE: Cuando retorna false, NO escribe NADA a Firestore.
  //          Así evitamos que la cola offline de Firestore aplaste
  //          las respuestas del otro usuario al reconectar.
  // ═══════════════════════════════════════════════════════════════════
  Future<bool> saveReportMerged(
    ServiceReportModel localReport, {
    required Map<String, Set<String>> dirtyResults,
    required Set<String> dirtyEntryFields,
    required bool dirtyMeta,
  }) async {
    final docRef = _db.collection('reports').doc(localReport.id);

    // ── Paso 1: Verificar conectividad ──
    bool isOnline = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      isOnline = !connectivity.contains(ConnectivityResult.none);
    } catch (_) {
      isOnline = false;
    }

    // ★ CLAVE: Si estamos offline, NO escribimos NADA a Firestore.
    // Los cambios se quedan en memoria (Riverpod state + dirty tracking).
    // Cuando reconecte, el stream de Firebase disparará _syncAndLoadReport,
    // que verá hasPendingChanges=true y hará el merge correctamente.
    if (!isOnline) {
      debugPrint('📴 Offline: cambios guardados solo en memoria (dirty tracking activo)');
      return false;
    }

    // ── Paso 2: Online → Transaction con merge inteligente ──
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);

        if (!snap.exists) {
          tx.set(docRef, localReport.toMap());
          return;
        }

        final serverData = snap.data()!;
        serverData['id'] = snap.id;
        final serverReport = ServiceReportModel.fromMap(serverData);

        // ── Construir lookup del servidor ──
        final serverEntryMap = <String, ReportEntry>{};
        for (final e in serverReport.entries) {
          serverEntryMap[e.instanceId] = e;
        }

        final mergedEntries = <ReportEntry>[];
        final processedIds = <String>{};

        // ── Recorrer entries locales ──
        for (final localEntry in localReport.entries) {
          processedIds.add(localEntry.instanceId);
          final serverEntry = serverEntryMap[localEntry.instanceId];

          if (serverEntry == null) {
            mergedEntries.add(localEntry);
            continue;
          }

          final dirtyActs = dirtyResults[localEntry.instanceId];
          final hasDirtyFields = dirtyEntryFields.contains(localEntry.instanceId);

          if (dirtyActs == null && !hasDirtyFields) {
            // Nada cambió localmente → usar servidor
            mergedEntries.add(serverEntry);
            continue;
          }

          // Merge results: servidor como base, overlay solo lo dirty
          final mergedResults = Map<String, String?>.from(serverEntry.results);
          if (dirtyActs != null) {
            for (final actId in dirtyActs) {
              if (localEntry.results.containsKey(actId)) {
                mergedResults[actId] = localEntry.results[actId];
              }
            }
          }

          mergedEntries.add(serverEntry.copyWith(
            results: mergedResults,
            observations: hasDirtyFields
                ? localEntry.observations
                : serverEntry.observations,
            photoUrls: hasDirtyFields
                ? localEntry.photoUrls
                : serverEntry.photoUrls,
            activityData: hasDirtyFields
                ? localEntry.activityData
                : serverEntry.activityData,
            customId: hasDirtyFields
                ? localEntry.customId
                : serverEntry.customId,
            area: hasDirtyFields
                ? localEntry.area
                : serverEntry.area,
          ));
        }

        // Entries que solo existen en servidor
        for (final serverEntry in serverReport.entries) {
          if (!processedIds.contains(serverEntry.instanceId)) {
            mergedEntries.add(serverEntry);
          }
        }

        // Merge reporte final
        final ServiceReportModel mergedReport;
        if (dirtyMeta) {
          mergedReport = localReport.copyWith(entries: mergedEntries);
        } else {
          mergedReport = serverReport.copyWith(entries: mergedEntries);
        }

        tx.set(docRef, mergedReport.toMap());
      });

      debugPrint('✅ Transaction merge exitosa');
      return true; // ★ Guardado exitosamente en servidor

    } catch (e) {
      debugPrint('⚠️ Transaction merge falló: $e');
      // ★ NO escribimos nada como fallback. Retornamos false.
      // El dirty tracking se mantiene y se reintentará.
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Todo lo demás queda EXACTAMENTE igual que antes
  // ═══════════════════════════════════════════════════════════════════

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

        final int deviceIndex = (deviceCounters[devInstance.definitionId] ?? 0) + 1;
        deviceCounters[devInstance.definitionId] = deviceIndex;

        final saved = savedLocations[uid];
        final savedCustomId = saved?['customId'] ?? '';
        final savedArea = saved?['area'] ?? '';

        final autoCustomId = savedCustomId.isNotEmpty 
            ? savedCustomId 
            : '$namePrefix-$deviceIndex';

        entries.add(ReportEntry(
          instanceId:  uid,
          deviceIndex: deviceIndex,
          customId:    autoCustomId,
          area:        savedArea,
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

        final Map<String, String?> activityResults = {};
        for (final act in def.activities) {
          if (devInstance.cumulativeActivities.contains(act.id)) {
            if (!devInstance.excludedActivities.contains(act.id)) {
              activityResults[act.id] = null;
            }
          }
        }

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

    // ignore: unused_local_variable
    final Set<String> idealIds = ideal.map((e) => e.instanceId).toSet();
    
    final Map<String, ReportEntry> idealMap = {};
    for (final e in ideal) {
      idealMap[e.instanceId] = e;
    }

    final List<ReportEntry> result = [];
    final Set<String> processedIds = {};

    for (final existingEntry in existing) {
      if (processedIds.contains(existingEntry.instanceId)) continue;
      processedIds.add(existingEntry.instanceId);

      final idealEntry = idealMap[existingEntry.instanceId];
      
      if (idealEntry == null) continue;

      final Map<String, String?> mergedResults = {};

      for (final actId in idealEntry.results.keys) {
        mergedResults[actId] = existingEntry.results.containsKey(actId)
            ? existingEntry.results[actId]
            : null;
      }

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