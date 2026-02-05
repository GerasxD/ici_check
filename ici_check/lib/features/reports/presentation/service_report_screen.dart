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
    if (assigned.isEmpty) return true; 
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
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E293B), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reporte de Servicio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
                letterSpacing: -0.3,
              ),
            ),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  widget.dateStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_report!.startTime != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _report!.endTime == null
                          ? const Color(0xFF10B981).withOpacity(0.1)
                          : const Color(0xFF64748B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _report!.endTime == null ? Icons.play_circle : Icons.check_circle,
                          size: 10,
                          color: _report!.endTime == null
                              ? const Color(0xFF10B981)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _report!.endTime == null ? 'En curso' : 'Finalizado',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: _report!.endTime == null
                                ? const Color(0xFF10B981)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          if (_isUserCoordinator())
            IconButton(
              icon: Icon(
                _adminOverride ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                color: _adminOverride ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                size: 22,
              ),
              onPressed: () => setState(() => _adminOverride = !_adminOverride),
              tooltip: _adminOverride ? 'Modo Admin Activo' : 'Activar Modo Admin',
            ),
          const SizedBox(width: 8),
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
                  allowedToEdit: _isEditable(), // <--- CAMBIO AQUÍ: Permitir ver controles si el reporte está abierto
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
                providerSignatureData: _report!.providerSignature, // Base64 desde Firebase
                clientSignatureData: _report!.clientSignature,
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
        floatingActionButton: (_activeObservationEntry == null && 
          _photoContextEntryIdx == null && 
          _isEditable() && 
          (_report!.assignedTechnicianIds.contains(_currentUserId) || _adminOverride))
          ? FloatingActionButton.extended(
              onPressed: _saveReport,
              backgroundColor: const Color(0xFF10B981),
              elevation: 4,
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text(
                'Guardar Cambios',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
              ),
            )
          : null,
      
      bottomSheet: _activeObservationEntry != null 
          ? _buildObservationModal() 
          : (_photoContextEntryIdx != null ? _buildPhotoModal() : null),
    );
  }

  List<Map<String, String>> _getRegisteredFindings() {
    final List<Map<String, String>> findings = [];
    if (_report == null) return findings;

    for (final entry in _report!.entries) {
      List<String> deviceFindingsTexts = [];

      // 1. Revisar observación general del dispositivo
      if (entry.observations.trim().isNotEmpty) {
        deviceFindingsTexts.add(entry.observations.trim());
      }

      // 2. Revisar observaciones de cada actividad dentro del dispositivo
      for (var actData in entry.activityData.values) {
        if (actData.observations.trim().isNotEmpty) {
          // Opcional: Podrías prefijar el nombre de la actividad si lo tuvieras disponible aquí
          deviceFindingsTexts.add(actData.observations.trim());
        }
      }

      // Si encontramos hallazgos para este dispositivo, los agregamos a la lista principal
      if (deviceFindingsTexts.isNotEmpty) {
        // Usamos el customId (ej. EXT-1) o el índice si no tiene ID.
        String distinctId = entry.customId.isNotEmpty ? entry.customId : 'Dispositivo #${entry.deviceIndex}';
        
        findings.add({
          'id': distinctId,
          // Si hay múltiples observaciones en un mismo equipo, las unimos con un salto de línea
          'text': deviceFindingsTexts.join('\n—\n'), 
        });
      }
    }
    return findings;
  }

  Widget _buildGeneralObservationsBox() {
    // Obtenemos los hallazgos dinámicamente
    final registeredFindings = _getRegisteredFindings();
    final hasFindings = registeredFindings.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      // Eliminamos el padding interno general para manejarlo por secciones
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===================== SECCIÓN 1: OBSERVACIONES GENERALES (Editable) =====================
          _buildSectionHeader(Icons.notes, 'OBSERVACIONES GENERALES DEL SERVICIO'),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              enabled: _isEditable(),
              // Usamos TextEditingController.fromValue para evitar saltos de cursor al reconstruir
              controller: TextEditingController.fromValue(
                TextEditingValue(
                  text: _report!.generalObservations,
                  selection: TextSelection.collapsed(offset: _report!.generalObservations.length),
                ),
              ),
              maxLines: 3,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              decoration: InputDecoration(
                hintText: 'Comentarios globales sobre la visita, accesos, estado general de las instalaciones...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFFF8FAFC), // Slate-50 background
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                ),
              ),
              onChanged: (val) {
                _report = _report!.copyWith(generalObservations: val);
                _repo.saveReport(_report!);
              },
            ),
          ),

          // Divisor entre secciones
          Divider(height: 1, color: Colors.grey.shade200),

          // ===================== SECCIÓN 2: HALLAZGOS REGISTRADOS (Lectura) =====================
          _buildSectionHeader(Icons.find_in_page_outlined, 'HALLAZGOS REGISTRADOS EN DISPOSITIVOS', color: const Color(0xFFF59E0B)), // Color ámbar para resaltar

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: hasFindings
                ? Column(
                    children: registeredFindings.map((finding) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // El "Badge" con el ID (ej. EXT-1:)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0), // Slate-200 (Gris claro como en la imagen)
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${finding['id']}:",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B), // Slate-800
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // El texto del hallazgo
                            Expanded(
                              child: Text(
                                finding['text']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF334155), // Slate-700
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade100)
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, size: 16, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text(
                          "No se registraron observaciones individuales en los equipos.",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, {Color color = const Color(0xFF3B82F6)}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B), // Slate-800
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. MODAL DE OBSERVACIONES (Bottom Sheet)
  // ==========================================
  Widget _buildObservationModal() {
    if (_activeObservationEntry == null) return const SizedBox();
    
    final entryIdx = int.parse(_activeObservationEntry!);
    final entry = _report!.entries[entryIdx];
    
    String currentObservation;
    String title;
    String subtitle;
    IconData icon;
    Color accentColor;

    if (_activeObservationActivityId != null) {
      final actData = entry.activityData[_activeObservationActivityId];
      currentObservation = actData?.observations ?? '';
      title = 'Observación de Actividad';
      subtitle = 'ID: ${entry.customId} • ${_activeObservationActivityId}';
      icon = Icons.assignment_outlined;
      accentColor = const Color(0xFFF59E0B); // Ámbar para actividades
    } else {
      currentObservation = entry.observations;
      title = entry.customId.isNotEmpty ? entry.customId : 'Dispositivo #${entry.deviceIndex}';
      subtitle = entry.area.isNotEmpty ? entry.area : 'Sin ubicación especificada';
      icon = Icons.devices_other;
      accentColor = const Color(0xFF3B82F6); // Azul para dispositivos
    }

    final textController = TextEditingController(text: currentObservation);
    final characterCount = ValueNotifier<int>(currentObservation.length);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, -5),
          )
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 24, 
        right: 24, 
        top: 12
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle (drag indicator)
          Center(
            child: Container(
              width: 36, 
              height: 4, 
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300, 
                borderRadius: BorderRadius.circular(2)
              ),
            ),
          ),

          // Header con gradiente sutil
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withOpacity(0.1), accentColor.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: accentColor.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))
                    ],
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title, 
                        style: const TextStyle(
                          fontWeight: FontWeight.w800, 
                          fontSize: 15, 
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.3,
                        )
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle, 
                        style: const TextStyle(
                          color: Color(0xFF64748B), 
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1, 
                        overflow: TextOverflow.ellipsis
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22), 
                  onPressed: () => setState(() { 
                    _activeObservationEntry = null; 
                    _activeObservationActivityId = null; 
                  }),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Label del campo
          const Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'DETALLES Y HALLAZGOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Input de Texto con contador
          Stack(
            children: [
              TextField(
                controller: textController,
                maxLines: 6,
                maxLength: 500,
                autofocus: true,
                style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155)),
                decoration: InputDecoration(
                  hintText: 'Describa cualquier anomalía, condición especial o recomendación técnica...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                  counterText: '', // Ocultar contador por defecto
                ),
                onChanged: (value) => characterCount.value = value.length,
              ),
              // Contador custom en la esquina
              Positioned(
                bottom: 8,
                right: 12,
                child: ValueListenableBuilder<int>(
                  valueListenable: characterCount,
                  builder: (context, count, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: count > 450 ? Colors.red.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: count > 450 ? Colors.red.shade200 : Colors.grey.shade200
                        ),
                      ),
                      child: Text(
                        '$count/500',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: count > 450 ? Colors.red.shade700 : const Color(0xFF94A3B8),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Botones de Acción
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() { 
                    _activeObservationEntry = null; 
                    _activeObservationActivityId = null; 
                  }),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: const Color(0xFF64748B),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Cancelar", style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    shadowColor: accentColor.withOpacity(0.3),
                  ),
                  onPressed: () {
                    if (_activeObservationActivityId != null) {
                      final currentData = entry.activityData[_activeObservationActivityId!] ?? 
                          ActivityData(photos: [], observations: '');
                      final newActivityData = Map<String, ActivityData>.from(entry.activityData);
                      newActivityData[_activeObservationActivityId!] = ActivityData(
                        photos: currentData.photos, 
                        observations: textController.text
                      );
                      _updateEntry(entryIdx, activityData: newActivityData);
                    } else {
                      _updateEntry(entryIdx, observations: textController.text);
                    }
                    setState(() { 
                      _activeObservationEntry = null; 
                      _activeObservationActivityId = null; 
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Modal de Fotos
  Widget _buildPhotoModal() {
    if (_photoContextEntryIdx == null) return const SizedBox();
    final entry = _report!.entries[_photoContextEntryIdx!];
    
    List<String> photos;
    String contextTitle;
    
    if (_photoContextActivityId != null) {
      photos = entry.activityData[_photoContextActivityId]?.photos ?? [];
      contextTitle = 'Fotos de Actividad • ${entry.customId}';
    } else {
      photos = entry.photos;
      contextTitle = 'Fotos del Dispositivo • ${entry.customId}';
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library, color: Color(0xFF3B82F6), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contextTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${photos.length} ${photos.length == 1 ? 'foto' : 'fotos'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                  onPressed: () => setState(() {
                    _photoContextEntryIdx = null;
                    _photoContextActivityId = null;
                  }),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Grid de fotos
          Expanded(
            child: photos.isEmpty
                ? _buildEmptyPhotoState()
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: photos.length + 1,
                      itemBuilder: (ctx, idx) {
                        if (idx == photos.length) {
                          return _buildAddPhotoButton();
                        }
                        return _buildPhotoThumbnail(photos[idx], idx);
                      },
                    ),
                  ),
          ),
          
          // Botón de acción flotante (si hay fotos)
          if (photos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_a_photo, size: 20),
                  label: const Text(
                    'Tomar Primera Foto',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyPhotoState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_a_photo_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Sin fotos registradas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toca el botón para agregar evidencia fotográfica',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return InkWell(
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF3B82F6),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle, color: Color(0xFF3B82F6), size: 32),
            SizedBox(height: 8),
            Text(
              'Agregar',
              style: TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoThumbnail(String base64Photo, int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              base64Decode(base64Photo),
              fit: BoxFit.cover,
            ),
            // Overlay con botón de eliminar
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showDeleteConfirmation(index),
                  icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                ),
              ),
            ),
            // Indicador de número
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(int photoIndex) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 24),
            SizedBox(width: 12),
            Text('Confirmar Eliminación', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          '¿Estás seguro de eliminar esta foto? Esta acción no se puede deshacer.',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDeletePhoto(photoIndex);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
