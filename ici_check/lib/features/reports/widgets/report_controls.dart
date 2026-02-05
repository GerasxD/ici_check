import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';

class ReportControls extends StatelessWidget {
  final ServiceReportModel report;
  final List<UserModel> users;
  final bool adminOverride;
  final bool isUserDesignated;
  final VoidCallback onStartService;
  final VoidCallback onEndService;
  final VoidCallback onResumeService;
  final Function(DateTime) onDateChanged;

  const ReportControls({
    super.key,
    required this.report,
    required this.users,
    required this.adminOverride,
    required this.isUserDesignated,
    required this.onStartService,
    required this.onEndService,
    required this.onResumeService,
    required this.onDateChanged,
  });

  bool _isReportComplete() {
    return report.entries.every((entry) {
      return entry.results.values.every((status) => status != null);
    });
  }

  // Helper para saber si el servicio está "en curso"
  bool get _isInProgress => report.startTime != null && report.endTime == null;
  bool get _isFinished => report.startTime != null && report.endTime != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        // Sombra más elegante y profunda
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
          // 1. ZONA DE ESTADO Y PERSONAL (SUPERIOR)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Etiqueta superior
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
                        letterSpacing: 0.5
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Lista de Avatares (Más limpia)
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: report.assignedTechnicianIds.isEmpty
                        ? [const Text("Sin asignar", style: TextStyle(color: Colors.grey, fontSize: 13))]
                        : report.assignedTechnicianIds.map((uid) {
                            final user = users.firstWhere(
                              (u) => u.id == uid,
                              orElse: () => UserModel(id: uid, name: 'Usuario', email: ''),
                            );
                            return _buildUserBadge(user);
                          }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // 2. ZONA DE ACCIÓN Y TIEMPOS (INFERIOR)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Fila de Fecha y Tiempos
                Row(
                  children: [
                    // Columna FECHA
                    Expanded(
                      flex: 4,
                      child: InkWell(
                         onTap: adminOverride
                              ? () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: report.serviceDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) onDateChanged(picked);
                                }
                              : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC), // Slate-50
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: adminOverride ? const Color(0xFFCBD5E1) : Colors.transparent),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('FECHA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8))),
                                  if(adminOverride) const Icon(Icons.edit, size: 10, color: Color(0xFF94A3B8)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_month, size: 16, color: Color(0xFF334155)),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('dd MMM yyyy', 'es').format(report.serviceDate).toUpperCase(),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                  ),
                                ],
                              )
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                           color: const Color(0xFFF8FAFC), // Slate-50
                           borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('HORARIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8))),
                            const SizedBox(height: 4),
                            Row(
                               children: [
                                 Text(
                                   report.startTime ?? '--:--',
                                   style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                 ),
                                 const Padding(
                                   padding: EdgeInsets.symmetric(horizontal: 4),
                                   child: Icon(Icons.arrow_right_alt, size: 12, color: Color(0xFF94A3B8)),
                                 ),
                                 Text(
                                   report.endTime ?? '--:--',
                                   style: TextStyle(
                                     fontSize: 13, 
                                     fontWeight: FontWeight.w600, 
                                     color: report.endTime != null ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
                                    ),
                                 ),
                               ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // BOTÓN DE ACCIÓN PRINCIPAL (Full Width)
                if (isUserDesignated) 
                  SizedBox(
                    width: double.infinity,
                    child: _buildActionButton(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Badge de Usuario más limpio
  Widget _buildUserBadge(UserModel user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
        ]
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: const Color(0xFF3B82F6), // Blue-500
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            user.name.split(' ').first, // Solo primer nombre
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (!_isInProgress && !_isFinished) {
      // ESTADO: INICIAL (Botón Verde Grande)
      return ElevatedButton(
        onPressed: onStartService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981), // Emerald-500
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_fill, size: 20),
            SizedBox(width: 8),
            Text('INICIAR SERVICIO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      );
    } else if (_isInProgress) {
      // ESTADO: EN PROGRESO (Botón Rojo Pulsante)
      return ElevatedButton(
        onPressed: onEndService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444), // Red-500
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.stop_circle, size: 20),
            SizedBox(width: 8),
            Text('FINALIZAR SERVICIO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      );
    } else if (!_isReportComplete()) {
      // ESTADO: INCOMPLETO (Botón Naranja para reabrir)
      return ElevatedButton(
        onPressed: onResumeService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF59E0B), // Amber-500
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.replay, size: 20),
            SizedBox(width: 8),
            Text('REANUDAR (Incompleto)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
      );
    } else {
      // ESTADO: COMPLETADO (Deshabilitado / Gris)
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9), // Slate-100
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
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)
            ),
          ],
        ),
      );
    }
  }
}