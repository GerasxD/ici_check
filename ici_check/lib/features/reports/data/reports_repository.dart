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
      return ServiceReportModel.fromMap(snapshot.docs.first.data());
    });
  }

  Future<void> saveReport(ServiceReportModel report) async {
    await _db.collection('reports').doc(report.id).set(report.toMap(), SetOptions(merge: true));
  }

  // Lógica para inicializar un reporte nuevo basado en la póliza
  ServiceReportModel initializeReport(
    PolicyModel policy, 
    String dateStr, 
    List<DeviceModel> definitions,
    bool isWeekly,
    int timeIndex
  ) {
    List<ReportEntry> entries = [];

    // CORRECCIÓN: Normalizar el timeIndex si viene mal calculado
    int correctedTimeIndex = timeIndex;
    
    if (!isWeekly && dateStr.isNotEmpty) {
      try {
        // Parsear el dateStr (formato "2025-02")
        final parts = dateStr.split('-');
        if (parts.length == 2) {
          final reportYear = int.parse(parts[0]);
          final reportMonth = int.parse(parts[1]);
          
          // Calcular desde la fecha de inicio de la póliza
          final policyStartYear = policy.startDate.year;
          final policyStartMonth = policy.startDate.month;
          
          // Calcular diferencia en meses
          correctedTimeIndex = (reportYear - policyStartYear) * 12 + (reportMonth - policyStartMonth);
          
          debugPrint('📅 Corrigiendo timeIndex: original=$timeIndex, corregido=$correctedTimeIndex para $dateStr');
        }
      } catch (e) {
        debugPrint('⚠️ Error parseando dateStr: $e');
      }
    }

    for (var devInstance in policy.devices) {
      final def = definitions.firstWhere(
        (d) => d.id == devInstance.definitionId, 
        orElse: () => DeviceModel(id: 'err', name: 'Unknown', description: '', activities: [])
      );
      
      if (def.id == 'err') {
        debugPrint('⚠️ Definición no encontrada para: ${devInstance.definitionId}');
        continue;
      }

      for (int i = 1; i <= devInstance.quantity; i++) {
        Map<String, String?> activityResults = {};

        for (var act in def.activities) {
          bool isDue = false;
          
          if (isWeekly) {
            // En reportes semanales, solo incluir actividades semanales
            if (act.frequency == Frequency.SEMANAL) {
              isDue = true;
            }
          } else {
            // En reportes mensuales, EXCLUIR actividades semanales
            if (act.frequency != Frequency.SEMANAL) {
              double freqMonths = _getFrequencyVal(act.frequency);
              int offset = devInstance.scheduleOffsets[act.id] ?? 0;
              
              // USAR EL TIME INDEX CORREGIDO
              double adjustedTime = correctedTimeIndex - offset.toDouble();
              
              const double epsilon = 0.05;
              
              if (adjustedTime >= -epsilon) {
                double remainder = (adjustedTime % freqMonths).abs();
                
                // Verificar si está en el ciclo correcto
                if (remainder < epsilon || (remainder - freqMonths).abs() < epsilon) {
                  isDue = true;
                }
              }
            }
          }

          if (isDue) {
            activityResults[act.id] = null; // Inicializar como null (vacío)
          }
        }

        // SIEMPRE agregamos la entrada, incluso si no tiene actividades programadas
        entries.add(ReportEntry(
          instanceId: devInstance.instanceId,
          deviceIndex: i,
          customId: "${def.name.substring(0, 3).toUpperCase()}-$i",
          results: activityResults,
        ));
      }
    }

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

  double _getFrequencyVal(Frequency f) {
    switch(f) {
      case Frequency.MENSUAL: return 1.0;
      case Frequency.TRIMESTRAL: return 3.0;
      case Frequency.SEMESTRAL: return 6.0;
      case Frequency.ANUAL: return 12.0;
      default: return 1.0;
    }
  }
}