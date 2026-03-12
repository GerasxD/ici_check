import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;

import 'package:ici_check/features/corrective_log/data/corrective_item_model.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';

enum CorrectivePdfType {
  pending,   // Pendientes + En Proceso
  corrected, // Corregido por ICISI + Corregido por Terceros
}

class CorrectiveLogPdfService {
  // ═══════════════════════════════════════════════════════════════════
  // ENTRADA PÚBLICA — ahora delega a la Cloud Function
  // ═══════════════════════════════════════════════════════════════════
  static Future<void> generateAndOpen({
    required List<CorrectiveItemModel> allItems,
    required PolicyModel policy,
    required ClientModel client,
    required CompanySettingsModel companySettings, // se mantiene para compatibilidad
    required CorrectivePdfType pdfType,
  }) async {
    // 1. Llamar a la Cloud Function
    final HttpsCallable callable = FirebaseFunctions.instance
        .httpsCallable('generateCorrectiveLogPdf');

    final result = await callable.call<Map<String, dynamic>>({
      'policyId': policy.id,
      'pdfType': pdfType == CorrectivePdfType.pending ? 'pending' : 'corrected',
    });

    final data = result.data;
    final downloadUrl = data['downloadUrl'] as String?;

    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('La función no devolvió una URL de descarga.');
    }

    // 2. Descargar el PDF y abrirlo
    final suffix   = pdfType == CorrectivePdfType.pending ? 'Pendientes' : 'Corregidos';
    final filename = 'Bitacora_${suffix}_${client.name.replaceAll(' ', '_')}.pdf';

    if (kIsWeb) {
      // En web: compartir directamente con la URL pública
      final response = await http.get(Uri.parse(downloadUrl));
      await Printing.sharePdf(
        bytes: response.bodyBytes,
        filename: filename,
      );
    } else {
      // En móvil/desktop: descargar y abrir
      final response = await http.get(Uri.parse(downloadUrl));
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(response.bodyBytes);
      await OpenFilex.open(file.path);
    }
  }
}