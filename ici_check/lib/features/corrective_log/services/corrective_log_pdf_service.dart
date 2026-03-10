import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:ici_check/features/corrective_log/data/corrective_item_model.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';

class CorrectiveLogPdfService {
  // Colores corporativos (match ICISI PDF)
  static const PdfColor _headerBg = PdfColor.fromInt(0xFF4BA3C7); // azul teal del PDF
  static const PdfColor _darkText = PdfColor.fromInt(0xFF1E293B);
  static const PdfColor _grayText = PdfColor.fromInt(0xFF64748B);
  static const PdfColor _borderColor = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor _levelA = PdfColor.fromInt(0xFFEF4444); // rojo
  static const PdfColor _levelB = PdfColor.fromInt(0xFFF59E0B); // amber
  static const PdfColor _levelC = PdfColor.fromInt(0xFF64748B); // gris
  static const PdfColor _white = PdfColors.white;

  /// Genera el PDF y lo abre directamente
  static Future<void> generateAndOpen({
    required List<CorrectiveItemModel> items,      // Solo pendientes (para el PDF)
    required List<CorrectiveItemModel> allItems,   // Todos (para stats)
    required PolicyModel policy,
    required ClientModel client,
    required CompanySettingsModel companySettings,
  }) async {
    final pdfBytes = await _generate(
      items: items,
      allItems: allItems,
      policy: policy,
      client: client,
      companySettings: companySettings,
    );

    if (kIsWeb) {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Bitacora_Correctivos_${client.name}.pdf',
      );
    } else {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/Bitacora_Correctivos_${client.name.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(pdfBytes);
      await OpenFilex.open(file.path);
    }
  }

  static Future<Uint8List> _generate({
    required List<CorrectiveItemModel> items,
    required List<CorrectiveItemModel> allItems,
    required PolicyModel policy,
    required ClientModel client,
    required CompanySettingsModel companySettings,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontBlack = await PdfGoogleFonts.robotoBlack();
    final dateFormat = DateFormat('dd/MM/yyyy');

    // Logo
    pw.ImageProvider? companyLogo;
    if (companySettings.logoUrl.isNotEmpty) {
      try {
        if (companySettings.logoUrl.startsWith('http')) {
          companyLogo = await networkImage(companySettings.logoUrl);
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final monthYear = DateFormat('MMMM yyyy', 'es').format(now).toUpperCase();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => _buildHeader(
          companySettings, companyLogo, client, monthYear,
          font, fontBold, fontBlack,
        ),
        footer: (context) => _buildFooter(context, font, fontBold),
        build: (context) {
          final List<pw.Widget> content = [];

          // Leyenda de niveles
          content.add(_buildLegend(font, fontBold));
          content.add(pw.SizedBox(height: 10));

          // Tabla de correctivos
          content.add(_buildTable(items, font, fontBold, fontBlack, dateFormat));

          return content;
        },
      ),
    );

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════
  // HEADER — Estilo ICISI
  // ═══════════════════════════════════════════════════════
  static pw.Widget _buildHeader(
    CompanySettingsModel company,
    pw.ImageProvider? logo,
    ClientModel client,
    String monthYear,
    pw.Font font,
    pw.Font fontBold,
    pw.Font fontBlack,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _darkText, width: 1.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Título
          pw.Expanded(
            flex: 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BITACORA DE CORRECTIVOS',
                  style: pw.TextStyle(font: fontBlack, fontSize: 18, color: _darkText),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Text(
                      DateFormat('yyyy').format(DateTime.now()),
                      style: pw.TextStyle(font: fontBlack, fontSize: 14, color: _darkText),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Text(
                      monthYear,
                      style: pw.TextStyle(font: fontBold, fontSize: 12, color: _grayText),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Cliente: ${client.name}',
                  style: pw.TextStyle(font: fontBold, fontSize: 10, color: _grayText),
                ),
              ],
            ),
          ),

          // Leyenda de niveles
          pw.Expanded(
            flex: 3,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF8FAFC),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: _borderColor),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Nivel de atención',
                    style: pw.TextStyle(font: fontBold, fontSize: 9, color: _darkText, fontStyle: pw.FontStyle.italic),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('A = Daño potencial para el equipo.', style: pw.TextStyle(font: font, fontSize: 7, color: _grayText)),
                  pw.Text('B = Riesgo de daño moderado.', style: pw.TextStyle(font: font, fontSize: 7, color: _grayText)),
                  pw.Text('C = Detalle de prevención.', style: pw.TextStyle(font: font, fontSize: 7, color: _grayText)),
                ],
              ),
            ),
          ),

          // Logo
          pw.SizedBox(width: 16),
          if (logo != null)
            pw.Image(logo, width: 60, height: 60, fit: pw.BoxFit.contain)
          else
            pw.SizedBox(width: 60),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // LEYENDA
  // ═══════════════════════════════════════════════════════
  static pw.Widget _buildLegend(pw.Font font, pw.Font fontBold) {
    return pw.Container(); // Ya incluida en el header
  }

  // ═══════════════════════════════════════════════════════
  // TABLA PRINCIPAL — Replica tu formato PDF
  // ═══════════════════════════════════════════════════════
  static pw.Widget _buildTable(
    List<CorrectiveItemModel> items,
    pw.Font font,
    pw.Font fontBold,
    pw.Font fontBlack,
    DateFormat dateFormat,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),   // ID
        1: const pw.FixedColumnWidth(80),   // Área
        2: const pw.FlexColumnWidth(2),     // Problema / Antes
        3: const pw.FlexColumnWidth(2),     // Acción Correctiva / Después
        4: const pw.FixedColumnWidth(70),   // Fecha Detección
        5: const pw.FixedColumnWidth(30),   // Nivel
        6: const pw.FixedColumnWidth(70),   // Fecha Est. Corrección
        7: const pw.FixedColumnWidth(60),   // Estatus
        8: const pw.FlexColumnWidth(1),     // Observaciones
      },
      children: [
        // HEADER ROW
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerBg),
          children: [
            _headerCell('ID', fontBold),
            _headerCell('Área', fontBold),
            _headerCell('Problema / Antes', fontBold),
            _headerCell('Acción Correctiva / Después', fontBold),
            _headerCell('Fecha de\nDetección', fontBold),
            _headerCell('Nivel', fontBold),
            _headerCell('Fecha estimada\nde corrección', fontBold),
            _headerCell('Estatus', fontBold),
            _headerCell('OBSERVACIONES', fontBold),
          ],
        ),

        // DATA ROWS
        ...items.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final item = entry.value;
          final PdfColor levelColor = _getLevelColor(item.level);

          return pw.TableRow(
            children: [
              // ID
              _dataCell(
                pw.Text('$idx', style: pw.TextStyle(font: fontBold, fontSize: 9, color: _darkText)),
              ),
              // Área
              _dataCell(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (item.deviceCustomId.isNotEmpty)
                      pw.Text(item.deviceCustomId, style: pw.TextStyle(font: fontBold, fontSize: 8, color: _darkText)),
                    pw.Text(
                      item.deviceArea.isNotEmpty ? item.deviceArea : item.deviceDefName,
                      style: pw.TextStyle(font: font, fontSize: 7, color: _grayText),
                    ),
                  ],
                ),
              ),
              // Problema
              _dataCell(
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (item.activityName.isNotEmpty)
                      pw.Text(
                        item.activityName.toUpperCase(),
                        style: pw.TextStyle(font: fontBold, fontSize: 7, color: _darkText),
                      ),
                    if (item.problemDescription.isNotEmpty)
                      pw.Text(
                        item.problemDescription,
                        style: pw.TextStyle(font: font, fontSize: 7, color: _grayText),
                        maxLines: 4,
                      ),
                  ],
                ),
              ),
              // Acción correctiva
              _dataCell(
                pw.Text(
                  item.correctionAction.isNotEmpty
                      ? item.correctionAction
                      : 'Pendiente de definir',
                  style: pw.TextStyle(
                    font: item.correctionAction.isNotEmpty ? font : font,
                    fontSize: 7,
                    color: item.correctionAction.isNotEmpty ? _darkText : _grayText,
                    fontStyle: item.correctionAction.isEmpty ? pw.FontStyle.italic : pw.FontStyle.normal,
                  ),
                  maxLines: 4,
                ),
              ),
              // Fecha detección
              _dataCell(
                pw.Text(
                  dateFormat.format(item.detectionDate),
                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: _darkText),
                ),
              ),
              // Nivel
              _dataCell(
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: levelColor,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    item.level.name,
                    style: pw.TextStyle(font: fontBlack, fontSize: 10, color: _white),
                  ),
                ),
                center: true,
              ),
              // Fecha estimada corrección
              _dataCell(
                pw.Text(
                  item.estimatedCorrectionDate != null
                      ? dateFormat.format(item.estimatedCorrectionDate!)
                      : '',
                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: _darkText),
                ),
              ),
              // Estatus
              _dataCell(
                pw.Column(
                  children: [
                    pw.Text(
                      item.statusLabel.toUpperCase(),
                      style: pw.TextStyle(font: fontBold, fontSize: 7, color: _darkText),
                    ),
                    if (item.reportedTo != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'REPORTADO A ${item.reportedTo!.toUpperCase()}',
                        style: pw.TextStyle(font: font, fontSize: 6, color: _grayText),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ],
                ),
                center: true,
              ),
              // Observaciones
              _dataCell(
                pw.Text(
                  item.observations,
                  style: pw.TextStyle(font: font, fontSize: 7, color: _grayText),
                  maxLines: 4,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _headerCell(String text, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: fontBold, fontSize: 8, color: _white),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _dataCell(pw.Widget child, {bool center = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: center ? pw.Alignment.center : pw.Alignment.topLeft,
      child: child,
    );
  }

  static PdfColor _getLevelColor(AttentionLevel level) {
    switch (level) {
      case AttentionLevel.A: return _levelA;
      case AttentionLevel.B: return _levelB;
      case AttentionLevel.C: return _levelC;
    }
  }

  // ═══════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════
  static pw.Widget _buildFooter(pw.Context context, pw.Font font, pw.Font fontBold) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: pw.TextStyle(font: font, fontSize: 8, color: _grayText),
        ),
      ],
    );
  }
}