import 'package:flutter/material.dart';
import 'package:ici_check/features/reports/data/report_model.dart';

class ReportSummary extends StatelessWidget {
  final ServiceReportModel report;

  const ReportSummary({super.key, required this.report});

  Map<String, int> _calculateStats() {
    int ok = 0, nok = 0, na = 0, nr = 0;
    
    for (var entry in report.entries) {
      for (var status in entry.results.values) {
        if (status == 'OK') ok++;
        if (status == 'NOK') nok++;
        if (status == 'NA') na++;
        if (status == 'NR') nr++;
      }
    }
    
    return {'ok': ok, 'nok': nok, 'na': na, 'nr': nr};
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), // slate-50
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2), // slate-200
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del Resumen
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.analytics_outlined, size: 18, color: Color(0xFF1E293B)),
                SizedBox(width: 8),
                Text(
                  'RESUMEN OPERATIVO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E293B),
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Grid de Estadísticas
          Row(
            children: [
              // OK
              Expanded(
                child: _StatCard(
                  label: 'OK',
                  value: stats['ok']!,
                  color: const Color(0xFF10B981), // green-500
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              
              // NOK (Falla)
              Expanded(
                child: _StatCard(
                  label: 'FALLA',
                  value: stats['nok']!,
                  color: const Color(0xFFEF4444), // red-500
                  icon: Icons.cancel,
                  subtitle: 'NOK',
                ),
              ),
              const SizedBox(width: 12),
              
              // N/A
              Expanded(
                child: _StatCard(
                  label: 'N/A',
                  value: stats['na']!,
                  color: const Color(0xFF64748B), // slate-500
                  icon: Icons.remove_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              
              // N/R
              Expanded(
                child: _StatCard(
                  label: 'N/R',
                  value: stats['nr']!,
                  color: const Color(0xFFF59E0B), // amber-500
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

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final String? subtitle;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 8,
                color: color.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}