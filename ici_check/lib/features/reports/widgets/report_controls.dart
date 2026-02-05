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

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Personal Designado
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.people, size: 16, color: Color(0xFF3B82F6)),
                    SizedBox(width: 8),
                    Text('PERSONAL DESIGNADO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: report.assignedTechnicianIds.map((uid) {
                    final user = users.firstWhere(
                      (u) => u.id == uid,
                      orElse: () => UserModel(id: uid, name: 'Usuario', email: ''),
                    );
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: const Color(0xFF3B82F6),
                        child: Text(user.name[0].toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                      ),
                      label: Text(user.name, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.blue.shade300),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Fechas y Controles
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FECHA DE EJECUCIÓN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    InkWell(
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: adminOverride ? Colors.white : Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: Color(0xFF3B82F6)),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd MMMM yyyy', 'es').format(report.serviceDate),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HORARIOS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildTimeBox(report.startTime ?? '--:--'),
                      const SizedBox(width: 12),
                      _buildTimeBox(report.endTime ?? '--:--'),
                    ],
                  ),
                ],
              ),
              if (isUserDesignated) ...[
                const SizedBox(width: 16),
                _buildActionButton(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBox(String time) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(time, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActionButton() {
    if (report.startTime == null) {
      return ElevatedButton.icon(
        onPressed: onStartService,
        icon: const Icon(Icons.play_arrow, size: 16),
        label: const Text('INICIAR'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
      );
    } else if (report.endTime == null) {
      return ElevatedButton.icon(
        onPressed: onEndService,
        icon: const Icon(Icons.stop, size: 16),
        label: const Text('FINALIZAR'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
      );
    } else if (!_isReportComplete()) {
      return ElevatedButton.icon(
        onPressed: onResumeService,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('REANUDAR'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
      );
    } else {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check, size: 16),
        label: const Text('FINALIZADO'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
      );
    }
  }
}