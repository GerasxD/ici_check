import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// TUS MODELOS
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';
import 'package:printing/printing.dart';

class SchedulePdfService {
  // COLORES CORPORATIVOS
  static const PdfColor colorSlate50 = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor colorSlate100 = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor colorSlate200 = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor colorSlate400 = PdfColor.fromInt(0xFF94A3B8);
  static const PdfColor colorSlate500 = PdfColor.fromInt(0xFF64748B);
  static const PdfColor colorSlate800 = PdfColor.fromInt(0xFF1E293B);
  
  static const PdfColor colorSky400 = PdfColor.fromInt(0xFF0284C7);   // sky-600
  static const PdfColor colorAmber400 = PdfColor.fromInt(0xFFD97706); // amber-600
  static const PdfColor colorRose400 = PdfColor.fromInt(0xFFE11D48);  // rose-600 

  static Future<Uint8List> generateSchedule({
    required PolicyModel policy,
    required ClientModel client,
    required CompanySettingsModel companySettings,
    required List<DeviceModel> deviceDefinitions,
    required List<Map<String, dynamic>> reports,
    required String viewMode,
  }) async {
    final pdf = pw.Document();
    final pageFormat = PdfPageFormat.legal.landscape; 
    
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontBlack = await PdfGoogleFonts.robotoBlack();

    // --- 1. PRE-CARGA DE IMÁGENES ---
    pw.ImageProvider? companyLogo;
    pw.ImageProvider? clientLogo;

    // A) Cargar Logo de TU Empresa
    if (companySettings.logoUrl.isNotEmpty) {
      try {
        if (companySettings.logoUrl.startsWith('http')) {
          companyLogo = await networkImage(companySettings.logoUrl);
        } else {
          companyLogo = pw.MemoryImage(base64Decode(companySettings.logoUrl));
        }
      } catch (e) {
        print("Error cargando logo empresa: $e");
      }
    }

    // B) Cargar Logo del CLIENTE
    if (client.logoUrl.isNotEmpty) {
      try {
        if (client.logoUrl.startsWith('http')) {
          clientLogo = await networkImage(client.logoUrl);
        } else {
          clientLogo = pw.MemoryImage(base64Decode(client.logoUrl));
        }
      } catch (e) {
        print("Error cargando logo cliente: $e");
      }
    }

    // 2. Calcular columnas
    int totalColumns = viewMode == 'monthly' 
        ? policy.durationMonths 
        : policy.durationMonths * 4;

    List<_TimeColumnData> allColumns = _calculateColumnsData(policy, totalColumns, viewMode);

    // 3. Paginación Horizontal
    final int columnsPerSlice = viewMode == 'weekly' ? 12 : 18;
    final int totalSlices = (allColumns.length / columnsPerSlice).ceil();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(30),
        
        header: (context) => _buildMainHeader(
          client, policy, companySettings, viewMode, 
          font, fontBold, fontBlack,
          companyLogo,
          clientLogo
        ),

        footer: (context) => _buildFooter(context, font, fontBold),

        build: (context) {
          final List<pw.Widget> content = [];

          for (int s = 0; s < totalSlices; s++) {
            if (s > 0) {
              content.add(pw.NewPage());
            }

            final int start = s * columnsPerSlice;
            final int end = (start + columnsPerSlice < allColumns.length) 
                ? start + columnsPerSlice 
                : allColumns.length;
            
            final sliceColumns = allColumns.sublist(start, end);

            content.add(
              _buildScheduleSliceTable(
                policy: policy,
                deviceDefinitions: deviceDefinitions,
                reports: reports,
                sliceColumns: sliceColumns,
                startIndex: start,
                viewMode: viewMode,
                font: font,
                fontBold: fontBold,
              )
            );
          }
          return content;
        },
      ),
    );

    return pdf.save();
  }

  // --- HEADER ---
  static pw.Widget _buildMainHeader(
    ClientModel client, 
    PolicyModel policy, 
    CompanySettingsModel company,
    String viewMode, 
    pw.Font font, 
    pw.Font fontBold,
    pw.Font fontBlack,
    pw.ImageProvider? companyLogoImg,
    pw.ImageProvider? clientLogoImg,
  ) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    
    pw.Widget logoWidget = pw.SizedBox(width: 50, height: 50);
    if (companyLogoImg != null) {
       logoWidget = pw.Image(companyLogoImg, width: 50, height: 50, fit: pw.BoxFit.contain);
    }

    pw.Widget clientLogoWidget = pw.SizedBox(width: 50, height: 50);
    if (clientLogoImg != null) {
       clientLogoWidget = pw.Image(clientLogoImg, width: 50, height: 50, fit: pw.BoxFit.contain);
    }

    return pw.Column(
      children: [
        pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
          ),
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // COLUMNA IZQUIERDA: TU EMPRESA
              pw.Expanded(
                flex: 3,
                child: pw.Row(
                  children: [
                    logoWidget,
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(company.name, style: pw.TextStyle(font: fontBold, fontSize: 10)),
                          pw.Text(company.legalName, style: pw.TextStyle(font: font, fontSize: 8)),
                          pw.Text(company.address, style: pw.TextStyle(font: font, fontSize: 8, color: colorSlate500)),
                          pw.Text(company.phone, style: pw.TextStyle(font: fontBold, fontSize: 8)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // COLUMNA CENTRAL: TÍTULO
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  children: [
                    pw.Text('CRONOGRAMA DE PÓLIZA', style: pw.TextStyle(font: fontBlack, fontSize: 16)),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text('INICIO: ${dateFormat.format(policy.startDate)}', style: pw.TextStyle(font: font, fontSize: 9)),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5),
                          child: pw.Text('|', style: pw.TextStyle(font: font, fontSize: 9)),
                        ),
                        pw.Text('VISTA: ${viewMode == "monthly" ? "MENSUAL" : "SEMANAL"}', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),

              // COLUMNA DERECHA: CLIENTE
              pw.Expanded(
                flex: 3,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(client.name, style: pw.TextStyle(font: fontBold, fontSize: 10), textAlign: pw.TextAlign.right),
                          pw.Text('Atn: ${client.contact}', style: pw.TextStyle(font: font, fontSize: 8), textAlign: pw.TextAlign.right),
                          pw.Text(client.address, style: pw.TextStyle(font: font, fontSize: 8, color: colorSlate500), textAlign: pw.TextAlign.right),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    clientLogoWidget,
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
      ],
    );
  }

  // --- FOOTER ---
  static pw.Widget _buildFooter(pw.Context context, pw.Font font, pw.Font fontBold) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 10),
        
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: colorSlate200),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text('TIPOS:', style: pw.TextStyle(font: fontBold, fontSize: 8, color: colorSlate400)),
              pw.SizedBox(width: 8),
              _legendDot(colorSky400, 'INSPECCIÓN', font),
              pw.SizedBox(width: 8),
              _legendDot(colorAmber400, 'PRUEBA', font),
              pw.SizedBox(width: 8),
              _legendDot(colorRose400, 'MANTENIMIENTO', font),
              
              pw.Container(width: 1, height: 10, color: colorSlate200, margin: const pw.EdgeInsets.symmetric(horizontal: 12)),
              
              pw.Text('ESTADO:', style: pw.TextStyle(font: fontBold, fontSize: 8, color: colorSlate400)),
              pw.SizedBox(width: 8),
              _legendStatus('EMPTY', 'VACÍO', font),
              pw.SizedBox(width: 8),
              _legendStatus('PARTIAL', 'INCOMPLETO', font),
              pw.SizedBox(width: 8),
              _legendStatus('COMPLETE', 'COMPLETO', font),
            ],
          ),
        ),

        pw.SizedBox(height: 5),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: pw.TextStyle(font: font, fontSize: 8, color: colorSlate500),
            ),
          ],
        ),
      ],
    );
  }

  // --- TABLA POR FRAGMENTOS ---
  static pw.Widget _buildScheduleSliceTable({
    required PolicyModel policy,
    required List<DeviceModel> deviceDefinitions,
    required List<Map<String, dynamic>> reports,
    required List<_TimeColumnData> sliceColumns,
    required int startIndex,
    required String viewMode,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    final Map<int, pw.TableColumnWidth> colWidths = {
      0: const pw.FixedColumnWidth(140),
    };
    for(int i=0; i<sliceColumns.length; i++) {
      colWidths[i+1] = const pw.FlexColumnWidth(1);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: colorSlate200, width: 0.5),
      columnWidths: colWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        // HEADER ROW
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: colorSlate50),
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(5),
              alignment: pw.Alignment.centerLeft,
              child: pw.Text('DISPOSITIVO / ACTIVIDAD', style: pw.TextStyle(font: fontBold, fontSize: 8, color: colorSlate400)),
            ),
            ...sliceColumns.map((col) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              alignment: pw.Alignment.center,
              child: pw.Column(
                children: [
                  if (col.topLabel.isNotEmpty)
                    pw.Text(col.topLabel, style: pw.TextStyle(font: fontBold, fontSize: 6, color: colorSlate400)),
                  pw.Text(col.labelMain, style: pw.TextStyle(font: fontBold, fontSize: 8, color: colorSlate800)),
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 1),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: col.hasScheduledDay 
                        ? pw.BoxDecoration(color: PdfColors.blue600, borderRadius: pw.BorderRadius.circular(2))
                        : null,
                    child: pw.Text(
                      col.labelSub, 
                      style: pw.TextStyle(
                        font: fontBold, 
                        fontSize: 6, 
                        color: col.hasScheduledDay ? PdfColors.white : colorSlate400
                      )
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),

        // DATA ROWS
        ...policy.devices.expand((devInstance) {
          final def = deviceDefinitions.firstWhere(
            (d) => d.id == devInstance.definitionId,
            orElse: () => DeviceModel(id: '?', name: 'Desconocido', description: '', activities: [])
          );

          final visibleActivities = def.activities.where((act) {
            bool isWeeklyFreq = act.frequency == Frequency.SEMANAL || 
                                act.frequency == Frequency.QUINCENAL;
            if (viewMode == 'monthly') return !isWeeklyFreq;
            return isWeeklyFreq; // vista semanal muestra SEMANAL y QUINCENAL
          }).toList();

          if (visibleActivities.isEmpty && viewMode == 'weekly') return <pw.TableRow>[];

          List<pw.TableRow> rows = [];

          // Device Header Row
          rows.add(pw.TableRow(
            decoration: const pw.BoxDecoration(color: colorSlate100),
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(def.name.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 7, color: colorSlate800)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Text('x${devInstance.quantity}', style: pw.TextStyle(font: fontBold, fontSize: 6, color: colorSlate500)),
                    ),
                  ],
                ),
              ),
              ...List.generate(sliceColumns.length, (_) => pw.Container(height: 18, color: const PdfColor(0.97, 0.98, 0.99))), 
            ],
          ));

          // Activity Rows
          for (var activity in visibleActivities) {
            final PdfColor typeColor = _getActivityColor(activity.type);
            
            rows.add(pw.TableRow(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.only(left: 10, right: 5, top: 4, bottom: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(right: pw.BorderSide(color: colorSlate200))
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(activity.name, style: pw.TextStyle(font: fontBold, fontSize: 7, color: colorSlate500)),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        children: [
                          pw.Container(width: 4, height: 4, decoration: pw.BoxDecoration(color: typeColor, shape: pw.BoxShape.circle)),
                          pw.SizedBox(width: 4),
                          pw.Text(
                            '${activity.type.toString().split('.').last.toUpperCase()} | ${activity.frequency.toString().split('.').last}', 
                            style: pw.TextStyle(font: font, fontSize: 5, color: colorSlate400)
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ...List.generate(sliceColumns.length, (index) {
                  final globalTimeIdx = startIndex + index;
                  bool isScheduled = _isScheduledHelper(devInstance, activity.id, globalTimeIdx, viewMode, deviceDefinitions);
                  
                  if (!isScheduled) return pw.Container();

                  // ✅ USAR LA LÓGICA MEJORADA PARA DETERMINAR EL ESTADO
                  String status = _getActivityStatusForReport(
                    reports,
                    sliceColumns[index].dateKey,
                    devInstance,
                    activity,
                  );

                  return pw.Container(
                    alignment: pw.Alignment.center,
                    height: 22,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(left: pw.BorderSide(color: colorSlate200, style: pw.BorderStyle.dashed))
                    ),
                    child: _buildStatusCircle(activity.type, status),
                  );
                }),
              ],
            ));
          }

          return rows;
        }),
      ],
    );
  }

  // ✅ NUEVA FUNCIÓN: Lógica idéntica a la del scheduler_screen.dart
  static String _getActivityStatusForReport(
    List<Map<String, dynamic>> reports,
    String dateKey,
    PolicyDevice devInstance,
    ActivityConfig activity,
  ) {
    // Paso 1: Buscar el reporte correspondiente
    Map<String, dynamic>? report;
    try {
      report = reports.firstWhere((r) => r['dateStr'] == dateKey);
    } catch (e) {
      return 'EMPTY'; // No hay reporte
    }

    // Paso 2: Verificar si el servicio fue iniciado
    final String? startTime = report['startTime'] as String?;
    final bool serviceInitiated = startTime != null && startTime.isNotEmpty;
    if (!serviceInitiated) return 'EMPTY';

    // Paso 3: Verificar entries
    if (report['entries'] == null || report['entries'] is! List) {
      return 'PARTIAL';
    }

    final entries = report['entries'] as List;

    // Filtrar TODAS las entradas que corresponden a este tipo de dispositivo
    final entryList = entries
        .where((e) => e['instanceId'] == devInstance.instanceId)
        .toList();

    if (entryList.isEmpty) return 'PARTIAL';

    // ✅ FIX: Contadores para el estado REAL
    int totalWithActivity = 0;
    int answeredCount = 0;

    for (var entry in entryList) {
      if (entry['results'] == null || entry['results'] is! Map) continue;

      final results = entry['results'] as Map;

      // Solo contar si esta actividad existe en los results de esta entrada
      if (!results.containsKey(activity.id)) continue;

      totalWithActivity++;

      final resValue = results[activity.id];

      // Verificación estricta: null y 'NR' NO son respuestas válidas
      if (resValue != null &&
          resValue != 'NR' &&
          (resValue == 'OK' || resValue == 'NOK' || resValue == 'NA')) {
        answeredCount++;
      }
    }

    // Paso 4: Estado basado en contadores
    if (totalWithActivity == 0) return 'PARTIAL';

    if (answeredCount == 0) {
      return 'PARTIAL'; // Ninguna respondida
    } else if (answeredCount == totalWithActivity) {
      return 'COMPLETE'; // ✅ TODAS respondidas → completo
    } else {
      return 'PARTIAL'; // Algunas respondidas → incompleto
    }
  }

  // --- HELPERS VISUALES (Círculos) ---
  static pw.Widget _buildStatusCircle(ActivityType type, String status) {
    final PdfColor color = _getActivityColor(type);
    if (status == 'COMPLETE') {
      return pw.Container(
        width: 8, 
        height: 8, 
        decoration: pw.BoxDecoration(
          color: color, 
          shape: pw.BoxShape.circle
        )
      );
    } else if (status == 'PARTIAL') {
      return pw.Container(
        width: 8, 
        height: 8, 
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle, 
          color: PdfColors.white,  // fondo blanco para que destaque el borde
          border: pw.Border.all(color: color, width: 2.0) 
        )
      );
    } else {
      return pw.Container(
        width: 8, 
        height: 8, 
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle, 
          color: PdfColors.white, 
          border: pw.Border.all(color: colorSlate400, width: 1.5)
        )
      );
    }
  }

  static pw.Widget _legendDot(PdfColor color, String label, pw.Font font) {
    return pw.Row(children: [
      pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle, border: pw.Border.all(color: color))),
      pw.SizedBox(width: 4),
      pw.Text(label, style: pw.TextStyle(font: font, fontSize: 7, color: colorSlate500, fontWeight: pw.FontWeight.bold)),
    ]);
  }

  static pw.Widget _legendStatus(String status, String label, pw.Font font) {
    return pw.Row(children: [
      _buildStatusCircleGeneric(status),
      pw.SizedBox(width: 4),
      pw.Text(label, style: pw.TextStyle(font: font, fontSize: 7, color: colorSlate500, fontWeight: pw.FontWeight.bold)),
    ]);
  }

  static pw.Widget _buildStatusCircleGeneric(String status) {
    if (status == 'COMPLETE') {
      return pw.Container(width: 6, height: 6, decoration: const pw.BoxDecoration(color: colorSlate500, shape: pw.BoxShape.circle));
    } else if (status == 'PARTIAL') {
      return pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(color: colorSlate200, shape: pw.BoxShape.circle, border: pw.Border.all(color: colorSlate400)));
    } else {
      return pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle, border: pw.Border.all(color: colorSlate200)));
    }
  }

  // --- LÓGICA DE NEGOCIO Y CÁLCULOS ---
  static PdfColor _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.INSPECCION: return colorSky400;
      case ActivityType.PRUEBA: return colorAmber400;
      case ActivityType.MANTENIMIENTO: return colorRose400;
    }
  }

  static List<_TimeColumnData> _calculateColumnsData(PolicyModel policy, int count, String viewMode) {
    List<_TimeColumnData> data = [];
    for (int i = 0; i < count; i++) {
      DateTime date;
      String labelMain;
      String labelSub;
      String topLabel = '';
      String dateKey;
      bool hasScheduledDay = false;

      if (viewMode == 'monthly') {
        date = DateTime(policy.startDate.year, policy.startDate.month + i, 1);
        labelMain = DateFormat('MMM', 'es').format(date).toUpperCase().replaceAll('.', '');
        labelSub = DateFormat('yy', 'es').format(date);
        dateKey = DateFormat('yyyy-MM').format(date);
      } else {
        date = policy.startDate.add(Duration(days: i * 7));
        DateTime endDate = date.add(const Duration(days: 6));
        dateKey = "${date.year}-W${i + 1}"; 
        topLabel = DateFormat('MMM', 'es').format(date).toUpperCase().replaceAll('.', '');
        labelMain = "S${i + 1}";
        if (date.month == endDate.month) {
           labelSub = "${date.day}-${endDate.day}";
        } else {
           labelSub = "${date.day}-${endDate.day}/${endDate.month}";
        }
      }
      data.add(_TimeColumnData(labelMain, labelSub, topLabel, dateKey, hasScheduledDay));
    }
    return data;
  }

  static bool _isScheduledHelper(PolicyDevice devInstance, String activityId, int timeIndex, String viewMode, List<DeviceModel> defs) {
    try {
      final def = defs.firstWhere((d) => d.id == devInstance.definitionId);
      final activity = def.activities.firstWhere((a) => a.id == activityId);

      double freqMonths = 0;
      switch (activity.frequency) {
        case Frequency.SEMANAL: freqMonths = 0.25; break;
        case Frequency.QUINCENAL: freqMonths = 0.5; break; // ← AGREGAR
        case Frequency.MENSUAL: freqMonths = 1.0; break;
        case Frequency.TRIMESTRAL: freqMonths = 3.0; break;
        case Frequency.CUATRIMESTRAL: freqMonths = 4.0; break; 
        case Frequency.SEMESTRAL: freqMonths = 6.0; break;
        case Frequency.ANUAL: freqMonths = 12.0; break;
        default: freqMonths = 0;
      }
      if (freqMonths == 0) return false;

      double offset = (devInstance.scheduleOffsets[activityId] ?? 0).toDouble();
      double currentTime = viewMode == 'monthly' ? timeIndex.toDouble() : timeIndex / 4.0;
      double adjustedTime = currentTime - offset;
      
      if (adjustedTime < -0.05) return false;
      double remainder = adjustedTime % freqMonths;
      return remainder < 0.05 || (remainder - freqMonths).abs() < 0.05;
    } catch (e) {
      return false;
    }
  }
}

class _TimeColumnData {
  final String labelMain;
  final String labelSub;
  final String topLabel;
  final String dateKey;
  final bool hasScheduledDay;
  _TimeColumnData(this.labelMain, this.labelSub, this.topLabel, this.dateKey, this.hasScheduledDay);
}