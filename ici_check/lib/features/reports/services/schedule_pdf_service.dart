import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// IMPORTA TUS MODELOS
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';
import 'package:printing/printing.dart';

class SchedulePdfService {
  // COLORES CORPORATIVOS (Estilo Tailwind)
  static const PdfColor colorSlate50 = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor colorSlate100 = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor colorSlate200 = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor colorSlate400 = PdfColor.fromInt(0xFF94A3B8);
  static const PdfColor colorSlate500 = PdfColor.fromInt(0xFF64748B);
  static const PdfColor colorSlate800 = PdfColor.fromInt(0xFF1E293B);
  
  static const PdfColor colorSky400 = PdfColor.fromInt(0xFF38BDF8);   // Inspección
  static const PdfColor colorAmber400 = PdfColor.fromInt(0xFFFBBF24); // Prueba
  static const PdfColor colorRose400 = PdfColor.fromInt(0xFFFB7185);  // Mantenimiento

  static Future<Uint8List> generateSchedule({
    required PolicyModel policy,
    required ClientModel client,
    required CompanySettingsModel companySettings,
    required List<DeviceModel> deviceDefinitions,
    required List<Map<String, dynamic>> reports,
    required String viewMode, // 'monthly' o 'weekly'
  }) async {
    final pdf = pw.Document();
    
    // Formato Legal Horizontal para dar más espacio ancho
    final pageFormat = PdfPageFormat.legal.landscape; 
    
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontBlack = await PdfGoogleFonts.robotoBlack();

    // 1. Preparar todas las columnas de tiempo
    int totalColumns = viewMode == 'monthly' 
        ? policy.durationMonths 
        : policy.durationMonths * 4; // Aprox 4 semanas por mes

    // Usamos una lógica mejorada para calcular semanas exactas como en tu React
    List<_TimeColumnData> allColumns = _calculateColumnsData(policy, totalColumns, viewMode);

    // 2. Lógica de "Slicing" (Paginación Horizontal)
    // En React usas 12 para semanal y 18 para mensual. Usaremos lo mismo.
    final int columnsPerSlice = viewMode == 'weekly' ? 12 : 18;
    final int totalSlices = (allColumns.length / columnsPerSlice).ceil();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(30),
        build: (context) {
          final List<pw.Widget> content = [];

          // HEADER PRINCIPAL
          content.add(_buildMainHeader(client, policy, companySettings, viewMode, font, fontBold, fontBlack));
          content.add(pw.SizedBox(height: 20));

          // GENERAR TABLAS POR "REBANADAS"
          for (int s = 0; s < totalSlices; s++) {
            final int start = s * columnsPerSlice;
            final int end = (start + columnsPerSlice < allColumns.length) 
                ? start + columnsPerSlice 
                : allColumns.length;
            
            final sliceColumns = allColumns.sublist(start, end);

            // Agregar la tabla de este segmento
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

            // Espacio entre tablas si hay más de una
            if (s < totalSlices - 1) {
              content.add(pw.SizedBox(height: 20)); 
            }
          }

          // LEYENDA AL FINAL
          content.add(pw.SizedBox(height: 15));
          content.add(_buildLegend(font, fontBold));

          return content;
        },
      ),
    );

    return pdf.save();
  }

  // --- 1. HEADER PRINCIPAL ---
  static pw.Widget _buildMainHeader(
    ClientModel client, 
    PolicyModel policy, 
    CompanySettingsModel company,
    String viewMode, 
    pw.Font font, 
    pw.Font fontBold,
    pw.Font fontBlack,
  ) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    
    // Logo Widget
    pw.Widget logoWidget = pw.SizedBox(width: 50, height: 50);
    if (company.logoUrl.isNotEmpty && !company.logoUrl.startsWith('http')) {
       try {
         logoWidget = pw.Image(pw.MemoryImage(base64Decode(company.logoUrl)), width: 50, height: 50, fit: pw.BoxFit.contain);
       } catch (_) {}
    }

    // Client Logo
    pw.Widget clientLogoWidget = pw.SizedBox(width: 50, height: 50);
    if (client.logoUrl.isNotEmpty && !client.logoUrl.startsWith('http')) {
       try {
         clientLogoWidget = pw.Image(pw.MemoryImage(base64Decode(client.logoUrl)), width: 50, height: 50, fit: pw.BoxFit.contain);
       } catch (_) {}
    }

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.5)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // PROVEEDOR
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

          // TÍTULO CENTRAL
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

          // CLIENTE
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
    );
  }

  // --- 2. TABLA POR FRAGMENTOS (SLICE) ---
  static pw.Widget _buildScheduleSliceTable({
    required PolicyModel policy,
    required List<DeviceModel> deviceDefinitions,
    required List<Map<String, dynamic>> reports,
    required List<_TimeColumnData> sliceColumns,
    required int startIndex, // Índice global para cálculos matemáticos
    required String viewMode,
    required pw.Font font,
    required pw.Font fontBold,
  }) {
    // Definir anchos de columna
    final Map<int, pw.TableColumnWidth> colWidths = {
      0: const pw.FixedColumnWidth(140), // Columna de nombres más ancha
    };
    for(int i=0; i<sliceColumns.length; i++) {
      colWidths[i+1] = const pw.FlexColumnWidth(1);
    }

    return pw.Table(
      border: pw.TableBorder.all(color: colorSlate200, width: 0.5),
      columnWidths: colWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        // 2.1 HEADER ROW (Fechas)
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
                  // Top Label (Mes)
                  if (col.topLabel.isNotEmpty)
                    pw.Text(col.topLabel, style: pw.TextStyle(font: fontBold, fontSize: 6, color: colorSlate400)),
                  // Main Label (S1 o ENE)
                  pw.Text(col.labelMain, style: pw.TextStyle(font: fontBold, fontSize: 8, color: colorSlate800)),
                  // Sub Label (Días o Año)
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

        // 2.2 FILAS DE DATOS
        ...policy.devices.expand((devInstance) {
          final def = deviceDefinitions.firstWhere(
            (d) => d.id == devInstance.definitionId,
            orElse: () => DeviceModel(id: '?', name: 'Desconocido', description: '', activities: [])
          );

          // Filtro de Actividades (Lógica React)
          final visibleActivities = def.activities.where((act) {
            if (viewMode == 'monthly') return act.frequency != Frequency.SEMANAL;
            // En vista semanal, React muestra SOLO las semanales.
            return act.frequency == Frequency.SEMANAL;
          }).toList();

          // Si no hay actividades visibles y estamos en semanal, no mostramos el dispositivo
          if (visibleActivities.isEmpty && viewMode == 'weekly') return <pw.TableRow>[];

          List<pw.TableRow> rows = [];

          // HEADER DE DISPOSITIVO
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
              // Celdas vacías
              ...List.generate(sliceColumns.length, (_) => pw.Container(height: 18, color: const PdfColor(0.97, 0.98, 0.99))), 
            ],
          ));

          // FILAS DE ACTIVIDAD
          for (var activity in visibleActivities) {
            final PdfColor typeColor = _getActivityColor(activity.type);
            
            rows.add(pw.TableRow(
              children: [
                // Columna Nombre Actividad
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

                // Celdas de Tiempo (Puntos)
                ...List.generate(sliceColumns.length, (index) {
                  final globalTimeIdx = startIndex + index;
                  
                  // 1. ¿Está programado matemáticamente?
                  bool isScheduled = _isScheduledHelper(devInstance, activity.id, globalTimeIdx, viewMode, deviceDefinitions);
                  
                  if (!isScheduled) return pw.Container();

                  // 2. Calcular Estado (Lógica React "getActivityState")
                  String status = 'EMPTY';
                  final dateKey = sliceColumns[index].dateKey;
                  
                  final reportMap = reports.cast<Map<String, dynamic>?>().firstWhere(
                    (r) => r?['dateStr'] == dateKey, orElse: () => null
                  );

                  if (reportMap != null) {
                    // Si existe reporte, verificar entradas
                    if (reportMap['entries'] != null) {
                      final entries = reportMap['entries'] as List;
                      final relevantEntries = entries.where((e) => e['instanceId'] == devInstance.instanceId).toList();
                      
                      if (relevantEntries.isNotEmpty) {
                        // Lógica: Si hay resultados válidos (OK/NOK/NA)
                        // Para simplificar en PDF: Si encontramos al menos 1 respuesta -> COMPLETE o PARTIAL
                        bool hasResponse = false;
                        for(var entry in relevantEntries) {
                           final res = entry['results']?[activity.id];
                           if (res == 'OK' || res == 'NOK' || res == 'NA') {
                             hasResponse = true;
                             break;
                           }
                        }
                        status = hasResponse ? 'COMPLETE' : 'PARTIAL';
                      } else {
                        // Reporte creado pero sin entradas para este dispositivo
                        status = 'PARTIAL'; 
                      }
                    } else {
                      status = 'PARTIAL';
                    }
                  }

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

  // --- 3. HELPER VISUAL (Círculos Idénticos a React) ---
  static pw.Widget _buildStatusCircle(ActivityType type, String status) {
    final PdfColor color = _getActivityColor(type);

    if (status == 'COMPLETE') {
      // LLENO (Color sólido)
      return pw.Container(
        width: 8, height: 8,
        decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
      );
    } else if (status == 'PARTIAL') {
      // PARCIAL (React: `bg-slate-200` o degradado)
      // Usaremos un gris claro de fondo con borde de color
      return pw.Container(
        width: 8, height: 8,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: colorSlate200, // Fondo grisáceo
          border: pw.Border.all(color: color, width: 1.5), // Borde de color de la actividad
        ),
      );
    } else {
      // VACÍO (React: border-slate-300 bg-white)
      return pw.Container(
        width: 8, height: 8,
        decoration: pw.BoxDecoration(
          shape: pw.BoxShape.circle,
          color: PdfColors.white,
          border: pw.Border.all(color: colorSlate200, width: 1.5),
        ),
      );
    }
  }

  // --- 4. LEYENDA (Footer) ---
  static pw.Widget _buildLegend(pw.Font font, pw.Font fontBold) {
    return pw.Container(
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
    );
  }

  static pw.Widget _legendDot(PdfColor color, String label, pw.Font font) {
    return pw.Row(children: [
      pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle, border: pw.Border.all(color: color))),
      pw.SizedBox(width: 4),
      pw.Text(label, style: pw.TextStyle(font: font, fontSize: 7, color: colorSlate500, fontWeight: pw.FontWeight.bold)),
    ]);
  }

  static pw.Widget _legendStatus(String status, String label, pw.Font font) {
    // Usamos gris para los ejemplos de estado
    return pw.Row(children: [
      // Simulamos el círculo usando color gris genérico para la leyenda
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

  // --- LÓGICA AUXILIAR ---

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
      // ignore: unused_local_variable
      bool hasScheduledDay = false; // (Mantenemos la variable por compatibilidad con tu clase)

      if (viewMode == 'monthly') {
        // Lógica Mensual (Esta estaba bien, pero asegúrate que coincida con tu pantalla)
        date = DateTime(policy.startDate.year, policy.startDate.month + i, 1);
        labelMain = DateFormat('MMM', 'es').format(date).toUpperCase().replaceAll('.', '');
        labelSub = DateFormat('yy', 'es').format(date);
        dateKey = DateFormat('yyyy-MM').format(date);
      } else {
        // --- LÓGICA SEMANAL CORREGIDA ---
        date = policy.startDate.add(Duration(days: i * 7));
        DateTime endDate = date.add(const Duration(days: 6));
        
        // ERROR ANTERIOR: Usabas _getWeekNumber(date) y padLeft.
        // CORRECCIÓN: Usar el índice 'i + 1' tal cual lo hace SchedulerScreen.
        // Esto asegura que si guardaste el reporte de la primera columna como "2025-W1",
        // aquí busquemos exactamente "2025-W1".
        
        dateKey = "${date.year}-W${i + 1}"; 

        // Etiquetas visuales
        topLabel = DateFormat('MMM', 'es').format(date).toUpperCase().replaceAll('.', '');
        labelMain = "S${i + 1}"; // Visualmente también mostramos Semana 1, 2... relativas
        
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
    // ... (Tu misma lógica matemática de antes) ...
    try {
      final def = defs.firstWhere((d) => d.id == devInstance.definitionId);
      final activity = def.activities.firstWhere((a) => a.id == activityId);

      double freqMonths = 0;
      switch (activity.frequency) {
        case Frequency.SEMANAL: freqMonths = 0.25; break;
        case Frequency.MENSUAL: freqMonths = 1.0; break;
        case Frequency.TRIMESTRAL: freqMonths = 3.0; break;
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
  // --- HELPER PARA CALCULAR SEMANA (Sin usar intl 'w') ---
}

class _TimeColumnData {
  final String labelMain;
  final String labelSub;
  final String topLabel;
  final String dateKey;
  final bool hasScheduledDay;
  _TimeColumnData(this.labelMain, this.labelSub, this.topLabel, this.dateKey, this.hasScheduledDay);
}