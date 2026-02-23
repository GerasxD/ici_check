import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

    try {
      await _db.collection(_collection).doc(_docId(policyId, instanceId)).set({
        'policyId': policyId,
        'instanceId': instanceId,
        'customId': customId,
        'area': area,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ Ubicación guardada con éxito: $instanceId -> $area');
    } catch (e) {
      debugPrint('🚨 ERROR GUARDANDO UBICACIÓN: $e');
    }
  }

  Future<Map<String, Map<String, String>>> getLocationsForPolicy(
    String policyId,
    List<String> instanceIds,
  ) async {
    final Map<String, Map<String, String>> result = {};

    if (instanceIds.isEmpty) return result;

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
          
          // ★ FIX: Extraer el instanceId directamente del ID del documento
          // doc.id es "policyId_instanceId". Le quitamos el policyId_.
          final docId = doc.id; 
          final instanceId = docId.replaceFirst('${policyId}_', '');

          result[instanceId] = {
            'customId': data['customId']?.toString() ?? '',
            'area': data['area']?.toString() ?? '',
          };
        }
      } catch (e) {
        // ★ FIX: ¡Que no muera en silencio!
        debugPrint('🚨 ERROR LEYENDO UBICACIONES EN FIRESTORE (Chunk): $e');
        continue;
      }
    }

    debugPrint('📍 Se cargaron ${result.length} ubicaciones guardadas.');
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