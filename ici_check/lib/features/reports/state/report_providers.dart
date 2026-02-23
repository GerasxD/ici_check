// lib/features/reports/state/report_providers.dart
//
// ★ ESTE ES EL ÚNICO ARCHIVO DE PROVIDERS.
// ★ TODOS los imports deben apuntar a ESTE archivo.

import 'dart:async';
import 'package:flutter/foundation.dart'; // ★ CAMBIO 1: Nuevo import para compute()
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';
import 'package:ici_check/features/reports/services/device_location_service.dart';
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
  Timer? _saveDebounce;
  bool _hasPendingChanges = false;
  ServiceReportModel? _pendingReport;
  bool _isSaving = false; // ★ CAMBIO 3: Flag anti-concurrencia

  @override
  ReportState? build() => null;

  void initialize(ReportState initialState) {
    state = initialState;
  }

  // ═══════════════════════════════════════════════════════
  // TOGGLE STATUS — ÚNICO path que recalcula stats
  // ═══════════════════════════════════════════════════════
 void toggleStatus(int entryIndex, String activityId) {
    if (state == null) return;
    final report = state!.report;
    if (entryIndex < 0 || entryIndex >= report.entries.length) return;

    final entry = report.entries[entryIndex];
    if (!entry.results.containsKey(activityId)) return;

    final current = entry.results[activityId];
    String? next;
    
    if (current == null) {
      next = 'OK';
    } else if (current == 'OK') {
      next = 'NOK';
    } else if (current == 'NOK') {
      next = 'NA';
    } else if (current == 'NA') {
      next = 'NR';
    } else {
      next = null;
    }

    // ARITMÉTICA DELTA O(1)
    final currentStats = state!.stats;
    int ok = currentStats.ok;
    int nok = currentStats.nok;
    int na = currentStats.na;
    int nr = currentStats.nr;
    int pending = currentStats.pending;

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
    final newReport = state!.report.copyWith(startTime: timeStr, serviceDate: date);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  void endService(String timeStr) {
    if (state == null) return;
    final newReport = state!.report.copyWith(endTime: timeStr);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
  }

  void resumeService() {
    if (state == null) return;
    final newReport = state!.report.copyWith(endTime: null, forceNullEndTime: true);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport); // ★ era _saveImmediate
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

  // ═══════════════════════════════════════════════════════════════
  // ★ CAMBIO 4: SAVE STRATEGIES — CON ISOLATE
  //
  // ANTES:
  //   _saveImmediate(report) → _repo.saveReport(report)
  //   internamente: report.toMap() en main thread → 100-300ms jank
  //
  // DESPUÉS:
  //   _saveImmediateAsync(report) → compute(toMap, report) en isolate
  //   → _repo.saveReportRaw(id, data) → 0ms jank en main thread
  // ═══════════════════════════════════════════════════════════════

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
    _hasPendingChanges = false;
    _pendingReport = null;
    _saveInIsolate(report);
  }

  /// ★ REEMPLAZA a _flushPendingChanges
  void _flushPendingChangesAsync() {
    if (_hasPendingChanges && _pendingReport != null) {
      _hasPendingChanges = false;
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
      // ★ Serialización en Isolate — NO bloquea main thread
      final Map<String, dynamic> data = await compute(
        _serializeReportInIsolate,
        report,
      );

      // ★ Solo Firestore write en main thread (rápido)
      await _repo.saveReportRaw(report.id, data);
    } catch (e) {
      debugPrint('Error en _saveInIsolate: $e');
      try {
        await _repo.saveReport(report);
      } catch (e2) {
        debugPrint('Error en fallback save: $e2');
      }
    } finally {
      _isSaving = false;
      if (_hasPendingChanges && _pendingReport != null) {
        _flushPendingChangesAsync();
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
    for (final value in freshEntry.results.values) {
      totalActivities++;
      if (value == 'OK' || value == 'NOK' || value == 'NA') {
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
