import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'report_model.dart';

class ReportsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // ignore: unused_field
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
      // Usamos merge: true para simplificar y evitar errores.
      await docRef.set(data, SetOptions(merge: true));
      _savedReportIds.add(report.id);
    } catch (e) {
      debugPrint('Error en saveReport: $e');
      rethrow;
    }
  }

  /// Evita llamar report.toMap() en el main thread.
  Future<void> saveReportRaw(String reportId, Map<String, dynamic> data) async {
    try {
      final docRef = _db.collection('reports').doc(reportId);
      // Usamos merge: true. Si el documento no existe, lo crea. Si existe, lo actualiza.
      await docRef.set(data, SetOptions(merge: true));
      _savedReportIds.add(reportId); // Mantenemos el registro por si acaso
    } catch (e) {
      debugPrint('Error en saveReportRaw: $e');
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

    final List<ReportEntry> result = [];
    final Set<String> processedIds = {};

    // ─── Paso 1: Recorrer ideales y hacer merge con existentes ───
    for (final idealEntry in ideal) {
      processedIds.add(idealEntry.instanceId);
      final existingEntry = existingMap[idealEntry.instanceId];

      if (existingEntry == null) {
        // No existe en el reporte guardado → entrada nueva
        final saved = savedLocations[idealEntry.instanceId];
        result.add(idealEntry.copyWith(
          customId: (saved?['customId'] ?? '').isNotEmpty 
              ? saved!['customId']! 
              : idealEntry.customId,
          area: (saved?['area'] ?? '').isNotEmpty 
              ? saved!['area']! 
              : idealEntry.area,
        ));
        continue;
      }

      // Existe → combinar resultados para no perder lo que ya se respondió
      final Map<String, String?> mergedResults = {};
      for (final actId in idealEntry.results.keys) {
        mergedResults[actId] = existingEntry.results.containsKey(actId)
            ? existingEntry.results[actId]
            : null;
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

    // ─── ELIMINADO EL PASO 2 (ENTRADAS HUÉRFANAS) ───
    // Al quitar el código que forzaba a mantener las entradas con respuestas, 
    // ahora los dispositivos que elimines de la póliza se borrarán correctamente 
    // del reporte.

    return result;
  }

  Future<ServiceReportModel?> getReportOnce(String policyId, String dateStr) async {
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