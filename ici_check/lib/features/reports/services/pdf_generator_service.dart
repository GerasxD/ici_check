import 'dart:typed_data';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http; // <--- AGREGA ESTO

class PdfGeneratorService {
  static Future<Uint8List> generateServiceReport({
    required ServiceReportModel report,
    required ClientModel client,
    required CompanySettingsModel companySettings,
    required List<DeviceModel> deviceDefinitions,
    required List<UserModel> technicians,
    required List<PolicyDevice> policyDevices,
  }) async {
    final pdf = pw.Document();

    Map<String, List<ReportEntry>> groupedEntries = _groupEntries(
      report,
      deviceDefinitions,
      policyDevices,
    );

    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pw.MemoryImage? companyLogo;
    pw.MemoryImage? clientLogo;
    pw.MemoryImage? providerSignature;
    pw.MemoryImage? clientSignature;

    // Cargar logos (tu código existente está bien)
    if (companySettings.logoUrl.isNotEmpty) {
      try {
        if (companySettings.logoUrl.startsWith('http')) {
          companyLogo = (await networkImage(companySettings.logoUrl)) as pw.MemoryImage?;
        } else {
          companyLogo = pw.MemoryImage(base64Decode(companySettings.logoUrl));
        }
      } catch (e) {
        print('Error loading company logo: $e');
      }
    }

    if (client.logoUrl.isNotEmpty) {
      try {
        if (client.logoUrl.startsWith('http')) {
          clientLogo = (await networkImage(client.logoUrl)) as pw.MemoryImage?;
        } else {
          clientLogo = pw.MemoryImage(base64Decode(client.logoUrl));
        }
      } catch (e) {
        print('Error loading client logo: $e');
      }
    }

    try {
      if (report.providerSignature != null && report.providerSignature!.isNotEmpty) {
        providerSignature = pw.MemoryImage(base64Decode(report.providerSignature!));
      }
    } catch (e) {
      print('Error loading provider signature: $e');
    }

    try {
      if (report.clientSignature != null && report.clientSignature!.isNotEmpty) {
        clientSignature = pw.MemoryImage(base64Decode(report.clientSignature!));
      }
    } catch (e) {
      print('Error loading client signature: $e');
    }

    String periodLabel = _getPeriodLabel(report.dateStr);
    String frequencies = _getInvolvedFrequencies(report, deviceDefinitions);
    Map<String, int> stats = _calculateStats(report);

    // ✅ GENERAR SECCIONES DE DISPOSITIVOS DE FORMA ASÍNCRONA
    final List<pw.Widget> deviceSections = [];
    for (var entry in groupedEntries.entries) {
      final defId = entry.key;
      final entries = entry.value;
      final deviceDef = deviceDefinitions.firstWhere(
        (d) => d.id == defId,
        orElse: () => DeviceModel(
          id: defId,
          name: 'Desconocido',
          description: '',
          activities: [],
        ),
      );

      final section = await _buildDeviceSection(
        deviceDef: deviceDef,
        entries: entries,
        report: report,
        technicians: technicians,
        font: font,
        fontBold: fontBold,
      );
      
      deviceSections.add(section);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(14.4),
        build: (context) => [
          _buildHeader(
            companySettings: companySettings,
            client: client,
            report: report,
            periodLabel: periodLabel,
            frequencies: frequencies,
            companyLogo: companyLogo,
            clientLogo: clientLogo,
            fontBold: fontBold,
            font: font,
          ),
          pw.SizedBox(height: 8),
          _buildInfoBar(
            report: report,
            technicians: technicians,
            font: font,
            fontBold: fontBold,
          ),
          pw.SizedBox(height: 8),
          
          // ✅ INSERTAR SECCIONES PRE-GENERADAS
          ...deviceSections,

          if (_hasGeneralFindings(report))
            _buildGeneralFindings(report, font: font, fontBold: fontBold),
          
          _buildObservationsAndSummary(
            report: report,
            stats: stats,
            font: font,
            fontBold: fontBold,
          ),
          
          _buildSignatures(
            report: report,
            providerSignature: providerSignature,
            clientSignature: clientSignature,
            font: font,
            fontBold: fontBold,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ==================== BUILDERS ====================

  static pw.Widget _buildHeader({
    required CompanySettingsModel companySettings,
    required ClientModel client,
    required ServiceReportModel report,
    required String periodLabel,
    required String frequencies,
    pw.MemoryImage? companyLogo,
    pw.MemoryImage? clientLogo,
    required pw.Font fontBold,
    required pw.Font font,
  }) {
    final executionDate = DateFormat(
      'dd MMM yyyy',
      'es',
    ).format(report.serviceDate).toUpperCase();

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          // FILA SUPERIOR: Proveedor | Título | Cliente
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 1.5),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // --- CAMBIAR EL PRIMER EXPANDED (PROVEEDOR) POR ESTO ---
                pw.Expanded(
                  flex: 28,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(right: pw.BorderSide(color: PdfColors.grey400)),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // AQUI ESTA EL LOGO DE LA EMPRESA
                        if (companyLogo != null)
                          pw.Container(
                            width: 35,
                            height: 35,
                            margin: const pw.EdgeInsets.only(right: 6),
                            child: pw.Image(companyLogo, fit: pw.BoxFit.contain),
                          ),
                        
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(companySettings.name, style: pw.TextStyle(font: fontBold, fontSize: 7)),
                              pw.SizedBox(height: 1),
                              pw.Text(companySettings.legalName, style: pw.TextStyle(font: font, fontSize: 6)),
                              pw.Text(companySettings.address, style: pw.TextStyle(font: font, fontSize: 6, color: PdfColors.grey700)),
                              pw.Text(companySettings.phone, style: pw.TextStyle(font: fontBold, fontSize: 6)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // TÍTULO CENTRAL (44%)
                pw.Expanded(
                  flex: 44,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 10),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'REPORTE DE SERVICIO',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.black,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'SISTEMA DE DETECCIÓN DE INCENDIOS',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 6,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.grey200,
                            borderRadius: pw.BorderRadius.circular(3),
                            border: pw.Border.all(color: PdfColors.grey400),
                          ),
                          child: pw.Text(
                            'EJECUCIÓN: $executionDate  |  PERIODO: ${periodLabel.toUpperCase()}',
                            style: pw.TextStyle(font: fontBold, fontSize: 6),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Frecuencias: $frequencies',
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 5,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // CLIENTE (28%)
                pw.Expanded(
                  flex: 28,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(color: PdfColors.grey400),
                      ),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                client.name,
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 7,
                                  color: PdfColors.black,
                                ),
                              ),
                              pw.SizedBox(height: 1),
                              pw.Text(
                                'Atn: ${client.contact}',
                                style: pw.TextStyle(font: font, fontSize: 6),
                              ),
                              pw.Text(
                                client.address,
                                style: pw.TextStyle(
                                  font: font,
                                  fontSize: 6,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 4),
                        if (clientLogo != null)
                          pw.Container(
                            width: 35,
                            height: 35,
                            child: pw.Image(clientLogo, fit: pw.BoxFit.contain),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoBar({
    required ServiceReportModel report,
    required List<UserModel> technicians,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    final staffNames = report.assignedTechnicianIds
        .map(
          (id) => technicians
              .firstWhere(
                (u) => u.id == id,
                orElse: () => UserModel(id: id, name: 'Desconocido', email: ''),
              )
              .name,
        )
        .join(', ');

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(2),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'FECHA: ',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 6,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                DateFormat('dd/MM/yyyy').format(report.serviceDate),
                style: pw.TextStyle(font: font, fontSize: 6),
              ),
              pw.SizedBox(width: 15),
              pw.Text(
                'HORARIO: ',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 6,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                '${report.startTime ?? '--:--'} - ${report.endTime ?? '--:--'}',
                style: pw.TextStyle(font: font, fontSize: 6),
              ),
            ],
          ),
          pw.Row(
            children: [
              pw.Text(
                'PERSONAL DESIGNADO: ',
                style: pw.TextStyle(font: fontBold, fontSize: 6),
              ),
              pw.Text(
                staffNames.isEmpty ? 'N/A' : staffNames,
                style: pw.TextStyle(font: font, fontSize: 6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<pw.Widget> _buildDeviceSection({
    required DeviceModel deviceDef,
    required List<ReportEntry> entries,
    required ServiceReportModel report,
    required List<UserModel> technicians,
    required pw.Font font,
    required pw.Font fontBold,
  }) async {
    final sectionTechIds = report.sectionAssignments[deviceDef.id] ?? [];
    final sectionTechNames = sectionTechIds
        .map((id) => technicians.firstWhere(
              (u) => u.id == id,
              orElse: () => UserModel(id: id, name: id, email: ''),
            ).name)
        .join(', ');

    final scheduledActivityIds = entries.expand((e) => e.results.keys).toSet().toList();
    final relevantActivities = deviceDef.activities
        .where((a) => scheduledActivityIds.contains(a.id))
        .toList();

    if (relevantActivities.isEmpty) return pw.SizedBox();

    final isListView = deviceDef.viewMode == 'list';

    return pw.Column(
      children: [
        // CABECERA
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey800,
            border: const pw.Border(
              top: pw.BorderSide(color: PdfColors.black),
              left: pw.BorderSide(color: PdfColors.black),
              right: pw.BorderSide(color: PdfColors.black),
              bottom: pw.BorderSide(color: PdfColors.black),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    deviceDef.name.toUpperCase(),
                    style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Text(
                    '(${entries.length} U.)',
                    style: pw.TextStyle(font: font, fontSize: 6, color: PdfColors.grey400),
                  ),
                ],
              ),
              pw.Text(
                'RESPONSABLES: ${sectionTechNames.isEmpty ? "General" : sectionTechNames}',
                style: pw.TextStyle(font: font, fontSize: 5, color: PdfColors.white),
              ),
            ],
          ),
        ),

        // ✅ CONTENIDO ASÍNCRONO
        if (!isListView)
          await _buildTableView(
            entries: entries,
            activities: relevantActivities,
            font: font,
            fontBold: fontBold,
          )
        else
          await _buildListView(
            entries: entries,
            activities: relevantActivities,
            font: font,
            fontBold: fontBold,
          ),

        pw.SizedBox(height: 12),
      ],
    );
  }

  static Future<pw.Widget> _buildTableView({
    required List<ReportEntry> entries,
    required List<ActivityConfig> activities,
    required pw.Font font,
    required pw.Font fontBold,
  }) async {
    final double activityColWidth = activities.length > 8 ? 25.0 : 38.0;

    // ✅ DESCARGAR FOTOS DE TODAS LAS ENTRADAS
    final Map<int, pw.Widget> photoGalleries = {};
    for (int i = 0; i < entries.length; i++) {
      photoGalleries[i] = await _buildPhotoGallery(entries[i].photoUrls);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(2),
        ...Map.fromIterable(
          List.generate(activities.length, (i) => i + 2),
          key: (i) => i,
          value: (_) => pw.FixedColumnWidth(activityColWidth),
        ),
      },
      children: [
        // HEADER ROW
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _tableCell('ID', fontBold, 6, align: pw.Alignment.center),
            _tableCell('UBICACIÓN', fontBold, 6),
            ...activities.map((act) {
              return pw.Container(
                padding: const pw.EdgeInsets.all(2),
                child: pw.Column(
                  children: [
                    pw.Text(
                      act.name,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: fontBold, fontSize: 5),
                      maxLines: 2,
                      overflow: pw.TextOverflow.clip,
                    ),
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 1),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                      child: pw.Text(
                        act.frequency.toString().split('.').last.substring(0, 1),
                        style: pw.TextStyle(font: font, fontSize: 4),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),

        // DATA ROWS
        ...entries.asMap().entries.map((entryMap) {
          final index = entryMap.key;
          final entry = entryMap.value;
          
          return pw.TableRow(
            children: [
              _tableCell(entry.customId, fontBold, 6, align: pw.Alignment.center),
              
              // ✅ UBICACIÓN + FOTOS
              pw.Container(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(entry.area, style: pw.TextStyle(font: font, fontSize: 6)),
                    photoGalleries[index] ?? pw.SizedBox(),
                  ],
                ),
              ),

              ...activities.map((act) {
                final status = entry.results[act.id];
                return _buildStatusCell(status, font);
              }),
            ],
          );
        }),
      ],
    );
  }

  static Future<pw.Widget> _buildListView({
    required List<ReportEntry> entries,
    required List<ActivityConfig> activities,
    required pw.Font font,
    required pw.Font fontBold,
  }) async {
    
    // 1. PREPARAR GALERÍAS (Esto ya lo tenías bien, lo dejamos igual)
    final Map<String, pw.Widget> activityPhotoGalleries = {};

    for (var entry in entries) {
      for (var act in activities) {
        final actData = entry.activityData[act.id];
        if (actData != null && actData.photoUrls.isNotEmpty) {
          final key = '${entry.instanceId}_${act.id}';
          // Generamos la galería asíncronamente aquí
          activityPhotoGalleries[key] = await _buildPhotoGallery(actData.photoUrls);
        }
      }
    }

    return pw.Wrap(
      spacing: 0,
      runSpacing: 0,
      children: entries.map((entry) {
        return pw.Container(
          width: 190,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Card
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: PdfColors.grey200,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      entry.customId,
                      style: pw.TextStyle(font: fontBold, fontSize: 6),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        entry.area,
                        style: pw.TextStyle(font: font, fontSize: 5, color: PdfColors.grey600),
                        textAlign: pw.TextAlign.right,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                  ],
                ),
              ),

              // Actividades
              ...activities.map((act) {
                final status = entry.results[act.id];
                if (status == null) return pw.SizedBox();

                final actData = entry.activityData[act.id];
                final actObs = actData?.observations ?? '';
                
                // CLAVE: Usamos la clave única para recuperar la galería generada previamente
                final galleryKey = '${entry.instanceId}_${act.id}';
                final photoWidget = activityPhotoGalleries[galleryKey]; 

                String statusText = '';
                PdfColor statusColor = PdfColors.black;

                switch (status) {
                  case 'OK': statusText = 'OK'; break;
                  case 'NOK': statusText = 'FALLA'; statusColor = PdfColors.red; break;
                  case 'NA': statusText = 'N/A'; statusColor = PdfColors.grey600; break;
                  case 'NR': statusText = 'N/R'; statusColor = PdfColors.orange; break;
                }

                return pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
                  ),
                  child: pw.Column(
                    children: [
                      // Nombre y estado
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        color: PdfColors.grey50,
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Row(
                              children: [
                                pw.Text(act.name, style: pw.TextStyle(font: fontBold, fontSize: 5)),
                                pw.SizedBox(width: 3),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(color: PdfColors.grey400),
                                    borderRadius: pw.BorderRadius.circular(2),
                                  ),
                                  child: pw.Text(
                                    act.frequency.toString().split('.').last,
                                    style: pw.TextStyle(font: font, fontSize: 4, color: PdfColors.grey600),
                                  ),
                                ),
                              ],
                            ),
                            pw.Text(statusText, style: pw.TextStyle(font: fontBold, fontSize: 6, color: statusColor)),
                          ],
                        ),
                      ),

                      // Fotos y observaciones
                      if (photoWidget != null || actObs.isNotEmpty) // Verificamos si hay widget de foto
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(2),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              // ✅ FOTOS CORREGIDAS: Usamos el widget pre-generado
                              pw.Expanded(
                                child: photoWidget ?? pw.Text('Sin fotos', style: pw.TextStyle(font: font, fontSize: 5, color: PdfColors.grey400)),
                              ),

                              // Observaciones
                              pw.Expanded(
                                child: actObs.isNotEmpty
                                    ? pw.Text(
                                        actObs,
                                        style: pw.TextStyle(font: font, fontSize: 5, fontStyle: pw.FontStyle.italic),
                                        maxLines: 3,
                                        overflow: pw.TextOverflow.clip,
                                      )
                                    : pw.Text('Sin obs.', style: pw.TextStyle(font: font, fontSize: 5, color: PdfColors.grey400)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }

  static pw.Widget _buildGeneralFindings(
    ServiceReportModel report, {
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    final entriesWithObs = report.entries
        .where((e) => e.observations.trim().isNotEmpty)
        .toList();

    if (entriesWithObs.isEmpty) return pw.SizedBox();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            color: PdfColors.grey800,
            child: pw.Text(
              'Hallazgos Generales (Modo Tabla)',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 7,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(60),
              1: const pw.FlexColumnWidth(),
            },
            children: entriesWithObs.map((e) {
              return pw.TableRow(
                children: [
                  _tableCell(e.customId, fontBold, 6),
                  _tableCell(e.observations, font, 6),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildObservationsAndSummary({
    required ServiceReportModel report,
    required Map<String, int> stats,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Observaciones generales
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Observaciones Generales',
                  style: pw.TextStyle(font: fontBold, fontSize: 6),
                ),
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 2, bottom: 2),
                  height: 0.5,
                  color: PdfColors.grey300,
                ),
                pw.Text(
                  report.generalObservations.isEmpty
                      ? 'Sin observaciones generales.'
                      : report.generalObservations,
                  style: pw.TextStyle(font: font, fontSize: 6),
                ),
              ],
            ),
          ),
        ),

        pw.SizedBox(width: 10),

        // Resumen
        pw.Expanded(
          flex: 1,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'Resumen',
                  style: pw.TextStyle(font: fontBold, fontSize: 6),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 2),
                  height: 0.5,
                  color: PdfColors.grey300,
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn('OK', stats['ok']!, fontBold, font),
                    _buildStatColumn(
                      'FALLA',
                      stats['nok']!,
                      fontBold,
                      font,
                      color: PdfColors.red,
                    ),
                    _buildStatColumn('N/A', stats['na']!, fontBold, font),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSignatures({
    required ServiceReportModel report,
    pw.MemoryImage? providerSignature,
    pw.MemoryImage? clientSignature,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        children: [
          // Firma Proveedor
          pw.Expanded(
            child: pw.Container(
              height: 70,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black),
              ),
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    top: 2,
                    left: 4,
                    child: pw.Text(
                      'Nombre y Firma del Responsable (Proveedor)',
                      style: pw.TextStyle(font: fontBold, fontSize: 5),
                    ),
                  ),
                  pw.Center(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        if (providerSignature != null)
                          pw.Container(
                            height: 35,
                            child: pw.Image(providerSignature),
                          )
                        else
                          pw.SizedBox(height: 35),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 5, bottom: 5),
                          width: 150,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              top: pw.BorderSide(color: PdfColors.grey400),
                            ),
                          ),
                          child: pw.Text(
                            report.providerSignerName ?? '',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: fontBold, fontSize: 6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          pw.SizedBox(width: 15),

          // Firma Cliente
          pw.Expanded(
            child: pw.Container(
              height: 70,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black),
              ),
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    top: 2,
                    left: 4,
                    child: pw.Text(
                      'Nombre y Firma del Responsable (Cliente)',
                      style: pw.TextStyle(font: fontBold, fontSize: 5),
                    ),
                  ),
                  pw.Center(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        if (clientSignature != null)
                          pw.Container(
                            height: 35,
                            child: pw.Image(clientSignature),
                          )
                        else
                          pw.SizedBox(height: 35),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 5, bottom: 5),
                          width: 150,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              top: pw.BorderSide(color: PdfColors.grey400),
                            ),
                          ),
                          child: pw.Text(
                            report.clientSignerName ?? '',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(font: fontBold, fontSize: 6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================

  static pw.Widget _tableCell(
    String text,
    pw.Font font,
    double fontSize, {
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(2),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: fontSize),
      ),
    );
  }

  static pw.Widget _buildStatusCell(String? status, pw.Font font) {
    if (status == null) return pw.SizedBox();

    if (status == 'OK') {
      return pw.Container(
        padding: const pw.EdgeInsets.all(2),
        alignment: pw.Alignment.center,
        child: pw.Container(
          width: 4,
          height: 4,
          decoration: const pw.BoxDecoration(
            color: PdfColors.black,
            shape: pw.BoxShape.circle,
          ),
        ),
      );
    } else if (status == 'NOK') {
      return pw.Container(
        padding: const pw.EdgeInsets.all(2),
        alignment: pw.Alignment.center,
        child: pw.Text(
          'X',
          style: pw.TextStyle(
            font: font,
            fontSize: 7,
            color: PdfColors.red,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    } else {
      return pw.Container(
        padding: const pw.EdgeInsets.all(2),
        alignment: pw.Alignment.center,
        child: pw.Text(status, style: pw.TextStyle(font: font, fontSize: 5)),
      );
    }
  }

  // Nuevo Helper para mostrar minigalería de fotos
  // ==================== NUEVO HELPER PARA DESCARGAR FOTOS ====================
  static Future<pw.ImageProvider?> _downloadPhoto(String photoUrl) async {
    try {
      if (photoUrl.startsWith('http')) {
        // Opción A: Descargar bytes manualmente (Más seguro y robusto)
        final response = await http.get(Uri.parse(photoUrl));
        if (response.statusCode == 200) {
          return pw.MemoryImage(response.bodyBytes);
        }
        return null;
      } else if (photoUrl.contains('base64,')) {
        final base64String = photoUrl.split('base64,').last;
        return pw.MemoryImage(base64Decode(base64String));
      } else {
        return pw.MemoryImage(base64Decode(photoUrl));
      }
    } catch (e) {
      print('❌ Error descargando foto: $e');
      return null;
    }
  }

  static Future<pw.Widget> _buildPhotoGallery(List<String> photos) async {
    if (photos.isEmpty) return pw.SizedBox();

    // ✅ DESCARGAR TODAS LAS FOTOS PRIMERO
    final List<pw.MemoryImage?> downloadedPhotos = [];
    
    for (final photoUrl in photos) {
      final image = await _downloadPhoto(photoUrl);
      downloadedPhotos.add(image as pw.MemoryImage?);
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 2),
      child: pw.Wrap(
        spacing: 2,
        runSpacing: 2,
        children: downloadedPhotos.asMap().entries.map((entry) {
          // ignore: unused_local_variable
          final index = entry.key;
          final photoImage = entry.value;
          
          if (photoImage == null) {
            // ⚠️ Foto no se pudo descargar
            return pw.Container(
              width: 25,
              height: 25,
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(2),
              ),
              child: pw.Center(
                child: pw.Text('!', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red)),
              ),
            );
          }

          return pw.Container(
            width: 25,
            height: 25,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.ClipRRect(
              horizontalRadius: 2,
              verticalRadius: 2,
              child: pw.Image(
                photoImage,
                fit: pw.BoxFit.cover,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _buildStatColumn(
    String label,
    int value,
    pw.Font fontBold,
    pw.Font font, {
    PdfColor color = PdfColors.black,
  }) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: fontBold, fontSize: 5, color: color),
        ),
        pw.Text(
          value.toString(),
          style: pw.TextStyle(font: fontBold, fontSize: 8, color: color),
        ),
      ],
    );
  }

  static String _getPeriodLabel(String dateStr) {
    if (dateStr.contains('W')) {
      return 'Semana $dateStr';
    } else {
      try {
        final date = DateFormat('yyyy-MM').parse('$dateStr-01');
        final month = DateFormat('MMMM yyyy', 'es').format(date);
        return "${month[0].toUpperCase()}${month.substring(1)}";
      } catch (e) {
        return dateStr;
      }
    }
  }

  static String _getInvolvedFrequencies(
    ServiceReportModel report,
    List<DeviceModel> deviceDefinitions,
  ) {
    final frequencies = <String>{};

    for (var entry in report.entries) {
      final activityIds = entry.results.keys;
      for (var defId in deviceDefinitions.map((d) => d.id)) {
        final def = deviceDefinitions.firstWhere((d) => d.id == defId);
        final acts = def.activities.where((a) => activityIds.contains(a.id));
        for (var act in acts) {
          frequencies.add(act.frequency.toString().split('.').last);
        }
      }
    }

    return frequencies.join(', ');
  }

  static Map<String, int> _calculateStats(ServiceReportModel report) {
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

  static Map<String, List<ReportEntry>> _groupEntries(
    ServiceReportModel report,
    List<DeviceModel> deviceDefinitions,
    List<PolicyDevice> policyDevices, // <--- Recibe la lista aquí
  ) {
    final grouped = <String, List<ReportEntry>>{};

    for (var entry in report.entries) {
      try {
        // LÓGICA DE VINCULACIÓN:
        // Buscamos en la póliza qué 'definitionId' corresponde a este 'instanceId'
        final policyDev = policyDevices.firstWhere(
          (pd) => pd.instanceId == entry.instanceId,
        );

        final defId = policyDev.definitionId;

        // Inicializamos la lista si es la primera vez que vemos este tipo de equipo
        if (!grouped.containsKey(defId)) {
          grouped[defId] = [];
        }

        // Agregamos la entrada a su grupo
        grouped[defId]!.add(entry);
      } catch (e) {
        print(
          'Advertencia: No se encontró definición para el dispositivo ${entry.instanceId}',
        );
      }
    }

    return grouped;
  }

  static bool _hasGeneralFindings(ServiceReportModel report) {
    return report.entries.any((e) => e.observations.trim().isNotEmpty);
  }
}
