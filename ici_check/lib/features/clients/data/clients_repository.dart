import 'dart:typed_data'; // ← NUEVO
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'client_model.dart';

class ClientsRepository {
  final CollectionReference _collection = 
      FirebaseFirestore.instance.collection('clients');
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Stream de clientes
  Stream<List<ClientModel>> getClientsStream() {
    return _collection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return ClientModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  // ====== CORREGIDO: Subir logo usando Uint8List (funciona en todas las plataformas) ======
  Future<String> uploadClientLogo(String clientId, Uint8List imageBytes, String fileName) async {
    try {
      // Crear referencia única en Storage
      final String storagePath = 'client_logos/$clientId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final Reference ref = _storage.ref().child(storagePath);
      
      // Subir archivo usando putData (funciona en Web y móvil)
      final UploadTask uploadTask = ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'), // Especificar tipo MIME
      );
      
      final TaskSnapshot snapshot = await uploadTask;
      
      // Obtener URL de descarga
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Error al subir logo: $e');
    }
  }

  // Eliminar logo anterior de Storage
  Future<void> deleteClientLogo(String logoUrl) async {
    try {
      if (logoUrl.isNotEmpty && logoUrl.contains('firebase')) {
        final Reference ref = _storage.refFromURL(logoUrl);
        await ref.delete();
      }
    } catch (e) {
      print('No se pudo eliminar logo anterior: $e');
    }
  }

  // ====== CORREGIDO: Guardar con Uint8List ======
  Future<void> saveClient(ClientModel client, {Uint8List? newLogoBytes, String? fileName}) async {
    String logoUrl = client.logoUrl;

    // Si hay nueva imagen, la subimos
    if (newLogoBytes != null) {
      // Generar ID temporal si es cliente nuevo
      final String clientId = client.id.isEmpty || client.id == 'temp' 
          ? _collection.doc().id 
          : client.id;

      // Borrar logo anterior si existe
      if (client.logoUrl.isNotEmpty) {
        await deleteClientLogo(client.logoUrl);
      }

      // Subir nuevo logo
      logoUrl = await uploadClientLogo(clientId, newLogoBytes, fileName ?? 'logo.jpg');
      
      // Actualizar el modelo con la nueva URL
      client = ClientModel(
      id: clientId,
      name: client.name,
      razonSocial: client.razonSocial,       // ← AGREGAR
      nombreContacto: client.nombreContacto, // ← AGREGAR
      address: client.address,
      contact: client.contact,
      email: client.email,
      logoUrl: logoUrl,
    );
    }

    // Guardar en Firestore
    if (client.id.isEmpty || client.id == 'temp') {
      await _collection.add(client.toMap());
    } else {
      await _collection.doc(client.id).set(client.toMap(), SetOptions(merge: true));
    }
  }

  // Eliminar
  Future<void> deleteClient(String id) async {
    final doc = await _collection.doc(id).get();
    if (doc.exists) {
      final client = ClientModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      if (client.logoUrl.isNotEmpty) {
        await deleteClientLogo(client.logoUrl);
      }
    }
    
    await _collection.doc(id).delete();
  }
}