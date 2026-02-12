import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ici_check/features/notifications/data/notification_model.dart';
import 'package:ici_check/features/notifications/data/notifications_repository.dart';
import 'package:intl/intl.dart';

// ==========================================
//  MODAL DE NOTIFICACIONES (COMPACTO)
//  Se muestra como un diálogo pequeño
// ==========================================

/// Función helper para mostrar el modal de notificaciones
void showNotificationsModal(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const NotificationsModal(),
  );
}

class NotificationsModal extends StatefulWidget {
  const NotificationsModal({super.key});

  @override
  State<NotificationsModal> createState() => _NotificationsModalState();
}

class _NotificationsModalState extends State<NotificationsModal> {
  final NotificationsRepository _repo = NotificationsRepository();
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;

  // Paleta coherente con el resto de la app
  static const Color _primaryDark = Color(0xFF0F172A);
  static const Color _accentBlue = Color(0xFF1E40AF);
  static const Color _bgGrey = Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return AlertDialog(
        title: const Text("Error"),
        content: const Text("No estás autenticado"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
        ],
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width > 600 ? 
          MediaQuery.of(context).size.width * 0.3 : 20,
        vertical: 40,
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 450,
          maxHeight: 600,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryDark,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications_active,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Notificaciones",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  // Botón "Marcar todas como leídas"
                  StreamBuilder<List<NotificationModel>>(
                    stream: _repo.getNotificationsStream(_userId),
                    builder: (context, snapshot) {
                      final hasUnread =
                          snapshot.data?.any((n) => !n.isRead) ?? false;
                      if (!hasUnread) return const SizedBox.shrink();
                      return TextButton.icon(
                        onPressed: () => _repo.markAllAsRead(_userId),
                        icon: const Icon(Icons.done_all,
                            color: Colors.white70, size: 16),
                        label: const Text(
                          "Leer todo",
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // BODY
            Expanded(
              child: StreamBuilder<List<NotificationModel>>(
                stream: _repo.getNotificationsStream(_userId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _accentBlue),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 40),
                            const SizedBox(height: 12),
                            Text(
                              "Error al cargar notificaciones",
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final notifications = snapshot.data ?? [];

                  if (notifications.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final notif = notifications[index];
                      return _NotificationCard(
                        notification: notif,
                        onTap: () => _handleNotificationTap(notif),
                        onDismiss: () => _repo.deleteNotification(notif.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleNotificationTap(NotificationModel notif) {
    // Marcar como leída
    if (!notif.isRead) {
      _repo.markAsRead(notif.id);
    }

    // Cerrar modal
    Navigator.pop(context);

    // Navegar según tipo (puedes expandir esta lógica)
    if (notif.data['policyId'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Abriendo póliza: ${notif.data['policyId']}"),
          backgroundColor: _accentBlue,
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () {
              // TODO: Navegar a la pantalla de la póliza
              // Navigator.push(context, MaterialPageRoute(...));
            },
          ),
        ),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _bgGrey,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_outlined,
                size: 48,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Sin notificaciones",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Aquí aparecerán tus asignaciones\ny recordatorios de servicios",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── TARJETA DE NOTIFICACIÓN (COMPACTA) ───
class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: notification.isRead
                  ? Colors.white
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: notification.isRead
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF93C5FD),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ícono del tipo
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getTypeColor(notification.type).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getTypeIcon(notification.type),
                    color: _getTypeColor(notification.type),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                // Contenido
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: notification.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          // Badge "NUEVO"
                          if (!notification.isRead)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E40AF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                "NUEVO",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 7,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Tiempo transcurrido y cliente
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 10,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(notification.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          // Chip extra de datos
                          if (notification.data['clientName'] != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF64748B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                notification.data['clientName'],
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(NotificationType type) {
    switch (type) {
      case NotificationType.SERVICE_ASSIGNED:
        return const Color(0xFF1E40AF); // Azul
      case NotificationType.SERVICE_REMINDER:
        return const Color(0xFFF59E0B); // Amarillo
      case NotificationType.REPORT_SUBMITTED:
        return const Color(0xFF10B981); // Verde
      case NotificationType.POLICY_EXPIRING:
        return const Color(0xFFEF4444); // Rojo
      case NotificationType.GENERAL:
        return const Color(0xFF64748B); // Gris
    }
  }

  IconData _getTypeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.SERVICE_ASSIGNED:
        return Icons.assignment_ind_outlined;
      case NotificationType.SERVICE_REMINDER:
        return Icons.alarm_outlined;
      case NotificationType.REPORT_SUBMITTED:
        return Icons.task_alt_outlined;
      case NotificationType.POLICY_EXPIRING:
        return Icons.warning_amber_outlined;
      case NotificationType.GENERAL:
        return Icons.notifications_outlined;
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return "Ahora";
    if (diff.inMinutes < 60) return "Hace ${diff.inMinutes}m";
    if (diff.inHours < 24) return "Hace ${diff.inHours}h";
    if (diff.inDays < 7) return "Hace ${diff.inDays}d";
    return DateFormat('dd MMM', 'es').format(dateTime);
  }
}

// ==========================================
//  WIDGET: BADGE DE NOTIFICACIONES
//  Úsalo en el menú/appbar para mostrar el contador
// ==========================================

class NotificationBadge extends StatelessWidget {
  final String userId;
  final Widget child;
  final VoidCallback? onTap;

  const NotificationBadge({
    super.key,
    required this.userId,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final repo = NotificationsRepository();

    return StreamBuilder<int>(
      stream: repo.getUnreadCountStream(userId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: const Color(0xFF0F172A), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Text(
                      count > 99 ? "99+" : count.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}