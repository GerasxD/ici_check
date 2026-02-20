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
    if (unitIndex == 1) return baseInstanceId;
    // ✅ Optimizado: Interpolación simple sin instanciar RegExp
    return '${baseInstanceId}_$unitIndex';
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
    
    // ✅ OPTIMIZACIÓN 1: Crear un HashMap de definiciones.
    // En lugar de hacer un `firstWhere` por cada dispositivo de la póliza
    // (lo cual es lento en listas grandes), creamos un mapa de acceso O(1).
    final Map<String, DeviceModel> definitionsMap = {
      for (final def in definitions) def.id: def
    };

    // ✅ OPTIMIZACIÓN 2: Crear un "Dummy" genérico una sola vez
    final dummyDevice = DeviceModel(id: 'err', name: 'Unknown', description: '', activities: []);

    for (final devInstance in policy.devices) {
      // ✅ Usar el mapa para búsqueda instantánea
      final def = definitionsMap[devInstance.definitionId] ?? dummyDevice;
      
      if (def.id == 'err') continue;

      final namePrefix = def.name.substring(0, min(3, def.name.length)).toUpperCase();

      for (int i = 1; i <= devInstance.quantity; i++) {
        final String uid = unitInstanceId(devInstance.instanceId, i);
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

        final saved = savedLocations[uid];
        final savedCustomId = saved?['customId'] ?? '';
        final savedArea = saved?['area'] ?? '';

        String autoCustomId;
        if (savedCustomId.isNotEmpty) {
          autoCustomId = savedCustomId;
        } else {
          // ✅ Optimizado: Asignación directa y lectura de una sola vez
          final count = (deviceCounters[devInstance.definitionId] ?? 0) + 1;
          deviceCounters[devInstance.definitionId] = count;
          autoCustomId = '$namePrefix-$count';
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

  List<ReportEntry> mergeEntries(
    List<ReportEntry> existing,
    List<ReportEntry> ideal,
    Map<String, Map<String, String>> savedLocations,
  ) {
    // Ya estaba usando un Map, lo cual es excelente.
    final Map<String, ReportEntry> existingMap = {
      for (final e in existing) e.instanceId: e,
    };

    return ideal.map((idealEntry) {
      final existingEntry = existingMap[idealEntry.instanceId];

      if (existingEntry == null) {
        final saved = savedLocations[idealEntry.instanceId];
        return idealEntry.copyWith(
          customId: (saved?['customId'] ?? '').isNotEmpty ? saved!['customId']! : idealEntry.customId,
          area:     (saved?['area']     ?? '').isNotEmpty ? saved!['area']!     : idealEntry.area,
        );
      }

      final Map<String, String?> mergedResults = {};
      for (final actId in idealEntry.results.keys) {
        mergedResults[actId] = existingEntry.results.containsKey(actId)
            ? existingEntry.results[actId]
            : null;
      }

      final saved = savedLocations[existingEntry.instanceId];
      return existingEntry.copyWith(
        results:  mergedResults,
        customId: (saved?['customId'] ?? '').isNotEmpty ? saved!['customId']! : existingEntry.customId,
        area:     (saved?['area']     ?? '').isNotEmpty ? saved!['area']!     : existingEntry.area,
      );
    }).toList();
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