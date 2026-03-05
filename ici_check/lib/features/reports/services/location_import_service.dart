import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Servicio para importar IDs y ubicaciones de dispositivos desde pólizas anteriores.
///
/// La lógica clave: mapea por (definitionId, índice de unidad) ya que eso se
/// mantiene constante entre pólizas del mismo cliente, aunque los instanceId
/// cambien al crear una póliza nueva.
class LocationImportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Busca todas las pólizas anteriores de un cliente específico.
  /// Retorna lista de mapas con {id, startDate, deviceCount} para mostrar en UI.
  Future<List<Map<String, dynamic>>> getPreviousPoliciesForClient(
    String clientId, {
    String? excludePolicyId,
  }) async {
    try {
      final query = _db
          .collection('policies')
          .where('clientId', isEqualTo: clientId)
          .orderBy('startDate', descending: true);

      final snapshot = await query.get();

      return snapshot.docs
          .where((doc) => doc.id != excludePolicyId)
          .map((doc) {
        final data = doc.data();
        final devices = data['devices'] as List<dynamic>? ?? [];

        // Contar unidades totales
        int totalUnits = 0;
        for (final dev in devices) {
          totalUnits += (dev['quantity'] as int? ?? 1);
        }

        return {
          'id': doc.id,
          'startDate': (data['startDate'] as Timestamp).toDate(),
          'durationMonths': data['durationMonths'] as int? ?? 12,
          'deviceTypes': devices.length,
          'totalUnits': totalUnits,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error buscando pólizas anteriores: $e');
      return [];
    }
  }

  /// Extrae todas las ubicaciones guardadas de una póliza fuente.
  ///
  /// Retorna un mapa organizado por (definitionId, unitIndex) → {customId, area}
  /// donde unitIndex es 1-based (primera unidad = 1, segunda = 2, etc.)
  ///
  /// Este formato permite mapear ubicaciones a nuevos instanceIds sin importar
  /// que los UUIDs sean completamente distintos.
  Future<Map<String, Map<int, LocationData>>> extractLocationsFromPolicy(
    String sourcePolicyId,
  ) async {
    try {
      // 1. Obtener la póliza fuente para saber sus instanceIds y definitionIds
      final policyDoc =
          await _db.collection('policies').doc(sourcePolicyId).get();
      if (!policyDoc.exists) return {};

      final policyData = policyDoc.data()!;
      final devices = policyData['devices'] as List<dynamic>? ?? [];

      // 2. Construir lista de instanceIds y su mapping a (definitionId, unitIndex)
      final Map<String, _DeviceMapping> instanceToMapping = {};

      for (final devMap in devices) {
        final instanceId = devMap['instanceId'] as String? ?? '';
        final definitionId = devMap['definitionId'] as String? ?? '';
        final quantity = devMap['quantity'] as int? ?? 1;

        for (int i = 1; i <= quantity; i++) {
          final uid = _unitInstanceId(instanceId, i);
          instanceToMapping[uid] = _DeviceMapping(
            definitionId: definitionId,
            unitIndex: i,
          );
        }
      }

      if (instanceToMapping.isEmpty) return {};

      // 3. Buscar ubicaciones guardadas en device_locations
      final allInstanceIds = instanceToMapping.keys.toList();
      final locations = await _fetchLocations(sourcePolicyId, allInstanceIds);

      // 4. Si no hay ubicaciones en device_locations, intentar extraer del último reporte
      if (locations.isEmpty) {
        return await _extractFromLatestReport(
            sourcePolicyId, instanceToMapping);
      }

      // 5. Organizar por (definitionId, unitIndex)
      final Map<String, Map<int, LocationData>> result = {};

      for (final entry in locations.entries) {
        final mapping = instanceToMapping[entry.key];
        if (mapping == null) continue;

        final locData = entry.value;
        if (locData['customId']!.isEmpty && locData['area']!.isEmpty) continue;

        result.putIfAbsent(mapping.definitionId, () => {});
        result[mapping.definitionId]![mapping.unitIndex] = LocationData(
          customId: locData['customId'] ?? '',
          area: locData['area'] ?? '',
        );
      }

      return result;
    } catch (e) {
      debugPrint('Error extrayendo ubicaciones: $e');
      return {};
    }
  }

  /// Fallback: extrae ubicaciones del último reporte de la póliza fuente
  /// por si las ubicaciones se editaron en el reporte pero no se guardaron
  /// en device_locations (caso legacy).
  Future<Map<String, Map<int, LocationData>>> _extractFromLatestReport(
    String sourcePolicyId,
    Map<String, _DeviceMapping> instanceToMapping,
  ) async {
    try {
      final reportSnapshot = await _db
          .collection('reports')
          .where('policyId', isEqualTo: sourcePolicyId)
          .orderBy('serviceDate', descending: true)
          .limit(1)
          .get();

      if (reportSnapshot.docs.isEmpty) return {};

      final reportData = reportSnapshot.docs.first.data();
      final entries = reportData['entries'] as List<dynamic>? ?? [];

      final Map<String, Map<int, LocationData>> result = {};

      for (final entryMap in entries) {
        final instanceId = entryMap['instanceId'] as String? ?? '';
        final customId = entryMap['customId'] as String? ?? '';
        final area = entryMap['area'] as String? ?? '';

        if (customId.isEmpty && area.isEmpty) continue;

        final mapping = instanceToMapping[instanceId];
        if (mapping == null) continue;

        result.putIfAbsent(mapping.definitionId, () => {});
        result[mapping.definitionId]![mapping.unitIndex] = LocationData(
          customId: customId,
          area: area,
        );
      }

      return result;
    } catch (e) {
      debugPrint('Error extrayendo del reporte: $e');
      return {};
    }
  }

  /// Aplica ubicaciones importadas a los dispositivos de una nueva póliza.
  ///
  /// [importedLocations]: resultado de extractLocationsFromPolicy()
  /// [newPolicyId]: ID de la póliza nueva (para guardar en device_locations)
  /// [newDevices]: lista de PolicyDevice de la nueva póliza
  ///
  /// Retorna el número de ubicaciones aplicadas.
  Future<int> applyLocationsToNewPolicy({
    required Map<String, Map<int, LocationData>> importedLocations,
    required String newPolicyId,
    required List<dynamic> newDevices, // List<PolicyDevice>
  }) async {
    int appliedCount = 0;

    try {
      final batch = _db.batch();

      for (final devInstance in newDevices) {
        final definitionId = devInstance.definitionId as String;
        final instanceId = devInstance.instanceId as String;
        final quantity = devInstance.quantity as int;

        final defLocations = importedLocations[definitionId];
        if (defLocations == null) continue;

        for (int i = 1; i <= quantity; i++) {
          final locData = defLocations[i];
          if (locData == null) continue;
          if (locData.customId.isEmpty && locData.area.isEmpty) continue;

          final uid = _unitInstanceId(instanceId, i);
          final docId = '${newPolicyId}_$uid';

          batch.set(
            _db.collection('device_locations').doc(docId),
            {
              'policyId': newPolicyId,
              'instanceId': uid,
              'customId': locData.customId,
              'area': locData.area,
              'lastUpdated': FieldValue.serverTimestamp(),
              'importedFrom': 'previous_policy',
            },
            SetOptions(merge: true),
          );

          appliedCount++;
        }
      }

      if (appliedCount > 0) {
        await batch.commit();
      }

      debugPrint(
          '✅ Importadas $appliedCount ubicaciones a póliza $newPolicyId');
      return appliedCount;
    } catch (e) {
      debugPrint('Error aplicando ubicaciones: $e');
      return 0;
    }
  }

  /// Obtiene un preview de qué se va a importar (para mostrar en UI antes de confirmar)
  Future<List<LocationPreviewItem>> getImportPreview({
    required Map<String, Map<int, LocationData>> importedLocations,
    required List<dynamic> newDevices,
    required Map<String, String> definitionNames, // defId → nombre del dispositivo
  }) async {
    final List<LocationPreviewItem> preview = [];

    for (final devInstance in newDevices) {
      final definitionId = devInstance.definitionId as String;
      final quantity = devInstance.quantity as int;
      final deviceName = definitionNames[definitionId] ?? 'Desconocido';

      final defLocations = importedLocations[definitionId];
      if (defLocations == null) continue;

      for (int i = 1; i <= quantity; i++) {
        final locData = defLocations[i];
        if (locData == null) continue;
        if (locData.customId.isEmpty && locData.area.isEmpty) continue;

        preview.add(LocationPreviewItem(
          deviceName: deviceName,
          unitIndex: i,
          customId: locData.customId,
          area: locData.area,
        ));
      }
    }

    return preview;
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS PRIVADOS
  // ═══════════════════════════════════════════════════════

  Future<Map<String, Map<String, String>>> _fetchLocations(
    String policyId,
    List<String> instanceIds,
  ) async {
    final Map<String, Map<String, String>> result = {};
    final String docPrefix = '${policyId}_';

    // Firestore whereIn limit = 30
    final chunks = _chunkList(instanceIds, 30);

    for (final chunk in chunks) {
      final docIds = chunk.map((id) => '${policyId}_$id').toList();

      try {
        final snapshots = await _db
            .collection('device_locations')
            .where(FieldPath.documentId, whereIn: docIds)
            .get();

        for (final doc in snapshots.docs) {
          final data = doc.data();
          final instanceId = doc.id.startsWith(docPrefix)
              ? doc.id.substring(docPrefix.length)
              : doc.id;

          result[instanceId] = {
            'customId': data['customId']?.toString() ?? '',
            'area': data['area']?.toString() ?? '',
          };
        }
      } catch (e) {
        debugPrint('Error leyendo ubicaciones chunk: $e');
      }
    }

    return result;
  }

  static String _unitInstanceId(String baseInstanceId, int unitIndex) {
    if (unitIndex == 1) return baseInstanceId;
    return '${baseInstanceId}_$unitIndex';
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

// ═══════════════════════════════════════════════════════
// MODELOS DE DATOS INTERNOS
// ═══════════════════════════════════════════════════════

class _DeviceMapping {
  final String definitionId;
  final int unitIndex;
  _DeviceMapping({required this.definitionId, required this.unitIndex});
}

class LocationData {
  final String customId;
  final String area;
  LocationData({required this.customId, required this.area});
}

/// Para mostrar preview en la UI antes de confirmar la importación
class LocationPreviewItem {
  final String deviceName;
  final int unitIndex;
  final String customId;
  final String area;

  LocationPreviewItem({
    required this.deviceName,
    required this.unitIndex,
    required this.customId,
    required this.area,
  });
}