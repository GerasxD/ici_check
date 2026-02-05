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
        color: const Color(0xFFF8FAFC), // slate-50 background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)), // slate-200
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
          // Header del Resumen con Icono
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
                  child: const Icon(Icons.analytics_outlined, size: 18, color: Color(0xFF1E293B)),
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
                        color: Color(0xFF1E293B), // slate-800
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Estadísticas del servicio actual',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B), // slate-500
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Grid de Estadísticas (Cards)
          Row(
            children: [
              // OK
              Expanded(
                child: _StatCard(
                  label: 'CORRECTO',
                  value: stats['ok']!,
                  color: const Color(0xFF10B981), // Emerald-500
                  bgColor: const Color(0xFFECFDF5), // Emerald-50
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              
              // NOK (Falla)
              Expanded(
                child: _StatCard(
                  label: 'FALLA',
                  value: stats['nok']!,
                  color: const Color(0xFFEF4444), // Red-500
                  bgColor: const Color(0xFFFEF2F2), // Red-50
                  icon: Icons.cancel,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Row(
            children: [
              // N/A
              Expanded(
                child: _StatCard(
                  label: 'NO APLICA',
                  value: stats['na']!,
                  color: const Color(0xFF64748B), // Slate-500
                  bgColor: const Color(0xFFF1F5F9), // Slate-100
                  icon: Icons.not_interested, // Icono más claro para N/A
                ),
              ),
              const SizedBox(width: 12),
              
              // N/R
              Expanded(
                child: _StatCard(
                  label: 'NO REALIZADO',
                  value: stats['nr']!,
                  color: const Color(0xFFF59E0B), // Amber-500
                  bgColor: const Color(0xFFFFFBEB), // Amber-50
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
          // Icono con fondo circular suave
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
              letterSpacing: -1.0, // Tight tracking para números grandes
            ),
          ),
          const SizedBox(height: 4),
          
          // Etiqueta
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF94A3B8), // Slate-400
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}