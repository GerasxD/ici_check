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
  final Function(String)? onStartTimeEdited;
  final Function(String)? onEndTimeEdited;

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
    this.onStartTimeEdited, // Opcionales para no romper código antiguo si no se pasan
    this.onEndTimeEdited,
  });

  // --- LÓGICA DE VALIDACIÓN CORREGIDA ---
  bool _isReportFullyComplete() {
    for (var entry in report.entries) {
      // ELIMINADO: if (entry.results.isEmpty) return false; 
      // Explicación: Si un dispositivo no tiene actividades este mes (results vacío),
      // NO debe contar como incompleto. Es simplemente un equipo sin tareas.

      // Solo revisamos los valores existentes
      for (var status in entry.results.values) {
        // Si encontramos un nulo (sin contestar) o un "NR", está incompleto.
        if (status == null || status == 'NR') {
          return false;
        }
      }
    }
    // Si pasamos todos los ciclos sin encontrar errores, está completo.
    return true;
  }

  // Helper para saber si el servicio está "en curso"
  bool get _isInProgress => report.startTime != null && report.endTime == null;
  
  // Helper para saber si ya se marcó como finalizado (tiene hora de fin)
  bool get _isFinished => report.startTime != null && report.endTime != null;

  Future<void> _pickTime(BuildContext context, String? currentTime, Function(String) onPicked) async {
    TimeOfDay initialTime = TimeOfDay.now();
    
    // Intentar parsear la hora actual si existe (HH:mm)
    if (currentTime != null && currentTime.contains(':')) {
      try {
        final parts = currentTime.split(':');
        initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Formatear a HH:mm
      final hour = picked.hour.toString().padLeft(2, '0');
      final minute = picked.minute.toString().padLeft(2, '0');
      onPicked("$hour:$minute");
    }
  }

  @override
  Widget build(BuildContext context) {
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
                
                // Lista de Avatares
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
                           color: const Color(0xFFF8FAFC),
                           borderRadius: BorderRadius.circular(10),
                           // Borde visible si es admin
                           border: Border.all(color: adminOverride ? const Color(0xFFCBD5E1) : Colors.transparent),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('HORARIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8))),
                                if(adminOverride) const Icon(Icons.edit, size: 10, color: Color(0xFF94A3B8)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                               children: [
                                 // HORA INICIO
                                 InkWell(
                                   onTap: (adminOverride && onStartTimeEdited != null) 
                                      ? () => _pickTime(context, report.startTime, onStartTimeEdited!) 
                                      : null,
                                   child: Text(
                                     report.startTime ?? '--:--',
                                     style: TextStyle(
                                       fontSize: 13, 
                                       fontWeight: FontWeight.w600, 
                                       color: const Color(0xFF334155),
                                       decoration: (adminOverride && report.startTime != null) ? TextDecoration.underline : null,
                                       decorationStyle: TextDecorationStyle.dotted
                                     ),
                                   ),
                                 ),
                                 
                                 const Padding(
                                   padding: EdgeInsets.symmetric(horizontal: 4),
                                   child: Icon(Icons.arrow_right_alt, size: 12, color: Color(0xFF94A3B8)),
                                 ),
                                 
                                 // HORA FIN
                                 InkWell(
                                   onTap: (adminOverride && onEndTimeEdited != null) 
                                      ? () => _pickTime(context, report.endTime, onEndTimeEdited!) 
                                      : null,
                                   child: Text(
                                     report.endTime ?? '--:--',
                                     style: TextStyle(
                                       fontSize: 13, 
                                       fontWeight: FontWeight.w600, 
                                       color: report.endTime != null ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                       decoration: (adminOverride && report.endTime != null) ? TextDecoration.underline : null,
                                       decorationStyle: TextDecorationStyle.dotted
                                     ),
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
      // 1. ESTADO: INICIAL -> Botón Verde
      return ElevatedButton(
        onPressed: onStartService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981), 
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
      // 2. ESTADO: EN PROGRESO (Abierto) -> Botón Rojo
      return ElevatedButton(
        onPressed: onEndService,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444), 
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
    } else {
      // 3. ESTADO: FINALIZADO (Cerrado)
      
      // Aquí está la lógica crítica
      if (!_isReportFullyComplete()) {
        // CASO A: INCOMPLETO -> Botón Naranja para reanudar
        return ElevatedButton(
          onPressed: onResumeService,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B), 
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber_rounded, size: 20),
              SizedBox(width: 8),
              Text('REANUDAR (PENDIENTES)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        );
      } else {
        // CASO B: COMPLETO (Perfecto) -> Etiqueta Verde
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)
              ),
            ],
          ),
        );
      }
    }
  }
}