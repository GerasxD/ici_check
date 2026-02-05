import 'package:cloud_firestore/cloud_firestore.dart';
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
    // Usamos set con merge para actualiza o crear si no existe, usando el ID del reporte como ID del documento
    await _db.collection('reports').doc(report.id).set(report.toMap(), SetOptions(merge: true));
  }

  // Lógica para inicializar un reporte nuevo basado en la póliza (Réplica de tu React useEffect)
  ServiceReportModel initializeReport(
    PolicyModel policy, 
    String dateStr, 
    List<DeviceModel> definitions,
    bool isWeekly,
    int timeIndex
  ) {
    List<ReportEntry> entries = [];

    for (var devInstance in policy.devices) {
      final def = definitions.firstWhere((d) => d.id == devInstance.definitionId, orElse: () => DeviceModel(id: 'err', name: 'Unknown', description: '', activities: []));
      if (def.id == 'err') continue;

      for (int i = 1; i <= devInstance.quantity; i++) {
        Map<String, String?> activityResults = {};
        // ignore: unused_local_variable
        bool hasScheduled = false;

        for (var act in def.activities) {
          bool isDue = false;
          
          if (isWeekly) {
            if (act.frequency == Frequency.SEMANAL) isDue = true;
          } else {
            // Lógica mensual
            if (act.frequency != Frequency.SEMANAL) {
              double freqMonths = _getFrequencyVal(act.frequency); // Helper function
              int offset = devInstance.scheduleOffsets[act.id] ?? 0;
              double adjustedTime = timeIndex - offset.toDouble();
              
              if (adjustedTime >= -0.05) {
                double remainder = (adjustedTime % freqMonths).abs();
                if (remainder < 0.05 || (remainder - freqMonths).abs() < 0.05) {
                  isDue = true;
                }
              }
            }
          }

          if (isDue) {
            activityResults[act.id] = null; // Inicializar como null (vacío)
            hasScheduled = true;
          }
        }

        // Agregamos la entrada incluso si no hay actividades (para mostrar el dispositivo)
        entries.add(ReportEntry(
          instanceId: devInstance.instanceId,
          deviceIndex: i,
          customId: "${def.name.substring(0, 3).toUpperCase()}-$i",
          results: activityResults,
        ));
      }
    }

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
    // Retornar valores numéricos según tu lógica (1.0 mensual, 3.0 trimestral, etc)
    switch(f) {
      case Frequency.MENSUAL: return 1.0;
      case Frequency.TRIMESTRAL: return 3.0;
      case Frequency.SEMESTRAL: return 6.0;
      case Frequency.ANUAL: return 12.0;
      default: return 1.0;
    }
  }
}