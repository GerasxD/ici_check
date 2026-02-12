import 'package:cloud_firestore/cloud_firestore.dart';

// ==========================================
//  MODELO DE NOTIFICACIÓN
// ==========================================

enum NotificationType {
  SERVICE_ASSIGNED,   // Servicio asignado
  SERVICE_REMINDER,   // Recordatorio de servicio
  REPORT_SUBMITTED,   // Reporte enviado
  POLICY_EXPIRING,    // Póliza por vencer
  GENERAL,            // Notificación general
}

class NotificationModel {
  final String id;
  final String recipientUserId;
  final String title;
  final String body;
  final NotificationType type;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationModel({
    required this.id,
    required this.recipientUserId,
    required this.title,
    required this.body,
    required this.type,
    this.data = const {},
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  // Convertir desde Firestore
  factory NotificationModel.fromMap(Map<String, dynamic> map, String id) {
    return NotificationModel(
      id: id,
      recipientUserId: map['recipientUserId'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: _parseType(map['type']),
      data: Map<String, dynamic>.from(map['data'] ?? {}),
      isRead: map['isRead'] ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (map['readAt'] as Timestamp?)?.toDate(),
    );
  }

  // Convertir a Firestore
  Map<String, dynamic> toMap() {
    return {
      'recipientUserId': recipientUserId,
      'title': title,
      'body': body,
      'type': type.toString().split('.').last,
      'data': data,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
    };
  }

  static NotificationType _parseType(String? typeStr) {
    if (typeStr == null) return NotificationType.GENERAL;
    try {
      return NotificationType.values.firstWhere(
        (e) => e.toString().split('.').last == typeStr,
        orElse: () => NotificationType.GENERAL,
      );
    } catch (e) {
      return NotificationType.GENERAL;
    }
  }
}