import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'policy_model.dart';

class PoliciesRepository {
  final CollectionReference _collection =
      FirebaseFirestore.instance.collection('policies');

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

  Future<void> savePolicy(PolicyModel policy) async {
    try {
      final data = policy.toMap();
      if (policy.id.isEmpty || policy.id == 'temp') {
        // Crear nuevo dejando que Firestore genere el ID
        await _collection.add(data);
      } else {
        // set con merge: crea si no existe, actualiza si existe
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