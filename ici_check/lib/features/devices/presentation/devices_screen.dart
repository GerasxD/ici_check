import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle; 
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart'; 
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/device_model.dart';
import '../data/devices_repository.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final DevicesRepository _repo = DevicesRepository();
  final _uuid = const Uuid();

  DeviceModel? _selectedDevice;
  bool _isEditing = false;
  bool _isLoading = false;
  String _searchQuery = ''; // Nuevo: Para el buscador

  // Paleta de Colores Profesional
  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _accentBlue = const Color(0xFF2563EB);
  final Color _bgLight = const Color(0xFFF8FAFC);
  final Color _textSlate = const Color(0xFF64748B);

  // --- ACCIONES ---
  void _handleCreate() {
    setState(() {
      _selectedDevice = DeviceModel(id: 'temp', name: '', description: '', activities: []);
      _isEditing = true;
    });
  }

  void _handleEdit(DeviceModel device) {
    setState(() {
      _selectedDevice = DeviceModel(
        id: device.id,
        name: device.name,
        description: device.description,
        viewMode: device.viewMode,
        activities: device.activities.map((a) => ActivityConfig(
          id: a.id, name: a.name, type: a.type, frequency: a.frequency, expectedValue: a.expectedValue
        )).toList(),
      );
      _isEditing = true;
    });
  }

  void _handleSave() async {
    if (_selectedDevice == null || _selectedDevice!.name.isEmpty) {
      _showSnack('El nombre es obligatorio', Colors.orange);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _repo.saveDevice(_selectedDevice!);
      _closeEditor();
      if(mounted) _showSnack('Guardado correctamente', Colors.green.shade700);
    } catch (e) {
      if(mounted) _showSnack('Error al guardar', Colors.red);
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  void _handleDelete(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Dispositivo?'),
        content: const Text('Esta acción borrará toda la configuración y el historial asociado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      )
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      await _repo.deleteDevice(id);
      if (_selectedDevice?.id == id) _closeEditor();
      setState(() => _isLoading = false);
    }
  }

  void _closeEditor() {
    setState(() {
      _selectedDevice = null;
      _isEditing = false;
    });
  }

  // --- HELPERS DE PARSEO ---
  ActivityType _parseActivityType(String val) {
    val = val.toLowerCase().trim();
    if (val.contains('inspecc') || val.contains('inspección')) return ActivityType.INSPECCION;
    if (val.contains('mantenim') || val.contains('limpieza')) return ActivityType.MANTENIMIENTO;
    if (val.contains('prueba') || val.contains('prueba')) return ActivityType.PRUEBA; 
    return ActivityType.MANTENIMIENTO; 
  }

  Frequency _parseFrequency(String val) {
    val = val.toLowerCase().trim();
    if (val.contains('diari')) return Frequency.DIARIO;
    if (val.contains('seman')) return Frequency.SEMANAL;
    if (val.contains('mensual')) return Frequency.MENSUAL;
    if (val.contains('trimest')) return Frequency.TRIMESTRAL;
    if (val.contains('semest')) return Frequency.SEMESTRAL;
    if (val.contains('anual')) return Frequency.ANUAL;
    return Frequency.MENSUAL; 
  }

  // --- IMPORTAR EXCEL ---
  Future<void> _handleImportExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true, 
      );

      if (result != null) {
        setState(() => _isLoading = true);
        
        Uint8List? fileBytes = result.files.single.bytes;
        if (fileBytes == null && !kIsWeb && result.files.single.path != null) {
          fileBytes = await File(result.files.single.path!).readAsBytes();
        }

        if (fileBytes == null) throw Exception("No se pudo leer el archivo");

        var decoder = SpreadsheetDecoder.decodeBytes(fileBytes);
        Map<String, DeviceModel> importedMap = {};

        for (var table in decoder.tables.keys) {
          var sheet = decoder.tables[table];
          if (sheet == null) continue;

          for (int i = 1; i < sheet.rows.length; i++) {
            var row = sheet.rows[i];
            
            String getCell(int idx) {
              if (idx >= row.length) return "";
              return row[idx]?.toString() ?? "";
            }

            String devName = getCell(0);
            if (devName.trim().isEmpty) continue;

            if (!importedMap.containsKey(devName)) {
              importedMap[devName] = DeviceModel(
                id: _uuid.v4(),
                name: devName,
                description: getCell(1),
                viewMode: getCell(2).toLowerCase().contains('list') ? 'list' : 'table',
                activities: []
              );
            }

            String actName = getCell(3);
            if (actName.isNotEmpty) {
              importedMap[devName]!.activities.add(ActivityConfig(
                id: _uuid.v4(),
                name: actName,
                type: _parseActivityType(getCell(4)),
                frequency: _parseFrequency(getCell(5)),
                expectedValue: getCell(6)
              ));
            }
          }
        }

        WriteBatch batch = FirebaseFirestore.instance.batch();
        int opCount = 0;
        final collection = FirebaseFirestore.instance.collection('devices');

        for (var dev in importedMap.values) {
          var docRef = collection.doc();
          dev.id = docRef.id;
          batch.set(docRef, dev.toMap());
          opCount++;

          if (opCount >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            opCount = 0;
          }
        }
        if (opCount > 0) await batch.commit();

        if(mounted) _showSnack('Importación exitosa: ${importedMap.length} equipos.', Colors.green);
      }
    } catch (e) {
      debugPrint("Error Import: $e");
      if(mounted) _showSnack('Error al importar. Verifica el formato.', Colors.red);
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  // --- EXPORTAR EXCEL ---
  Future<void> _handleExportExcel(List<DeviceModel> devices) async {
    try {
      var excel = Excel.createExcel();
      String sheetName = 'Dispositivos';
      if (excel.sheets.containsKey('Sheet1')) excel.rename('Sheet1', sheetName);
      
      Sheet sheet = excel[sheetName];
      sheet.appendRow(["Dispositivo", "Descripción", "Vista Reporte", "Actividad", "Tipo", "Frecuencia", "Valor Referencia"].map((e) => TextCellValue(e)).toList());

      for (var dev in devices) {
        if (dev.activities.isEmpty) {
          sheet.appendRow([TextCellValue(dev.name), TextCellValue(dev.description), TextCellValue(dev.viewMode), TextCellValue(""), TextCellValue(""), TextCellValue(""), TextCellValue("")]);
        } else {
          for (var act in dev.activities) {
            sheet.appendRow([
              TextCellValue(dev.name), 
              TextCellValue(dev.description), 
              TextCellValue(dev.viewMode),
              TextCellValue(act.name), 
              TextCellValue(act.type.toString().split('.').last), 
              TextCellValue(act.frequency.toString().split('.').last), 
              TextCellValue(act.expectedValue),
            ]);
          }
        }
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        if (kIsWeb) {
           _showSnack('Archivo generado (Descarga Web no implementada)', Colors.blue);
        } else {
           final directory = await getApplicationDocumentsDirectory();
           final path = '${directory.path}/Configuracion_Dispositivos.xlsx';
           File(path)
             ..createSync(recursive: true)
             ..writeAsBytesSync(fileBytes);
           await Share.shareXFiles([XFile(path)], text: 'Configuración ICI-CHECK');
        }
      }
    } catch (e) {
      _showSnack('Error exportando: $e', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)), 
      backgroundColor: color, 
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // --- UI HELPERS ---
  void _addActivity() {
    if (_selectedDevice == null) return;
    setState(() {
      _selectedDevice!.activities.add(ActivityConfig(id: _uuid.v4(), name: '', type: ActivityType.MANTENIMIENTO, frequency: Frequency.MENSUAL));
    });
  }

  void _removeActivity(int index) {
    setState(() {
      _selectedDevice!.activities.removeAt(index);
    });
  }

  // Filtrar dispositivos
  List<DeviceModel> _filterDevices(List<DeviceModel> allDevices) {
    if (_searchQuery.isEmpty) return allDevices;
    return allDevices.where((d) => 
      d.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
      d.description.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    // LOADING OVERLAY
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF1E40AF)),
              const SizedBox(height: 24),
              Text("Procesando datos...", style: TextStyle(color: _primaryDark, fontSize: 16, fontWeight: FontWeight.w600))
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isLargeScreen = constraints.maxWidth > 900;

        // MODO MÓVIL EDITOR (Pantalla Completa)
        if (!isLargeScreen && _isEditing) {
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) { if (!didPop) _closeEditor(); },
            child: Scaffold(
              backgroundColor: _bgLight,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black87), onPressed: _closeEditor),
                title: Text(_selectedDevice?.id == 'temp' ? 'Nuevo Dispositivo' : 'Editar Dispositivo', style: TextStyle(color: _primaryDark, fontWeight: FontWeight.bold)),
                actions: [
                  TextButton(
                    onPressed: _handleSave, 
                    child: Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold, color: _accentBlue))
                  )
                ],
              ),
              body: _buildEditorForm(isMobile: true),
            ),
          );
        }

        // VISTA PRINCIPAL
        return Scaffold(
          backgroundColor: _bgLight,
          body: Row(
            children: [
              // --- COLUMNA IZQUIERDA: LISTA ---
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _buildHeader(isLargeScreen), // Header con Buscador
                    Expanded(
                      child: StreamBuilder<List<DeviceModel>>(
                        stream: _repo.getDevicesStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          
                          final allDevices = snapshot.data ?? [];
                          final devices = _filterDevices(allDevices); // Aplicar filtro

                          if (devices.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty ? 'No hay dispositivos registrados' : 'No se encontraron resultados',
                                    style: TextStyle(color: _textSlate)
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final dev = devices[index];
                              return _DeviceProCard(
                                device: dev,
                                isActive: _selectedDevice?.id == dev.id,
                                onTap: () => _handleEdit(dev),
                                onDelete: () => _handleDelete(dev.id),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              // --- COLUMNA DERECHA: EDITOR (Desktop) ---
              if (_isEditing && isLargeScreen)
                Expanded(
                  flex: 6,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0,8))],
                    ),
                    child: Column(
                      children: [
                        // Header del Editor
                        Container(
                          padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _selectedDevice?.id == 'temp' ? 'Nuevo Dispositivo' : 'Editar Dispositivo',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryDark),
                              ),
                              IconButton(onPressed: _closeEditor, icon: const Icon(Icons.close), color: Colors.grey)
                            ],
                          ),
                        ),
                        Expanded(child: _buildEditorForm(isMobile: false)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: (!isLargeScreen) 
            ? FloatingActionButton(
                onPressed: _handleCreate, 
                backgroundColor: _accentBlue, 
                child: const Icon(Icons.add, color: Colors.white)
              ) 
            : null,
        );
      },
    );
  }

 // --- HEADER CON BUSCADOR RESPONSIVE (SOLUCIÓN AL OVERFLOW) ---
  Widget _buildHeader(bool isLargeScreen) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: Título + Botón Crear (ajustable)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Título (flexible para evitar overflow)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inventario de Equipos', 
                      style: TextStyle(
                        fontSize: isLargeScreen ? 24 : 20, 
                        fontWeight: FontWeight.w800, 
                        color: _primaryDark, 
                        letterSpacing: -0.5
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gestiona tipos de dispositivos y mantenimientos', 
                      style: TextStyle(color: _textSlate, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Botón Crear (solo Desktop)
              if (isLargeScreen) ...[
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _handleCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Crear Nuevo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ]
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Fila 2: Buscador + Botones Excel (Responsive)
          if (isLargeScreen)
            // VERSIÓN DESKTOP: Todo en una fila
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Buscar dispositivos...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: _bgLight,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _ActionButton(
                  icon: Icons.upload_file, 
                  label: 'Importar', 
                  onTap: _handleImportExcel,
                  isCompact: false
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.download, 
                  label: 'Exportar', 
                  onTap: () async {
                    final snapshot = await _repo.getDevicesStream().first;
                    _handleExportExcel(snapshot);
                  },
                  isCompact: false
                ),
              ],
            )
          else
            // VERSIÓN MÓVIL: Apilado verticalmente
            Column(
              children: [
                // Buscador (ancho completo)
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar dispositivos...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    filled: true,
                    fillColor: _bgLight,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Botones Excel (fila compacta)
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.upload_file, 
                        label: 'Importar', 
                        onTap: _handleImportExcel,
                        isCompact: true,
                        fullWidth: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.download, 
                        label: 'Exportar', 
                        onTap: () async {
                          final snapshot = await _repo.getDevicesStream().first;
                          _handleExportExcel(snapshot);
                        },
                        isCompact: true,
                        fullWidth: true,
                      ),
                    ),
                  ],
                ),
              ],
            )
        ],
      ),
    );
  }

  // --- FORMULARIO DE EDICIÓN CON KEYS PARA ACTUALIZACIÓN ---
  Widget _buildEditorForm({required bool isMobile}) {
    if (_selectedDevice == null) return const SizedBox();

    // Guardamos el ID para usarlo en las keys
    final String devId = _selectedDevice!.id;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- SECCIÓN 1: DATOS GENERALES ---
                Text('INFORMACIÓN GENERAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _textSlate, letterSpacing: 1.0)),
                const SizedBox(height: 16),
                
                _CustomTextField(
                  key: ValueKey('name_$devId'), // <--- KEY ÚNICA
                  label: 'Nombre del Equipo',
                  hint: 'Ej. Bomba Diesel Principal',
                  initialValue: _selectedDevice!.name,
                  icon: Icons.inventory_2_outlined,
                  onChanged: (v) => _selectedDevice!.name = v,
                ),
                const SizedBox(height: 16),
                
                // Dropdown Vista
                const Text('Formato de Reporte', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: _bgLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: ValueKey('view_$devId'), // <--- KEY ÚNICA
                      value: _selectedDevice!.viewMode,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                      items: const [
                        DropdownMenuItem(value: 'table', child: Row(children: [Icon(Icons.table_chart_outlined, size: 18, color: Colors.grey), SizedBox(width: 8), Text('Vista Tabla')])),
                        DropdownMenuItem(value: 'list', child: Row(children: [Icon(Icons.view_list_outlined, size: 18, color: Colors.grey), SizedBox(width: 8), Text('Vista Lista')])),
                      ],
                      onChanged: (v) => setState(() => _selectedDevice!.viewMode = v!),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                _CustomTextField(
                  key: ValueKey('desc_$devId'), // <--- KEY ÚNICA
                  label: 'Descripción / Notas',
                  hint: 'Especificaciones técnicas...',
                  maxLines: 3,
                  initialValue: _selectedDevice!.description,
                  icon: Icons.notes_outlined,
                  onChanged: (v) => _selectedDevice!.description = v,
                ),

                const SizedBox(height: 32),
                
                // --- SECCIÓN 2: ACTIVIDADES ---
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.0, // Espacio horizontal entre elementos
                  runSpacing: 4.0, // Espacio vertical si baja de línea
                  children: [
                    Text(
                      'CONFIGURACIÓN DE MANTENIMIENTO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _textSlate,
                        letterSpacing: 1.0
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addActivity,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Nueva Actividad'),
                      style: TextButton.styleFrom(foregroundColor: _accentBlue),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                
                if (_selectedDevice!.activities.isEmpty)
                   Container(
                     padding: const EdgeInsets.symmetric(vertical: 40),
                     width: double.infinity,
                     decoration: BoxDecoration(color: _bgLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid)),
                     child: Column(
                       children: [
                         Icon(Icons.playlist_add, color: Colors.grey.shade400, size: 40),
                         const SizedBox(height: 8),
                         Text('No hay actividades configuradas', style: TextStyle(color: Colors.grey.shade500)),
                       ],
                     ),
                   ),

                // Lista de Actividades
                ..._selectedDevice!.activities.asMap().entries.map((entry) {
                  int idx = entry.key;
                  ActivityConfig act = entry.value;
                  // Usamos el ID de la actividad para la key, así no se pierden al reordenar o borrar
                  final String actKey = act.id; 

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))]
                    ),
                    child: Column(
                      children: [
                        // Encabezado
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                              child: Text('#${idx + 1}', style: TextStyle(color: _accentBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _CustomTextField(
                                key: ValueKey('act_name_$actKey'), // <--- KEY ÚNICA POR ACTIVIDAD
                                label: 'Nombre de la Actividad',
                                hint: 'Ej. Revisión de niveles',
                                initialValue: act.name,
                                onChanged: (v) => act.name = v,
                                noIcon: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _removeActivity(idx),
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 22),
                              tooltip: 'Eliminar',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Fila 1: Tipo y Frecuencia
                        Row(
                          children: [
                            Expanded(
                              child: _DropdownEnum<ActivityType>(
                                key: ValueKey('act_type_$actKey'), // <--- KEY ÚNICA
                                label: 'Tipo',
                                value: act.type,
                                values: ActivityType.values,
                                onChanged: (v) => setState(() => act.type = v!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DropdownEnum<Frequency>(
                                key: ValueKey('act_freq_$actKey'), // <--- KEY ÚNICA
                                label: 'Frecuencia',
                                value: act.frequency,
                                values: Frequency.values,
                                onChanged: (v) => setState(() => act.frequency = v!),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Fila 2: Valor de Referencia
                        _CustomTextField(
                          key: ValueKey('act_val_$actKey'), // <--- KEY ÚNICA
                          label: 'Valor de Referencia / Esperado',
                          hint: 'Ej. > 50 PSI, Led encendido, Sin fugas...',
                          initialValue: act.expectedValue,
                          onChanged: (v) => act.expectedValue = v,
                          noIcon: true,
                        ),
                      ],
                    ),
                  );
                }),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        
        // Footer Botones (Solo en Desktop)
        if (!isMobile)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _closeEditor, 
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey))
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _handleSave,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Guardar Cambios'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              ],
            ),
          )
      ],
    );
  }
}

// --- WIDGET AUXILIAR ACTUALIZADO ---
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isCompact;
  final bool fullWidth;

  const _ActionButton({
    required this.icon, 
    required this.label, 
    required this.onTap, 
    this.isCompact = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16, 
          vertical: 12
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade700),
            if (!isCompact || fullWidth) ...[
              const SizedBox(width: 8),
              Text(
                label, 
                style: TextStyle(
                  color: Colors.grey.shade800, 
                  fontWeight: FontWeight.w600, 
                  fontSize: 13
                )
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _DeviceProCard extends StatelessWidget {
  final DeviceModel device;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DeviceProCard({required this.device, required this.isActive, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade50.withOpacity(0.5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? Colors.blue.shade200 : Colors.transparent),
          boxShadow: isActive 
            ? [] 
            : [BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            // Indicador visual lateral
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: isActive ? Colors.blue : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4)
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey.shade900)),
                  const SizedBox(height: 4),
                  Text(
                    device.description.isEmpty ? 'Sin descripción' : device.description, 
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Chips de información
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                        child: Text('${device.activities.length} Actividades', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                      ),
                      const SizedBox(width: 8),
                      if (device.viewMode == 'table')
                        const Icon(Icons.table_chart, size: 14, color: Colors.grey)
                      else
                        const Icon(Icons.list, size: 14, color: Colors.grey)
                    ],
                  )
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade400),
              splashRadius: 20,
            )
          ],
        ),
      ),
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final String initialValue;
  final int maxLines;
  final IconData? icon;
  final Function(String) onChanged;
  final bool noIcon;

  // CAMBIO AQUÍ: Agregamos super.key
  const _CustomTextField({
    // ignore: unused_element_parameter
    super.key, 
    required this.label, 
    this.hint, 
    required this.initialValue, 
    this.maxLines = 1, 
    this.icon, 
    required this.onChanged, 
    // ignore: unused_element_parameter
    this.noIcon = false
  });

  @override
  Widget build(BuildContext context) {
    // ... (El resto del build se queda igual)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (noIcon)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
          ),
        TextFormField(
          initialValue: initialValue, // Ahora sí se actualizará gracias a la Key
          maxLines: maxLines,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: noIcon ? null : label,
            hintText: hint,
            alignLabelWithHint: true,
            prefixIcon: (icon != null) ? Icon(icon, size: 20, color: Colors.grey) : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
          ),
        ),
      ],
    );
  }
}

class _DropdownEnum<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final Function(T?) onChanged;

  // CAMBIO AQUÍ: Agregamos super.key
  const _DropdownEnum({
    super.key, 
    required this.label, 
    required this.value, 
    required this.values, 
    required this.onChanged
  });

  @override
  Widget build(BuildContext context) {
    // ... (El resto del build se queda igual)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey),
              items: values.map((e) => DropdownMenuItem(
                value: e, 
                child: Text(e.toString().split('.').last, style: const TextStyle(fontSize: 13, color: Colors.black87))
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}