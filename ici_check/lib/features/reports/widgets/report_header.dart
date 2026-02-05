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
        return DateFormat('MMMM yyyy', 'es').format(date);
      } catch (e) {
        return dateStr;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildCompanyInfo(companySettings, isProvider: true),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    const Text(
                      'REPORTE DE SERVICIO',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sistema de Detección de Incendios',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'EJECUCIÓN: ${DateFormat('dd MMM yyyy', 'es').format(serviceDate).toUpperCase()}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PERIODO: ${_getPeriodLabel().toUpperCase()}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Frecuencias: $frequencies',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildCompanyInfo(null, client: client, isProvider: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyInfo(CompanySettingsModel? company, {ClientModel? client, required bool isProvider}) {
    final name = isProvider ? company?.name ?? '' : client?.name ?? '';
    final address = isProvider ? company?.address ?? '' : client?.address ?? '';
    final logoUrl = isProvider ? company?.logoUrl : client?.logoUrl;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isProvider) const Spacer(),
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: logoUrl != null && logoUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: logoUrl.startsWith('http')
                      ? Image.network(logoUrl, fit: BoxFit.contain)
                      : Image.memory(base64Decode(logoUrl), fit: BoxFit.contain),
                )
              : const Center(child: Text('LOGO', style: TextStyle(fontSize: 8))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: isProvider ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), textAlign: isProvider ? TextAlign.left : TextAlign.right),
              if (address.isNotEmpty)
                Text(address, style: const TextStyle(fontSize: 8, color: Color(0xFF64748B)), textAlign: isProvider ? TextAlign.left : TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (isProvider) const Spacer(),
      ],
    );
  }
}