// lib/features/reports/state/report_providers.dart
//
// ★ ESTE ES EL ÚNICO ARCHIVO DE PROVIDERS.
// ★ TODOS los imports deben apuntar a ESTE archivo.

import 'dart:async';
import 'package:flutter/foundation.dart'; // ★ CAMBIO 1: Nuevo import para compute()
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';
import 'package:ici_check/features/reports/services/device_location_service.dart';
import 'package:uuid/uuid.dart';
import 'report_state.dart';

// ★ CAMBIO 2: Función TOP-LEVEL para compute()
// ─────────────────────────────────────────────────────────────────
// compute() REQUIERE una función top-level (fuera de cualquier clase).
// Se ejecuta en un Isolate separado → la serialización pesada de
// 600+ entries a JSON NO bloquea el main thread.
// ─────────────────────────────────────────────────────────────────
Map<String, dynamic> _serializeReportInIsolate(ServiceReportModel report) {
  return report.toMap();
}

// ─────────────────────────────────────────────────────────────────
// NOTIFIER CENTRAL
// ─────────────────────────────────────────────────────────────────
class ReportNotifier extends Notifier<ReportState?> {
  final ReportsRepository _repo = ReportsRepository();
  final DeviceLocationService _locationService = DeviceLocationService();
  final _uuid = const Uuid();
  Timer? _saveDebounce;
  bool _hasPendingChanges = false;
  ServiceReportModel? _pendingReport;
  bool _isSaving = false; // ★ CAMBIO 3: Flag anti-concurrencia
  // En la clase ReportNotifier, junto a las otras variables de instancia:
  DateTime? _lastSaveTimestamp;
  DateTime? get lastSaveTimestamp => _lastSaveTimestamp;

  @override
  ReportState? build() => null;

  void initialize(ReportState initialState) {
    state = initialState;
  }

  // ═══════════════════════════════════════════════════════
  // TOGGLE STATUS — ÚNICO path que recalcula stats
  // ═══════════════════════════════════════════════════════
  void toggleStatus(int entryIndex, String activityId, {
    ActivityInputType inputType = ActivityInputType.toggle, // ★ NUEVO parámetro
    String? measuredValue, // ★ NUEVO: valor medido cuando inputType == value
  }) {
    if (state == null) return;
    final report = state!.report;
    if (entryIndex < 0 || entryIndex >= report.entries.length) return;

    final entry = report.entries[entryIndex];
    if (!entry.results.containsKey(activityId)) return;

    // ★ Si es tipo value, guardamos el valor medido directamente
    if (inputType == ActivityInputType.value) {
      if (measuredValue == null) return; // Nada que guardar
      final newResults = Map<String, String?>.from(entry.results);
      newResults[activityId] = measuredValue.isEmpty ? null : measuredValue;

      // Recalcular stats: un valor medido cuenta como "completado" (como OK)
      final currentStats = state!.stats;
      final oldValue = entry.results[activityId];
      int ok = currentStats.ok;
      int pending = currentStats.pending;

      // Quitar el conteo anterior
      if (oldValue == null || oldValue == 'NR') pending--;
      else ok--; // Contaba como completado

      // Sumar el nuevo
      if (measuredValue.isEmpty) pending++;
      else ok++; // Valor medido = completado

      final newStats = ReportStats(
        ok: ok, nok: currentStats.nok, na: currentStats.na, nr: currentStats.nr,
        total: currentStats.total, pending: pending,
      );

      final entries = List<ReportEntry>.from(report.entries);
      entries[entryIndex] = _copyEntry(entry, results: newResults);
      final newReport = report.copyWith(entries: entries);

      state = ReportState(
        report: newReport,
        stats: newStats,
        isFullyComplete: pending == 0,
        instanceIdToGlobalIndex: state!.instanceIdToGlobalIndex,
        groupedEntriesMap: state!.groupedEntriesMap,
        frequencies: state!.frequencies,
      );

      _scheduleSave(newReport);
      return;
    }

    // ── Toggle normal (comportamiento anterior sin cambios) ──
    final current = entry.results[activityId];
    String? next;
    if (current == null) next = 'OK';
    else if (current == 'OK') next = 'NOK';
    else if (current == 'NOK') next = 'NA';
    else if (current == 'NA') next = 'NR';
    else next = null;

    // Aritmética delta O(1) — igual que antes
    final currentStats = state!.stats;
    int ok = currentStats.ok, nok = currentStats.nok,
        na = currentStats.na, nr = currentStats.nr, pending = currentStats.pending;

    if (current == 'OK') ok--;
    else if (current == 'NOK') nok--;
    else if (current == 'NA') na--;
    else if (current == 'NR') nr--;
    else pending--;

    if (next == 'OK') ok++;
    else if (next == 'NOK') nok++;
    else if (next == 'NA') na++;
    else if (next == 'NR') nr++;
    else pending++;

    final newStats = ReportStats(
      ok: ok, nok: nok, na: na, nr: nr,
      total: currentStats.total, pending: pending,
    );

    final newResults = Map<String, String?>.from(entry.results);
    newResults[activityId] = next;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entry, results: newResults);
    final newReport = report.copyWith(entries: entries);

    state = ReportState(
      report: newReport, stats: newStats,
      isFullyComplete: pending == 0,
      instanceIdToGlobalIndex: state!.instanceIdToGlobalIndex,
      groupedEntriesMap: state!.groupedEntriesMap,
      frequencies: state!.frequencies,
    );

    _scheduleSave(newReport);
  }
  
  // ═══════════════════════════════════════════════════════
  // OBSERVACIONES
  // ═══════════════════════════════════════════════════════
  void updateObservation(int entryIndex, String text) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entries[entryIndex], observations: text);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // ACTIVITY DATA
  // ═══════════════════════════════════════════════════════
  void updateActivityData(int entryIndex, Map<String, ActivityData> activityData) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entries[entryIndex], activityData: activityData);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // FILL ALL OK — Solo para Admin/SuperUser
  // ═══════════════════════════════════════════════════════
  void fillAllOk() {
    if (state == null) return;
    final report = state!.report;

    int ok = 0, nok = 0, na = 0, nr = 0, pending = 0;
    final entries = List<ReportEntry>.from(report.entries);

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final newResults = Map<String, String?>.from(entry.results);

      for (final actId in newResults.keys) {
        if (newResults[actId] == null || newResults[actId] == 'NR') {
          newResults[actId] = 'OK';
        }
      }

      entries[i] = _copyEntry(entry, results: newResults);

      for (final status in newResults.values) {
        switch (status) {
          case 'OK': ok++; break;
          case 'NOK': nok++; break;
          case 'NA': na++; break;
          case 'NR': nr++; break;
          default: pending++; break;
        }
      }
    }

    final newStats = ReportStats(
      ok: ok, nok: nok, na: na, nr: nr,
      total: ok + nok + na + nr + pending,
      pending: pending,
    );

    final newReport = report.copyWith(entries: entries);

    state = ReportState(
      report: newReport,
      stats: newStats,
      isFullyComplete: pending == 0,
      instanceIdToGlobalIndex: state!.instanceIdToGlobalIndex,
      groupedEntriesMap: state!.groupedEntriesMap,
      frequencies: state!.frequencies,
    );

    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // SORT SECTION BY CUSTOM ID
  // ═══════════════════════════════════════════════════════
  void sortSectionByCustomId(String defId) {
    if (state == null) return;
    final report = state!.report;

    // 1. Obtener los instanceIds que pertenecen a esta sección
    final sectionInstanceIds = <String>{};
    final sectionEntries = state!.groupedEntriesMap[defId];
    if (sectionEntries == null || sectionEntries.length < 2) return;

    for (final e in sectionEntries) {
      sectionInstanceIds.add(e.instanceId);
    }

    // 2. Separar entries de esta sección vs el resto (mantener posición relativa)
    final List<ReportEntry> otherEntries = [];
    final List<ReportEntry> thisSectionEntries = [];
    final List<int> sectionPositions = []; // posiciones originales en la lista global

    for (int i = 0; i < report.entries.length; i++) {
      if (sectionInstanceIds.contains(report.entries[i].instanceId)) {
        thisSectionEntries.add(report.entries[i]);
        sectionPositions.add(i);
      } else {
        otherEntries.add(report.entries[i]);
      }
    }

    // 3. Ordenar la sección por customId numérico/alfanumérico
    thisSectionEntries.sort((a, b) => _compareCustomIds(a.customId, b.customId));

    // 4. Reinsertar los entries ordenados en sus posiciones originales
    final newEntries = List<ReportEntry>.from(report.entries);
    for (int i = 0; i < sectionPositions.length; i++) {
      newEntries[sectionPositions[i]] = thisSectionEntries[i];
    }

    // 5. Reconstruir el groupedEntriesMap para esta sección
    final newGroupedMap = Map<String, List<ReportEntry>>.from(state!.groupedEntriesMap);
    newGroupedMap[defId] = thisSectionEntries;

    // 6. Actualizar estado con recompute completo (recalcula índices)
    final newReport = report.copyWith(entries: newEntries);
    state = state!.copyWithFullRecompute(
      newReport,
      newGroupedMap: newGroupedMap,
    );

    _scheduleSave(newReport);
  }

  /// Comparador inteligente: extrae la parte numérica del final del ID
  /// para ordenar numéricamente (no alfabéticamente).
  /// "EXT-002" < "EXT-010" < "EXT-100"
  /// "3" < "4" < "12" (no "12" < "3" como sería alfabético)
  int _compareCustomIds(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;  // vacíos al final
    if (b.isEmpty) return -1;

    // Extraer prefijo y número
    final aParsed = _extractPrefixAndNumber(a);
    final bParsed = _extractPrefixAndNumber(b);

    // Primero comparar por prefijo
    final prefixCompare = aParsed.prefix.compareTo(bParsed.prefix);
    if (prefixCompare != 0) return prefixCompare;

    // Luego por número
    if (aParsed.number != null && bParsed.number != null) {
      return aParsed.number!.compareTo(bParsed.number!);
    }

    // Fallback: comparar como string
    return a.compareTo(b);
  }

  ({String prefix, int? number}) _extractPrefixAndNumber(String id) {
    int numStart = id.length;
    while (numStart > 0 &&
        id.codeUnitAt(numStart - 1) >= 48 &&
        id.codeUnitAt(numStart - 1) <= 57) {
      numStart--;
    }

    if (numStart == id.length) {
      // No hay número al final
      return (prefix: id, number: null);
    }

    final prefix = id.substring(0, numStart);
    final number = int.tryParse(id.substring(numStart));
    return (prefix: prefix, number: number);
  }

  void renumberFromIndex({
    required int startGlobalIndex,
    required int endGlobalIndex,
    required String prefix,
    required int startNumber,
    required int padding,
  }) {
    final current = state;
    if (current == null) return;

    final entries = List<ReportEntry>.from(current.report.entries);
    int counter = startNumber;

    for (int i = startGlobalIndex; i <= endGlobalIndex && i < entries.length; i++) {
      final numberStr = counter.toString().padLeft(padding, '0');
      final newId = prefix.isEmpty ? numberStr : '$prefix$numberStr';
      entries[i] = entries[i].copyWith(customId: newId);
      counter++;
    }

    final updatedReport = current.report.copyWith(entries: entries);
    state = current.copyWithReportOnly(updatedReport);
    _scheduleSave(updatedReport);
  }


  // ═══════════════════════════════════════════════════════
  // CUSTOM ID / AREA — NO recalcula, NO notifica
  // ═══════════════════════════════════════════════════════
  void updateCustomId(int entryIndex, String customId) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    
    entries[entryIndex] = _copyEntry(entries[entryIndex], customId: customId);
    final newReport = report.copyWith(entries: entries);
    
    // ★ EL FIX: ¡Actualizar el estado local para que Riverpod se entere!
    state = state!.copyWithReportOnly(newReport);
    
    _scheduleSaveQuiet(newReport);

    final policyId = report.policyId;

    _locationService.saveLocation(
      policyId: policyId,
      instanceId: entries[entryIndex].instanceId,
      customId: customId,
      area: entries[entryIndex].area, 
    );
  }

  void updateArea(int entryIndex, String area) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    
    entries[entryIndex] = _copyEntry(entries[entryIndex], area: area);
    final newReport = report.copyWith(entries: entries);
    
    // ★ EL FIX: Mantener el estado sincronizado
    state = state!.copyWithReportOnly(newReport);
    
    _scheduleSaveQuiet(newReport);

    final policyId = report.policyId;
    _locationService.saveLocation(
      policyId: policyId,
      instanceId: entries[entryIndex].instanceId,
      customId: entries[entryIndex].customId, 
      area: area,
    );
  }

  // ═══════════════════════════════════════════════════════
  // PHOTOS
  // ═══════════════════════════════════════════════════════
  void updatePhotoUrls(int entryIndex, List<String> photoUrls) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entries[entryIndex], photoUrls: photoUrls);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // GENERAL OBSERVATIONS
  // ═══════════════════════════════════════════════════════
  void updateGeneralObservations(String text) {
    if (state == null) return;
    final newReport = state!.report.copyWith(generalObservations: text);
    
    // ★ EL FIX: Evita que se borren si finalizas el reporte muy rápido
    state = state!.copyWithReportOnly(newReport);
    
    _scheduleSaveQuiet(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // SERVICE LIFECYCLE
  // ═══════════════════════════════════════════════════════
  void startService(String timeStr, DateTime date) {
    if (state == null) return;
    final report = state!.report;

    final newSession = ServiceSession(
      id: _uuid.v4(),
      date: date,
      startTime: timeStr,
      endTime: null,
    );

    final updatedSessions = [...report.sessions, newSession];

    // Compatibilidad con campos legacy startTime / endTime
    // startTime = primera sesión, endTime = null (hay sesión abierta)
    final isFirstSession = report.sessions.isEmpty;
    final newReport = report.copyWith(
      sessions: updatedSessions,
      startTime: isFirstSession ? timeStr : report.startTime,
      serviceDate: isFirstSession ? date : report.serviceDate,
      endTime: null,
      forceNullEndTime: true,
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void endService(String timeStr) {
    if (state == null) return;
    final report = state!.report;

    final sessions = List<ServiceSession>.from(report.sessions);
    final openIdx = sessions.lastIndexWhere((s) => s.isOpen);

    if (openIdx == -1) {
      // Fallback: no hay sesión abierta, usamos legacy
      final newReport = report.copyWith(endTime: timeStr);
      state = state!.copyWithReportOnly(newReport);
      _saveImmediateAsync(newReport);
      return;
    }

    sessions[openIdx] = sessions[openIdx].copyWith(endTime: timeStr);

    // Actualizar endTime legacy = última sesión cerrada
    final newReport = report.copyWith(
      sessions: sessions,
      endTime: timeStr,
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void resumeService() {
    if (state == null) return;
    final report = state!.report;

    // Abrimos una nueva sesión (continuación)
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final newSession = ServiceSession(
      id: _uuid.v4(),
      date: now,
      startTime: timeStr,
      endTime: null,
    );

    final updatedSessions = [...report.sessions, newSession];

    final newReport = report.copyWith(
      sessions: updatedSessions,
      endTime: null,
      forceNullEndTime: true,
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void updateServiceDate(DateTime date) {
    if (state == null) return;
    final newReport = state!.report.copyWith(serviceDate: date);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  void updateStartTime(String time) {
    if (state == null) return;
    final newReport = state!.report.copyWith(startTime: time);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  void updateEndTime(String time) {
    if (state == null) return;
    final newReport = state!.report.copyWith(endTime: time);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  void updateSession(String sessionId, {String? startTime, String? endTime}) {
    if (state == null) return;
    final report = state!.report;
    final sessions = List<ServiceSession>.from(report.sessions);
    final idx = sessions.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;

    sessions[idx] = sessions[idx].copyWith(
      startTime: startTime,
      endTime: endTime,
    );

    final newReport = report.copyWith(sessions: sessions);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  /// Elimina una sesión del historial (Admin Override).
   void deleteSession(String sessionId) {
    if (state == null) return;
    final report = state!.report;

    // 1. Verificar que exista
    final exists = report.sessions.any((s) => s.id == sessionId);
    if (!exists) return;

    // 2. Filtrar
    final remaining = report.sessions.where((s) => s.id != sessionId).toList();

    // 3. Recalcular legacy fields
    ServiceReportModel newReport;

    if (remaining.isEmpty) {
      // No quedan sesiones → vuelve a "no iniciado"
      newReport = report.copyWith(
        sessions: remaining,
        forceNullStartTime: true,
        forceNullEndTime: true,
      );
    } else {
      final hasOpenSession = remaining.any((s) => s.isOpen);
      if (hasOpenSession) {
        // Hay sesión abierta → en progreso
        newReport = report.copyWith(
          sessions: remaining,
          startTime: remaining.first.startTime,
          forceNullEndTime: true,
        );
      } else {
        // Todas cerradas → finalizado
        newReport = report.copyWith(
          sessions: remaining,
          startTime: remaining.first.startTime,
          endTime: remaining.last.endTime,
        );
      }
    }

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  /// Agrega una sesión manual (Admin Override).
  void addManualSession({
    required DateTime date,
    required String startTime,
    required String endTime,
  }) {
    if (state == null) return;
    final report = state!.report;

    final newSession = ServiceSession(
      id: _uuid.v4(),
      date: date,
      startTime: startTime,
      endTime: endTime,
    );

    final updatedSessions = [...report.sessions, newSession];

    // ★ Ordenar por fecha y luego por hora de inicio
    updatedSessions.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });

    final newReport = report.copyWith(
      sessions: updatedSessions,
      startTime: report.startTime ?? startTime,
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // SIGNATURES
  // ═══════════════════════════════════════════════════════
  void updateSignatures({
    String? providerSignature,
    String? clientSignature,
    String? providerName,
    String? clientName,
  }) {
    if (state == null) return;
    final newReport = state!.report.copyWith(
      providerSignature: providerSignature,
      clientSignature: clientSignature,
      providerSignerName: providerName,
      clientSignerName: clientName,
    );
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  List<String> getNokWithoutPhotos(List<DeviceModel> deviceDefs) {
    if (state == null) return [];
    final missing = <String>[];

    // Construir mapa de activityId → nombre legible
    final actNameMap = <String, String>{};
    for (final dev in deviceDefs) {
      for (final act in dev.activities) {
        actNameMap[act.id] = act.name;
      }
    }

    for (final entry in state!.report.entries) {
      final label = entry.customId.isNotEmpty
          ? entry.customId
          : 'Dispositivo #${entry.deviceIndex}';

      for (final actId in entry.results.keys) {
        if (entry.results[actId] == 'NOK') {
          final actPhotos = entry.activityData[actId]?.photoUrls ?? [];
          final entryPhotos = entry.photoUrls;

          if (actPhotos.isEmpty && entryPhotos.isEmpty) {
            final actName = actNameMap[actId] ?? actId;
            missing.add('$label → $actName');
          }
        }
      }
    }
    return missing;
  }

  // ═══════════════════════════════════════════════════════
  // SECTION ASSIGNMENTS
  // ═══════════════════════════════════════════════════════
  void toggleSectionAssignment(String defId, String userId) {
    if (state == null) return;
    final report = state!.report;

    final currentAssignments = List<String>.from(
      report.sectionAssignments[defId] ?? [],
    );

    if (currentAssignments.contains(userId)) {
      currentAssignments.remove(userId);
    } else {
      currentAssignments.add(userId);
    }

    final newSectionAssignments = Map<String, List<String>>.from(report.sectionAssignments);
    newSectionAssignments[defId] = currentAssignments;

    final allTechs = <String>{};
    newSectionAssignments.forEach((_, ids) => allTechs.addAll(ids));

    final newReport = report.copyWith(
      sectionAssignments: newSectionAssignments,
      assignedTechnicianIds: allTechs.toList(),
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  // ═══════════════════════════════════════════════════════
  // SYNC FROM FIREBASE
  // ═══════════════════════════════════════════════════════
  void syncFromFirebase(
    ServiceReportModel updatedReport, {
    required List<MapEntry<String, List<ReportEntry>>> groupedEntries,
    required String frequencies,
  }) {
    if (_hasPendingChanges) return;
    state = ReportState.fromReport(
      updatedReport,
      groupedEntries: groupedEntries,
      frequencies: frequencies,
    );
  }

  void _scheduleSave(ServiceReportModel report) {
    _hasPendingChanges = true;
    _pendingReport = report;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _flushPendingChangesAsync);
  }

  void _scheduleSaveQuiet(ServiceReportModel report) {
    _hasPendingChanges = true;
    _pendingReport = report;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _flushPendingChangesAsync);
  }

  /// ★ REEMPLAZA a _saveImmediate
  void _saveImmediateAsync(ServiceReportModel report) {
    _saveDebounce?.cancel();
    _hasPendingChanges = true;
    _pendingReport = null;
    _saveInIsolate(report);
  }

  /// ★ REEMPLAZA a _flushPendingChanges
  void _flushPendingChangesAsync() {
    if (_hasPendingChanges && _pendingReport != null) {
      final report = _pendingReport!;
      _pendingReport = null;
      _saveInIsolate(report);
    }
  }

  /// ★ CORE: Serializa en Isolate, escribe en Firestore
  Future<void> _saveInIsolate(ServiceReportModel report) async {
    if (_isSaving) {
      _hasPendingChanges = true;
      _pendingReport = report;
      _saveDebounce?.cancel();
      _saveDebounce = Timer(
        const Duration(milliseconds: 500),
        _flushPendingChangesAsync,
      );
      return;
    }

    _isSaving = true;

    try {
      final Map<String, dynamic> data = await compute(
        _serializeReportInIsolate,
        report,
      );
      await _repo.saveReportRaw(report.id, data);
      _lastSaveTimestamp = DateTime.now();
    } catch (e) {
      debugPrint('Error en _saveInIsolate: $e');
      try {
        await _repo.saveReport(report);
      } catch (e2) {
        debugPrint('Error en fallback save: $e2');
      }
    } finally {
      _isSaving = false;
      // ★ Solo limpiar si NO hay más cambios pendientes en cola
      if (_pendingReport != null) {
        _flushPendingChangesAsync();
      } else {
        _hasPendingChanges = false;  // ★ AHORA sí es seguro limpiar
      }
    }
  }

  /// Para dispose() — sync fallback para no perder cambios
  void flushBeforeDispose() {
    if (_hasPendingChanges && _pendingReport != null) {
      _hasPendingChanges = false;
      _repo.saveReport(_pendingReport!);
      _pendingReport = null;
    }
  }

  bool get hasPendingChanges => _hasPendingChanges;

  // ═══════════════════════════════════════════════════════
  // HELPER
  // ═══════════════════════════════════════════════════════
  ReportEntry _copyEntry(
    ReportEntry entry, {
    String? customId,
    String? area,
    Map<String, String?>? results,
    String? observations,
    List<String>? photoUrls,
    Map<String, ActivityData>? activityData,
  }) {
    return ReportEntry(
      instanceId: entry.instanceId,
      deviceIndex: entry.deviceIndex,
      customId: customId ?? entry.customId,
      area: area ?? entry.area,
      results: results ?? entry.results,
      observations: observations ?? entry.observations,
      photoUrls: photoUrls ?? entry.photoUrls,
      activityData: activityData ?? entry.activityData,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PROVIDERS
// ─────────────────────────────────────────────────────────────────

final reportNotifierProvider =
    NotifierProvider<ReportNotifier, ReportState?>(ReportNotifier.new);

final reportStatsProvider = Provider<ReportStats?>((ref) {
  return ref.watch(reportNotifierProvider.select((s) => s?.stats));
});

final reportMetaProvider = Provider<ReportMeta?>((ref) {
  return ref.watch(reportNotifierProvider.select((s) => s?.meta));
});

final reportSessionsProvider = Provider<List<ServiceSession>>((ref) {
    return ref.watch(
    reportNotifierProvider.select((s) => s?.report.sessions ?? []),
  );
});

/// ★ FIX: O(1) lookup con Map en vez de .where() lineal
final sectionEntriesProvider =
    Provider.family<List<ReportEntry>, String>((ref, defId) {
  final state = ref.watch(reportNotifierProvider);
  if (state == null) return [];
  return state.groupedEntriesMap[defId] ?? [];
});

final sectionAssignmentsProvider =
    Provider.family<List<String>, String>((ref, defId) {
  return ref.watch(
    reportNotifierProvider.select((s) => s?.report.sectionAssignments[defId] ?? []),
  );
});

final singleEntryProvider = Provider.family<ReportEntry?, int>((ref, index) {
  return ref.watch(reportNotifierProvider.select((s) {
    if (s == null || index < 0 || index >= s.report.entries.length) return null;
    return s.report.entries[index];
  }));
});

/// Lee directamente del árbol principal del estado usando los índices globales.
/// Ya no depende de ningún otro provider intermedio que pueda quedarse cacheado.
final sectionProgressProvider =
    Provider.family<({int total, int completed, double percentage}), String>((ref, defId) {
  
  // Escuchamos el estado central. Si cambia un toggle, esto se re-ejecuta.
  final state = ref.watch(reportNotifierProvider);
  if (state == null) return (total: 0, completed: 0, percentage: 0.0);

  int totalActivities = 0;
  int completedActivities = 0;

  // 1. Usamos el mapa agrupado SOLO para saber qué IDs (instanceId) pertenecen a esta sección
  final groupedEntries = state.groupedEntriesMap[defId] ?? [];
  
  for (final staleEntry in groupedEntries) {
    // 2. Buscamos el índice global exacto de este equipo en tiempo real
    final globalIndex = state.instanceIdToGlobalIndex[staleEntry.instanceId];
    if (globalIndex == null) continue;
    
    // 3. Extraemos el equipo directamente de la lista maestra (¡Datos 100% frescos!)
    final freshEntry = state.report.entries[globalIndex];
    
    // 4. Calculamos sobre los results actualizados
    // DESPUÉS — También reconoce cualquier valor medido como completado:
    for (final value in freshEntry.results.values) {
      totalActivities++;
      if (value != null && value.isNotEmpty && value != 'NR') {
        completedActivities++;
      }
    }
  }
  
  final percentage = totalActivities > 0
      ? (completedActivities / totalActivities) * 100
      : 0.0;
  
  // Retornamos el Record
  return (
    total: totalActivities, 
    completed: completedActivities, 
    percentage: percentage
  );
});
