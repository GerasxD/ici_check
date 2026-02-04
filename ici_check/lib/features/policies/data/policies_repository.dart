import 'package:cloud_firestore/cloud_firestore.dart';
import 'policy_model.dart';

class PoliciesRepository {
  final CollectionReference _collection = FirebaseFirestore.instance.collection('policies');

  Stream<List<PolicyModel>> getPoliciesStream() {
    return _collection.orderBy('startDate', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return PolicyModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  Future<void> savePolicy(PolicyModel policy) async {
    if (policy.id.isEmpty || policy.id == 'temp') {
      await _collection.add(policy.toMap());
    } else {
      await _collection.doc(policy.id).set(policy.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> deletePolicy(String id) async {
    await _collection.doc(id).delete();
  }
}