import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/data/models/user_model.dart'; // Asegúrate de tener el modelo que creamos antes

class UsersRepository {
  final CollectionReference _usersCollection = 
      FirebaseFirestore.instance.collection('users');

  // 1. LEER (Stream): Escucha cambios en tiempo real
  Stream<List<UserModel>> getUsersStream() {
    return _usersCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // 2. GUARDAR (Crear o Actualizar)
  // Nota: Esto guarda los datos en la BD. Para crear el Login (Auth), 
  // idealmente se usa una Cloud Function, pero aquí manejamos la ficha del usuario.
  Future<void> saveUser(UserModel user) async {
    // Si el ID está vacío, Firestore genera uno automático
    if (user.id.isEmpty) {
      await _usersCollection.add(user.toMap());
    } else {
     await _usersCollection
        .doc(user.id) // Usamos SIEMPRE el ID (sea nuevo o viejo)
        .set(user.toMap(), SetOptions(merge: true));
    }
  }

  // 3. ELIMINAR
  Future<void> deleteUser(String id) async {
    await _usersCollection.doc(id).delete();
  }
}