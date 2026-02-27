// lib/features/reports/widgets/report_controls.dart
//
// ═══════════════════════════════════════════════════════════════════════
// ReportControls — Lógica original + Historial de Sesiones Multi-Día
//
// LÓGICA DE BOTONES (IDÉNTICA AL ORIGINAL):
//   isNotStarted                            → INICIAR SERVICIO (verde)
//   isInProgress (start!=null, end==null)   → FINALIZAR SERVICIO (rojo)
//   isFinished + !isFullyComplete           → REANUDAR (PENDIENTES) (naranja)
//     ↳ isFullyComplete = false si hay actividades null o 'NR'
//     ↳ onResumeService → resumeService() → nueva sesión + forceNullEndTime
//   isFinished + isFullyComplete            → SERVICIO COMPLETADO (gris)
//
// NUEVA FUNCIONALIDAD (AGREGADA, no reemplaza nada):
//   - Panel "HISTORIAL DE SESIONES" expandible debajo de fecha/horario
//   - Cada sesión: fecha inteligente (Hoy/Ayer/fecha), inicio→fin, duración
//   - Sesión activa: badge verde "En curso"
//   - Pie del panel: tiempo total acumulado
//   - Admin: editar horas por sesión, eliminar sesiones con confirmación
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/state/report_providers.dart';
import 'package:ici_check/features/reports/state/report_state.dart';

// ═══════════════════════════════════════════════════════════════════════
// WIDGET PRINCIPAL
// Necesita ConsumerStatefulWidget (en lugar del ConsumerWidget original)
// únicamente para la animación del panel de historial.
// La lógica de negocio es idéntica al original.
// ═══════════════════════════════════════════════════════════════════════
class ReportControls extends ConsumerStatefulWidget {
  final List<UserModel> users;
  final bool adminOverride;
  final bool isUserDesignated;
  final String? currentUserId;
  final VoidCallback onStartService;
  final VoidCallback onEndService;
  final VoidCallback onResumeService;

  const ReportControls({
    super.key,
    required this.users,
    required this.adminOverride,
    required this.isUserDesignated,
    this.currentUserId,
    required this.onStartService,
    required this.onEndService,
    required this.onResumeService,
  });

  @override
  ConsumerState<ReportControls> createState() => _ReportControlsState();
}

class _ReportControlsState extends ConsumerState<ReportControls>
    with SingleTickerProviderStateMixin {
  // ── Estado local solo para la animación del historial ──
  bool _historyExpanded = false;
  bool _autoExpandedOnce = false; // evita re-expandir en cada rebuild
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleHistory() {
    setState(() => _historyExpanded = !_historyExpanded);
    _historyExpanded ? _animController.forward() : _animController.reverse();
  }

  Future<void> _pickTime(
    BuildContext context,
    String? currentTime,
    Function(String) onPicked,
  ) async {
    TimeOfDay initialTime = TimeOfDay.now();

    if (currentTime != null && currentTime.contains(':')) {
      try {
        final parts = currentTime.split(':');
        initialTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      } catch (_) {}
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (picked != null) {
      final hour = picked.hour.toString().padLeft(2, '0');
      final minute = picked.minute.toString().padLeft(2, '0');
      onPicked('$hour:$minute');
    }
  }

  @override
  Widget build(BuildContext context) {
    // ★ IGUAL AL ORIGINAL: Solo escucha ReportMeta.
    // Cambios en observaciones, customId, area, fotos → NO rebuild aquí.
    // isFullyComplete ya viene PRE-COMPUTADO en ReportState → O(1).
    final meta = ref.watch(reportMetaProvider);

    // ★ NUEVO: Provider selectivo para sesiones.
    // Solo rebuild cuando cambia la lista de sesiones.
    final sessions = ref.watch(reportSessionsProvider);

    if (meta == null) return const SizedBox.shrink();

    final notifier = ref.read(reportNotifierProvider.notifier);

    // Auto-expandir historial la primera vez que hay más de 1 sesión
    if (sessions.length > 1 && !_autoExpandedOnce) {
      _autoExpandedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_historyExpanded) _toggleHistory();
      });
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // ─── 1. ZONA DE ESTADO Y PERSONAL (SUPERIOR) ───
          // (idéntico al original)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.engineering, size: 16, color: Color(0xFF64748B)),
                    SizedBox(width: 8),
                    Text(
                      'EQUIPO TÉCNICO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: meta.assignedTechnicianIds.isEmpty
                        ? [
                            const Text(
                              'Sin asignar',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13),
                            )
                          ]
                        : meta.assignedTechnicianIds.map((uid) {
                            final user = widget.users.firstWhere(
                              (u) => u.id == uid,
                              orElse: () =>
                                  UserModel(id: uid, name: 'Usuario', email: ''),
                            );
                            return _buildUserBadge(user);
                          }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // ─── 2. ZONA DE ACCIÓN Y TIEMPOS (INFERIOR) ───
          // (mismo layout que el original + panel de sesiones insertado)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // ── Fila Fecha / Horario (igual al original) ──
                Row(
                  children: [
                    // Columna FECHA
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: widget.adminOverride
                            ? () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: meta.serviceDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  notifier.updateServiceDate(picked);
                                }
                              }
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: widget.adminOverride
                                  ? const Color(0xFFCBD5E1)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'FECHA',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  if (widget.adminOverride)
                                    const Icon(Icons.edit,
                                        size: 10, color: Color(0xFF94A3B8)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_month,
                                      size: 16, color: Color(0xFF334155)),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('dd MMM yyyy', 'es')
                                        .format(meta.serviceDate)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Columna HORARIOS
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.adminOverride
                                ? const Color(0xFFCBD5E1)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'HORARIO',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                if (widget.adminOverride)
                                  const Icon(Icons.edit,
                                      size: 10, color: Color(0xFF94A3B8)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                // HORA INICIO
                                InkWell(
                                  onTap: widget.adminOverride
                                      ? () => _pickTime(
                                            context,
                                            meta.startTime,
                                            (time) =>
                                                notifier.updateStartTime(time),
                                          )
                                      : null,
                                  child: Text(
                                    meta.startTime ?? '--:--',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF334155),
                                      decoration: (widget.adminOverride &&
                                              meta.startTime != null)
                                          ? TextDecoration.underline
                                          : null,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.arrow_right_alt,
                                      size: 12, color: Color(0xFF94A3B8)),
                                ),
                                // HORA FIN
                                InkWell(
                                  onTap: widget.adminOverride
                                      ? () => _pickTime(
                                            context,
                                            meta.endTime,
                                            (time) =>
                                                notifier.updateEndTime(time),
                                          )
                                      : null,
                                  child: Text(
                                    meta.endTime ?? '--:--',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: meta.endTime != null
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFCBD5E1),
                                      decoration: (widget.adminOverride &&
                                              meta.endTime != null)
                                          ? TextDecoration.underline
                                          : null,
                                      decorationStyle:
                                          TextDecorationStyle.dotted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ── NUEVO: Panel de historial de sesiones ──
                // Solo aparece si hay al menos 1 sesión registrada.
                // No interfiere con la lógica original de botones.
                if (sessions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSessionsPanel(sessions, notifier),
                ],

                const SizedBox(height: 20),

                // ── BOTÓN DE ACCIÓN PRINCIPAL ──
                // ★ LÓGICA 100% IDÉNTICA AL ORIGINAL:
                //   isNotStarted           → INICIAR SERVICIO (verde)
                //   isInProgress           → FINALIZAR SERVICIO (rojo)
                //   isFinished+!isComplete → REANUDAR (PENDIENTES) (naranja)
                //   isFinished+isComplete  → SERVICIO COMPLETADO (gris)
                if (widget.isUserDesignated)
                  SizedBox(
                    width: double.infinity,
                    child: _buildActionButton(meta),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // BOTÓN DE ACCIÓN — IDÉNTICO AL ORIGINAL
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildActionButton(ReportMeta meta) {
    if (meta.isNotStarted) {
      // 1. ESTADO: INICIAL → Botón Verde
      return ElevatedButton(
        onPressed: widget.onStartService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_fill, size: 20),
            SizedBox(width: 8),
            Text(
              'INICIAR SERVICIO',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    } else if (meta.isInProgress) {
      // 2. ESTADO: EN PROGRESO → Botón Rojo
      return ElevatedButton(
        onPressed: widget.onEndService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stop_circle, size: 20),
            SizedBox(width: 8),
            Text(
              'FINALIZAR SERVICIO',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    } else {
      // 3. ESTADO: FINALIZADO (startTime != null && endTime != null)
      if (!meta.isFullyComplete) {
        // CASO A: Hay actividades en null o 'NR' → permite reanudar
        //
        // ★ CLAVE: onResumeService llama a resumeService() en el notifier,
        //   que hace: nueva ServiceSession + forceNullEndTime: true
        //   → meta.isInProgress = true → _isEditable() vuelve a ser true
        //   → el técnico puede seguir respondiendo actividades
        return ElevatedButton(
          onPressed: widget.onResumeService,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 20),
              SizedBox(width: 8),
              Text(
                'REANUDAR (PENDIENTES)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      } else {
        // CASO B: Todas las actividades OK/NOK/NA → completado
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 20, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                'SERVICIO COMPLETADO',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // PANEL DE HISTORIAL DE SESIONES (NUEVO)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildSessionsPanel(
      List<ServiceSession> sessions, ReportNotifier notifier) {
    final openSession = sessions.where((s) => s.isOpen).lastOrNull;
    final closedSessions = sessions.where((s) => !s.isOpen).toList();
    final totalDays = sessions
        .map((s) => DateFormat('yyyy-MM-dd').format(s.date))
        .toSet()
        .length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // ── Header (toca para expandir/colapsar) ──
          InkWell(
            onTap: _toggleHistory,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom:
                  _historyExpanded ? Radius.zero : const Radius.circular(12),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: _historyExpanded
                      ? Radius.zero
                      : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  // Icono
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.history_rounded,
                        size: 14, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(width: 10),

                  // Texto resumen
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HISTORIAL DE SESIONES',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '$totalDays ${totalDays == 1 ? 'día' : 'días'} · '
                          '${sessions.length} '
                          '${sessions.length == 1 ? 'sesión' : 'sesiones'}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Badge "ACTIVA" si hay sesión abierta
                  if (openSession != null)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                const Color(0xFF10B981).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'ACTIVA',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10B981),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Chevron animado
                  AnimatedRotation(
                    turns: _historyExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(Icons.expand_more_rounded,
                        size: 20, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),

          // ── Lista de sesiones (expandible con animación) ──
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Column(
                children: [
                  // Sesión activa primero
                  if (openSession != null)
                    _SessionTile(
                      key: ValueKey('open_${openSession.id}'),
                      session: openSession,
                      sessionNumber: sessions.indexOf(openSession) + 1,
                      isActive: true,
                      adminOverride: widget.adminOverride,
                      onEditStart: (t) => notifier.updateSession(
                          openSession.id,
                          startTime: t,
                          endTime: openSession.endTime),
                      onEditEnd: (t) => notifier.updateSession(
                          openSession.id,
                          startTime: openSession.startTime,
                          endTime: t),
                      onDelete: () =>
                          notifier.deleteSession(openSession.id),
                      onPickTime: _pickTime,
                    ),

                  // Sesiones cerradas, más reciente primero
                  ...closedSessions.reversed.map((session) {
                    final num = sessions.indexOf(session) + 1;
                    return _SessionTile(
                      key: ValueKey('closed_${session.id}'),
                      session: session,
                      sessionNumber: num,
                      isActive: false,
                      adminOverride: widget.adminOverride,
                      onEditStart: (t) => notifier.updateSession(session.id,
                          startTime: t, endTime: session.endTime),
                      onEditEnd: (t) => notifier.updateSession(session.id,
                          startTime: session.startTime, endTime: t),
                      onDelete: () => notifier.deleteSession(session.id),
                      onPickTime: _pickTime,
                    );
                  }),

                  // Botón agregar sesión (solo admin)
                  if (widget.adminOverride)
                    InkWell(
                      onTap: () => _showAddSessionDialog(context, notifier),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.add_rounded, size: 14, color: Color(0xFF3B82F6)),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'AGREGAR SESIÓN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF3B82F6),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Pie: tiempo total
                  _TotalTimeSummary(sessions: sessions),

                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // DIÁLOGO PARA AGREGAR SESIÓN MANUAL (Admin)
  // ═══════════════════════════════════════════════════════════════════
  void _showAddSessionDialog(BuildContext context, ReportNotifier notifier) {
    DateTime selectedDate = DateTime.now();
    String? startTime;
    String? endTime;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: Color(0xFF3B82F6), size: 22),
                  SizedBox(width: 10),
                  Text('Agregar Sesión', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FECHA
                  const Text(
                    'FECHA',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 16, color: Color(0xFF334155)),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd MMM yyyy', 'es').format(selectedDate).toUpperCase(),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit, size: 12, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // HORARIOS
                  Row(
                    children: [
                      // HORA INICIO
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'INICIO',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _pickTime(context, startTime, (t) {
                                setModalState(() => startTime = t);
                              }),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: startTime != null ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.play_circle_outline,
                                      size: 16,
                                      color: startTime != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      startTime ?? '--:--',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: startTime != null ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Icon(Icons.arrow_right_alt_rounded, size: 18, color: Color(0xFFCBD5E1)),
                        ),
                      ),

                      // HORA FIN
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FIN',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _pickTime(context, endTime, (t) {
                                setModalState(() => endTime = t);
                              }),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: endTime != null ? const Color(0xFFEF4444) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.stop_circle_outlined,
                                      size: 16,
                                      color: endTime != null ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      endTime ?? '--:--',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: endTime != null ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Duración calculada
                  if (startTime != null && endTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Duración: ${_calcDurationFromTimes(startTime!, endTime!)}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton.icon(
                  onPressed: (startTime != null && endTime != null)
                      ? () {
                          Navigator.pop(ctx);
                          notifier.addManualSession(
                            date: selectedDate,
                            startTime: startTime!,
                            endTime: endTime!,
                          );
                        }
                      : null,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _calcDurationFromTimes(String start, String end) {
    try {
      final sp = start.split(':');
      final ep = end.split(':');
      final s = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final e = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final diff = e - s;
      if (diff <= 0) return 'Inválido';
      final h = diff ~/ 60;
      final m = diff % 60;
      return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
    } catch (_) {
      return 'Error';
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Badge de Usuario (idéntico al original)
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildUserBadge(UserModel user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: const Color(0xFF3B82F6),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            user.name.split(' ').first,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SESSION TILE — Fila individual del historial
// ═══════════════════════════════════════════════════════════════════════
class _SessionTile extends StatelessWidget {
  final ServiceSession session;
  final int sessionNumber;
  final bool isActive;
  final bool adminOverride;
  final Function(String) onEditStart;
  final Function(String) onEditEnd;
  final VoidCallback onDelete;
  final Future<void> Function(BuildContext, String?, Function(String))
      onPickTime;

  const _SessionTile({
    super.key,
    required this.session,
    required this.sessionNumber,
    required this.isActive,
    required this.adminOverride,
    required this.onEditStart,
    required this.onEditEnd,
    required this.onDelete,
    required this.onPickTime,
  });

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Hoy';
    if (day == yesterday) return 'Ayer';
    return DateFormat('EEE d MMM', 'es').format(date);
  }

  String _calcDuration() {
    if (session.endTime == null) return '';
    try {
      final sp = session.startTime.split(':');
      final ep = session.endTime!.split(':');
      final s = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final e = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      final diff = e - s;
      if (diff <= 0) return '';
      final h = diff ~/ 60;
      final m = diff % 60;
      return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatDate(session.date);
    final dur = _calcDuration();
    final Color accent =
        isActive ? const Color(0xFF10B981) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF10B981).withOpacity(0.03)
            : Colors.white,
        border:
            const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          // Número / punto activo
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withOpacity(isActive ? 0.45 : 0.2),
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: isActive
                  ? Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: accent, shape: BoxShape.circle),
                    )
                  : Text(
                      '$sessionNumber',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent),
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // Fecha + horarios
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila: fecha + badge "En curso"
                Row(
                  children: [
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? const Color(0xFF10B981)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'En curso',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),

                // Fila: inicio → fin (duración)
                Row(
                  children: [
                    _TimeChip(
                      time: session.startTime,
                      canEdit: adminOverride,
                      onTap: () => onPickTime(
                          context, session.startTime, onEditStart),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.arrow_right_alt_rounded,
                          size: 11, color: Color(0xFFCBD5E1)),
                    ),
                    if (session.endTime != null)
                      _TimeChip(
                        time: session.endTime!,
                        canEdit: adminOverride,
                        onTap: () => onPickTime(
                            context, session.endTime, onEditEnd),
                      )
                    else
                      const Text(
                        '--:--',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFCBD5E1),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (dur.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '($dur)',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Botón eliminar (solo admin + sesión cerrada)
          if (adminOverride && !isActive)
            InkWell(
              onTap: () => _confirmDelete(context),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 14, color: Color(0xFFEF4444)),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B), size: 22),
            SizedBox(width: 10),
            Text('Eliminar sesión',
                style: TextStyle(fontSize: 15)),
          ],
        ),
        content: const Text(
          '¿Eliminar este registro del historial?\nEsta acción no se puede deshacer.',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TOTAL TIME SUMMARY — Pie del historial
// ═══════════════════════════════════════════════════════════════════════
class _TotalTimeSummary extends StatelessWidget {
  final List<ServiceSession> sessions;
  const _TotalTimeSummary({required this.sessions});

  @override
  Widget build(BuildContext context) {
    int totalMinutes = 0;
    for (final s in sessions) {
      if (s.startTime.isNotEmpty && s.endTime != null) {
        try {
          final sp = s.startTime.split(':');
          final ep = s.endTime!.split(':');
          final start = int.parse(sp[0]) * 60 + int.parse(sp[1]);
          final end = int.parse(ep[0]) * 60 + int.parse(ep[1]);
          if (end > start) totalMinutes += (end - start);
        } catch (_) {}
      }
    }

    final closedCount = sessions.where((s) => !s.isOpen).length;
    if (closedCount == 0) return const SizedBox.shrink();

    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final timeStr =
        h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m' : '${m}m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Tiempo total ($closedCount '
            '${closedCount == 1 ? 'sesión' : 'sesiones'})',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              timeStr,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TIME CHIP — Hora editable (admin) o solo lectura
// ═══════════════════════════════════════════════════════════════════════
class _TimeChip extends StatelessWidget {
  final String time;
  final bool canEdit;
  final VoidCallback onTap;

  const _TimeChip({
    required this.time,
    required this.canEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: canEdit ? onTap : null,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(5),
          border: canEdit
              ? Border.all(color: const Color(0xFFCBD5E1), width: 0.8)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 3),
              const Icon(Icons.edit, size: 8, color: Color(0xFF94A3B8)),
            ],
          ],
        ),
      ),
    );
  }
}