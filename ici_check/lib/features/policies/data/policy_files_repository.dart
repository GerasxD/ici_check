import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'policy_file_model.dart';

class PolicyFilesRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Referencia a la subcolección de archivos de una póliza
  CollectionReference _filesCollection(String policyId) {
    return _db.collection('policies').doc(policyId).collection('files');
  }

  /// Stream de todos los archivos de una póliza
  Stream<List<PolicyFileModel>> getFilesStream(String policyId) {
    return _filesCollection(policyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                PolicyFileModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  /// Obtiene las carpetas únicas que existen
  Future<List<String>> getFolders(String policyId) async {
    final snapshot = await _filesCollection(policyId).get();
    final folders = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final folder = data['folder'] as String? ?? '';
      if (folder.isNotEmpty) folders.add(folder);
    }
    final sorted = folders.toList()..sort();
    return sorted;
  }

  /// Sube un archivo a Storage y guarda el registro en Firestore
  Future<PolicyFileModel> uploadFile({
    required String policyId,
    required String fileName,
    required Uint8List fileBytes,
    required String contentType,
    String folder = '',
    String uploadedBy = '',
    String uploadedByName = '',
  }) async {
    try {
      // 1. Subir a Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final storagePath = 'policies/$policyId/files/${timestamp}_$safeName';

      final ref = _storage.ref().child(storagePath);
      final metadata = SettableMetadata(contentType: contentType);
      await ref.putData(fileBytes, metadata);

      final downloadUrl = await ref.getDownloadURL();

      // 2. Guardar registro en Firestore
      final fileModel = PolicyFileModel(
        id: '',
        name: fileName,
        url: downloadUrl,
        folder: folder,
        contentType: contentType,
        sizeBytes: fileBytes.length,
        uploadedBy: uploadedBy,
        uploadedByName: uploadedByName,
      );

      final docRef = await _filesCollection(policyId).add(fileModel.toMap());
      fileModel.id = docRef.id;

      return fileModel;
    } catch (e) {
      debugPrint('Error subiendo archivo: $e');
      rethrow;
    }
  }

  /// Mover archivo a otra carpeta
  Future<void> moveToFolder({
    required String policyId,
    required String fileId,
    required String newFolder,
  }) async {
    await _filesCollection(policyId).doc(fileId).update({'folder': newFolder});
  }

  /// Renombrar archivo
  Future<void> renameFile({
    required String policyId,
    required String fileId,
    required String newName,
  }) async {
    await _filesCollection(policyId).doc(fileId).update({'name': newName});
  }

  /// Eliminar archivo (Storage + Firestore)
  Future<void> deleteFile({
    required String policyId,
    required String fileId,
    required String fileUrl,
  }) async {
    try {
      // Eliminar de Storage
      final ref = _storage.refFromURL(fileUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('Error eliminando de Storage (puede que ya no exista): $e');
    }

    // Eliminar de Firestore
    await _filesCollection(policyId).doc(fileId).delete();
  }

  /// Referencia a la subcolección de carpetas de una póliza
  CollectionReference _foldersCollection(String policyId) {
    return _db.collection('policies').doc(policyId).collection('folders');
  }

  /// Stream de carpetas
  Stream<List<String>> getFoldersStream(String policyId) {
    return _foldersCollection(policyId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => doc['name'] as String)
            .toList());
  }

  /// Crear carpeta
  Future<void> createFolder({
    required String policyId,
    required String folderName,
  }) async {
    // Verificar que no exista ya
    final existing = await _foldersCollection(policyId)
        .where('name', isEqualTo: folderName)
        .get();
    if (existing.docs.isNotEmpty) return;

    await _foldersCollection(policyId).add({
      'name': folderName,
      'createdAt': Timestamp.now(),
    });
  }

  /// Eliminar carpeta (solo si está vacía)
  Future<bool> deleteFolder({
    required String policyId,
    required String folderName,
  }) async {
    // Verificar que no tenga archivos
    final filesInFolder = await _filesCollection(policyId)
        .where('folder', isEqualTo: folderName)
        .limit(1)
        .get();
    if (filesInFolder.docs.isNotEmpty) return false;

    final folderDocs = await _foldersCollection(policyId)
        .where('name', isEqualTo: folderName)
        .get();
    for (final doc in folderDocs.docs) {
      await doc.reference.delete();
    }
    return true;
  }

  /// Renombrar carpeta (actualiza la carpeta Y todos los archivos que la usan)
  Future<void> renameFolder({
    required String policyId,
    required String oldName,
    required String newName,
  }) async {
    // Renombrar el registro de la carpeta
    final folderDocs = await _foldersCollection(policyId)
        .where('name', isEqualTo: oldName)
        .get();
    for (final doc in folderDocs.docs) {
      await doc.reference.update({'name': newName});
    }

    // Actualizar todos los archivos que estaban en esa carpeta
    final filesInFolder = await _filesCollection(policyId)
        .where('folder', isEqualTo: oldName)
        .get();
    for (final doc in filesInFolder.docs) {
      await doc.reference.update({'folder': newName});
    }
  } 
}