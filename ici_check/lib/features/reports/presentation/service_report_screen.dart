import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:ici_check/features/devices/data/devices_repository.dart';
import 'package:ici_check/features/reports/services/device_location_service.dart';
import 'package:ici_check/features/reports/services/photo_storage_service.dart';
import 'package:ici_check/features/reports/widgets/device_section_improved.dart';
import 'package:ici_check/features/reports/widgets/report_controls.dart';
import 'package:ici_check/features/reports/widgets/report_header.dart';
import 'package:ici_check/features/reports/widgets/report_signatures.dart';
import 'package:ici_check/features/reports/widgets/report_summary.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/policies/data/policies_repository.dart';
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
  // ══════════════════════════════════════════════════════════════════════
  // REPOSITORIOS Y SERVICIOS
  // ══════════════════════════════════════════════════════════════════════
  final ReportsRepository _repo = ReportsRepository();
  final SettingsRepository _settingsRepo = SettingsRepository();
  final PoliciesRepository _policiesRepo = PoliciesRepository();
  final DevicesRepository _devicesRepo = DevicesRepository();
  final ImagePicker _picker = ImagePicker();
  final PhotoStorageService _photoService = PhotoStorageService();
  final DeviceLocationService _locationService = DeviceLocationService();

  // ══════════════════════════════════════════════════════════════════════
  // ESTADO PRINCIPAL
  // ══════════════════════════════════════════════════════════════════════
  ServiceReportModel? _report;
  CompanySettingsModel? _companySettings;
  PolicyModel? _currentPolicy;
  List<DeviceModel> _currentDevices = [];
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  // Estado de usuario
  bool _adminOverride = false;
  String? _currentUserId;
  UserModel? _currentUser;

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #1: MAPA DE ÍNDICES GLOBALES PRE-CALCULADO
  // Elimina los costosos `indexWhere` en O(n) que se ejecutaban en cada
  // callback de cada celda. Ahora es O(1) por lookup.
  // ══════════════════════════════════════════════════════════════════════
  Map<String, int> _instanceIdToGlobalIndex = {};

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #2: CACHÉ DE DATOS DERIVADOS
  // Se recalculan SOLO cuando cambian las entries, no en cada build().
  // ══════════════════════════════════════════════════════════════════════
  List<MapEntry<String, List<ReportEntry>>> _cachedGroupedEntries = [];
  String _cachedFrequencies = "";
  List<UserModel> _cachedAssignedUsers = [];

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #3: DEBOUNCE UNIFICADO PARA FIREBASE
  // En lugar de guardar en Firebase en cada tecla o toggle, acumulamos
  // los cambios y hacemos UN SOLO write cada 800ms.
  // ══════════════════════════════════════════════════════════════════════
  Timer? _saveDebounce;
  bool _hasPendingChanges = false;

  // Suscripciones
  StreamSubscription? _policySubscription;
  StreamSubscription? _reportSubscription;
  StreamSubscription? _devicesSubscription;
  Timer? _locationSaveDebounce;

  // Ubicaciones guardadas
  Map<String, Map<String, String>> _savedLocations = {};

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

  // ✅ OPTIMIZACIÓN #4: Controller estable para observaciones generales
  // Evita recrear TextEditingController en cada build().
  late final TextEditingController _generalObsController;
  Timer? _generalObsDebounce;

  // Colores
  static const Color _bgLight = Color(0xFFF8FAFC);
  static const Color _primaryDark = Color(0xFF0F172A);

  List<DeviceModel> get _devicesEffective =>
      _currentDevices.isNotEmpty ? _currentDevices : widget.devices;

  // ══════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _generalObsController = TextEditingController();
    _loadData();
    _providerSigController.addListener(_onSignatureChanged);
    _clientSigController.addListener(_onSignatureChanged);
  }

  @override
  void dispose() {
    // Guardar cambios pendientes antes de destruir
    _flushPendingChanges();
    _locationSaveDebounce?.cancel();
    _providerSigController.dispose();
    _clientSigController.dispose();
    _policySubscription?.cancel();
    _reportSubscription?.cancel();
    _devicesSubscription?.cancel();
    _saveDebounce?.cancel();
    _generalObsDebounce?.cancel();
    _generalObsController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #5: RECALCULAR DATOS DERIVADOS EN UN SOLO LUGAR
  // Se llama SOLO cuando _report.entries cambia, NO en build().
  // ══════════════════════════════════════════════════════════════════════
  void _updateDerivedData() {
    if (_report == null) return;

    // 1. Reconstruir mapa de índices globales
    final newIndexMap = <String, int>{};
    for (int i = 0; i < _report!.entries.length; i++) {
      newIndexMap[_report!.entries[i].instanceId] = i;
    }
    _instanceIdToGlobalIndex = newIndexMap;

    // 2. Recalcular agrupación
    final grouped = _groupEntries();
    _cachedGroupedEntries = grouped.entries.toList();
    _cachedFrequencies = _getFrequencies(grouped);

    // 3. Recalcular usuarios asignados
    _cachedAssignedUsers = widget.users
        .where((user) => _report!.assignedTechnicianIds.contains(user.id))
        .toList();
  }

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #6: GUARDADO DIFERIDO (DEBOUNCED)
  // Acumula cambios y hace UN write a Firebase cada 800ms.
  // ══════════════════════════════════════════════════════════════════════
  void _scheduleSave() {
    _hasPendingChanges = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      _flushPendingChanges();
    });
  }

  void _flushPendingChanges() {
    if (_hasPendingChanges && _report != null) {
      _hasPendingChanges = false;
      _repo.saveReport(_report!);
    }
  }

  /// Guarda inmediatamente (para acciones críticas como start/end service)
  void _saveImmediate() {
    _saveDebounce?.cancel();
    _hasPendingChanges = false;
    if (_report != null) _repo.saveReport(_report!);
  }

  // ══════════════════════════════════════════════════════════════════════
  // CARGA DE DATOS
  // ══════════════════════════════════════════════════════════════════════
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

      final instanceIds =
          widget.policy.devices.map((d) => d.instanceId).toList();

      _savedLocations = await _locationService.getLocationsForPolicy(
        widget.policyId,
        instanceIds,
      );

      // Stream de dispositivos
      _devicesSubscription = _devicesRepo.getDevicesStream().listen((
        updatedDevices,
      ) {
        if (!mounted) return;
        final bool firstLoad = _currentDevices.isEmpty;
        bool hasChanges =
            firstLoad ||
            _hasRelevantDeviceChanges(_currentDevices, updatedDevices);

        setState(() => _currentDevices = updatedDevices);

        if (!firstLoad && hasChanges && _report != null) {
          _resyncReportWithCurrentDevices();
        }
      });

      // Stream de póliza
      _policySubscription =
          _policiesRepo.getPoliciesStream().listen((policies) {
        try {
          final updatedPolicy =
              policies.firstWhere((p) => p.id == widget.policyId);
          final previousPolicy = _currentPolicy;

          if (mounted) setState(() => _currentPolicy = updatedPolicy);

          if (previousPolicy != null &&
              _hasRelevantPolicyChanges(previousPolicy, updatedPolicy) &&
              _report != null) {
            _syncReportWithPolicy(updatedPolicy);
          }
        } catch (e) {
          debugPrint("Error actualizando póliza: $e");
        }
      });

      // Stream del reporte
      _reportSubscription = _repo
          .getReportStream(widget.policyId, widget.dateStr)
          .listen((existingReport) {
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

  // ══════════════════════════════════════════════════════════════════════
  // DETECCIÓN DE CAMBIOS
  // ══════════════════════════════════════════════════════════════════════

  bool _hasRelevantDeviceChanges(
    List<DeviceModel> oldDevs,
    List<DeviceModel> newDevs,
  ) {
    if (oldDevs.length != newDevs.length) return true;
    // ✅ Usar mapa para comparación O(n) en vez de O(n²)
    final oldMap = {for (final d in oldDevs) d.id: d};
    for (final newDev in newDevs) {
      final oldDev = oldMap[newDev.id];
      if (oldDev == null) return true;
      if (oldDev.activities.length != newDev.activities.length) return true;
      for (int i = 0; i < oldDev.activities.length; i++) {
        if (oldDev.activities[i].id != newDev.activities[i].id) return true;
        if (oldDev.activities[i].frequency != newDev.activities[i].frequency) {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasRelevantPolicyChanges(PolicyModel old, PolicyModel updated) {
    if (old.includeWeekly != updated.includeWeekly) return true;
    if (old.devices.length != updated.devices.length) return true;

    final oldMap = {for (final d in old.devices) d.instanceId: d};
    final newMap = {for (final d in updated.devices) d.instanceId: d};

    for (final id in newMap.keys) {
      if (!oldMap.containsKey(id)) return true;
    }
    for (final id in oldMap.keys) {
      if (!newMap.containsKey(id)) return true;
      final o = oldMap[id]!;
      final n = newMap[id]!;
      if (o.quantity != n.quantity) return true;
      if (o.definitionId != n.definitionId) return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════════════════════════════
  // SINCRONIZACIÓN
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _resyncReportWithCurrentDevices() async {
    if (_report == null || _currentDevices.isEmpty) return;

    final policyToUse = _currentPolicy ?? widget.policy;
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    final idealEntries = _repo.generateEntriesForDate(
      policyToUse,
      widget.dateStr,
      _currentDevices,
      isWeekly,
      timeIndex,
    );

    final mergedEntries = _mergeEntries(_report!.entries, idealEntries);
    if (!_entriesStructureChanged(_report!.entries, mergedEntries)) return;

    final updatedReport = _report!.copyWith(entries: mergedEntries);
    await _repo.saveReport(updatedReport);

    if (mounted) {
      setState(() {
        _report = updatedReport;
        _updateDerivedData();
      });
      _showSnackBar(
        'Actividades actualizadas según la nueva frecuencia',
        Colors.blue,
      );
    }
  }

  Future<void> _syncReportWithPolicy(PolicyModel updatedPolicy) async {
    if (_report == null) return;

    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    final idealEntries = _repo.generateEntriesForDate(
      updatedPolicy,
      widget.dateStr,
      _devicesEffective,
      isWeekly,
      timeIndex,
    );

    final mergedEntries = _mergeEntries(_report!.entries, idealEntries);
    final updatedReport = _report!.copyWith(entries: mergedEntries);

    await _repo.saveReport(updatedReport);

    if (mounted) {
      setState(() {
        _report = updatedReport;
        _updateDerivedData();
      });
      _showSnackBar(
        'Reporte actualizado con los cambios de la póliza',
        Colors.blue,
      );
    }
  }

  /// ✅ Comparación eficiente de estructura de entries
  bool _entriesStructureChanged(
    List<ReportEntry> oldEntries,
    List<ReportEntry> newEntries,
  ) {
    if (oldEntries.length != newEntries.length) return true;
    for (int i = 0; i < newEntries.length; i++) {
      final newKeys = newEntries[i].results.keys.toSet();
      final oldKeys = oldEntries[i].results.keys.toSet();
      if (!newKeys.containsAll(oldKeys) || !oldKeys.containsAll(newKeys)) {
        return true;
      }
    }
    return false;
  }

  void _syncAndLoadReport(ServiceReportModel existingReport) {
    // ✅ AÑADIDO: Si hay cambios locales pendientes, no pisar con snapshot de Firebase
    if (_hasPendingChanges) return;

    if (_devicesEffective.isEmpty) {
      if (mounted) {
        setState(() {
          _report = existingReport;
          _syncGeneralObsController(existingReport.generalObservations);
          _updateDerivedData();
          _isLoading = false;
          _loadSignatures();
        });
      }
      return;
    }

    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);
    final policyToUse = _currentPolicy ?? widget.policy;

    final idealEntries = _repo.generateEntriesForDate(
      policyToUse,
      widget.dateStr,
      _devicesEffective,
      isWeekly,
      timeIndex,
    );

    final mergedEntries = _mergeEntries(existingReport.entries, idealEntries);

    bool hasStructureChanges =
        _entriesStructureChanged(existingReport.entries, mergedEntries);

    bool hasLocationChanges = false;
    if (!hasStructureChanges && _savedLocations.isNotEmpty) {
      for (int i = 0; i < mergedEntries.length; i++) {
        final original = existingReport.entries[i];
        final merged = mergedEntries[i];
        if (original.customId != merged.customId ||
            original.area != merged.area) {
          hasLocationChanges = true;
          break;
        }
      }
    }

    if (hasStructureChanges || hasLocationChanges) {
      final updatedReport = existingReport.copyWith(entries: mergedEntries);
      if (hasStructureChanges) {
        _repo.saveReport(updatedReport);
      }
      if (mounted) {
        setState(() {
          _report = updatedReport;
          _syncGeneralObsController(updatedReport.generalObservations);
          _updateDerivedData();
          _isLoading = false;
          _loadSignatures();
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _report = existingReport;
          _syncGeneralObsController(existingReport.generalObservations);
          _updateDerivedData();
          _isLoading = false;
          _loadSignatures();
        });
      }
    }
  }

  /// ✅ Sincroniza el controller de observaciones generales solo si cambió externamente
  void _syncGeneralObsController(String newText) {
    if (_generalObsController.text != newText) {
      _generalObsController.text = newText;
    }
  }

  void _initializeNewReport() {
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);
    final policyToUse = _currentPolicy ?? widget.policy;

    final newReport = _repo.initializeReport(
      policyToUse,
      widget.dateStr,
      _devicesEffective,
      isWeekly,
      timeIndex,
      savedLocations: _savedLocations,
    );

    _repo.saveReport(newReport);

    if (mounted) {
      setState(() {
        _report = newReport;
        _syncGeneralObsController(newReport.generalObservations);
        _updateDerivedData();
        _isLoading = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════

  int _calculateTimeIndex(bool isWeekly) {
    if (!isWeekly) {
      DateTime pStart = DateTime(
        widget.policy.startDate.year,
        widget.policy.startDate.month,
        1,
      );
      try {
        DateTime rDate = DateFormat('yyyy-MM').parse(widget.dateStr);
        return (rDate.year - pStart.year) * 12 + (rDate.month - pStart.month);
      } catch (e) {
        debugPrint("Error parsing date: $e");
        return 0;
      }
    } else {
      int weekNumber = int.tryParse(widget.dateStr.split('W').last) ?? 1;
      return (weekNumber > 0) ? weekNumber - 1 : 0;
    }
  }

  List<ReportEntry> _mergeEntries(
    List<ReportEntry> existing,
    List<ReportEntry> ideal,
  ) {
    return _repo.mergeEntries(existing, ideal, _savedLocations);
  }

  Future<String?> _getCurrentUserId() async {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }

  void _showSnackBar(String message, Color color, {int seconds = 2}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: seconds),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // FIRMAS
  // ══════════════════════════════════════════════════════════════════════

  Timer? _signatureDebounce;

  void _onSignatureChanged() {
    _signatureDebounce?.cancel();
    _signatureDebounce = Timer(const Duration(seconds: 2), () {
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

    if (hasChanges && mounted) {
      _report = _report!.copyWith(
        providerSignature: providerSigBase64,
        clientSignature: clientSigBase64,
      );
      _saveImmediate();
    }
  }

  void _loadSignatures() {
    // Carga de firmas si es necesaria
  }

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #7: _updateEntry SIN setState PARA TOGGLES RÁPIDOS
  // El problema principal: cada toggle hacía setState → rebuild de 600+
  // widgets → lag visible. Ahora _updateEntryQuiet modifica el modelo
  // sin rebuild, y solo recalcular el caché de frecuencias mínimo.
  // ══════════════════════════════════════════════════════════════════════

  /// Actualiza una entry y programa un guardado diferido.
  /// `rebuild`: si false, no hace setState (para toggles rápidos en tabla).
  void _updateEntry(
    int index, {
    String? customId,
    String? area,
    Map<String, String?>? results,
    String? observations,
    List<String>? photoUrls,
    Map<String, ActivityData>? activityData,
    bool rebuild = true,
  }) {
    if (_report == null || index < 0 || index >= _report!.entries.length) return;

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

    _report = _report!.copyWith(entries: entries);

    if (rebuild) {
      setState(() {
        _updateDerivedData();
      });
    }

    _scheduleSave();

    // Auto-guardar ubicación
    if (customId != null || area != null) {
      _locationSaveDebounce?.cancel();
      _locationSaveDebounce = Timer(const Duration(seconds: 2), () {
        _locationService.saveLocation(
          policyId: widget.policyId,
          instanceId: entry.instanceId,
          customId: customId ?? entry.customId,
          area: area ?? entry.area,
        );
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #8: TOGGLE STATUS OPTIMIZADO
  // Usa setState MÍNIMO: solo el badge cambia visualmente.
  // ══════════════════════════════════════════════════════════════════════
  void _toggleStatus(int entryIndex, String activityId, String defId) {
    if (_report == null || !_canEditSection(defId)) return;

    final entry = _report!.entries[entryIndex];
    if (!entry.results.containsKey(activityId)) return;

    String? current = entry.results[activityId];
    String? next;
    if (current == null)
      next = 'OK';
    else if (current == 'OK')
      next = 'NOK';
    else if (current == 'NOK')
      next = 'NA';
    else if (current == 'NA')
      next = 'NR';
    else
      next = null;

    final newResults = Map<String, String?>.from(entry.results);
    newResults[activityId] = next;

    _updateEntry(entryIndex, results: newResults);
    _saveImmediate(); // ← AÑADIDO: guarda inmediato para evitar race condition con Firebase stream
  }

  void _toggleSectionAssignment(String defId, String userId) {
    if (_report == null) return;

    final currentAssignments = List<String>.from(
      _report!.sectionAssignments[defId] ?? [],
    );

    if (currentAssignments.contains(userId)) {
      currentAssignments.remove(userId);
    } else {
      currentAssignments.add(userId);
    }

    final newSectionAssignments = Map<String, List<String>>.from(
      _report!.sectionAssignments,
    );
    newSectionAssignments[defId] = List<String>.from(currentAssignments);

    final Set<String> allAssignedTechs = Set<String>.from(
      _report!.assignedTechnicianIds,
    );
    newSectionAssignments.forEach((_, techIds) {
      allAssignedTechs.addAll(techIds);
    });

    final updatedReport = _report!.copyWith(
      sectionAssignments: newSectionAssignments,
      assignedTechnicianIds: allAssignedTechs.toList(),
    );

    setState(() {
      _report = updatedReport;
      _updateDerivedData();
    });

    _saveImmediate();
  }

  // ══════════════════════════════════════════════════════════════════════
  // PERMISOS
  // ══════════════════════════════════════════════════════════════════════

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

  bool _canSignReport() => _report != null;

  bool _isUserCoordinator() {
    if (_currentUser == null) return false;
    if (_currentUser!.role == UserRole.SUPER_USER ||
        _currentUser!.role == UserRole.ADMIN) {
      return true;
    }
    return widget.policy.assignedUserIds.contains(_currentUserId);
  }

  bool _areAllSectionsAssigned() {
    if (_report == null) return false;
    final activeDefIds = <String>{};
    for (final entry in _report!.entries) {
      if (entry.results.isEmpty) continue;
      final deviceInstance = _findPolicyDevice(entry.instanceId);
      if (deviceInstance != null) {
        activeDefIds.add(deviceInstance.definitionId);
      }
    }
    for (final defId in activeDefIds) {
      final assigned = _report!.sectionAssignments[defId];
      if (assigned == null || assigned.isEmpty) return false;
    }
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════
  // ACCIONES DE SERVICIO
  // ══════════════════════════════════════════════════════════════════════

  void _handleStartService() {
    if (_report == null || _currentUserId == null) {
      _showSnackBar(
        'Debes seleccionar un usuario para registrar tiempos',
        Colors.orange,
      );
      return;
    }

    if (!_areAllSectionsAssigned()) {
      _showSnackBar(
        'No se puede iniciar: Hay tipos de dispositivos sin responsable asignado.',
        Colors.red,
        seconds: 3,
      );
      return;
    }

    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    final updatedReport = _report!.copyWith(
      startTime: timeStr,
      serviceDate: now,
    );

    setState(() {
      _report = updatedReport;
      _updateDerivedData();
    });
    _saveImmediate();
  }

  void _handleEndService() {
    if (_report == null || _currentUserId == null) {
      _showSnackBar(
        'Debes seleccionar un usuario para registrar tiempos',
        Colors.orange,
      );
      return;
    }

    if (!_areAllSectionsAssigned()) {
      _showSnackBar(
        'Asigna técnicos a todas las secciones antes de finalizar.',
        Colors.red,
      );
      return;
    }

    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    final updatedReport = _report!.copyWith(endTime: timeStr);

    setState(() {
      _report = updatedReport;
      _updateDerivedData();
    });
    _saveImmediate();
  }

  void _handleResumeService() {
    _report = _report!.copyWith(endTime: null, forceNullEndTime: true);
    setState(() {});
    _saveImmediate();
  }

  // ══════════════════════════════════════════════════════════════════════
  // FOTOS
  // ══════════════════════════════════════════════════════════════════════

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
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF3B82F6),
                ),
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

  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (image != null) {
        try {
          await Gal.putImage(image.path, album: "ICI Check");
        } catch (e) {
          debugPrint("⚠️ Error guardando en galería local: $e");
        }
        await _processAndUploadImages([image]);
      }
    } catch (e) {
      debugPrint('Error en cámara: $e');
    }
  }

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

  Future<void> _processAndUploadImages(List<XFile> images) async {
    if (_isUploadingPhoto || _photoContextEntryIdx == null || _report == null)
      return;

    setState(() => _isUploadingPhoto = true);
    int successCount = 0;

    try {
      for (int i = 0; i < images.length; i++) {
        final image = images[i];

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Subiendo ${i + 1} de ${images.length}...'),
              ],
            ),
            duration: const Duration(seconds: 10),
          ),
        );

        final bytes = await image.readAsBytes();
        final entryIdx = _photoContextEntryIdx!;
        final activityId = _photoContextActivityId;

        final photoUrl = await _photoService.uploadPhoto(
          photoBytes: bytes,
          reportId: '${widget.policyId}_${widget.dateStr}',
          deviceInstanceId: _report!.entries[entryIdx].instanceId,
          activityId: activityId,
        );

        final entry = _report!.entries[entryIdx];
        if (activityId != null) {
          final currentData =
              entry.activityData[activityId] ??
              ActivityData(photoUrls: [], observations: '');
          final newPhotoUrls = [...currentData.photoUrls, photoUrl];
          final newActivityData = Map<String, ActivityData>.from(
            entry.activityData,
          );
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

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSnackBar(
        successCount == 1
            ? 'Foto subida'
            : '$successCount fotos subidas',
        Colors.green,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSnackBar('Error: $e', Colors.red);
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
        final newActivityData = Map<String, ActivityData>.from(
          entry.activityData,
        );
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

    if (photoUrlToDelete != null) {
      try {
        await _photoService.deletePhoto(photoUrlToDelete);
      } catch (e) {
        debugPrint('Error eliminando foto: $e');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // AGRUPACIÓN Y BÚSQUEDA OPTIMIZADA
  // ══════════════════════════════════════════════════════════════════════

  PolicyDevice? _findPolicyDevice(String entryInstanceId) {
    final policyToUse = _currentPolicy ?? widget.policy;
    try {
      return policyToUse.devices.firstWhere(
        (d) =>
            entryInstanceId == d.instanceId ||
            entryInstanceId.startsWith('${d.instanceId}_'),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, List<ReportEntry>> _groupEntries() {
    if (_report == null) return {};

    final policyToUse = _currentPolicy ?? widget.policy;
    final Map<String, PolicyDevice> policyDevicesMap = {
      for (final d in policyToUse.devices) d.instanceId: d
    };

    final grouped = <String, List<ReportEntry>>{};

    for (final entry in _report!.entries) {
      String baseId = entry.instanceId;
      final lastUnderscore = baseId.lastIndexOf('_');
      if (lastUnderscore != -1) {
        final suffix = baseId.substring(lastUnderscore + 1);
        if (int.tryParse(suffix) != null) {
          baseId = baseId.substring(0, lastUnderscore);
        }
      }

      final deviceInstance =
          policyDevicesMap[baseId] ?? policyDevicesMap[entry.instanceId];
      if (deviceInstance == null) continue;

      final defId = deviceInstance.definitionId;
      (grouped[defId] ??= []).add(entry);
    }

    return grouped;
  }

  String _getFrequencies(Map<String, List<ReportEntry>> grouped) {
    final bool isWeekly = widget.dateStr.contains('W');
    if (!isWeekly) return "Mensual";

    final Set<String> frecuenciasPresentes = {};
    final policyToUse = _currentPolicy ?? widget.policy;
    // ✅ Usar mapa para O(1) lookups
    final defMap = {for (final d in _devicesEffective) d.id: d};

    for (final devInstance in policyToUse.devices) {
      final def = defMap[devInstance.definitionId];
      if (def == null) continue;
      for (final act in def.activities) {
        if (act.frequency == Frequency.SEMANAL) {
          frecuenciasPresentes.add('Semanal');
        } else if (act.frequency == Frequency.QUINCENAL) {
          frecuenciasPresentes.add('Quincenal');
        }
      }
    }

    if (frecuenciasPresentes.isEmpty) return "Semanal";
    final lista = frecuenciasPresentes.toList()..sort();
    return lista.join(' / ');
  }

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #9: RESOLUCIÓN DE ÍNDICE GLOBAL EN O(1)
  // En lugar de _report!.entries.indexWhere(...) que es O(n),
  // usamos el mapa pre-calculado.
  // ══════════════════════════════════════════════════════════════════════
  int _globalIndexOf(String instanceId) {
    return _instanceIdToGlobalIndex[instanceId] ?? -1;
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _report == null || _companySettings == null) {
      return const Scaffold(
        backgroundColor: _bgLight,
        body: Center(child: CircularProgressIndicator(color: _primaryDark)),
      );
    }

    // ✅ NO recalculamos nada aquí - todo viene del caché
    final groupedEntriesList = _cachedGroupedEntries;
    final frequencies = _cachedFrequencies;
    final assignedUsers = _cachedAssignedUsers;

    String adminTooltip = 'Modo Admin';
    if (_isUserCoordinator()) {
      final role = _currentUser!.role;
      final isHighRole =
          role == UserRole.SUPER_USER || role == UserRole.ADMIN;
      final label = isHighRole ? '$role' : 'Responsable de Póliza';
      adminTooltip = _adminOverride
          ? 'Modo Admin Activo ($label)'
          : 'Activar Modo Admin ($label)';
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: _buildAppBar(adminTooltip),
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
                  isUserDesignated:
                      _report!.assignedTechnicianIds.contains(_currentUserId),
                  onStartService: _handleStartService,
                  onEndService: _handleEndService,
                  onResumeService: _handleResumeService,
                  onDateChanged: (newDate) {
                    _report = _report!.copyWith(serviceDate: newDate);
                    setState(() {});
                    _saveImmediate();
                  },
                  onStartTimeEdited: (newTime) {
                    _report = _report!.copyWith(startTime: newTime);
                    setState(() {});
                    _saveImmediate();
                  },
                  onEndTimeEdited: (newTime) {
                    _report = _report!.copyWith(endTime: newTime);
                    setState(() {});
                    _saveImmediate();
                  },
                ),
              ],
            ),
          ),

          // ══════════════════════════════════════════════════════════
          // ✅ OPTIMIZACIÓN #10: SliverList con callbacks O(1)
          // ══════════════════════════════════════════════════════════
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final entryGroup = groupedEntriesList[index];
              final defId = entryGroup.key;
              final sectionEntries = entryGroup.value;

              final deviceDef = _devicesEffective.firstWhere(
                (d) => d.id == defId,
                orElse: () => DeviceModel(
                  id: defId,
                  name: 'Desconocido',
                  description: '',
                  activities: [],
                ),
              );

              // ✅ Wrap en RepaintBoundary para aislar repaints
              return RepaintBoundary(
                child: DeviceSectionImproved(
                  defId: defId,
                  deviceDef: deviceDef,
                  entries: sectionEntries,
                  users: assignedUsers,
                  sectionAssignments:
                      _report!.sectionAssignments[defId] ?? [],
                  isEditable: _isEditable(),
                  allowedToEdit: _isEditable(),
                  isUserCoordinator: _isUserCoordinator(),
                  adminOverride: _adminOverride,
                  currentUserId: _currentUserId,
                  onToggleAssignment: (uid) =>
                      _toggleSectionAssignment(defId, uid),
                  // ✅ O(1) global index lookup
                  onCustomIdChanged: (localIndex, val) {
                    final gi =
                        _globalIndexOf(sectionEntries[localIndex].instanceId);
                    if (gi != -1) _updateEntry(gi, customId: val, rebuild: false);
                  },
                  onAreaChanged: (localIndex, val) {
                    final gi =
                        _globalIndexOf(sectionEntries[localIndex].instanceId);
                    if (gi != -1) _updateEntry(gi, area: val, rebuild: false);
                  },
                  onToggleStatus: (localIndex, activityId) {
                    final gi =
                        _globalIndexOf(sectionEntries[localIndex].instanceId);
                    if (gi != -1) _toggleStatus(gi, activityId, defId);
                  },
                  onCameraClick: (localIndex, {activityId}) {
                    final gi =
                        _globalIndexOf(sectionEntries[localIndex].instanceId);
                    if (gi != -1)
                      _handleCameraClick(gi, activityId: activityId);
                  },
                  onObservationClick: (localIndex, {activityId}) {
                    final gi =
                        _globalIndexOf(sectionEntries[localIndex].instanceId);
                    if (gi != -1) {
                      setState(() {
                        _activeObservationEntry = gi.toString();
                        _activeObservationActivityId = activityId;
                      });
                    }
                  },
                ),
              );
            }, childCount: groupedEntriesList.length),
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
                    _report = _report!.copyWith(providerSignerName: val);
                    _scheduleSave();
                  },
                  onClientNameChanged: (val) {
                    _report = _report!.copyWith(clientSignerName: val);
                    _scheduleSave();
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

  // ══════════════════════════════════════════════════════════════════════
  // APP BAR
  // ══════════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(String adminTooltip) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Color(0xFF1E293B),
          size: 20,
        ),
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
                _buildStatusChip(),
              ],
            ],
          ),
        ],
      ),
      actions: [
        if (_isUserCoordinator())
          IconButton(
            icon: Icon(
              _adminOverride
                  ? Icons.admin_panel_settings
                  : Icons.admin_panel_settings_outlined,
              color: _adminOverride
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF94A3B8),
              size: 22,
            ),
            onPressed: () => setState(() => _adminOverride = !_adminOverride),
            tooltip: adminTooltip,
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildStatusChip() {
    final isRunning = _report!.endTime == null;
    final color = isRunning ? const Color(0xFF10B981) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRunning ? Icons.play_circle : Icons.check_circle,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isRunning ? 'En curso' : 'Finalizado',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ✅ OPTIMIZACIÓN #11: OBSERVACIONES GENERALES CON CONTROLLER ESTABLE
  // ══════════════════════════════════════════════════════════════════════

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
        String distinctId = entry.customId.isNotEmpty
            ? entry.customId
            : 'Dispositivo #${entry.deviceIndex}';
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
          _buildSectionHeader(
            Icons.notes,
            'OBSERVACIONES GENERALES DEL SERVICIO',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            // ✅ Usa el controller estable - no se recrea en cada build
            child: TextField(
              enabled: _isEditable(),
              controller: _generalObsController,
              maxLines: 3,
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              decoration: InputDecoration(
                hintText:
                    'Comentarios globales sobre la visita, accesos, estado general...',
                hintStyle:
                    TextStyle(color: Colors.grey.shade400, fontSize: 12),
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
                  borderSide: const BorderSide(
                    color: Color(0xFF3B82F6),
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (val) {
                _generalObsDebounce?.cancel();
                _generalObsDebounce =
                    Timer(const Duration(milliseconds: 1500), () {
                  _report = _report!.copyWith(generalObservations: val);
                  _scheduleSave();
                });
              },
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildSectionHeader(
            Icons.find_in_page_outlined,
            'COMENTARIOS / HALLAZGOS REGISTRADOS EN DISPOSITIVOS',
            color: const Color(0xFFF59E0B),
          ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
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
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "No se registraron observaciones individuales en los equipos.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
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

  Widget _buildSectionHeader(
    IconData icon,
    String title, {
    Color color = const Color(0xFF3B82F6),
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // MODALES
  // ══════════════════════════════════════════════════════════════════════

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
      title = entry.customId.isNotEmpty
          ? entry.customId
          : 'Dispositivo #${entry.deviceIndex}';
      subtitle = entry.area.isNotEmpty
          ? entry.area
          : 'Sin ubicación especificada';
      icon = Icons.devices_other;
      accentColor = const Color(0xFF3B82F6);
    }

    return _ObservationModal(
      key: ValueKey(
        'obs_${entryIdx}_${_activeObservationActivityId ?? 'device'}',
      ),
      initialText: currentObservation,
      title: title,
      subtitle: subtitle,
      icon: icon,
      accentColor: accentColor,
      onClose: () => setState(() {
        _activeObservationEntry = null;
        _activeObservationActivityId = null;
      }),
      onSave: (text) {
        if (_activeObservationActivityId != null) {
          final currentData =
              entry.activityData[_activeObservationActivityId!] ??
              ActivityData(photoUrls: [], observations: '');
          final newActivityData =
              Map<String, ActivityData>.from(entry.activityData);
          newActivityData[_activeObservationActivityId!] = ActivityData(
            photoUrls: currentData.photoUrls,
            observations: text,
          );
          _updateEntry(entryIdx, activityData: newActivityData);
        } else {
          _updateEntry(entryIdx, observations: text);
        }
        setState(() {
          _activeObservationEntry = null;
          _activeObservationActivityId = null;
        });
      },
    );
  }

  Widget _buildPhotoModal() {
    if (_photoContextEntryIdx == null) return const SizedBox();
    final entry = _report!.entries[_photoContextEntryIdx!];

    List<String> photos;
    String contextTitle;

    if (_photoContextActivityId != null) {
      photos =
          entry.activityData[_photoContextActivityId]?.photoUrls ?? [];
      contextTitle = 'Fotos de Actividad • ${entry.customId}';
    } else {
      photos = entry.photoUrls;
      contextTitle = 'Fotos del Dispositivo • ${entry.customId}';
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
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
                  child: const Icon(
                    Icons.photo_library,
                    color: Color(0xFF3B82F6),
                    size: 22,
                  ),
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
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: () => setState(() {
                    _photoContextEntryIdx = null;
                    _photoContextActivityId = null;
                  }),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                  onPressed: _showImageSourceSelection,
                  icon: const Icon(Icons.add_a_photo, size: 20),
                  label: const Text(
                    'Agregar Fotos',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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

  Widget _buildPhotoThumbnail(String photoUrl, int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              photoUrl,
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
                        Icon(Icons.error_outline,
                            color: Color(0xFFEF4444), size: 24),
                        SizedBox(height: 4),
                        Text('Error',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                );
              },
            ),
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
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showDeleteConfirmation(index),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B), size: 24),
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
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDeletePhoto(photoIndex);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// OBSERVATION MODAL (Sin cambios significativos, ya estaba bien aislado)
// ══════════════════════════════════════════════════════════════════════════

class _ObservationModal extends StatefulWidget {
  final String initialText;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onClose;
  final Function(String) onSave;

  const _ObservationModal({
    super.key,
    required this.initialText,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onClose,
    required this.onSave,
  });

  @override
  State<_ObservationModal> createState() => _ObservationModalState();
}

class _ObservationModalState extends State<_ObservationModal> {
  late final TextEditingController _controller;
  late int _charCount;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _charCount = widget.initialText.length;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 24,
        right: 24,
        top: 12,
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  widget.accentColor.withOpacity(0.1),
                  widget.accentColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: widget.accentColor.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(widget.icon,
                      color: widget.accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF94A3B8), size: 22),
                  onPressed: widget.onClose,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                controller: _controller,
                maxLines: 6,
                maxLength: 500,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF334155),
                ),
                decoration: InputDecoration(
                  hintText:
                      'Describa cualquier anomalía, condición especial o recomendación técnica...',
                  hintStyle: TextStyle(
                      color: Colors.grey.shade400, fontSize: 13),
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
                    borderSide: BorderSide(
                        color: widget.accentColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                  counterText: '',
                ),
                onChanged: (value) {
                  setState(() => _charCount = value.length);
                },
              ),
              Positioned(
                bottom: 8,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _charCount > 450
                        ? Colors.red.shade50
                        : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _charCount > 450
                          ? Colors.red.shade200
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Text(
                    '$_charCount/500',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _charCount > 450
                          ? Colors.red.shade700
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: const Color(0xFF64748B),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Cancelar",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Guardar',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () => widget.onSave(_controller.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}