import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceLocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'device_locations';

  // Genera un ID único por póliza + instancia
  String _docId(String policyId, String instanceId) => '${policyId}_$instanceId';

  // Guardar/actualizar ubicación
  Future<void> saveLocation({
    required String policyId,
    required String instanceId,
    required String customId,
    required String area,
  }) async {
    // Solo guardamos si hay algo que guardar
    if (customId.isEmpty && area.isEmpty) return;

    await _db.collection(_collection).doc(_docId(policyId, instanceId)).set({
      'policyId': policyId,
      'instanceId': instanceId,
      'customId': customId,
      'area': area,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Obtener todas las ubicaciones guardadas para una póliza
  Future<Map<String, Map<String, String>>> getLocationsForPolicy(
    String policyId,
    List<String> instanceIds,
  ) async {
    final Map<String, Map<String, String>> result = {};

    // Consulta batch por los instanceIds de esta póliza
    final futures = instanceIds.map((instanceId) =>
      _db.collection(_collection)
        .doc(_docId(policyId, instanceId))
        .get()
    );

    final docs = await Future.wait(futures);

    for (final doc in docs) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final instanceId = data['instanceId'] as String;
        result[instanceId] = {
          'customId': data['customId'] ?? '',
          'area': data['area'] ?? '',
        };
      }
    }

    return result;
  }
}