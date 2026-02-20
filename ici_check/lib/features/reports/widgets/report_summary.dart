// lib/features/reports/widgets/report_summary.dart
//
// ═══════════════════════════════════════════════════════════════════════
// ReportSummary — Refactorizado con Riverpod
//
// ANTES: Recibía `ServiceReportModel report` completo, ejecutaba
//        _calculateStats() en build() → O(N×M) en cada rebuild.
//
// DESPUÉS: Escucha SOLO reportStatsProvider.
//          Si el usuario teclea una observación o cambia un customId,
//          las stats no cambian → este widget NO se reconstruye.
//          Solo se reconstruye cuando alguien hace tap en un toggle.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/reports/state/report_notifier.dart';

class ReportSummary extends ConsumerWidget {
  const ReportSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ CLAVE: select() compara con ReportStats.operator ==
    // Si ok/nok/na/nr no cambiaron → build() NO se ejecuta
    final stats = ref.watch(reportStatsProvider);

    if (stats == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header del Resumen ───
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.analytics_outlined,
                    size: 18,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESUMEN OPERATIVO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Estadísticas del servicio actual',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ─── Grid de Estadísticas (Fila 1: OK + NOK) ───
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'CORRECTO',
                  value: stats.ok,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'FALLA',
                  value: stats.nok,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  icon: Icons.cancel,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ─── Grid de Estadísticas (Fila 2: NA + NR) ───
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'NO APLICA',
                  value: stats.na,
                  color: const Color(0xFF64748B),
                  bgColor: const Color(0xFFF1F5F9),
                  icon: Icons.not_interested,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'NO REALIZADO',
                  value: stats.nr,
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                  icon: Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// _StatCard — Sin cambios visuales, exactamente igual que antes
// ═══════════════════════════════════════════════════════════════════════
class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Icono con fondo circular
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),

          // Número Grande
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.0,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),

          // Etiqueta
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}