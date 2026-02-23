import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'policy_model.dart';

class PoliciesRepository {
  final CollectionReference _collection =
      FirebaseFirestore.instance.collection('policies');

  // ══════════════════════════════════════════════════════════════════════
  // STREAMS
  // ══════════════════════════════════════════════════════════════════════

  /// Escucha toda la colección de pólizas (útil para listados generales)
  Stream<List<PolicyModel>> getPoliciesStream() {
    return _collection
        .orderBy('startDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return PolicyModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  /// Escucha los cambios en TIEMPO REAL de una SOLA póliza por su ID
  /// Retorna null si el documento no existe o fue eliminado.
  Stream<PolicyModel?> getPolicyStream(String id) {
    return _collection.doc(id).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return PolicyModel.fromMap(
          snapshot.data() as Map<String, dynamic>,
          snapshot.id,
        );
      }
      return null;
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // MUTACIONES
  // ══════════════════════════════════════════════════════════════════════

  Future<void> savePolicy(PolicyModel policy) async {
    try {
      final data = policy.toMap();
      if (policy.id.isEmpty || policy.id == 'temp') {
        // Crear nuevo dejando que Firestore genere el ID
        await _collection.add(data);
      } else {
        // set con merge: false sobrescribe el documento completo
        await _collection.doc(policy.id).set(data, SetOptions(merge: false));
      }
    } catch (e) {
      debugPrint('Error en savePolicy: $e');
      rethrow;
    }
  }

  Future<void> deletePolicy(String id) async {
    await _collection.doc(id).delete();
  }
}