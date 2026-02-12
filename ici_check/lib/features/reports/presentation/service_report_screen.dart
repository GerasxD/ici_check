import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:ici_check/features/reports/services/photo_storage_service.dart';
import 'package:ici_check/features/reports/widgets/device_section_improved.dart';
import 'package:ici_check/features/reports/widgets/report_controls.dart';
import 'package:ici_check/features/reports/widgets/report_header.dart';
import 'package:ici_check/features/reports/widgets/report_signatures.dart';
import 'package:ici_check/features/reports/widgets/report_summary.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';

// Imports de Modelos y Repositorios
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/policies/data/policies_repository.dart'; // NUEVO
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
  final PoliciesRepository _policiesRepo = PoliciesRepository(); // NUEVO
  final ImagePicker _picker = ImagePicker();
  Timer? _autoSaveDebounce;
  final PhotoStorageService _photoService = PhotoStorageService();
  bool _isUploadingPhoto = false;
  
  // Estado del Reporte
  ServiceReportModel? _report;
  CompanySettingsModel? _companySettings;
  PolicyModel? _currentPolicy; // NUEVO - Guardamos la póliza actual
  bool _isLoading = true;
  
  // Estado de la UI
  bool _adminOverride = false;
  String? _currentUserId;
  UserModel? _currentUser;
  
  // Suscripciones de streams
  StreamSubscription? _policySubscription; // NUEVO
  StreamSubscription? _reportSubscription; // NUEVO
  
  // Controladores de firma
  final SignatureController _providerSigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );
  final SignatureController _clientSigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );

  // Estados para Modales
  String? _activeObservationEntry;
  String? _activeObservationActivityId;
  int? _photoContextEntryIdx;
  String? _photoContextActivityId;

  // Colores
  final Color _bgLight = const Color(0xFFF8FAFC);
  final Color _primaryDark = const Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _loadData();
    _providerSigController.addListener(_onSignatureChanged);
    _clientSigController.addListener(_onSignatureChanged);
  }

  @override
  void dispose() {
    _providerSigController.dispose();
    _clientSigController.dispose();
    _policySubscription?.cancel(); // NUEVO
    _reportSubscription?.cancel(); // NUEVO
    _autoSaveDebounce?.cancel();
    super.dispose();
  }

  // ==========================================
  // CARGA DE DATOS E INICIALIZACIÓN (MEJORADO)
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

      // ====================================================
      // NUEVO: ESCUCHAR CAMBIOS EN LA PÓLIZA EN TIEMPO REAL
      // ====================================================
      _policySubscription = _policiesRepo.getPoliciesStream().listen((policies) {
        try {
          final updatedPolicy = policies.firstWhere((p) => p.id == widget.policyId);
          
          // Si detectamos cambios en la póliza, re-sincronizamos el reporte
          if (_currentPolicy != null && _hasRelevantPolicyChanges(_currentPolicy!, updatedPolicy)) {
            debugPrint("🔄 Detectados cambios en la póliza. Re-sincronizando reporte...");
            setState(() {
              _currentPolicy = updatedPolicy;
            });
            
            // Solo re-sincronizamos si ya tenemos un reporte cargado
            if (_report != null) {
              _syncReportWithPolicy(updatedPolicy);
            }
          } else {
            // Primera carga o sin cambios relevantes
            if (mounted) {
              setState(() {
                _currentPolicy = updatedPolicy;
              });
            }
          }
        } catch (e) {
          debugPrint("Error actualizando póliza: $e");
        }
      });

      // Escuchamos el stream del reporte
      _reportSubscription = _repo.getReportStream(widget.policyId, widget.dateStr).listen((existingReport) {
        if (existingReport != null) {
          _syncAndLoadReport(existingReport);
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

  // ====================================================
  // NUEVO: DETECTAR SI HUBO CAMBIOS RELEVANTES EN LA PÓLIZA
  // ====================================================
  bool _hasRelevantPolicyChanges(PolicyModel old, PolicyModel updated) {
    // Comparar si cambiaron los dispositivos (cantidad o tipo)
    if (old.devices.length != updated.devices.length) return true;
    
    // Verificar si algún dispositivo cambió su definitionId o cantidad
    for (int i = 0; i < old.devices.length; i++) {
      if (i >= updated.devices.length) return true;
      if (old.devices[i].definitionId != updated.devices[i].definitionId) return true;
      if (old.devices[i].quantity != updated.devices[i].quantity) return true;
    }
    
    // Verificar si cambió la frecuencia semanal (afecta qué actividades se muestran)
    if (old.includeWeekly != updated.includeWeekly) return true;
    
    return false;
  }

  // ====================================================
  // NUEVO: SINCRONIZAR REPORTE CUANDO LA PÓLIZA CAMBIA
  // ====================================================
  Future<void> _syncReportWithPolicy(PolicyModel updatedPolicy) async {
    if (_report == null) return;

    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    // Generar las entradas ideales con la póliza actualizada
    final idealEntries = _repo.generateEntriesForDate(
      updatedPolicy, // Usar la póliza actualizada
      widget.dateStr,
      widget.devices,
      isWeekly,
      timeIndex,
    );

    // Fusionar con datos existentes
    final mergedEntries = _mergeEntries(_report!.entries, idealEntries);

    // Guardar el reporte actualizado
    final updatedReport = _report!.copyWith(entries: mergedEntries);
    
    await _repo.saveReport(updatedReport);
    
    if (mounted) {
      setState(() {
        _report = updatedReport;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte actualizado con los cambios de la póliza'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ====================================================
  // HELPER: CALCULAR ÍNDICE DE TIEMPO
  // ====================================================
  int _calculateTimeIndex(bool isWeekly) {
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
      int weekNumber = int.tryParse(widget.dateStr.split('W').last) ?? 1;
      timeIndex = (weekNumber > 0) ? weekNumber - 1 : 0;
    }

    return timeIndex;
  }

  // ====================================================
  // HELPER: FUSIONAR ENTRADAS (MANTENER DATOS EXISTENTES)
  // ====================================================
  List<ReportEntry> _mergeEntries(List<ReportEntry> existing, List<ReportEntry> ideal) {
    List<ReportEntry> merged = [];
    
    // Mapa para búsqueda rápida
    Map<String, ReportEntry> existingMap = {
      for (var e in existing) e.instanceId: e
    };

    for (var idealEntry in ideal) {
      if (existingMap.containsKey(idealEntry.instanceId)) {
        // El dispositivo ya existía: Combinamos resultados
        var existingEntry = existingMap[idealEntry.instanceId]!;
        Map<String, String?> mergedResults = Map.from(existingEntry.results);
        
        // Agregar actividades nuevas
        idealEntry.results.forEach((actId, _) {
          if (!mergedResults.containsKey(actId)) {
            mergedResults[actId] = null;
          }
        });

        // Eliminar actividades que ya no tocan (solo si están vacías)
        List<String> toRemove = [];
        mergedResults.keys.forEach((actId) {
          if (!idealEntry.results.containsKey(actId)) {
            if (mergedResults[actId] == null) {
              toRemove.add(actId);
            }
          }
        });
        
        toRemove.forEach(mergedResults.remove);

        merged.add(existingEntry.copyWith(results: mergedResults));
      } else {
        // Dispositivo nuevo
        merged.add(idealEntry);
      }
    }

    return merged;
  }

  void _syncAndLoadReport(ServiceReportModel existingReport) {
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    // Usamos la póliza actual (que puede haber cambiado)
    final policyToUse = _currentPolicy ?? widget.policy;

    final idealEntries = _repo.generateEntriesForDate(
      policyToUse,
      widget.dateStr,
      widget.devices,
      isWeekly,
      timeIndex,
    );

    final mergedEntries = _mergeEntries(existingReport.entries, idealEntries);
    bool hasChanges = mergedEntries.length != existingReport.entries.length;

    if (hasChanges) {
      debugPrint("🔄 Sincronizando reporte con cambios...");
      final updatedReport = existingReport.copyWith(entries: mergedEntries);
      _repo.saveReport(updatedReport);

      if (mounted) {
        setState(() {
          _report = updatedReport;
          _isLoading = false;
          _loadSignatures();
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _report = existingReport;
          _isLoading = false;
          _loadSignatures();
        });
      }
    }
  }

  Future<String?> _getCurrentUserId() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      return currentUser?.uid;
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }

  void _onSignatureChanged() {
    if (_autoSaveDebounce?.isActive ?? false) _autoSaveDebounce!.cancel();
    _autoSaveDebounce = Timer(const Duration(seconds: 2), () {
      _processAndSaveSignatures();
    });
  }

  Future<void> _processAndSaveSignatures() async {
    if (_report == null) return;
    
    String? providerSigBase64 = _report!.providerSignature;
    String? clientSigBase64 = _report!.clientSignature;

    bool hasChanges = false;

    if (_providerSigController.isNotEmpty) {
      final bytes = await _providerSigController.toPngBytes();
      if (bytes != null) {
        final newSig = base64Encode(bytes);
        if (newSig != providerSigBase64) {
          providerSigBase64 = newSig;
          hasChanges = true;
        }
      }
    }

    if (_clientSigController.isNotEmpty) {
      final bytes = await _clientSigController.toPngBytes();
      if (bytes != null) {
        final newSig = base64Encode(bytes);
        if (newSig != clientSigBase64) {
          clientSigBase64 = newSig;
          hasChanges = true;
        }
      }
    }

    if (hasChanges) {
      final updatedReport = _report!.copyWith(
        providerSignature: providerSigBase64,
        clientSignature: clientSigBase64,
      );

      if (mounted) {
        setState(() {
          _report = updatedReport;
        });
        await _repo.saveReport(_report!);
        debugPrint("Firma auto-guardada");
      }
    }
  }

  void _loadSignatures() {
    // Lógica de carga de firmas si es necesaria
  }

  void _initializeNewReport() {
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    final policyToUse = _currentPolicy ?? widget.policy;

    final newReport = _repo.initializeReport(
      policyToUse,
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
  // LÓGICA DE NEGOCIO (Sin cambios)
  // ==========================================
  void _updateEntry(int index, {
    String? customId,
    String? area,
    Map<String, String?>? results,
    String? observations,
    List<String>? photoUrls,
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
      photoUrls: photoUrls ?? entry.photoUrls,
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

    // PASO 1: Obtener asignaciones actuales del dispositivo
    final currentAssignments = List<String>.from(_report!.sectionAssignments[defId] ?? []);
    
    debugPrint("📋 ANTES: Dispositivo $defId tiene asignados: $currentAssignments");
    debugPrint("   Intentando toggle de usuario: $userId");

    // PASO 2: Agregar o quitar el usuario
    if (currentAssignments.contains(userId)) {
      currentAssignments.remove(userId);
      debugPrint("   ✂️ REMOVIENDO: Técnico $userId eliminado");
    } else {
      currentAssignments.add(userId);
      debugPrint("   ➕ AGREGANDO: Técnico $userId agregado");
    }

    debugPrint("📋 DESPUÉS: Dispositivo $defId ahora tiene: $currentAssignments");

    // PASO 3: Actualizar mapa de asignaciones por dispositivo
    final newSectionAssignments = Map<String, List<String>>.from(_report!.sectionAssignments);
    newSectionAssignments[defId] = List<String>.from(currentAssignments);

    // ✅ PASO 4 CORREGIDO: Preservar técnicos globales existentes
    // Primero tomamos TODOS los técnicos que ya estaban asignados globalmente
    final Set<String> allAssignedTechs = Set<String>.from(_report!.assignedTechnicianIds);
    
    // Luego agregamos los técnicos de dispositivos específicos
    newSectionAssignments.forEach((defId, techIds) {
      debugPrint("   Device $defId → Tecnicos: $techIds");
      allAssignedTechs.addAll(techIds);
    });

    debugPrint("✅ TÉCNICOS GLOBALES FINALES: $allAssignedTechs");

    // PASO 5: Crear reporte actualizado
    final updatedReport = _report!.copyWith(
      sectionAssignments: newSectionAssignments,
      assignedTechnicianIds: allAssignedTechs.toList(),
    );
    
    // PASO 6: Actualizar estado
    setState(() => _report = updatedReport);

    // PASO 7: Guardar en Firebase
    debugPrint("💾 Guardando reporte con asignaciones actualizadas...");
    _repo.saveReport(_report!);
  }

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

  // ✅ NUEVO: Las firmas siempre pueden ser editadas, incluso después de finalizar
  bool _canSignReport() {
    return _report != null;
  }

  bool _isUserCoordinator() {
    if (_currentUser == null) return false;
    return _currentUser!.role == UserRole.SUPER_USER ||
        _currentUser!.role == UserRole.ADMIN ||
        widget.policy.assignedUserIds.contains(_currentUserId);
  }

  bool _areAllSectionsAssigned() {
    if (_report == null) return false;

    final activeDefIds = <String>{};

    for (var entry in _report!.entries) {
      if (entry.results.isNotEmpty) {
        try {
          final policyToUse = _currentPolicy ?? widget.policy;
          final deviceInstance = policyToUse.devices.firstWhere(
            (d) => d.instanceId == entry.instanceId,
          );
          activeDefIds.add(deviceInstance.definitionId);
        } catch (e) {
          debugPrint('Advertencia: Dispositivo ${entry.instanceId} no encontrado en la póliza.');
        }
      }
    }

    for (var defId in activeDefIds) {
      final assignedTechnicians = _report!.sectionAssignments[defId];
      if (assignedTechnicians == null || assignedTechnicians.isEmpty) {
        return false;
      }
    }

    return true;
  }

  void _handleStartService() {
    if (_report == null || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar un usuario para registrar tiempos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_areAllSectionsAssigned()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se puede iniciar: Hay tipos de dispositivos sin responsable asignado.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final now = DateTime.now(); // 1. Capturamos el momento exacto
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    final updatedReport = _report!.copyWith(
      startTime: timeStr,      // 2. Guardamos la hora (esto activa la condición verde en el cronograma)
      serviceDate: now,        // 3. IMPORTANTÍSIMO: Actualizamos la fecha del reporte al día real de hoy
    );

    setState(() {
      _report = updatedReport;
    });

    _repo.saveReport(_report!);
  }

  void _handleEndService() {
    if (_report == null || _currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar un usuario para registrar tiempos'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (!_areAllSectionsAssigned()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asigna técnicos a todas las secciones antes de finalizar.'), backgroundColor: Colors.red),
      );
      return;
    }

    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    final updatedReport = _report!.copyWith(endTime: timeStr);

    setState(() {
      _report = updatedReport;
    });
    _repo.saveReport(_report!);
  }

  void _handleResumeService() {
    setState(() {
      _report = _report!.copyWith(endTime: null, forceNullEndTime: true);
    });
    _repo.saveReport(_report!);
  }

  Future<void> _handleCameraClick(int entryIdx, {String? activityId}) async {
    if (_report == null) return;

    final entry = _report!.entries[entryIdx];
    List<String> existingPhotos;

    if (activityId != null) {
      existingPhotos = entry.activityData[activityId]?.photoUrls ?? [];
    } else {
      existingPhotos = entry.photoUrls;
    }

    setState(() {
      _photoContextEntryIdx = entryIdx;
      _photoContextActivityId = activityId;
    });

    if (existingPhotos.isEmpty) {
      _showImageSourceSelection(); 
    }
  }

  // --- NUEVA LÓGICA DE SELECCIÓN DE FOTOS ---

  // 1. Mostrar menú para elegir entre Cámara o Galería
  void _showImageSourceSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3B82F6)),
                title: const Text('Tomar Foto'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF3B82F6)),
                title: const Text('Seleccionar de Galería (Múltiple)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 2. Lógica para la Cámara (Una sola foto + Guardar en Galería con GAL)
  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        // Solo guardamos en galería si viene de la cámara
        try {
          await Gal.putImage(image.path, album: "ICI Check");
        } catch (e) {
          debugPrint("⚠️ Error guardando en galería local: $e");
        }
        // Procesamos como una lista de 1 elemento
        await _processAndUploadImages([image]);
      }
    } catch (e) {
      debugPrint('Error en cámara: $e');
    }
  }

  // 3. Lógica para la Galería (Múltiples fotos)
  Future<void> _pickFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        await _processAndUploadImages(images);
      }
    } catch (e) {
      debugPrint('Error en galería: $e');
    }
  }

  // 4. Lógica unificada de subida (Procesa una lista de imágenes)
  Future<void> _processAndUploadImages(List<XFile> images) async {
    if (_isUploadingPhoto || _photoContextEntryIdx == null || _report == null) return;

    setState(() => _isUploadingPhoto = true);
    int successCount = 0;

    try {
      // Iteramos sobre todas las imágenes seleccionadas
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        
        // Actualizar SnackBar para mostrar progreso
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(width: 20, height: 20, 
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 12),
                Text('Subiendo ${i + 1} de ${images.length}...'),
              ],
            ),
            duration: const Duration(seconds: 10), // Duración larga para que no se oculte
          ),
        );

        final bytes = await image.readAsBytes();
        final entryIdx = _photoContextEntryIdx!;
        final activityId = _photoContextActivityId;

        // Subir a Firebase Storage
        final photoUrl = await _photoService.uploadPhoto(
          photoBytes: bytes,
          reportId: '${widget.policyId}_${widget.dateStr}',
          deviceInstanceId: _report!.entries[entryIdx].instanceId,
          activityId: activityId,
        );

        // Actualizar el estado local con la nueva URL
        final entry = _report!.entries[entryIdx];
        if (activityId != null) {
          final currentData = entry.activityData[activityId] ?? 
              ActivityData(photoUrls: [], observations: '');
          final newPhotoUrls = [...currentData.photoUrls, photoUrl];
          
          final newActivityData = Map<String, ActivityData>.from(entry.activityData);
          newActivityData[activityId] = ActivityData(
            photoUrls: newPhotoUrls,
            observations: currentData.observations,
          );
          _updateEntry(entryIdx, activityData: newActivityData);
        } else {
          final newPhotoUrls = [...entry.photoUrls, photoUrl];
          _updateEntry(entryIdx, photoUrls: newPhotoUrls);
        }
        successCount++;
      }

      // Éxito Final
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text(successCount == 1 ? 'Foto subida' : '$successCount fotos subidas'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _confirmDeletePhoto(int photoIndex) async {
    if (_photoContextEntryIdx == null || _report == null) return;

    final entryIdx = _photoContextEntryIdx!;
    final activityId = _photoContextActivityId;
    final entry = _report!.entries[entryIdx];

    String? photoUrlToDelete;

    if (activityId != null) {
      final currentData = entry.activityData[activityId];
      if (currentData != null && photoIndex < currentData.photoUrls.length) {
        photoUrlToDelete = currentData.photoUrls[photoIndex];
        
        final newPhotoUrls = List<String>.from(currentData.photoUrls);
        newPhotoUrls.removeAt(photoIndex);
        
        final newActivityData = Map<String, ActivityData>.from(entry.activityData);
        newActivityData[activityId] = ActivityData(
          photoUrls: newPhotoUrls,
          observations: currentData.observations,
        );
        
        _updateEntry(entryIdx, activityData: newActivityData);
        
        if (newPhotoUrls.isEmpty) {
          setState(() {
            _photoContextEntryIdx = null;
            _photoContextActivityId = null;
          });
        }
      }
    } else {
      if (photoIndex < entry.photoUrls.length) {
        photoUrlToDelete = entry.photoUrls[photoIndex];
        
        final newPhotoUrls = List<String>.from(entry.photoUrls);
        newPhotoUrls.removeAt(photoIndex);
        
        _updateEntry(entryIdx, photoUrls: newPhotoUrls);
        
        if (newPhotoUrls.isEmpty) {
          setState(() {
            _photoContextEntryIdx = null;
            _photoContextActivityId = null;
          });
        }
      }
    }

    // ✅ Eliminar de Storage
    if (photoUrlToDelete != null) {
      try {
        await _photoService.deletePhoto(photoUrlToDelete);
      } catch (e) {
        debugPrint('Error eliminando foto: $e');
      }
    }
  }

  Map<String, List<ReportEntry>> _groupEntries() {
    if (_report == null) return {};
    final grouped = <String, List<ReportEntry>>{};
    final policyToUse = _currentPolicy ?? widget.policy;
    
    for (var entry in _report!.entries) {
      try {
        final deviceInstance = policyToUse.devices.firstWhere((d) => d.instanceId == entry.instanceId);
        final defId = deviceInstance.definitionId;
        if (!grouped.containsKey(defId)) grouped[defId] = [];
        grouped[defId]!.add(entry);
      } catch (e) {
        debugPrint('Warning: Device ${entry.instanceId} not found in policy');
      }
    }
    return grouped;
  }

  String _getFrequencies(Map<String, List<ReportEntry>> grouped) {
    return "Mensual";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _report == null || _companySettings == null) {
      return Scaffold(
        backgroundColor: _bgLight,
        body: Center(child: CircularProgressIndicator(color: _primaryDark)),
      );
    }

    final groupedEntries = _groupEntries();
    final groupedEntriesList = groupedEntries.entries.toList();
    final frequencies = _getFrequencies(groupedEntries);
    final assignedUsers = widget.users.where((user) => 
      _report!.assignedTechnicianIds.contains(user.id)
    ).toList();
    
    debugPrint("👥 Usuarios asignados al reporte: ${assignedUsers.length}");

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
            const Text('Reporte de Servicio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.3)),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(widget.dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                if (_report!.startTime != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _report!.endTime == null ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFF64748B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_report!.endTime == null ? Icons.play_circle : Icons.check_circle, size: 10, color: _report!.endTime == null ? const Color(0xFF10B981) : const Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Text(_report!.endTime == null ? 'En curso' : 'Finalizado', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _report!.endTime == null ? const Color(0xFF10B981) : const Color(0xFF64748B))),
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
              icon: Icon(_adminOverride ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined, color: _adminOverride ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8), size: 22),
              onPressed: () => setState(() => _adminOverride = !_adminOverride),
              tooltip: _adminOverride ? 'Modo Admin Activo' : 'Activar Modo Admin',
            ),
          const SizedBox(width: 8),
        ],
      ),

      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                ReportHeader(
                  companySettings: _companySettings!,
                  client: widget.client,
                  serviceDate: _report!.serviceDate,
                  dateStr: widget.dateStr,
                  frequencies: frequencies,
                ),
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
                  onStartTimeEdited: (newTime) {
                    final updated = _report!.copyWith(startTime: newTime);
                    setState(() => _report = updated);
                    _repo.saveReport(_report!);
                  },
                  onEndTimeEdited: (newTime) {
                    final updated = _report!.copyWith(endTime: newTime);
                    setState(() => _report = updated);
                    _repo.saveReport(_report!);
                  },
                ),
              ],
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entryGroup = groupedEntriesList[index];
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
                  users: assignedUsers, // ✅ PASAR SOLO USUARIOS ASIGNADOS
                  sectionAssignments: _report!.sectionAssignments[defId] ?? [],
                  isEditable: _isEditable(),
                  allowedToEdit: _isEditable(),
                  isUserCoordinator: _isUserCoordinator(),
                  currentUserId: _currentUserId,
                  onToggleAssignment: (uid) => _toggleSectionAssignment(defId, uid),
                  onCustomIdChanged: (localIndex, val) {
                    final entry = sectionEntries[localIndex];
                    final globalIndex = _report!.entries.indexOf(entry);
                    if (globalIndex != -1) _updateEntry(globalIndex, customId: val);
                  },
                  onAreaChanged: (localIndex, val) {
                    final entry = sectionEntries[localIndex];
                    final globalIndex = _report!.entries.indexOf(entry);
                    if (globalIndex != -1) _updateEntry(globalIndex, area: val);
                  },
                  onToggleStatus: (localIndex, activityId) {
                    final entry = sectionEntries[localIndex];
                    final globalIndex = _report!.entries.indexOf(entry);
                    if (globalIndex != -1) _toggleStatus(globalIndex, activityId, defId);
                  },
                  onCameraClick: (localIndex, {activityId}) {
                    final entry = sectionEntries[localIndex];
                    final globalIndex = _report!.entries.indexOf(entry);
                    if (globalIndex != -1) _handleCameraClick(globalIndex, activityId: activityId);
                  },
                  onObservationClick: (localIndex, {activityId}) {
                    final entry = sectionEntries[localIndex];
                    final globalIndex = _report!.entries.indexOf(entry);
                    if (globalIndex != -1) {
                      setState(() {
                        _activeObservationEntry = globalIndex.toString();
                        _activeObservationActivityId = activityId;
                      });
                    }
                  },
                );
              },
              childCount: groupedEntriesList.length,
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildGeneralObservationsBox(),
                ReportSummary(report: _report!),
                ReportSignatures(
                  providerController: _providerSigController,
                  clientController: _clientSigController,
                  providerName: _report!.providerSignerName,
                  clientName: _report!.clientSignerName,
                  providerSignatureData: _report!.providerSignature,
                  clientSignatureData: _report!.clientSignature,
                  isEditable: _canSignReport(),
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
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),

      floatingActionButton: null,

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

      if (entry.observations.trim().isNotEmpty) {
        deviceFindingsTexts.add(entry.observations.trim());
      }

      for (var actData in entry.activityData.values) {
        if (actData.observations.trim().isNotEmpty) {
          deviceFindingsTexts.add(actData.observations.trim());
        }
      }

      if (deviceFindingsTexts.isNotEmpty) {
        String distinctId = entry.customId.isNotEmpty ? entry.customId : 'Dispositivo #${entry.deviceIndex}';
        
        findings.add({
          'id': distinctId,
          'text': deviceFindingsTexts.join('\n—\n'),
        });
      }
    }
    return findings;
  }

  Widget _buildGeneralObservationsBox() {
    final registeredFindings = _getRegisteredFindings();
    final hasFindings = registeredFindings.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
          _buildSectionHeader(Icons.notes, 'OBSERVACIONES GENERALES DEL SERVICIO'),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              enabled: _isEditable(),
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
                fillColor: const Color(0xFFF8FAFC),
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
                setState(() {
                  _report = _report!.copyWith(generalObservations: val);
                });

                if (_autoSaveDebounce?.isActive ?? false) _autoSaveDebounce!.cancel();

                _autoSaveDebounce = Timer(const Duration(milliseconds: 1500), () {
                    _repo.saveReport(_report!);
                    debugPrint("Observaciones auto-guardadas");
                });
              },
            ),
          ),

          Divider(height: 1, color: Colors.grey.shade200),

          _buildSectionHeader(Icons.find_in_page_outlined, 'HALLAZGOS REGISTRADOS EN DISPOSITIVOS', color: const Color(0xFFF59E0B)),

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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${finding['id']}:",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                finding['text']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF334155),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "No se registraron observaciones individuales en los equipos.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic
                          ),
                          overflow: TextOverflow.visible,
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
              color: const Color(0xFF1E293B),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

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
      accentColor = const Color(0xFFF59E0B);
    } else {
      currentObservation = entry.observations;
      title = entry.customId.isNotEmpty ? entry.customId : 'Dispositivo #${entry.deviceIndex}';
      subtitle = entry.area.isNotEmpty ? entry.area : 'Sin ubicación especificada';
      icon = Icons.devices_other;
      accentColor = const Color(0xFF3B82F6);
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
                  counterText: '',
                ),
                onChanged: (value) => characterCount.value = value.length,
              ),
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
                          ActivityData(photoUrls: [], observations: '');
                      final newActivityData = Map<String, ActivityData>.from(entry.activityData);
                      newActivityData[_activeObservationActivityId!] = ActivityData(
                        photoUrls: currentData.photoUrls,
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

  Widget _buildPhotoModal() {
    if (_photoContextEntryIdx == null) return const SizedBox();
    final entry = _report!.entries[_photoContextEntryIdx!];
    
    List<String> photos;
    String contextTitle;
    
    if (_photoContextActivityId != null) {
      photos = entry.activityData[_photoContextActivityId]?.photoUrls ?? [];
      contextTitle = 'Fotos de Actividad • ${entry.customId}';
    } else {
      photos = entry.photoUrls;
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
          
          if (photos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showImageSourceSelection, // <--- CAMBIO AQUÍ (antes era _pickImage)
                  icon: const Icon(Icons.add_a_photo, size: 20),
                  label: const Text(
                    'Agregar Fotos', // <--- CAMBIAR TEXTO (para que sea genérico)
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
      onTap: _showImageSourceSelection,
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

  Widget _buildPhotoThumbnail(String photoUrls, int index) {
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
            // ✅ Imagen desde red
            Image.network(
              photoUrls,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: const Color(0xFFF1F5F9),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFFFEE2E2),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 24),
                        SizedBox(height: 4),
                        Text('Error', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            // Botón eliminar
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
            
            // Badge número
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