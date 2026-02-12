import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'notification_model.dart';

// ==========================================
//  REPOSITORIO DE NOTIFICACIONES
//  Maneja toda la lógica con Firestore
// ==========================================

class NotificationsRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Colección principal ───
  CollectionReference get _col => _db.collection('notifications');

  // ─── Stream en tiempo real para el usuario actual ───
  Stream<List<NotificationModel>> getNotificationsStream(String userId) {
    return _col
        .where('recipientUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50) // Últimas 50 notificaciones
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromMap(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                ))
            .toList());
  }

  // ─── Stream solo NO LEÍDAS (para el badge) ───
  Stream<int> getUnreadCountStream(String userId) {
    return _col
        .where('recipientUserId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ─── Crear una notificación para UN usuario ───
  Future<void> createNotification({
    required String recipientUserId,
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      await _col.add({
        'recipientUserId': recipientUserId,
        'title': title,
        'body': body,
        'type': type.toString().split('.').last,
        'data': data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
      });
      debugPrint("✅ Notificación creada para usuario: $recipientUserId");
    } catch (e) {
      debugPrint("❌ Error creando notificación: $e");
      rethrow;
    }
  }

  // ─── Crear notificaciones para MÚLTIPLES usuarios (batch) ───
  Future<void> createBatchNotifications({
    required List<String> recipientUserIds,
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic> data = const {},
  }) async {
    if (recipientUserIds.isEmpty) return;

    try {
      final batch = _db.batch();

      for (final userId in recipientUserIds) {
        final docRef = _col.doc(); // ID automático
        batch.set(docRef, {
          'recipientUserId': userId,
          'title': title,
          'body': body,
          'type': type.toString().split('.').last,
          'data': data,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'readAt': null,
        });
      }

      await batch.commit();
      debugPrint(
          "✅ ${recipientUserIds.length} notificaciones creadas exitosamente");
    } catch (e) {
      debugPrint("❌ Error en batch de notificaciones: $e");
      rethrow;
    }
  }

  // ─── Marcar una notificación como leída ───
  Future<void> markAsRead(String notificationId) async {
    try {
      await _col.doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("❌ Error marcando notificación como leída: $e");
    }
  }

  // ─── Marcar TODAS como leídas para un usuario ───
  Future<void> markAllAsRead(String userId) async {
    try {
      final snapshot = await _col
          .where('recipientUserId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      debugPrint("✅ Todas las notificaciones marcadas como leídas");
    } catch (e) {
      debugPrint("❌ Error marcando todas como leídas: $e");
    }
  }

  // ─── Eliminar una notificación ───
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _col.doc(notificationId).delete();
      debugPrint("✅ Notificación eliminada");
    } catch (e) {
      debugPrint("❌ Error eliminando notificación: $e");
    }
  }

  // ─── Eliminar notificaciones antiguas (opcional - limpieza) ───
  Future<void> deleteOldNotifications(String userId, {int daysOld = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final snapshot = await _col
          .where('recipientUserId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint("✅ ${snapshot.docs.length} notificaciones antiguas eliminadas");
    } catch (e) {
      debugPrint("❌ Error eliminando notificaciones antiguas: $e");
    }
  }
}