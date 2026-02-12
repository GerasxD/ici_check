import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'report_model.dart';

class ReportsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  Stream<ServiceReportModel?> getReportStream(String policyId, String dateStr) {
    return _db
        .collection('reports')
        .where('policyId', isEqualTo: policyId)
        .where('dateStr', isEqualTo: dateStr)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      
      // ✅ IMPORTANTE: Agregar el ID del documento
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      
      return ServiceReportModel.fromMap(data);
    });
  }

  Future<void> saveReport(ServiceReportModel report) async {
    await _db
        .collection('reports')
        .doc(report.id)
        .set(report.toMap(), SetOptions(merge: true));
  }

  List<ReportEntry> generateEntriesForDate(
    PolicyModel policy,
    String dateStr,
    List<DeviceModel> definitions,
    bool isWeekly,
    int timeIndex,
  ) {
    List<ReportEntry> entries = [];
    int correctedTimeIndex = timeIndex;

    if (!isWeekly && dateStr.isNotEmpty) {
      try {
        final parts = dateStr.split('-');
        if (parts.length == 2) {
          final reportYear = int.parse(parts[0]);
          final reportMonth = int.parse(parts[1]);
          final policyStartYear = policy.startDate.year;
          final policyStartMonth = policy.startDate.month;
          correctedTimeIndex =
              (reportYear - policyStartYear) * 12 + (reportMonth - policyStartMonth);
        }
      } catch (e) {
        debugPrint('⚠️ Error parseando dateStr: $e');
      }
    }

    for (var devInstance in policy.devices) {
      final def = definitions.firstWhere(
        (d) => d.id == devInstance.definitionId,
        orElse: () => DeviceModel(
          id: 'err', 
          name: 'Unknown', 
          description: '', 
          activities: []
        )
      );

      if (def.id == 'err') continue;

      for (int i = 1; i <= devInstance.quantity; i++) {
        Map<String, String?> activityResults = {};

        for (var act in def.activities) {
          bool isDue = false;

          if (isWeekly) {
            if (act.frequency == Frequency.SEMANAL) {
              isDue = true;
            }
          } else {
            if (act.frequency != Frequency.SEMANAL) {
              double freqMonths = _getFrequencyVal(act.frequency);
              int offset = devInstance.scheduleOffsets[act.id] ?? 0;
              
              double adjustedTime = correctedTimeIndex - offset.toDouble();
              const double epsilon = 0.05;

              if (adjustedTime >= -epsilon) {
                double remainder = (adjustedTime % freqMonths).abs();
                if (remainder < epsilon || (remainder - freqMonths).abs() < epsilon) {
                  isDue = true;
                }
              }
            }
          }

          if (isDue) {
            activityResults[act.id] = null; 
          }
        }

        entries.add(ReportEntry(
          instanceId: devInstance.instanceId,
          deviceIndex: i,
          customId: "${def.name.substring(0, 3).toUpperCase()}-$i",
          results: activityResults,
        ));
      }
    }
    return entries;
  }

  ServiceReportModel initializeReport(
    PolicyModel policy,
    String dateStr,
    List<DeviceModel> definitions,
    bool isWeekly,
    int timeIndex,
  ) {
    final entries = generateEntriesForDate(
      policy, dateStr, definitions, isWeekly, timeIndex
    );

    debugPrint('✅ Reporte inicializado: ${entries.length} entradas para $dateStr');

    return ServiceReportModel(
      id: _uuid.v4(),
      policyId: policy.id,
      dateStr: dateStr,
      serviceDate: DateTime.now(),
      assignedTechnicianIds: policy.assignedUserIds,
      entries: entries,
    );
  }

  // ✅ ARREGLADO: Agregar CUATRIMESTRAL
  double _getFrequencyVal(Frequency f) {
    switch (f) {
      case Frequency.MENSUAL: 
        return 1.0;
      case Frequency.TRIMESTRAL: 
        return 3.0;
      case Frequency.CUATRIMESTRAL:  // ✅ AGREGADO
        return 4.0;
      case Frequency.SEMESTRAL: 
        return 6.0;
      case Frequency.ANUAL: 
        return 12.0;
      case Frequency.SEMANAL:
        return 0.25;
      default: 
        return 1.0;
    }
  }
}