// ═══════════════════════════════════════════════════════════════════════
// ServiceReportScreen — Refactorizado con Riverpod
//   - _adminOverride, _currentUserId → estado local de UI
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:ici_check/features/devices/data/devices_repository.dart';
import 'package:ici_check/features/reports/services/device_location_service.dart';
import 'package:ici_check/features/reports/services/offline_photo_queue.dart';
import 'package:ici_check/features/reports/services/photo_storage_service.dart';
import 'package:ici_check/features/reports/services/photo_sync_service.dart';
import 'package:ici_check/features/reports/widgets/device_section_improved.dart';
import 'package:ici_check/features/reports/widgets/renumber_dialog.dart';
import 'package:ici_check/features/reports/widgets/report_controls.dart';
import 'package:ici_check/features/reports/widgets/report_header.dart';
import 'package:ici_check/features/reports/widgets/report_signatures.dart';
import 'package:ici_check/features/reports/widgets/report_summary.dart';
import 'package:ici_check/features/reports/state/report_providers.dart';
import 'package:ici_check/features/reports/state/report_state.dart';
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

class ServiceReportScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ServiceReportScreen> createState() =>
      _ServiceReportScreenState();
}

class _ServiceReportScreenState extends ConsumerState<ServiceReportScreen> {
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
  final PhotoSyncService _photoSyncService = PhotoSyncService();

  // ══════════════════════════════════════════════════════════════════════
  // ESTADO LOCAL DE UI (no pertenece al Notifier)
  // ══════════════════════════════════════════════════════════════════════
  CompanySettingsModel? _companySettings;
  PolicyModel? _currentPolicy;
  List<DeviceModel> _currentDevices = [];
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  bool _adminOverride = false;
  String? _currentUserId;
  UserModel? _currentUser;

  // Suscripciones a Firebase
  StreamSubscription? _policySubscription;
  StreamSubscription? _reportSubscription;
  StreamSubscription? _devicesSubscription;
  // ★ Timestamp del último save para ignorar ecos de Firebase

  // Ubicaciones guardadas
  Map<String, Map<String, String>> _savedLocations = {};

  // ★ Scroll groups para sincronización horizontal por sección
  final Map<String, LinkedScrollGroup> _scrollGroups = {};

  // Controladores de firma
  final SignatureController _providerSigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );
  final SignatureController _clientSigController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );
  Timer? _signatureDebounce;

  // Estados para Modales
  int? _activeObservationEntryIdx;
  String? _activeObservationActivityId;
  int? _photoContextEntryIdx;
  String? _photoContextActivityId;

  // Controller estable para observaciones generales
  late final TextEditingController _generalObsController;
  Timer? _generalObsDebounce;

  // Location save debounce
  Timer? _locationSaveDebounce;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Colores
  static const Color _bgLight = Color(0xFFF8FAFC);
  static const Color _primaryDark = Color(0xFF0F172A);

  List<DeviceModel> get _devicesEffective =>
      _currentDevices.isNotEmpty ? _currentDevices : widget.devices;

  // Acceso rápido al notifier
  ReportNotifier get _notifier =>
      ref.read(reportNotifierProvider.notifier);

  bool get _isCumulative => widget.dateStr == 'CUMULATIVE';

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
    // ★ NUEVO: Iniciar sincronización automática de fotos offline
    _photoSyncService.onSyncComplete = () {
      if (mounted) {
        _showSnackBar('Fotos offline sincronizadas', Colors.green);
      }
    };
    _photoSyncService.startListening();
  }

  @override
  void dispose() {
    // ★ FIX: Proteger acceso a ref en dispose (no puede usarse después de disposed)
    try {
      _notifier.saveLocalBackupOnDispose();
    } catch (e) {
      debugPrint('⚠️ Error al guardar backup en dispose: $e');
    }
    _locationSaveDebounce?.cancel();
    _signatureDebounce?.cancel();
    _providerSigController.dispose();
    _clientSigController.dispose();
    _policySubscription?.cancel();
    _reportSubscription?.cancel();
    _devicesSubscription?.cancel();
    _generalObsDebounce?.cancel();
    _generalObsController.dispose();
    // ★ Dispose scroll groups
    for (final group in _scrollGroups.values) {
      group.dispose();
    }
    _photoSyncService.stopListening();
    _scrollGroups.clear();
    super.dispose();
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

      final instanceIds = <String>[];
        for (final dev in widget.policy.devices) {
          for (int i = 1; i <= dev.quantity; i++) {
            instanceIds.add(ReportsRepository.unitInstanceId(dev.instanceId, i));
          }
        }

      _savedLocations = await _locationService.getLocationsForPolicy(
        widget.policyId,
        instanceIds,
      );

      // Stream de dispositivos
      _devicesSubscription =
          _devicesRepo.getDevicesStream().listen((updatedDevices) {
        if (!mounted) return;
        final bool firstLoad = _currentDevices.isEmpty;
        bool hasChanges = firstLoad ||
            _hasRelevantDeviceChanges(_currentDevices, updatedDevices);

        setState(() => _currentDevices = updatedDevices);

        if (!firstLoad && hasChanges) {
          _resyncReportWithCurrentDevices();
        }
      });

      // DESPUÉS: getPolicyStream(id) → solo escucha UN documento
      _policySubscription =
          _policiesRepo.getPolicyStream(widget.policyId).listen((updatedPolicy) {
        if (updatedPolicy == null) return;
        try {
          final previousPolicy = _currentPolicy;

          if (mounted) setState(() => _currentPolicy = updatedPolicy);

          if (previousPolicy != null &&
              _hasRelevantPolicyChanges(previousPolicy, updatedPolicy)) {
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
  // SINCRONIZACIÓN CON FIREBASE
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _resyncReportWithCurrentDevices() async {
    if (_isCumulative) return;
    final state = ref.read(reportNotifierProvider);
    if (state == null || _currentDevices.isEmpty) return;

    final policyToUse = _currentPolicy ?? widget.policy;
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    final idealEntries = _repo.generateEntriesForDate(
      policyToUse,
      widget.dateStr,
      _currentDevices,
      isWeekly,
      timeIndex,
      savedLocations: _savedLocations,
    );

    final mergedEntries = _mergeEntries(state.report.entries, idealEntries);
    if (!_entriesStructureChanged(state.report.entries, mergedEntries)) return;

    final updatedReport = state.report.copyWith(entries: mergedEntries);
    await _repo.saveReport(updatedReport);

    _notifier.syncFromFirebase(
      updatedReport,
      groupedEntries: _buildGroupedEntries(updatedReport),
      frequencies: _computeFrequencies(),
    );

    _showSnackBar(
      'Actividades actualizadas según la nueva frecuencia',
      Colors.blue,
    );
  }

  Future<void> _syncReportWithPolicy(PolicyModel updatedPolicy) async {
    if (_isCumulative) {
      final synced = await _repo.syncCumulativeReport(
        policy: updatedPolicy,
        definitions: _devicesEffective,
        savedLocations: _savedLocations,
      );
      if (synced == null || !mounted) return;

      _notifier.syncFromFirebase(
        synced,
        groupedEntries: _buildGroupedEntries(synced),
        frequencies: _computeFrequencies(),
      );
      _showSnackBar(
        'Reporte acumulativo actualizado con los cambios de la póliza',
        Colors.blue,
      );
      return;
    }

    final state = ref.read(reportNotifierProvider);
    if (state == null) return;

    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = _calculateTimeIndex(isWeekly);

    final idealEntries = _repo.generateEntriesForDate(
      updatedPolicy,
      widget.dateStr,
      _devicesEffective,
      isWeekly,
      timeIndex,
      savedLocations: _savedLocations,
    );

    final mergedEntries = _mergeEntries(state.report.entries, idealEntries);
    final updatedReport = state.report.copyWith(entries: mergedEntries);
    await _repo.saveReport(updatedReport);

    _notifier.syncFromFirebase(
      updatedReport,
      groupedEntries: _buildGroupedEntries(updatedReport),
      frequencies: _computeFrequencies(),
    );

    _showSnackBar(
      'Reporte actualizado con los cambios de la póliza',
      Colors.blue,
    );
  }

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

  Future<void> _syncAndLoadCumulativeReport(
    ServiceReportModel existingReport,
  ) async {
    final policyToUse = _currentPolicy ?? widget.policy;
    final cumulativeDefs = _devicesEffective; // Pasar todos, el repo filtra

    if (cumulativeDefs.isEmpty) {
      _handleNotifierUpdate(existingReport);
      return;
    }

    // Generar el ideal según la póliza actual usando syncCumulativeReport
    final synced = await _repo.syncCumulativeReport(
      policy: policyToUse,
      definitions: cumulativeDefs,
      savedLocations: _savedLocations,
    );

    if (synced == null) {
      _handleNotifierUpdate(existingReport);
      return;
    }

    // Merge: preserva respuestas, agrega nuevos, elimina removidos
    final mergedEntries = _mergeEntries(existingReport.entries, synced.entries);

    // Verificar si realmente hubo cambios para no guardar innecesariamente
    final hasChanges =
        _entriesStructureChanged(existingReport.entries, mergedEntries);

    if (!hasChanges) {
      _handleNotifierUpdate(existingReport);
      return;
    }

    final updatedReport = existingReport.copyWith(entries: mergedEntries);
    _repo.saveReport(updatedReport); // fire-and-forget
    _handleNotifierUpdate(updatedReport);
  }

void _syncAndLoadReport(ServiceReportModel existingReport) {
  // ★ FIX REALTIME: Reducido de 3s a 1s.
  // 1 segundo es suficiente para ignorar nuestro propio eco de Firebase,
  // pero no bloquea updates legítimos del otro usuario.
  final lastSave = _notifier.lastSaveTimestamp;
  if (lastSave != null &&
      DateTime.now().difference(lastSave) < const Duration(seconds: 1)) {
    return;
  }
 
  // ★ MERGE FIX: Si hay cambios pendientes Y ya cargó → MERGE
  if (_notifier.hasPendingChanges && !_isLoading) {
    final localState = ref.read(reportNotifierProvider);
    if (localState != null) {
      final mergedReport = _notifier.mergeServerWithLocal(existingReport);
      _handleNotifierUpdate(mergedReport);
      return;
    }
  }
 
  if (_isCumulative) {
    _syncAndLoadCumulativeReport(existingReport);
    return;
  }
 
  final currentState = ref.read(reportNotifierProvider);
  if (currentState != null && !_isLoading) {
    final current = currentState.report;
 
    // ★ FIX REALTIME: Comparación rápida de metadata primero
    if (current.entries.length != existingReport.entries.length ||
        current.startTime != existingReport.startTime ||
        current.endTime != existingReport.endTime ||
        current.generalObservations != existingReport.generalObservations ||
        current.providerSignerName != existingReport.providerSignerName ||
        current.clientSignerName != existingReport.clientSignerName ||
        jsonEncode(current.assignedTechnicianIds) !=
            jsonEncode(existingReport.assignedTechnicianIds) ||
        jsonEncode(current.sectionAssignments) !=
            jsonEncode(existingReport.sectionAssignments)) {
      // Metadata cambió → procesar update (no hacer return)
    } else {
      // Metadata igual → revisar entries
 
      // ★ FIX REALTIME: Revisar TODOS los entries, no solo 3 muestreados.
      // Esto detecta cambios del otro usuario sin importar en qué entry estén.
      bool likelySame = true;
 
      for (int i = 0; i < current.entries.length && likelySame; i++) {
        if (i >= existingReport.entries.length) {
          likelySame = false;
          break;
        }
 
        final a = current.entries[i];
        final b = existingReport.entries[i];
 
        // Comparar instanceId y cantidad de results
        if (a.instanceId != b.instanceId ||
            a.results.length != b.results.length) {
          likelySame = false;
          break;
        }
 
        // Comparar cada resultado (toggle status)
        for (final key in a.results.keys) {
          if (a.results[key] != b.results[key]) {
            likelySame = false;
            break;
          }
        }
 
        // ★ FIX REALTIME: También detectar results nuevos del servidor
        if (likelySame) {
          for (final key in b.results.keys) {
            if (!a.results.containsKey(key)) {
              likelySame = false;
              break;
            }
          }
        }
 
        // ★ FIX REALTIME: Detectar cambios en observations y fotos
        if (likelySame) {
          if (a.observations != b.observations ||
              a.photoUrls.length != b.photoUrls.length) {
            likelySame = false;
          }
        }
 
        // ★ FIX REALTIME: Detectar cambios en activityData (fotos/obs por actividad)
        if (likelySame) {
          if (a.activityData.length != b.activityData.length) {
            likelySame = false;
          } else {
            for (final actKey in b.activityData.keys) {
              final aData = a.activityData[actKey];
              final bData = b.activityData[actKey];
              if (aData == null && bData != null) {
                likelySame = false;
                break;
              }
              if (aData != null && bData != null) {
                if (aData.observations != bData.observations ||
                    aData.photoUrls.length != bData.photoUrls.length) {
                  likelySame = false;
                  break;
                }
              }
            }
          }
        }
      }
 
      if (likelySame) return; // ← Solo retorna si REALMENTE es idéntico
    }
  }
 
  // ══════════════════════════════════════════════════════════════
  // A partir de aquí TODO sigue igual que tu código original
  // ══════════════════════════════════════════════════════════════
 
  if (_devicesEffective.isEmpty) {
    _handleNotifierUpdate(existingReport);
    return;
  }
 
  bool isWeekly = widget.dateStr.contains('W');
  int timeIndex = _calculateTimeIndex(isWeekly);
  final policyToUse = _currentPolicy ?? widget.policy;
 
  final localState = ref.read(reportNotifierProvider);
  if (localState != null) {
    for (final entry in localState.report.entries) {
      _savedLocations[entry.instanceId] = {
        'customId': entry.customId,
        'area': entry.area,
      };
    }
  }
 
  final idealEntries = _repo.generateEntriesForDate(
    policyToUse,
    widget.dateStr,
    _devicesEffective,
    isWeekly,
    timeIndex,
    savedLocations: _savedLocations,
  );
 
  final mergedEntries =
      _mergeEntries(existingReport.entries, idealEntries);
 
  bool hasStructureChanges =
      _entriesStructureChanged(existingReport.entries, mergedEntries);
 
  bool hasLocationChanges = false;
 
  if (!hasStructureChanges && _savedLocations.isNotEmpty) {
    for (int i = 0; i < mergedEntries.length; i++) {
      if (i >= existingReport.entries.length) break;
 
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
    _handleNotifierUpdate(updatedReport);
    _repo.saveReport(updatedReport);
  } else {
    _handleNotifierUpdate(existingReport);
  }
}

// SOLUCIÓN 2: Función de apoyo para evitar reiniciar la UI si ya había cargado
void _handleNotifierUpdate(ServiceReportModel report) {
  if (_isLoading) {
    _initializeNotifier(report);
  } else {
    _notifier.syncFromFirebase(
      report,
      groupedEntries: _buildGroupedEntries(report),
      frequencies: _computeFrequencies(),
    );
  }
}

  void _initializeNewReport() {
    if (_isCumulative) {
      _initializeCumulativeReport();
      return;
    }

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
    _initializeNotifier(newReport);
  }

  void _initializeCumulativeReport() async {
    // ★ Usar syncCumulativeReport en lugar de getOrCreateCumulativeReport
    // así siempre queda alineado con la póliza actual
    final report = await _repo.syncCumulativeReport(
      policy: _currentPolicy ?? widget.policy,
      definitions: _devicesEffective,
      savedLocations: _savedLocations,
    );

    if (report == null) {
      if (mounted) {
        _showSnackBar(
          'No hay dispositivos acumulativos configurados',
          Colors.orange,
        );
        Navigator.pop(context);
      }
      return;
    }

    _initializeNotifier(report);
  }

  /// Inicializa el Notifier con un report y marca la carga como completada
  void _initializeNotifier(ServiceReportModel report) {
    final grouped = _buildGroupedEntries(report);
    final frequencies = _computeFrequencies();

    _notifier.initialize(
      ReportState.fromReport(
        report,
        groupedEntries: grouped,
        frequencies: frequencies,
      ),
    );

    _syncGeneralObsController(report.generalObservations);

    Future.microtask(() async {
      if (!mounted) return;
      await _notifier.restoreLocalDirtyBackup(report.id);
    });

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  void _syncGeneralObsController(String newText) {
    if (_generalObsController.text != newText) {
      _generalObsController.text = newText;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // HELPERS DE AGRUPACIÓN (solo usados en sync, NO en build)
  // ══════════════════════════════════════════════════════════════════════

  List<MapEntry<String, List<ReportEntry>>> _buildGroupedEntries(
    ServiceReportModel report,
  ) {
    final policyToUse = _currentPolicy ?? widget.policy;
    final Map<String, PolicyDevice> policyDevicesMap = {
      for (final d in policyToUse.devices) d.instanceId: d,
    };

    final grouped = <String, List<ReportEntry>>{};

    for (final entry in report.entries) {
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

      final excludedIds = deviceInstance.excludedActivities;
      final cumulativeIds = deviceInstance.cumulativeActivities;

      // En reporte normal: ocultar excluidas + ocultar acumulativas
      // En reporte acumulativo: ocultar excluidas + ocultar las NO acumulativas
      final Set<String> idsToRemove;
      if (_isCumulative) {
        final allResultKeys = entry.results.keys.toSet();
        idsToRemove = {
          ...excludedIds,
          ...allResultKeys.where((k) => !cumulativeIds.contains(k)),
        };
      } else {
        idsToRemove = {...excludedIds, ...cumulativeIds};
      }

      if (idsToRemove.isNotEmpty) {
        final filteredResults = Map<String, String?>.from(entry.results)
          ..removeWhere((key, _) => idsToRemove.contains(key));

        if (filteredResults.isEmpty) continue;

        final filteredEntry = ReportEntry(
          instanceId: entry.instanceId,
          deviceIndex: entry.deviceIndex,
          customId: entry.customId,
          area: entry.area,
          results: filteredResults,
          observations: entry.observations,
          photoUrls: entry.photoUrls,
          activityData: Map<String, ActivityData>.from(entry.activityData)
            ..removeWhere((key, _) => idsToRemove.contains(key)),
          assignedUserId: entry.assignedUserId,
        );
        (grouped[defId] ??= []).add(filteredEntry);
        continue;
      }
      (grouped[defId] ??= []).add(entry);
    }

   // ★ FIX: Ordenar las secciones según el orden de devices en la póliza
    final policyDefOrder = <String, int>{};
    for (int i = 0; i < policyToUse.devices.length; i++) {
      final defId = policyToUse.devices[i].definitionId;
      // Solo guardar la PRIMERA aparición (el orden del primer device de ese tipo)
      policyDefOrder.putIfAbsent(defId, () => i);
    }

    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) {
        final orderA = policyDefOrder[a.key] ?? 999;
        final orderB = policyDefOrder[b.key] ?? 999;
        return orderA.compareTo(orderB);
      });

    return sortedEntries;
  }

  String _computeFrequencies() {
    if (_isCumulative) return "Acumulativo";
    final bool isWeekly = widget.dateStr.contains('W');
    if (!isWeekly) return "Mensual";

    final Set<String> frecuenciasPresentes = {};
    final policyToUse = _currentPolicy ?? widget.policy;
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

  int _calculateTimeIndex(bool isWeekly) {
    if (_isCumulative) return 0;
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
  // PERMISOS (estado local de UI)
  // ══════════════════════════════════════════════════════════════════════

  bool _isEditable(ReportState state) {
    if (_adminOverride) return true;
    return state.report.startTime != null && state.report.endTime == null;
  }

  /// ★ NUEVO: Verifica si el reporte está en progreso (iniciado y no finalizado)
  bool _isReportInProgress(ReportState state) {
    return state.report.startTime != null && state.report.endTime == null;
  }

  /// ★ NUEVO: Obtiene los nombres de los técnicos asignados que están trabajando
  String _getActiveTechnicianNames(ReportState state) {
    final techIds = state.report.assignedTechnicianIds;
    if (techIds.isEmpty) return '';

    final names = <String>[];
    for (final uid in techIds) {
      final user = widget.users.firstWhere(
        (u) => u.id == uid,
        orElse: () => UserModel(id: uid, name: 'Usuario', email: ''),
      );
      names.add(user.name);
    }
    return names.join(', ');
  }

  bool _isUserCoordinator() {
    if (_currentUser == null) return false;
    if (_currentUser!.role == UserRole.SUPER_USER ||
        _currentUser!.role == UserRole.ADMIN) {
      return true;
    }
    return widget.policy.assignedUserIds.contains(_currentUserId);
  }

  bool _areAllSectionsAssigned(ReportState state) {
    final activeDefIds = <String>{};
    for (final entry in state.report.entries) {
      if (entry.results.isEmpty) continue;
      final deviceInstance = _findPolicyDevice(entry.instanceId);
      if (deviceInstance != null) {
        activeDefIds.add(deviceInstance.definitionId);
      }
    }
    for (final defId in activeDefIds) {
      final assigned = state.report.sectionAssignments[defId];
      if (assigned == null || assigned.isEmpty) return false;
    }
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════
  // ACCIONES DE SERVICIO
  // ══════════════════════════════════════════════════════════════════════

  void _handleStartService() {
    final state = ref.read(reportNotifierProvider);
    if (state == null || _currentUserId == null) {
      _showSnackBar(
        'Debes seleccionar un usuario para registrar tiempos',
        Colors.orange,
      );
      return;
    }

    if (!_areAllSectionsAssigned(state)) {
      _showSnackBar(
        'No se puede iniciar: Hay tipos de dispositivos sin responsable asignado.',
        Colors.red,
        seconds: 3,
      );
      return;
    }

    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);
    _notifier.startService(timeStr, now);
    // ★ NUEVO: Desactivar modo admin automáticamente al iniciar servicio
    if (_adminOverride) {
      setState(() => _adminOverride = false);
    }
  }

  void _handleEndService() {
    final state = ref.read(reportNotifierProvider);
    if (state == null || _currentUserId == null) {
      _showSnackBar(
        'Debes seleccionar un usuario para registrar tiempos',
        Colors.orange,
      );
      return;
    }

    if (!_areAllSectionsAssigned(state)) {
      _showSnackBar(
        'Asigna técnicos a todas las secciones antes de finalizar.',
        Colors.red,
      );
      return;
    }

    final nokSinFoto = _notifier.getNokWithoutPhotos(_devicesEffective);
    if (nokSinFoto.isNotEmpty) {
      _showNokPhotoDialog(nokSinFoto);
      return;
    }

    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    _notifier.endService(timeStr);
  }

  void _handleResumeService() {
    _notifier.resumeService();
    // ★ NUEVO: Desactivar modo admin automáticamente al reanudar
    if (_adminOverride) {
      setState(() => _adminOverride = false);
    }
  }


  void _showNokPhotoDialog(List<String> missing) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.photo_camera_outlined, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Fotos requeridas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Las siguientes actividades marcadas como NOK requieren evidencia fotográfica:',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              // ★ FIX: Usar ConstrainedBox + SingleChildScrollView en vez de ListView.builder
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: missing.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Entendido',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // LLENAR TODO OK (Admin)
  // ══════════════════════════════════════════════════════════════════════

  void _confirmFillAllOk() {
    final state = ref.read(reportNotifierProvider);
    if (state == null) return;

    final pendingCount = state.stats.pending + state.stats.nr;
    if (pendingCount == 0) {
      _showSnackBar('No hay actividades pendientes por llenar', Colors.blue);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.done_all_rounded, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 12),
            Text('Llenar Todo con OK', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          'Se marcarán $pendingCount actividades pendientes como OK.\n\nLas actividades ya marcadas como NOK o N/A no se modificarán.\n\n¿Deseas continuar?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _notifier.fillAllOk();
              _showSnackBar(
                '$pendingCount actividades marcadas como OK',
                const Color(0xFF10B981),
              );
            },
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Confirmar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRenumberFromHere(
    int globalIndex,
    String defId,
    List<ReportEntry> sectionEntries,
    Map<String, int> indexMap,
  ) async {
    final state = ref.read(reportNotifierProvider);
    if (state == null) return;

    final entry = state.report.entries[globalIndex];

    // Calcular cuántos entries quedan desde este punto en la sección
    final sectionGlobalIndices = sectionEntries
        .map((e) => indexMap[e.instanceId] ?? -1)
        .where((i) => i >= globalIndex)
        .toList()
      ..sort();

    if (sectionGlobalIndices.isEmpty) return;

    final config = await showRenumberDialog(
      context: context,
      currentId: entry.customId,
      remainingCount: sectionGlobalIndices.length,
    );

    if (config == null) return; // Usuario canceló

    // Aplicar la renumeración a cada entry de la sección desde este punto
    int offset = 0;
    for (final gi in sectionGlobalIndices) {
      final newId = config.generateId(offset);
      _notifier.updateCustomId(gi, newId);
      offset++;
    }

    _showSnackBar(
      '${sectionGlobalIndices.length} IDs renumerados: ${config.generateId(0)} → ${config.generateId(sectionGlobalIndices.length - 1)}',
      const Color(0xFF3B82F6),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // FIRMAS
  // ══════════════════════════════════════════════════════════════════════

  void _onSignatureChanged() {
    _signatureDebounce?.cancel();
    _signatureDebounce = Timer(const Duration(seconds: 2), () {
      _processAndSaveSignatures();
    });
  }

  Future<void> _processAndSaveSignatures() async {
  final state = ref.read(reportNotifierProvider);
  if (state == null) return;

  String? providerSigBase64 = state.report.providerSignature;
  String? clientSigBase64 = state.report.clientSignature;
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
    _notifier.updateSignatures(
      providerSignature: providerSigBase64,
      clientSignature: clientSigBase64,
    );
  }
}

  // ══════════════════════════════════════════════════════════════════════
  // FOTOS
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _handleCameraClick(int entryIdx, {String? activityId}) async {
    final state = ref.read(reportNotifierProvider);
    if (state == null) return;

    final entry = state.report.entries[entryIdx];
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
                leading:
                    const Icon(Icons.camera_alt, color: Color(0xFF3B82F6)),
                title: const Text('Tomar Foto'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: Color(0xFF3B82F6)),
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

  // En _pickFromCamera():
  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (image != null) {
        if (!kIsWeb) { // ← Solo guardar en galería en móvil
          try {
            await Gal.putImage(image.path, album: "ICI Check");
          } catch (e) {
            debugPrint("⚠️ Error guardando en galería local: $e");
          }
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
    final state = ref.read(reportNotifierProvider);
    if (_isUploadingPhoto || _photoContextEntryIdx == null || state == null) {
      return;
    }

    setState(() => _isUploadingPhoto = true);
    int successCount = 0;

    // ★ OFFLINE: Verificar conectividad
    bool isOffline = false;
    if (!kIsWeb) {
      final connectivity = await Connectivity().checkConnectivity();
      isOffline = connectivity.contains(ConnectivityResult.none);
    }

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
                Text(isOffline
                    ? 'Guardando localmente ${i + 1} de ${images.length}...'
                    : 'Subiendo ${i + 1} de ${images.length}...'),
              ],
            ),
            duration: const Duration(seconds: 10),
          ),
        );

        final bytes = await image.readAsBytes();
        final entryIdx = _photoContextEntryIdx!;
        final activityId = _photoContextActivityId;

        final currentState = ref.read(reportNotifierProvider)!;
        final entry = currentState.report.entries[entryIdx];

        String? photoUrl;

        if (isOffline) {
          // ★ OFFLINE: Guardar localmente
          photoUrl = await OfflinePhotoQueue.enqueue(
            photoBytes: bytes,
            reportId: '${widget.policyId}_${widget.dateStr}',
            deviceInstanceId: entry.instanceId,
            entryIndex: entryIdx,
            activityId: activityId,
          );

          if (photoUrl == null) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _showSnackBar(
              'Almacenamiento offline lleno. Conecta a internet para sincronizar.',
              Colors.red,
              seconds: 4,
            );
            break;
          }
        } else {
          // ★ ONLINE: Subir normalmente, con fallback offline si falla
          try {
            photoUrl = await _photoService.uploadPhoto(
              photoBytes: bytes,
              reportId: '${widget.policyId}_${widget.dateStr}',
              deviceInstanceId: entry.instanceId,
              activityId: activityId,
            );
          } catch (e) {
            debugPrint('⚠️ Upload online falló, guardando offline: $e');
            photoUrl = await OfflinePhotoQueue.enqueue(
              photoBytes: bytes,
              reportId: '${widget.policyId}_${widget.dateStr}',
              deviceInstanceId: entry.instanceId,
              entryIndex: entryIdx,
              activityId: activityId,
            );
          }
        }

        if (photoUrl == null) continue;

        // Actualizar el reporte con la URL (local o remota)
        if (activityId != null) {
          final currentData = entry.activityData[activityId] ??
              ActivityData(photoUrls: [], observations: '');
          final newPhotoUrls = [...currentData.photoUrls, photoUrl];
          final newActivityData =
              Map<String, ActivityData>.from(entry.activityData);
          newActivityData[activityId] = ActivityData(
            photoUrls: newPhotoUrls,
            observations: currentData.observations,
          );
          _notifier.updateActivityData(entryIdx, newActivityData);
        } else {
          final newPhotoUrls = [...entry.photoUrls, photoUrl];
          _notifier.updatePhotoUrls(entryIdx, newPhotoUrls);
        }
        successCount++;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (successCount > 0) {
        _showSnackBar(
          isOffline
              ? '$successCount foto(s) guardadas localmente ☁️'
              : successCount == 1
                  ? 'Foto subida'
                  : '$successCount fotos subidas',
          isOffline ? Colors.orange : Colors.green,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _confirmDeletePhoto(int photoIndex) async {
    final state = ref.read(reportNotifierProvider);
    if (_photoContextEntryIdx == null || state == null) return;

    final entryIdx = _photoContextEntryIdx!;
    final activityId = _photoContextActivityId;
    final entry = state.report.entries[entryIdx];
    String? photoUrlToDelete;

    if (activityId != null) {
      final currentData = entry.activityData[activityId];
      if (currentData != null && photoIndex < currentData.photoUrls.length) {
        photoUrlToDelete = currentData.photoUrls[photoIndex];
        final newPhotoUrls = List<String>.from(currentData.photoUrls);
        newPhotoUrls.removeAt(photoIndex);
        final newActivityData =
            Map<String, ActivityData>.from(entry.activityData);
        newActivityData[activityId] = ActivityData(
          photoUrls: newPhotoUrls,
          observations: currentData.observations,
        );
        _notifier.updateActivityData(entryIdx, newActivityData);
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
        _notifier.updatePhotoUrls(entryIdx, newPhotoUrls);
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
  // BUILD
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final reportState = ref.watch(reportNotifierProvider);

    if (_isLoading || reportState == null || _companySettings == null) {
      return const Scaffold(
        backgroundColor: _bgLight,
        body: Center(child: CircularProgressIndicator(color: _primaryDark)),
      );
    }

    final groupedEntriesList = reportState.groupedEntries;
    final frequencies = reportState.frequencies;

    final assignedUsers = widget.users
        .where((user) =>
            reportState.report.assignedTechnicianIds.contains(user.id))
        .toList();

    final isEditable = _isEditable(reportState);
    final indexMap = reportState.instanceIdToGlobalIndex;
    final notifier = ref.read(reportNotifierProvider.notifier);

    String adminTooltip = 'Modo Admin';
    if (_isUserCoordinator()) {
      final role = _currentUser!.role;
      final isHighRole =
          role == UserRole.SUPER_USER || role == UserRole.ADMIN;
      final label = isHighRole ? '$role' : 'Responsable de Póliza';

      if (_isReportInProgress(reportState)) {
        adminTooltip = 'No disponible mientras el servicio está en curso';
      } else {
        adminTooltip = _adminOverride
            ? 'Modo Admin Activo ($label)'
            : 'Activar Modo Admin ($label)';
      }
    }

    // ★ Construir lista plana de widgets con scroll sincronizado
    final List<Widget> sliverSectionGroups = [];
    for (final entryGroup in groupedEntriesList) {
      final defId = entryGroup.key;
      final entries = entryGroup.value;

      List<ReportEntry> filteredEntries = entries;
      if (_searchQuery.isNotEmpty) {
        filteredEntries = entries.where((e) {
          final customIdMatch = e.customId.toLowerCase().contains(_searchQuery);
          final areaMatch = e.area.toLowerCase().contains(_searchQuery);
          return customIdMatch || areaMatch;
        }).toList();
      }

      if (filteredEntries.isEmpty) continue;

      final deviceDef = _devicesEffective.firstWhere(
        (d) => d.id == defId,
        orElse: () => DeviceModel(
          id: defId,
          name: 'Desconocido',
          description: '',
          activities: [],
        ),
      );

      // ★ Obtener las actividades excluidas para este dispositivo
      final policyToUse = _currentPolicy ?? widget.policy;
      final excludedForDef = policyToUse.devices
          .where((d) => d.definitionId == defId)
          .expand((d) => d.excludedActivities)
          .toSet();

      final scheduledActivityIds = entries.expand((e) => e.results.keys).toSet();
      final cumulativeForDef = policyToUse.devices
          .where((d) => d.definitionId == defId)
          .expand((d) => d.cumulativeActivities)
          .toSet();

      final relevantActivities = deviceDef.activities.where((a) {
        if (!scheduledActivityIds.contains(a.id)) return false;
        if (excludedForDef.contains(a.id)) return false;
        if (_isCumulative) return cumulativeForDef.contains(a.id);
        return !cumulativeForDef.contains(a.id);
      }).toList();

      if (relevantActivities.isEmpty) continue;

      final assignments =
          reportState.report.sectionAssignments[defId] ?? [];

      // ★ Crear o reutilizar scroll group para esta sección
      _scrollGroups[defId] ??= LinkedScrollGroup();

      final sectionData = FlatSectionData(
        defId: defId,
        deviceDef: deviceDef,
        entries: filteredEntries, // ★ PASAMOS LOS EQUIPOS FILTRADOS
        assignments: assignments,
        relevantActivities: relevantActivities,
        users: assignedUsers,
        isEditable: isEditable,
        isUserCoordinator: _isUserCoordinator(),
        adminOverride: _adminOverride,
        currentUserId: _currentUserId,
        indexMap: indexMap,
        onCameraClick: (gi, {activityId}) =>
            _handleCameraClick(gi, activityId: activityId),
        onObservationClick: (gi, {activityId}) {
          setState(() {
            _activeObservationEntryIdx = gi;
            _activeObservationActivityId = activityId;
          });
        },
        scrollGroup: _scrollGroups[defId]!,
        onRenumberFromHere: (globalIndex) => _handleRenumberFromHere(
          globalIndex,
          defId,
          filteredEntries,
          indexMap,
        ),
      );

      sliverSectionGroups.add(buildSliverGroupForSection(sectionData, notifier));
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: _buildAppBar(adminTooltip, reportState),
      body: CustomScrollView(
        slivers: [

          SliverToBoxAdapter(
            child: Column(
              children: [
                // ★ OFFLINE: Banner de estado
                StreamBuilder<List<ConnectivityResult>>(
                  stream: Connectivity().onConnectivityChanged,
                  builder: (context, snapshot) {
                    final isOffline =
                        snapshot.data?.contains(ConnectivityResult.none) ?? false;
                    if (!isOffline) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FutureBuilder<int>(
                              future: OfflinePhotoQueue.pendingCount(),
                              builder: (ctx, snap) {
                                final pending = snap.data ?? 0;
                                return Text(
                                  pending > 0
                                      ? 'Modo Offline — $pending foto(s) pendientes de subir.'
                                      : 'Modo Offline — Los cambios se sincronizarán al reconectarse.',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF92400E),
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ReportHeader(
                  companySettings: _companySettings!,
                  client: widget.client,
                  serviceDate: reportState.report.serviceDate,
                  dateStr: widget.dateStr,
                  frequencies: frequencies,
                ),
                ReportControls(
                  users: widget.users,
                  adminOverride: _adminOverride,
                  isUserDesignated: reportState.report
                      .assignedTechnicianIds
                      .contains(_currentUserId),
                  currentUserId: _currentUserId,
                  onStartService: _handleStartService,
                  onEndService: _handleEndService,
                  onResumeService: _handleResumeService,
                ),
                const SizedBox(height: 16),
                _buildSearchBar(),
              ],
            ),
          ),
          if (sliverSectionGroups.isEmpty && _searchQuery.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'No se encontraron equipos\ncon "$_searchQuery"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
          ...sliverSectionGroups,
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildGeneralObservationsBox(reportState, isEditable),
                const ReportSummary(),
                ReportSignatures(
                  providerController: _providerSigController,
                  clientController: _clientSigController,
                  providerName: reportState.report.providerSignerName,
                  clientName: reportState.report.clientSignerName,
                  providerSignatureData: reportState.report.providerSignature,
                  clientSignatureData: reportState.report.clientSignature,
                  isEditable: true,
                  onProviderNameChanged: (val) {
                    _notifier.updateSignatures(providerName: val);
                  },
                  onClientNameChanged: (val) {
                    _notifier.updateSignatures(clientName: val);
                  },
                  onClearProviderSignature: () {
                    _providerSigController.clear();
                    _notifier.updateSignatures(
                      providerSignature: '',
                    );
                  },
                  onClearClientSignature: () {
                    _clientSigController.clear();
                    _notifier.updateSignatures(
                      clientSignature: '',
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: _activeObservationEntryIdx != null
          ? _buildObservationModal(reportState)
          : (_photoContextEntryIdx != null
              ? _buildPhotoModal(reportState)
              : null),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // APP BAR
  // ══════════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(
    String adminTooltip,
    ReportState reportState,
  ) {
    final bool inProgress = _isReportInProgress(reportState);
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
              if (reportState.report.startTime != null) ...[
                const SizedBox(width: 8),
                _buildStatusChip(reportState),
              ],
            ],
          ),
        ],
      ),
        actions: [
        // ★ NUEVO: Botón "Llenar Todo OK" solo para coordinadores con admin override
        if (_isUserCoordinator() && _adminOverride && _isEditable(reportState) && !inProgress)
          IconButton(
            icon: const Icon(
              Icons.done_all_rounded,
              color: Color(0xFF10B981),
              size: 22,
            ),
            onPressed: () => _confirmFillAllOk(),
            tooltip: 'Llenar todo con OK',
          ),
        if (_isUserCoordinator())
          IconButton(
            icon: Icon(
              inProgress
                  ? Icons.admin_panel_settings_outlined
                  : (_adminOverride
                      ? Icons.admin_panel_settings
                      : Icons.admin_panel_settings_outlined),
              color: inProgress
                  ? const Color(0xFFCBD5E1)
                  : (_adminOverride
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF94A3B8)),
              size: 22,
            ),
            onPressed: () {
              if (inProgress) {
                // ★ Mostrar diálogo informativo
                final techNames = _getActiveTechnicianNames(reportState);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Color(0xFF3B82F6), size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Servicio en curso',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Color(0xFFF59E0B), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Para evitar pérdida de respuestas, el modo Admin se bloquea mientras un técnico está trabajando en planta.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (techNames.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'TÉCNICO(S) EN PLANTA:',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.person,
                                      size: 16, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    techNames,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.circle,
                                          size: 6, color: Color(0xFF10B981)),
                                      SizedBox(width: 4),
                                      Text('Activo',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF10B981),
                                          )),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: const Text('Entendido',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
              } else {
                setState(() => _adminOverride = !_adminOverride);
              }
            },
            tooltip: adminTooltip,
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
        decoration: InputDecoration(
          hintText: 'Buscar equipo por ID o Ubicación...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
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
            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
          ),
        ),
        onChanged: (val) {
          // ★ Debounce para no saturar el hilo principal al escribir rápido
          if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 250), () {
            setState(() {
              _searchQuery = val.trim().toLowerCase();
            });
          });
        },
      ),
    );
  } 

  Widget _buildStatusChip(ReportState state) {
    final isRunning = state.report.endTime == null;
    final color =
        isRunning ? const Color(0xFF10B981) : const Color(0xFF64748B);
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
  // OBSERVACIONES GENERALES
  // ══════════════════════════════════════════════════════════════════════

  List<Map<String, dynamic>> _getRegisteredFindings(ReportState state) {
  final List<Map<String, dynamic>> findings = [];

    for (final entry in state.report.entries) {
      final nokActivityIds = entry.results.entries
          .where((e) => e.value == 'NOK')
          .map((e) => e.key)
          .toSet();

      final hasDeviceObs = entry.observations.trim().isNotEmpty;
      final hasActivityObs =
          entry.activityData.values.any((d) => d.observations.trim().isNotEmpty);
      final hasNok = nokActivityIds.isNotEmpty;

      if (!hasDeviceObs && !hasActivityObs && !hasNok) continue;

      final List<Map<String, dynamic>> lines = [];

      if (hasDeviceObs) {
        lines.add({'text': entry.observations.trim(), 'isNok': false});
      }

      for (final actId in nokActivityIds) {
        String actName = actId;
        for (final dev in _devicesEffective) {
          final match = dev.activities.where((a) => a.id == actId).toList();
          if (match.isNotEmpty) {
            actName = match.first.name;
            break;
          }
        }
        final actObs = entry.activityData[actId]?.observations.trim() ?? '';
        final text = actObs.isNotEmpty ? '$actName: $actObs' : actName;
        lines.add({'text': text, 'isNok': true});
      }

      for (final mapEntry in entry.activityData.entries) {
        if (nokActivityIds.contains(mapEntry.key)) continue;
        if (mapEntry.value.observations.trim().isEmpty) continue;

        String actName = mapEntry.key;
        for (final dev in _devicesEffective) {
          final match = dev.activities.where((a) => a.id == mapEntry.key).toList();
          if (match.isNotEmpty) {
            actName = match.first.name;
            break;
          }
        }
        lines.add({
          'text': '$actName: ${mapEntry.value.observations.trim()}',
          'isNok': false,
        });
      }

      if (lines.isNotEmpty) {
        final String distinctId = entry.customId.isNotEmpty
            ? entry.customId
            : 'Dispositivo #${entry.deviceIndex}';
        findings.add({
          'id': distinctId,
          'lines': lines as dynamic,
        });
      }
    }

    return findings;
  }

  Widget _buildGeneralObservationsBox(ReportState state, bool isEditable) {
  final registeredFindings = _getRegisteredFindings(state);
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
            Icons.notes, 'OBSERVACIONES GENERALES DEL SERVICIO'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextField(
            enabled: isEditable,
            controller: _generalObsController,
            maxLines: 3,
            style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
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
                _notifier.updateGeneralObservations(val);
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
                    final lines = List<Map<String, dynamic>>.from(finding['lines'] as List);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: lines.map((line) {
                                final isNok = line['isNok'] as bool;
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (isNok) ...[
                                        Container(
                                          width: 16,
                                          height: 16,
                                          margin: const EdgeInsets.only(top: 1, right: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          line['text'] as String,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isNok
                                                ? const Color(0xFFEF4444)
                                                : const Color(0xFF334155),
                                            fontWeight: isNok
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
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
                      Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.grey.shade400),
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

  Widget _buildObservationModal(ReportState state) {
    if (_activeObservationEntryIdx == null) return const SizedBox();

    final entryIdx = _activeObservationEntryIdx!;
    if (entryIdx >= state.report.entries.length) return const SizedBox();
    final entry = state.report.entries[entryIdx];

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
          'obs_${entryIdx}_${_activeObservationActivityId ?? 'device'}'),
      initialText: currentObservation,
      title: title,
      subtitle: subtitle,
      icon: icon,
      accentColor: accentColor,
      onClose: () => setState(() {
        _activeObservationEntryIdx = null;
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
          _notifier.updateActivityData(entryIdx, newActivityData);
        } else {
          _notifier.updateObservation(entryIdx, text);
        }
        setState(() {
          _activeObservationEntryIdx = null;
          _activeObservationActivityId = null;
        });
      },
    );
  }

  Widget _buildPhotoModal(ReportState state) {
    if (_photoContextEntryIdx == null) return const SizedBox();
    if (_photoContextEntryIdx! >= state.report.entries.length) {
      return const SizedBox();
    }

    final entry = state.report.entries[_photoContextEntryIdx!];

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
                  child: const Icon(Icons.photo_library,
                      color: Color(0xFF3B82F6), size: 22),
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
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF94A3B8)),
                  onPressed: () => setState(() {
                    _photoContextEntryIdx = null;
                    _photoContextActivityId = null;
                  }),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                  label: const Text('Agregar Fotos',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_a_photo_outlined,
                size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text('Sin fotos registradas',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text('Toca el botón para agregar evidencia fotográfica',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              textAlign: TextAlign.center),
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
            Text('Agregar',
                style: TextStyle(
                    color: Color(0xFF3B82F6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoThumbnail(String photoUrl, int index) {
    final bool isLocal = photoUrl.startsWith('local://');

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
            // ★ Imagen local o remota
            if (isLocal)
              Builder(builder: (context) {
                final thumbPath = OfflinePhotoQueue.getThumbnailPath(photoUrl);
                final filePath =
                    thumbPath ?? photoUrl.replaceFirst('local://', '');
                return Image.file(
                  File(filePath),
                  fit: BoxFit.cover,
                  cacheWidth: 200, // ★ Limita RAM del decoder
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFFEE2E2),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              color: Color(0xFFEF4444), size: 24),
                          SizedBox(height: 4),
                          Text('Error',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFFEF4444))),
                        ],
                      ),
                    ),
                  ),
                );
              })
            else
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                cacheWidth: 200, // ★ Limita RAM del decoder
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

            // ★ Badge "Local" para fotos offline
            if (isLocal)
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 10, color: Colors.white),
                      SizedBox(width: 3),
                      Text('Local',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
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
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _showDeleteConfirmation(index),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.white, size: 18),
                ),
              ),
            ),

            // Número
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
                child: Text('#${index + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
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
// OBSERVATION MODAL
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
                      Text(widget.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text(widget.subtitle,
                          style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Color(0xFF94A3B8), size: 22),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onClose();
                    });
                  },
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
              Text('DETALLES Y HALLAZGOS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5)),
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
                    fontSize: 14, height: 1.5, color: Color(0xFF334155)),
                decoration: InputDecoration(
                  hintText:
                      'Describa cualquier anomalía, condición especial o recomendación técnica...',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: widget.accentColor, width: 2)),
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
                            : Colors.grey.shade200),
                  ),
                  child: Text('$_charCount/500',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _charCount > 450
                              ? Colors.red.shade700
                              : const Color(0xFF94A3B8))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onClose();
                    });
                  },
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
                  onPressed: () {
                    // ★ FIX: Capturar el texto ANTES de cualquier cambio de estado
                    final text = _controller.text;
                    // Cerrar el teclado primero
                    FocusScope.of(context).unfocus();
                    // Esperar a que el teclado se cierre para evitar conflictos de layout
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onSave(text);
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
}

