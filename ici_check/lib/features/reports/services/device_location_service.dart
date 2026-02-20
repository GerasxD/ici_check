import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceLocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'device_locations';

  String _docId(String policyId, String instanceId) =>
      '${policyId}_$instanceId';

  Future<void> saveLocation({
    required String policyId,
    required String instanceId,
    required String customId,
    required String area,
  }) async {
    if (customId.isEmpty && area.isEmpty) return;

    await _db.collection(_collection).doc(_docId(policyId, instanceId)).set({
      'policyId': policyId,
      'instanceId': instanceId,
      'customId': customId,
      'area': area,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ★ FIX: Batch queries en chunks de 30 (límite de whereIn)
  /// ANTES: 600 instanceIds = 600 reads individuales → ANR
  /// AHORA: 600 instanceIds = 20 queries batch → ~2 segundos
  Future<Map<String, Map<String, String>>> getLocationsForPolicy(
    String policyId,
    List<String> instanceIds,
  ) async {
    final Map<String, Map<String, String>> result = {};

    if (instanceIds.isEmpty) return result;

    // Firestore limita whereIn a 30 elementos por query
    final chunks = _chunkList(instanceIds, 30);

    for (final chunk in chunks) {
      final docIds = chunk.map((id) => _docId(policyId, id)).toList();

      try {
        final snapshots = await _db
            .collection(_collection)
            .where(FieldPath.documentId, whereIn: docIds)
            .get();

        for (final doc in snapshots.docs) {
          final data = doc.data();
          if (data.isNotEmpty) {
            final instanceId = data['instanceId'] as String? ?? '';
            if (instanceId.isNotEmpty) {
              result[instanceId] = {
                'customId': data['customId'] ?? '',
                'area': data['area'] ?? '',
              };
            }
          }
        }
      } catch (e) {
        // Si falla un chunk, continuar con los demás
        // (mejor parcial que nada)
        continue;
      }
    }

    return result;
  }

  static List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      final end = (i + size > list.length) ? list.length : i + size;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}