import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Servicio profesional para manejo de fotos con Firebase Storage
/// - Compresión automática
/// - Caché local
/// - Manejo de errores robusto
class PhotoStorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const int _maxImageWidth = 1200;
  static const int _compressionQuality = 85;
  static const Duration _cacheExpiration = Duration(days: 7);

  /// Sube una foto desde un archivo XFile y retorna la URL de descarga
  /// 
  /// [photoBytes] - Bytes de la imagen original
  /// [reportId] - ID del reporte para organizar en carpetas
  /// [deviceInstanceId] - ID del dispositivo
  /// [activityId] - (Opcional) ID de la actividad específica
  /// 
  /// Returns: URL de descarga de Firebase Storage
  Future<String> uploadPhoto({
    required Uint8List photoBytes,
    required String reportId,
    required String deviceInstanceId,
    String? activityId,
  }) async {
    try {
      // 1. Comprimir imagen antes de subir
      final compressedBytes = await _compressImage(photoBytes);
      
      // 2. Generar nombre único usando hash + timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final hash = sha256.convert(compressedBytes).toString().substring(0, 8);
      final filename = '${timestamp}_$hash.jpg';
      
      // 3. Construir path organizado en Storage
      // Estructura: reports/{reportId}/devices/{deviceInstanceId}/[activities/{activityId}/]{filename}
      String storagePath = 'reports/$reportId/devices/$deviceInstanceId';
      if (activityId != null) {
        storagePath += '/activities/$activityId';
      }
      storagePath += '/$filename';
      
      // 4. Subir a Firebase Storage
      final ref = _storage.ref().child(storagePath);
      final uploadTask = await ref.putData(
        compressedBytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'reportId': reportId,
            'deviceInstanceId': deviceInstanceId,
            if (activityId != null) 'activityId': activityId,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
      
      // 5. Obtener URL de descarga
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      
      // 6. Guardar en caché local
      await _saveToCacheMetadata(downloadUrl, filename);
      
      debugPrint('✅ Foto subida exitosamente: $filename (${compressedBytes.length} bytes)');
      return downloadUrl;
      
    } catch (e) {
      debugPrint('❌ Error subiendo foto: $e');
      rethrow;
    }
  }

  /// Comprime una imagen para reducir su tamaño sin perder calidad perceptible
  Future<Uint8List> _compressImage(Uint8List imageBytes) async {
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: _maxImageWidth,
        quality: _compressionQuality,
        format: CompressFormat.jpeg,
      );
      
      final originalSize = imageBytes.length / 1024; // KB
      final compressedSize = compressed.length / 1024; // KB
      final reduction = ((1 - (compressedSize / originalSize)) * 100).toStringAsFixed(1);
      
      debugPrint('📦 Compresión: ${originalSize.toStringAsFixed(1)}KB → ${compressedSize.toStringAsFixed(1)}KB ($reduction% reducción)');
      
      return compressed;
    } catch (e) {
      debugPrint('⚠️ Error en compresión, usando imagen original: $e');
      return imageBytes;
    }
  }

  /// Elimina una foto de Firebase Storage
  Future<void> deletePhoto(String downloadUrl) async {
    try {
      // Extraer path del storage desde la URL
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
      
      // Limpiar caché local
      await _removeFromCache(downloadUrl);
      
      debugPrint('🗑️ Foto eliminada: ${ref.fullPath}');
    } catch (e) {
      debugPrint('❌ Error eliminando foto: $e');
      // No lanzamos error aquí para no interrumpir el flujo si la foto ya fue eliminada
    }
  }

  /// Elimina todas las fotos de un reporte (útil al eliminar un reporte completo)
  Future<void> deleteReportPhotos(String reportId) async {
    try {
      final reportsRef = _storage.ref().child('reports/$reportId');
      final ListResult result = await reportsRef.listAll();
      
      // Eliminar todos los archivos recursivamente
      for (var item in result.items) {
        await item.delete();
      }
      
      // Eliminar subcarpetas vacías
      for (var prefix in result.prefixes) {
        await _deleteFolder(prefix);
      }
      
      debugPrint('🗑️ Todas las fotos del reporte $reportId eliminadas');
    } catch (e) {
      debugPrint('❌ Error eliminando fotos del reporte: $e');
    }
  }

  /// Elimina recursivamente una carpeta en Storage
  Future<void> _deleteFolder(Reference folderRef) async {
    try {
      final ListResult result = await folderRef.listAll();
      
      for (var item in result.items) {
        await item.delete();
      }
      
      for (var prefix in result.prefixes) {
        await _deleteFolder(prefix);
      }
    } catch (e) {
      debugPrint('Error eliminando carpeta ${folderRef.fullPath}: $e');
    }
  }

  /// Obtiene bytes de la imagen desde URL con caché automático
  Future<Uint8List?> getPhotoBytes(String downloadUrl) async {
    try {
      // 1. Intentar cargar desde caché local primero
      final cachedBytes = await _loadFromCache(downloadUrl);
      if (cachedBytes != null) {
        debugPrint('📦 Foto cargada desde caché');
        return cachedBytes;
      }
      
      // 2. Descargar desde Firebase Storage
      final ref = _storage.refFromURL(downloadUrl);
      final bytes = await ref.getData();
      
      if (bytes != null) {
        // 3. Guardar en caché para futuras cargas
        await _saveToCache(downloadUrl, bytes);
        debugPrint('📥 Foto descargada y cacheada');
      }
      
      return bytes;
      
    } catch (e) {
      debugPrint('❌ Error obteniendo foto: $e');
      return null;
    }
  }

  /// Limpia caché expirado (llamar periódicamente, ej. al iniciar app)
  Future<void> cleanExpiredCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) return;
      
      final now = DateTime.now();
      int deletedFiles = 0;
      
      await for (var entity in cacheDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);
          
          if (age > _cacheExpiration) {
            await entity.delete();
            deletedFiles++;
          }
        }
      }
      
      if (deletedFiles > 0) {
        debugPrint('🧹 Caché limpiado: $deletedFiles archivos eliminados');
      }
      
    } catch (e) {
      debugPrint('Error limpiando caché: $e');
    }
  }

  /// Obtiene el directorio de caché de la app
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/photo_cache');
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    return cacheDir;
  }

  /// Guarda imagen en caché local
  Future<void> _saveToCache(String url, Uint8List bytes) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final filename = _urlToFilename(url);
      final file = File('${cacheDir.path}/$filename');
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint('Error guardando en caché: $e');
    }
  }

  /// Guarda metadata de caché
  Future<void> _saveToCacheMetadata(String url, String originalFilename) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final metaFile = File('${cacheDir.path}/.metadata');
      
      Map<String, dynamic> metadata = {};
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        metadata = jsonDecode(content);
      }
      
      metadata[url] = {
        'filename': originalFilename,
        'cachedAt': DateTime.now().toIso8601String(),
      };
      
      await metaFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      debugPrint('Error guardando metadata: $e');
    }
  }

  /// Carga imagen desde caché local
  Future<Uint8List?> _loadFromCache(String url) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final filename = _urlToFilename(url);
      final file = File('${cacheDir.path}/$filename');
      
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('Error cargando desde caché: $e');
    }
    return null;
  }

  /// Elimina archivo de caché
  Future<void> _removeFromCache(String url) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final filename = _urlToFilename(url);
      final file = File('${cacheDir.path}/$filename');
      
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error eliminando de caché: $e');
    }
  }

  /// Convierte URL a nombre de archivo seguro para caché
  String _urlToFilename(String url) {
    return sha256.convert(utf8.encode(url)).toString();
  }

  /// Obtiene tamaño total del caché
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) return 0;
      
      int totalSize = 0;
      await for (var entity in cacheDir.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      debugPrint('Error calculando tamaño de caché: $e');
      return 0;
    }
  }

  /// Limpia todo el caché (útil para configuración de usuario)
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        debugPrint('🧹 Caché completamente limpiado');
      }
    } catch (e) {
      debugPrint('Error limpiando caché: $e');
    }
  }
}