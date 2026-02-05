import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ici_check/features/reports/widgets/device_section_improved.dart';
import 'package:ici_check/features/reports/widgets/report_controls.dart';
import 'package:ici_check/features/reports/widgets/report_header.dart';
import 'package:ici_check/features/reports/widgets/report_signatures.dart';
import 'package:ici_check/features/reports/widgets/report_summary.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';

// Imports de Modelos y Repositorios (Ajusta según tu estructura real)
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';
import 'package:ici_check/features/settings/data/settings_repository.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';

class ServiceReportScreen extends StatefulWidget {
  final String policyId;
  final String dateStr;
  final PolicyModel policy;
  final List<DeviceModel> devices;
  final List<UserModel> users;
  final ClientModel client;

  const ServiceReportScreen({
    super.key,
    required this.policyId,
    required this.dateStr,
    required this.policy,
    required this.devices,
    required this.users,
    required this.client,
  });

  @override
  State<ServiceReportScreen> createState() => _ServiceReportScreenState();
}

class _ServiceReportScreenState extends State<ServiceReportScreen> {
  // Repositorios y Servicios
  final ReportsRepository _repo = ReportsRepository();
  final SettingsRepository _settingsRepo = SettingsRepository();
  final ImagePicker _picker = ImagePicker();
  
  // Estado del Reporte
  ServiceReportModel? _report;
  CompanySettingsModel? _companySettings;
  bool _isLoading = true;
  
  // Estado de la UI
  bool _adminOverride = false;
  String? _currentUserId;
  UserModel? _currentUser;
  
  // Controladores de firma
  final SignatureController _providerSigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );
  final SignatureController _clientSigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );

  // Estados para Modales (Observaciones y Fotos)
  String? _activeObservationEntry; // Guardamos el índice como String para consistencia con tu código anterior
  String? _activeObservationActivityId;
  int? _photoContextEntryIdx;
  String? _photoContextActivityId;

  // Colores (Para usarlos en los modales internos si es necesario)
  final Color _bgLight = const Color(0xFFF8FAFC);
  final Color _primaryDark = const Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _providerSigController.dispose();
    _clientSigController.dispose();
    super.dispose();
  }

  // ==========================================
  // CARGA DE DATOS E INICIALIZACIÓN
  // ==========================================

  Future<void> _loadData() async {
    try {
      final companyData = await _settingsRepo.getSettings();
      final storedUserId = await _getCurrentUserId();
      
      UserModel? currentU;
      if (storedUserId != null && widget.users.isNotEmpty) {
        currentU = widget.users.firstWhere(
          (u) => u.id == storedUserId,
          orElse: () => widget.users.first,
        );
      }

      final stream = _repo.getReportStream(widget.policyId, widget.dateStr);
      stream.listen((existingReport) {
        if (existingReport != null) {
          if (mounted) {
            setState(() {
              _report = existingReport;
              _isLoading = false;
              _loadSignatures();
            });
          }
        } else {
          _initializeNewReport();
        }
      });

      if (mounted) {
        setState(() {
          _companySettings = companyData;
          _currentUserId = storedUserId;
          _currentUser = currentU;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _getCurrentUserId() async {
    // Aquí iría tu lógica real de sesión
    // Por ahora retornamos el primer usuario de la lista si existe para probar
    if (widget.users.isNotEmpty) return widget.users.first.id;
    return null; 
  }

  void _loadSignatures() {
    if (_report?.providerSignature != null && _report!.providerSignature!.isNotEmpty) {
      try {
         // Si necesitaras visualizar la firma guardada en el canvas, la lógica iría aquí.
         // Nota: SignatureController no soporta cargar imagen base64 fácilmente para editar,
         // normalmente se muestra una imagen estática si ya existe firma.
      } catch (e) {
        debugPrint('Error loading provider signature: $e');
      }
    }
    // Idem para cliente
  }

  void _initializeNewReport() {
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = 0;

    if (!isWeekly) {
      DateTime pStart = DateTime(widget.policy.startDate.year, widget.policy.startDate.month, 1);
      try {
        DateTime rDate = DateFormat('yyyy-MM').parse(widget.dateStr);
        timeIndex = (rDate.year - pStart.year) * 12 + (rDate.month - pStart.month);
      } catch (e) {
        debugPrint("Error parsing date: $e");
      }
    } else {
      timeIndex = int.tryParse(widget.dateStr.split('W').last) ?? 0;
    }

    final newReport = _repo.initializeReport(
      widget.policy,
      widget.dateStr,
      widget.devices,
      isWeekly,
      timeIndex,
    );

    _repo.saveReport(newReport);
    if (mounted) {
      setState(() {
        _report = newReport;
        _isLoading = false;
      });
    }
  }

  // ==========================================
  // LÓGICA DE NEGOCIO (Guardar, Actualizar)
  // ==========================================

  Future<void> _saveReport() async {
    if (_report == null) return;

    try {
      String? providerSigBase64 = _report!.providerSignature;
      String? clientSigBase64 = _report!.clientSignature;

      if (_providerSigController.isNotEmpty) {
        final bytes = await _providerSigController.toPngBytes();
        if (bytes != null) providerSigBase64 = base64Encode(bytes);
      }

      if (_clientSigController.isNotEmpty) {
        final bytes = await _clientSigController.toPngBytes();
        if (bytes != null) clientSigBase64 = base64Encode(bytes);
      }

      final updatedReport = _report!.copyWith(
        providerSignature: providerSigBase64,
        clientSignature: clientSigBase64,
      );

      setState(() {
        _report = updatedReport;
      });

      await _repo.saveReport(_report!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reporte guardado exitosamente'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _updateEntry(int index, {
    String? customId,
    String? area,
    Map<String, String?>? results,
    String? observations,
    List<String>? photos,
    Map<String, ActivityData>? activityData,
  }) {
    if (_report == null) return;

    final entries = List<ReportEntry>.from(_report!.entries);
    final entry = entries[index];

    entries[index] = ReportEntry(
      instanceId: entry.instanceId,
      deviceIndex: entry.deviceIndex,
      customId: customId ?? entry.customId,
      area: area ?? entry.area,
      results: results ?? entry.results,
      observations: observations ?? entry.observations,
      photos: photos ?? entry.photos,
      activityData: activityData ?? entry.activityData,
    );

    final updatedReport = _report!.copyWith(entries: entries);
    
    setState(() {
      _report = updatedReport;
    });

    _repo.saveReport(_report!);
  }

  void _toggleStatus(int entryIndex, String activityId, String defId) {
    if (_report == null || !_canEditSection(defId)) return;

    final entry = _report!.entries[entryIndex];
    if (!entry.results.containsKey(activityId)) return;

    String? current = entry.results[activityId];
    String? next;

    // Ciclo de estados: null -> OK -> NOK -> NA -> NR -> null
    if (current == null) next = 'OK';
    else if (current == 'OK') next = 'NOK';
    else if (current == 'NOK') next = 'NA';
    else if (current == 'NA') next = 'NR';
    else next = null;

    final newResults = Map<String, String?>.from(entry.results);
    newResults[activityId] = next;

    _updateEntry(entryIndex, results: newResults);
  }

  void _toggleSectionAssignment(String defId, String userId) {
    if (_report == null) return;

    final currentAssignments = _report!.sectionAssignments[defId] ?? [];
    List<String> newAssignments;

    if (currentAssignments.contains(userId)) {
      newAssignments = currentAssignments.where((id) => id != userId).toList();
    } else {
      newAssignments = [...currentAssignments, userId];
    }

    final newSectionAssignments = Map<String, List<String>>.from(_report!.sectionAssignments);
    newSectionAssignments[defId] = newAssignments;

    final updatedReport = _report!.copyWith(sectionAssignments: newSectionAssignments);
    setState(() {
      _report = updatedReport;
    });
    _repo.saveReport(_report!);
  }

  // ==========================================
  // CONTROL DE TIEMPOS Y PERMISOS
  // ==========================================

  bool _canEditSection(String defId) {
    if (!_isEditable()) return false;
    if (_isUserCoordinator() && _adminOverride) return true;
    final assigned = _report?.sectionAssignments[defId] ?? [];
    return _currentUserId != null && assigned.contains(_currentUserId);
  }

  bool _isEditable() {
    if (_report == null) return false;
    if (_adminOverride) return true;
    return _report!.startTime != null && _report!.endTime == null;
  }

  bool _isUserCoordinator() {
    if (_currentUser == null) return false;
    return _currentUser!.role == UserRole.SUPER_USER ||
        _currentUser!.role == UserRole.ADMIN ||
        widget.policy.assignedUserIds.contains(_currentUserId);
  }

  bool _areAllSectionsAssigned() {
    if (_report == null) return false;

    // 1. Identificar qué secciones (Definition IDs) tienen trabajo activo.
    // Usamos un Set para evitar duplicados (solo queremos los IDs únicos de las secciones).
    final activeDefIds = <String>{};

    for (var entry in _report!.entries) {
      // Solo consideramos una sección como "activa" si sus entradas tienen 
      // actividades programadas (es decir, el mapa 'results' no está vacío).
      // Si un dispositivo no tiene mantenimiento este mes, no obliga a asignar técnico.
      if (entry.results.isNotEmpty) {
        try {
          // Buscamos la instancia del dispositivo en la póliza para obtener su definitionId
          final deviceInstance = widget.policy.devices.firstWhere(
            (d) => d.instanceId == entry.instanceId,
          );
          
          activeDefIds.add(deviceInstance.definitionId);
        } catch (e) {
          debugPrint('Advertencia: Dispositivo ${entry.instanceId} no encontrado en la póliza.');
        }
      }
    }

    // 2. Verificar en el mapa de asignaciones si esas secciones tienen gente.
    for (var defId in activeDefIds) {
      final assignedTechnicians = _report!.sectionAssignments[defId];
      
      // Si la lista es nula o está vacía, fallamos la validación.
      if (assignedTechnicians == null || assignedTechnicians.isEmpty) {
        return false; 
      }
    }

    // Si pasamos el ciclo sin retornar false, es que todo está asignado.
    return true;
  }

  void _handleStartService() {
    // 1. Validación básica de estado y usuario
    if (_report == null || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar un usuario para registrar tiempos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 2. NUEVA VALIDACIÓN: Verificar asignaciones
    // Si NO (! negación) están todas las secciones asignadas, entramos al if
    if (!_areAllSectionsAssigned()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se puede iniciar: Hay tipos de dispositivos sin responsable asignado.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red, // Rojo para indicar error bloqueante
          duration: Duration(seconds: 3),
        ),
      );
      return; // <--- IMPORTANTE: Detenemos la ejecución aquí.
    }

    // 3. Si pasó las validaciones, procedemos a guardar la hora
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    
    // Usamos el copyWith que agregamos al modelo
    final updatedReport = _report!.copyWith(startTime: timeStr);

    setState(() {
      _report = updatedReport;
    });

    _repo.saveReport(_report!);
  }

  void _handleEndService() {
    if (_report == null) return;
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    final updatedReport = _report!.copyWith(endTime: timeStr);
    
    setState(() {
      _report = updatedReport;
    });
    _repo.saveReport(_report!);
  }
  
  void _handleResumeService() {
      // Lógica simple para reanudar si es necesario
      // Podrías mostrar el diálogo de cambio de fecha aquí si lo deseas
      setState(() {
        _report = _report!.copyWith(
          endTime: null, 
          forceNullEndTime: true // <--- Agrega esto para forzar que sea null
        ); 
      });
      _repo.saveReport(_report!);
  }

  // ==========================================
  // MANEJO DE FOTOS
  // ==========================================

  Future<void> _handleCameraClick(int entryIdx, {String? activityId}) async {
    if (_report == null) return;

    final entry = _report!.entries[entryIdx];
    List<String> existingPhotos;

    if (activityId != null) {
      existingPhotos = entry.activityData[activityId]?.photos ?? [];
    } else {
      existingPhotos = entry.photos;
    }

    if (existingPhotos.isNotEmpty) {
      setState(() {
        _photoContextEntryIdx = entryIdx;
        _photoContextActivityId = activityId;
      });
    } else {
      setState(() {
        _photoContextEntryIdx = entryIdx;
        _photoContextActivityId = activityId;
      });
      _pickImage();
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (image != null && _photoContextEntryIdx != null && _report != null) {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);

        final entryIdx = _photoContextEntryIdx!;
        final activityId = _photoContextActivityId;
        final entry = _report!.entries[entryIdx];

        if (activityId != null) {
          final currentData = entry.activityData[activityId] ?? ActivityData(photos: [], observations: '');
          final newPhotos = [...currentData.photos, base64Image];
          final newActivityData = Map<String, ActivityData>.from(entry.activityData);
          newActivityData[activityId] = ActivityData(
            photos: newPhotos,
            observations: currentData.observations,
          );
          _updateEntry(entryIdx, activityData: newActivityData);
        } else {
          final newPhotos = [...entry.photos, base64Image];
          _updateEntry(entryIdx, photos: newPhotos);
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _deletePhoto(int photoIndex) {
    if (_photoContextEntryIdx == null || _report == null) return;
    _confirmDeletePhoto(photoIndex); // Podrías poner el showDialog aquí
  }

  void _confirmDeletePhoto(int photoIndex) {
    final entryIdx = _photoContextEntryIdx!;
    final activityId = _photoContextActivityId;
    final entry = _report!.entries[entryIdx];

    if (activityId != null) {
      final currentData = entry.activityData[activityId];
      if (currentData != null) {
        final newPhotos = List<String>.from(currentData.photos);
        newPhotos.removeAt(photoIndex);
        final newActivityData = Map<String, ActivityData>.from(entry.activityData);
        newActivityData[activityId] = ActivityData(photos: newPhotos, observations: currentData.observations);
        _updateEntry(entryIdx, activityData: newActivityData);
        if (newPhotos.isEmpty) {
          setState(() { _photoContextEntryIdx = null; _photoContextActivityId = null; });
        }
      }
    } else {
      final newPhotos = List<String>.from(entry.photos);
      newPhotos.removeAt(photoIndex);
      _updateEntry(entryIdx, photos: newPhotos);
      if (newPhotos.isEmpty) {
        setState(() { _photoContextEntryIdx = null; _photoContextActivityId = null; });
      }
    }
  }

  // ==========================================
  // HELPERS DE UI
  // ==========================================

  Map<String, List<ReportEntry>> _groupEntries() {
    if (_report == null) return {};
    final grouped = <String, List<ReportEntry>>{};
    for (var entry in _report!.entries) {
      final deviceInstance = widget.policy.devices.firstWhere((d) => d.instanceId == entry.instanceId);
      final defId = deviceInstance.definitionId;
      if (!grouped.containsKey(defId)) grouped[defId] = [];
      grouped[defId]!.add(entry);
    }
    return grouped;
  }

  String _getFrequencies(Map<String, List<ReportEntry>> grouped) {
    // Tu lógica original para obtener frecuencias
    return "Mensual"; // Simplificado para el ejemplo
  }

  // ==========================================
  // BUILD PRINCIPAL
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _report == null || _companySettings == null) {
      return Scaffold(
        backgroundColor: _bgLight,
        body: Center(child: CircularProgressIndicator(color: _primaryDark)),
      );
    }

    final groupedEntries = _groupEntries();
    final frequencies = _getFrequencies(groupedEntries);

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: _primaryDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reporte de Servicio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
            Text(widget.dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          if (_isUserCoordinator())
            IconButton(
              icon: Icon(_adminOverride ? Icons.lock_open : Icons.lock, color: _adminOverride ? Colors.amber : Colors.grey),
              onPressed: () => setState(() => _adminOverride = !_adminOverride),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. CABECERA
            ReportHeader(
              companySettings: _companySettings!,
              client: widget.client,
              serviceDate: _report!.serviceDate,
              dateStr: widget.dateStr,
              frequencies: frequencies,
            ),

            // 2. CONTROLES (Iniciar/Fin/Asignación)
            ReportControls(
              report: _report!,
              users: widget.users,
              adminOverride: _adminOverride,
              isUserDesignated: _report!.assignedTechnicianIds.contains(_currentUserId),
              onStartService: _handleStartService,
              onEndService: _handleEndService,
              onResumeService: _handleResumeService,
              onDateChanged: (newDate) {
                final updated = _report!.copyWith(serviceDate: newDate);
                setState(() => _report = updated);
                _repo.saveReport(_report!);
              },
            ),

            // 3. SECCIONES DE DISPOSITIVOS (Tablas/Listas)
            ...groupedEntries.entries.map((entryGroup) {
              final defId = entryGroup.key;
              final sectionEntries = entryGroup.value;
              
              final deviceDef = widget.devices.firstWhere(
                (d) => d.id == defId,
                orElse: () => DeviceModel(id: defId, name: 'Desconocido', description: '', activities: []),
              );

              return DeviceSectionImproved(
                defId: defId,
                deviceDef: deviceDef,
                entries: sectionEntries,
                users: widget.users,
                sectionAssignments: _report!.sectionAssignments[defId] ?? [],
                isEditable: _isEditable(),
                allowedToEdit: _canEditSection(defId),
                isUserCoordinator: _isUserCoordinator(),
                currentUserId: _currentUserId,
                
                // CALLBACKS IMPORTANTE: Mapeo de índices locales a globales
                onToggleAssignment: (uid) => _toggleSectionAssignment(defId, uid),
                
                onCustomIdChanged: (localIndex, val) {
                   final entry = sectionEntries[localIndex];
                   final globalIndex = _report!.entries.indexOf(entry);
                   if(globalIndex != -1) _updateEntry(globalIndex, customId: val);
                },
                
                onAreaChanged: (localIndex, val) {
                   final entry = sectionEntries[localIndex];
                   final globalIndex = _report!.entries.indexOf(entry);
                   if(globalIndex != -1) _updateEntry(globalIndex, area: val);
                },
                
                onToggleStatus: (localIndex, activityId) {
                   final entry = sectionEntries[localIndex];
                   final globalIndex = _report!.entries.indexOf(entry);
                   if(globalIndex != -1) _toggleStatus(globalIndex, activityId, defId);
                },
                
                onCameraClick: (localIndex, {activityId}) {
                   final entry = sectionEntries[localIndex];
                   final globalIndex = _report!.entries.indexOf(entry);
                   if(globalIndex != -1) _handleCameraClick(globalIndex, activityId: activityId);
                },
                
                onObservationClick: (localIndex, {activityId}) {
                   final entry = sectionEntries[localIndex];
                   final globalIndex = _report!.entries.indexOf(entry);
                   if(globalIndex != -1) {
                     setState(() {
                       _activeObservationEntry = globalIndex.toString();
                       _activeObservationActivityId = activityId;
                     });
                   }
                },
              );
            }),

            // 4. OBSERVACIONES GENERALES
            _buildGeneralObservationsBox(),
            ReportSummary(report: _report!),

            // 5. FIRMAS
            ReportSignatures(
              providerController: _providerSigController,
              clientController: _clientSigController,
              providerName: _report!.providerSignerName,
              clientName: _report!.clientSignerName,
              isEditable: _isEditable(),
              onProviderNameChanged: (val) {
                 final updated = _report!.copyWith(providerSignerName: val);
                 setState(() => _report = updated);
                 _repo.saveReport(_report!);
              },
              onClientNameChanged: (val) {
                 final updated = _report!.copyWith(clientSignerName: val);
                 setState(() => _report = updated);
                 _repo.saveReport(_report!);
              },
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
      
      // BOTÓN FLOTANTE
      floatingActionButton: (_activeObservationEntry == null && _photoContextEntryIdx == null && _isEditable() && (_report!.assignedTechnicianIds.contains(_currentUserId) || _adminOverride))
          ? FloatingActionButton.extended(
              onPressed: _saveReport,
              backgroundColor: Colors.green,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            )
          : null,
      
      // MODALES (Se muestran sobre el contenido si los estados no son nulos)
      bottomSheet: _activeObservationEntry != null 
          ? _buildObservationModal() 
          : (_photoContextEntryIdx != null ? _buildPhotoModal() : null),
    );
  }

  // ==========================================
  // WIDGETS INTERNOS (Modales y Obs Generales)
  // ==========================================
  
  // Widget simple para Observaciones Generales que quedó fuera de los widgets extraídos
  Widget _buildGeneralObservationsBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OBSERVACIONES GENERALES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            enabled: _isEditable(),
            controller: TextEditingController(text: _report!.generalObservations), // Nota: Esto recrea el controller en cada build, idealmente usar uno persistente o onChanged directo
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Comentarios generales del servicio...',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
               // Pequeña optimización: no guardar en cada caracter, usar debounce en producción
               final updated = _report!.copyWith(generalObservations: val);
               // No hacemos setState aquí para no reconstruir todo el árbol mientras escribe
               _report = updated; 
               _repo.saveReport(_report!);
            },
          ),
        ],
      ),
    );
  }

  // Modal de Observaciones (Copiado y adaptado para funcionar con el nuevo stack)
  Widget _buildObservationModal() {
    if (_activeObservationEntry == null) return const SizedBox();
    
    final entryIdx = int.parse(_activeObservationEntry!);
    final entry = _report!.entries[entryIdx];
    
    String currentObservation;
    String title;

    if (_activeObservationActivityId != null) {
      currentObservation = entry.activityData[_activeObservationActivityId]?.observations ?? '';
      title = 'Observación de Actividad';
    } else {
      currentObservation = entry.observations;
      title = '${entry.customId} - Observaciones';
    }

    // Usamos un Controller local para el modal
    final textController = TextEditingController(text: currentObservation);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _activeObservationEntry = null; _activeObservationActivityId = null; })),
            ],
          ),
          TextField(
            controller: textController,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _primaryDark, foregroundColor: Colors.white),
            onPressed: () {
              if (_activeObservationActivityId != null) {
                final currentData = entry.activityData[_activeObservationActivityId!] ?? ActivityData(photos: [], observations: '');
                final newActivityData = Map<String, ActivityData>.from(entry.activityData);
                newActivityData[_activeObservationActivityId!] = ActivityData(photos: currentData.photos, observations: textController.text);
                _updateEntry(entryIdx, activityData: newActivityData);
              } else {
                _updateEntry(entryIdx, observations: textController.text);
              }
              setState(() { _activeObservationEntry = null; _activeObservationActivityId = null; });
            },
            child: const Text('Guardar Observación'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Modal de Fotos
  Widget _buildPhotoModal() {
    if (_photoContextEntryIdx == null) return const SizedBox();
    final entry = _report!.entries[_photoContextEntryIdx!];
    
    List<String> photos;
    if (_photoContextActivityId != null) {
      photos = entry.activityData[_photoContextActivityId]?.photos ?? [];
    } else {
      photos = entry.photos;
    }

    return Container(
      height: 400,
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gestión de Fotos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _photoContextEntryIdx = null; _photoContextActivityId = null; })),
            ],
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: photos.length + 1,
              itemBuilder: (ctx, idx) {
                if (idx == photos.length) {
                  return InkWell(
                    onTap: _pickImage,
                    child: Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.add_a_photo, color: Colors.grey),
                    ),
                  );
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(base64Decode(photos[idx]), fit: BoxFit.cover),
                    Positioned(
                      top: 0, right: 0,
                      child: Container(
                        color: Colors.black54,
                        child: InkWell(
                          onTap: () => _deletePhoto(idx),
                          child: const Icon(Icons.delete, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
