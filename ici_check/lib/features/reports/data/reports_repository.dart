import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'report_model.dart';

class ReportsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();
  final Set<String> _savedReportIds = {};

  static String unitInstanceId(String baseInstanceId, int unitIndex) {
    // unitIndex es 1-based
    if (unitIndex == 1) return baseInstanceId;        // siempre sin sufijo
    return '${baseInstanceId}_$unitIndex';             // _2, _3, _4 ...
  }

  Stream<ServiceReportModel?> getReportStream(String policyId, String dateStr) {
    return _db
        .collection('reports')
        .where('policyId', isEqualTo: policyId)
        .where('dateStr', isEqualTo: dateStr)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      return ServiceReportModel.fromMap(data);
    });
  }

  Future<void> saveReport(ServiceReportModel report) async {
    try {
      final data = report.toMap();
      final docRef = _db.collection('reports').doc(report.id);
      if (_savedReportIds.contains(report.id)) {
        await docRef.update(data);
      } else {
        await docRef.set(data);
        _savedReportIds.add(report.id);
      }
    } catch (e) {
      debugPrint('Error en saveReport: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // generateEntriesForDate
  //
  // Genera la lista "ideal" de entradas según la póliza actual.
  // Cada unidad recibe un instanceId ESTABLE: base para la 1ª, base_N para las demás.
  // ─────────────────────────────────────────────────────────────────────────
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

    // Contador global por definitionId → para el número en el customId (BOM-1, BOM-2…)
    final Map<String, int> deviceCounters = {};

    for (final devInstance in policy.devices) {
      final def = definitions.firstWhere(
        (d) => d.id == devInstance.definitionId,
        orElse: () => DeviceModel(id: 'err', name: 'Unknown', description: '', activities: []),
      );
      if (def.id == 'err') continue;

      final namePrefix = def.name.substring(0, min(3, def.name.length)).toUpperCase();

      for (int i = 1; i <= devInstance.quantity; i++) {
        // ── instanceId estable: unidad 1 = base, unidad N = base_N ──────
        final String uid = unitInstanceId(devInstance.instanceId, i);

        // ── Actividades que aplican en esta fecha ──────────────────────
        final Map<String, String?> activityResults = {};
        for (final act in def.activities) {
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

        // ── customId: savedLocation > auto-generado ────────────────────
        final saved         = savedLocations[uid];
        final savedCustomId = saved?['customId'] ?? '';
        final savedArea     = saved?['area']     ?? '';

        String autoCustomId;
        if (savedCustomId.isNotEmpty) {
          autoCustomId = savedCustomId;
        } else {
          deviceCounters[devInstance.definitionId] =
              (deviceCounters[devInstance.definitionId] ?? 0) + 1;
          autoCustomId = '$namePrefix-${deviceCounters[devInstance.definitionId]}';
        }

        final int deviceIndex = deviceCounters[devInstance.definitionId] ?? (entries.length + 1);

        entries.add(ReportEntry(
          instanceId:  uid,
          deviceIndex: deviceIndex,
          customId:    autoCustomId,
          area:        savedArea,
          results:     activityResults,
        ));
      }
    }

    return entries;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // mergeEntries
  //
  // • Entrada EXISTENTE (mismo instanceId) → preservar TODO lo capturado
  // • Entrada NUEVA                        → vacía (results = null)
  // • Entrada REMOVIDA                     → desaparece
  // ─────────────────────────────────────────────────────────────────────────
  List<ReportEntry> mergeEntries(
    List<ReportEntry> existing,
    List<ReportEntry> ideal,
    Map<String, Map<String, String>> savedLocations,
  ) {
    final Map<String, ReportEntry> existingMap = {
      for (final e in existing) e.instanceId: e,
    };

    return ideal.map((idealEntry) {
      final existingEntry = existingMap[idealEntry.instanceId];

      if (existingEntry == null) {
        // ── NUEVA unidad ──────────────────────────────────────────────
        final saved = savedLocations[idealEntry.instanceId];
        return idealEntry.copyWith(
          customId: (saved?['customId'] ?? '').isNotEmpty ? saved!['customId']! : idealEntry.customId,
          area:     (saved?['area']     ?? '').isNotEmpty ? saved!['area']!     : idealEntry.area,
        );
      }

      // ── UNIDAD EXISTENTE: preservar TODO, solo ajustar actividades ─
      final Map<String, String?> mergedResults = {};
      for (final actId in idealEntry.results.keys) {
        mergedResults[actId] = existingEntry.results.containsKey(actId)
            ? existingEntry.results[actId]   // respuesta previa ✅
            : null;                           // actividad nueva  ✅
      }

      final saved = savedLocations[existingEntry.instanceId];
      return existingEntry.copyWith(
        results:  mergedResults,
        customId: (saved?['customId'] ?? '').isNotEmpty ? saved!['customId']! : existingEntry.customId,
        area:     (saved?['area']     ?? '').isNotEmpty ? saved!['area']!     : existingEntry.area,
        // observations, photoUrls, activityData → intactos ✅
      );
    }).toList();
  }

// MIGRACIÓN: Esquema viejo (instanceIds duplicados) → Nuevo (únicos)
 List<ReportEntry> migrateOldEntries(List<ReportEntry> entries) {
  // ✅ Detectar si hay instanceIds O customIds duplicados
  final instanceIdCounts = <String, int>{};
  final customIdCounts = <String, int>{};

  for (final e in entries) {
    instanceIdCounts[e.instanceId] = (instanceIdCounts[e.instanceId] ?? 0) + 1;
    customIdCounts[e.customId] = (customIdCounts[e.customId] ?? 0) + 1;
  }

  final hasDuplicates =
      instanceIdCounts.values.any((c) => c > 1) ||
      customIdCounts.values.any((c) => c > 1);

  if (!hasDuplicates) return entries; // Ya está limpio, no tocar nada

  debugPrint("⚠️ Migrando reporte con duplicados...");

  // ✅ Sort numérico inteligente: DET-1, DET-2, ..., DET-10 (no DET-10 antes de DET-2)
  final _sortRegExp = RegExp(r'^(.+?)-(\d+)$');
  final sortedEntries = List<ReportEntry>.from(entries)
    ..sort((a, b) {
      final matchA = _sortRegExp.firstMatch(a.customId);
      final matchB = _sortRegExp.firstMatch(b.customId);

      if (matchA != null && matchB != null) {
        final prefixCompare = matchA.group(1)!.compareTo(matchB.group(1)!);
        if (prefixCompare != 0) return prefixCompare;
        // Mismo prefijo → comparar numéricamente
        return int.parse(matchA.group(2)!).compareTo(int.parse(matchB.group(2)!));
      }

      // Fallback: alfabético normal
      return a.customId.compareTo(b.customId);
    });

  // Contadores separados por base de instanceId y por prefijo de customId
  final instanceCounters = <String, int>{};
  final customIdCounters = <String, int>{};

  return sortedEntries.map((entry) {
    // ── Nuevo instanceId único ──────────────────────────────────────
    final cleanBase = _extractBaseInstanceId(entry.instanceId);
    instanceCounters[cleanBase] = (instanceCounters[cleanBase] ?? 0) + 1;
    final instanceCount = instanceCounters[cleanBase]!;
    final newInstanceId = ReportsRepository.unitInstanceId(cleanBase, instanceCount);

    // ── Nuevo customId único (DET-1, DET-2, DET-3...) ──────────────
    final customPrefix = _extractCustomIdPrefix(entry.customId);
    customIdCounters[customPrefix] = (customIdCounters[customPrefix] ?? 0) + 1;
    final customCount = customIdCounters[customPrefix]!;
    final newCustomId = '$customPrefix-$customCount';

    debugPrint(
      "   instanceId: ${entry.instanceId} → $newInstanceId  |  "
      "customId: ${entry.customId} → $newCustomId"
    );

    // ✅ TODOS los datos se preservan, solo cambian instanceId y customId
    return ReportEntry(
      instanceId:     newInstanceId,
      deviceIndex:    instanceCount,
      customId:       newCustomId,        // ✅ DET-1, DET-2, DET-3...
      area:           entry.area,         // ✅ intacto
      results:        entry.results,      // ✅ intacto (OK/NOK/NA/NR)
      observations:   entry.observations, // ✅ intacto
      photoUrls:      entry.photoUrls,    // ✅ intacto
      activityData:   entry.activityData, // ✅ intacto
      assignedUserId: entry.assignedUserId,
    );
  }).toList();
}

  // "DET-1" → "DET" | "BOM-2" → "BOM" | "ABC" → "ABC"
  String _extractCustomIdPrefix(String customId) {
    final regex = RegExp(r'^(.+)-\d+$');
    final match = regex.firstMatch(customId);
    return match != null ? match.group(1)! : customId;
  }

  // "836c5853_2" → "836c5853" | "836c5853" → "836c5853"
  String _extractBaseInstanceId(String instanceId) {
    final regex = RegExp(r'^(.+)_(\d+)$');
    final match = regex.firstMatch(instanceId);
    return match != null ? match.group(1)! : instanceId;
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
    return ServiceReportModel(
      id:                    _uuid.v4(),
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