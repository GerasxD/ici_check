import 'package:cloud_firestore/cloud_firestore.dart';
import 'device_model.dart';

class DevicesRepository {
  final CollectionReference _collection = 
      FirebaseFirestore.instance.collection('devices');

  // Stream en tiempo real
  Stream<List<DeviceModel>> getDevicesStream() {
    return _collection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return DeviceModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // Guardar (Crear o Editar)
  Future<void> saveDevice(DeviceModel device) async {
    // Si es nuevo (id temporal o vacío), dejamos que Firestore genere ID
    if (device.id.isEmpty || device.id == 'temp') {
      await _collection.add(device.toMap());
    } else {
      await _collection.doc(device.id).set(device.toMap(), SetOptions(merge: true));
    }
  }

  // Eliminar
  Future<void> deleteDevice(String id) async {
    await _collection.doc(id).delete();
  }
}