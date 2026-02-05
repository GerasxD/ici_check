import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';

class ReportHeader extends StatelessWidget {
  final CompanySettingsModel companySettings;
  final ClientModel client;
  final DateTime serviceDate;
  final String dateStr;
  final String frequencies;

  const ReportHeader({
    super.key,
    required this.companySettings,
    required this.client,
    required this.serviceDate,
    required this.dateStr,
    required this.frequencies,
  });

  String _getPeriodLabel() {
    if (dateStr.contains('W')) {
      return 'Semana $dateStr';
    } else {
      try {
        final date = DateFormat('yyyy-MM').parse('$dateStr-01');
        String month = DateFormat('MMMM yyyy', 'es').format(date);
        return "${month[0].toUpperCase()}${month.substring(1)}";
      } catch (e) {
        return dateStr;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. BARRA SUPERIOR (LOGO PROVEEDOR Y TÍTULO)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
            ),
            child: Row(
              children: [
                _buildLogo(companySettings.logoUrl, size: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companySettings.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sistema de Detección de Incendios',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. CUERPO PRINCIPAL (RESPONSIVO)
          // Usamos LayoutBuilder para detectar si estamos en móvil o tablet
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Si el ancho es menor a 600px (Móvil), usamos Columna (uno abajo del otro)
                // Si es mayor (Tablet/Web), usamos Fila (uno al lado del otro)
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bloque Cliente
                      _buildClientSection(),
                      
                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFFE2E8F0)), // Divisor horizontal
                      const SizedBox(height: 20),
                      
                      // Bloque Detalles
                      _buildDetailsSection(),
                    ],
                  );
                } else {
                  // LAYOUT TABLET / ESCRITORIO
                  return IntrinsicHeight( // Truco para que el divisor vertical tenga la altura correcta
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _buildClientSection()),
                        Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          color: const Color(0xFFE2E8F0),
                        ),
                        Expanded(flex: 2, child: _buildDetailsSection()),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // Extrajimos la sección del cliente a un método para reutilizarlo en Column o Row
  Widget _buildClientSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CLIENTE',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLogo(client.logoUrl, size: 36, isClient: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  if (client.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      client.address,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Extrajimos la sección de detalles
  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DETALLES',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        _buildDetailRow('Fecha Ejecución:', DateFormat('dd MMM yyyy', 'es').format(serviceDate)),
        const SizedBox(height: 6),
        _buildDetailRow('Periodo:', _getPeriodLabel()),
        const SizedBox(height: 6),
        _buildDetailRow('Frecuencia:', frequencies, isBadge: true),
      ],
    );
  }

  // [CORRECCIÓN CLAVE]: Usamos Expanded y TextAlign.end para evitar el overflow en el texto
  Widget _buildDetailRow(String label, String value, {bool isBadge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start, // Alineación superior por si el texto se envuelve
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8), // Espacio mínimo seguro
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
            ),
          )
        else
          // Expanded obliga al texto a respetar el ancho disponible
          Expanded( 
            child: Text(
              value,
              textAlign: TextAlign.end, // Alinear a la derecha
              style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
              overflow: TextOverflow.visible, // Permitir que baje al siguiente renglón si es necesario
            ),
          ),
      ],
    );
  }

  Widget _buildLogo(String? url, {required double size, bool isClient = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: isClient ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: url != null && url.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: url.startsWith('http')
                  ? Image.network(url, fit: BoxFit.contain)
                  : Image.memory(base64Decode(url), fit: BoxFit.contain),
            )
          : Center(
              child: Icon(
                isClient ? Icons.business : Icons.local_fire_department,
                color: Colors.grey.shade300,
                size: size * 0.5,
              ),
            ),
    );
  }
}