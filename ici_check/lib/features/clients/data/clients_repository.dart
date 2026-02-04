import 'package:cloud_firestore/cloud_firestore.dart';
import 'client_model.dart';

class ClientsRepository {
  final CollectionReference _collection = 
      FirebaseFirestore.instance.collection('clients');

  // Stream de clientes
  Stream<List<ClientModel>> getClientsStream() {
    return _collection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return ClientModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // Guardar (Crear o Actualizar)
  Future<void> saveClient(ClientModel client) async {
    if (client.id.isEmpty || client.id == 'temp') {
      await _collection.add(client.toMap());
    } else {
      await _collection.doc(client.id).set(client.toMap(), SetOptions(merge: true));
    }
  }

  // Eliminar
  Future<void> deleteClient(String id) async {
    await _collection.doc(id).delete();
  }
}