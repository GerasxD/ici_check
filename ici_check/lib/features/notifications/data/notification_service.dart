import 'package:flutter/foundation.dart';
import 'notifications_repository.dart';
import 'notification_model.dart';

// ==========================================
//  SERVICIO DE NOTIFICACIONES IN-APP
//  Maneja solo notificaciones de Firestore
//  (sin FCM push)
// ==========================================

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final NotificationsRepository _repo = NotificationsRepository();

  // ─── INICIALIZACIÓN SIMPLE ───
  // Solo valida que el usuario exista
  Future<void> initialize(String userId) async {
    debugPrint("✅ NotificationService inicializado para usuario: $userId");
    // Las notificaciones se manejan automáticamente vía StreamBuilder en la UI
  }

  // ─── Crear notificación para un usuario ───
  Future<void> createNotification({
    required String recipientUserId,
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic> data = const {},
  }) async {
    await _repo.createNotification(
      recipientUserId: recipientUserId,
      title: title,
      body: body,
      type: type,
      data: data,
    );
  }

  // ─── Crear notificaciones para múltiples usuarios ───
  Future<void> createBatchNotifications({
    required List<String> recipientUserIds,
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic> data = const {},
  }) async {
    await _repo.createBatchNotifications(
      recipientUserIds: recipientUserIds,
      title: title,
      body: body,
      type: type,
      data: data,
    );
  }

  // ─── Ejemplo: Notificar asignación de servicio ───
  Future<void> notifyServiceAssigned({
    required String technicianUserId,
    required String clientName,
    required String policyId,
    required String serviceDate,
  }) async {
    await createNotification(
      recipientUserId: technicianUserId,
      title: '🔧 Nuevo Servicio Asignado',
      body: 'Se te ha asignado un servicio para $clientName el $serviceDate',
      type: NotificationType.SERVICE_ASSIGNED,
      data: {
        'policyId': policyId,
        'clientName': clientName,
        'dateStr': serviceDate,
      },
    );
  }

  // ─── Ejemplo: Recordatorio de servicio ───
  Future<void> notifyServiceReminder({
    required String technicianUserId,
    required String clientName,
    required String policyId,
    required String serviceTime,
  }) async {
    await createNotification(
      recipientUserId: technicianUserId,
      title: '⏰ Recordatorio de Servicio',
      body: 'Tienes un servicio programado con $clientName a las $serviceTime',
      type: NotificationType.SERVICE_REMINDER,
      data: {
        'policyId': policyId,
        'clientName': clientName,
        'time': serviceTime,
      },
    );
  }

  // ─── Ejemplo: Reporte enviado ───
  Future<void> notifyReportSubmitted({
    required String adminUserId,
    required String technicianName,
    required String clientName,
    required String policyId,
  }) async {
    await createNotification(
      recipientUserId: adminUserId,
      title: '✅ Reporte Enviado',
      body: '$technicianName ha completado el servicio para $clientName',
      type: NotificationType.REPORT_SUBMITTED,
      data: {
        'policyId': policyId,
        'clientName': clientName,
        'technicianName': technicianName,
      },
    );
  }

  // ─── Ejemplo: Póliza por vencer ───
  Future<void> notifyPolicyExpiring({
    required String adminUserId,
    required String clientName,
    required String policyId,
    required int daysRemaining,
  }) async {
    await createNotification(
      recipientUserId: adminUserId,
      title: '⚠️ Póliza por Vencer',
      body: 'La póliza de $clientName vence en $daysRemaining días',
      type: NotificationType.POLICY_EXPIRING,
      data: {
        'policyId': policyId,
        'clientName': clientName,
        'daysRemaining': daysRemaining,
      },
    );
  }
}