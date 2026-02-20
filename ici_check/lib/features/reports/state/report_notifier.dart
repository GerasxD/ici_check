// lib/features/reports/state/report_notifier.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';
import 'report_state.dart';

class ReportNotifier extends Notifier<ReportState?> {
  final ReportsRepository _repo = ReportsRepository();
  Timer? _saveDebounce;
  bool _hasPendingChanges = false;

  @override
  ReportState? build() => null; // Se inicializa en loadReport()

  // ═══════════════════════════════════════════════════════
  // INICIALIZACIÓN
  // ═══════════════════════════════════════════════════════
  void initialize(ReportState initialState) {
    state = initialState;
  }

  // ═══════════════════════════════════════════════════════
  // TOGGLE STATUS — Este es el ÚNICO path que recalcula stats
  // ═══════════════════════════════════════════════════════
  void toggleStatus(int entryIndex, String activityId) {
    if (state == null) return;
    final report = state!.report;
    final entry = report.entries[entryIndex];
    if (!entry.results.containsKey(activityId)) return;

    final current = entry.results[activityId];
    String? next;
    if (current == null) next = 'OK';
    else if (current == 'OK') next = 'NOK';
    else if (current == 'NOK') next = 'NA';
    else if (current == 'NA') next = 'NR';
    else next = null;

    final newResults = Map<String, String?>.from(entry.results);
    newResults[activityId] = next;

    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entry, results: newResults);
    final newReport = report.copyWith(entries: entries);

    // ★ FULL RECOMPUTE — stats e isComplete cambian
    state = state!.copyWithFullRecompute(newReport);
    _saveImmediate(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // OBSERVACIONES — NO recalcula stats
  // ═══════════════════════════════════════════════════════
  void updateObservation(int entryIndex, String text) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(
      entries[entryIndex], 
      observations: text,
    );
    final newReport = report.copyWith(entries: entries);

    // ★ REPORT ONLY — stats NO cambian, NO se recalculan
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // ACTIVITY DATA (fotos/obs de actividad) — NO recalcula stats
  // ═══════════════════════════════════════════════════════
  void updateActivityData(
    int entryIndex,
    Map<String, ActivityData> activityData,
  ) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(
      entries[entryIndex],
      activityData: activityData,
    );
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // CUSTOM ID / AREA — NO recalcula stats
  // ═══════════════════════════════════════════════════════
  void updateCustomId(int entryIndex, String customId) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entries[entryIndex], customId: customId);
    final newReport = report.copyWith(entries: entries);

    // ★ CLAVE: NO hacemos state = ... aquí.
    // El campo de texto ya tiene su propio controller local.
    // Solo programamos el guardado.
    _hasPendingChanges = true;
    // Guardamos el report internamente para que el próximo state update
    // lo tenga, pero NO notificamos a los listeners.
    _scheduleSaveWithoutNotify(newReport);
  }

  void updateArea(int entryIndex, String area) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entries[entryIndex], area: area);
    final newReport = report.copyWith(entries: entries);
    _scheduleSaveWithoutNotify(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // GENERAL OBSERVATIONS — NO recalcula nada
  // ═══════════════════════════════════════════════════════
  void updateGeneralObservations(String text) {
    if (state == null) return;
    final newReport = state!.report.copyWith(generalObservations: text);
    // No notificar — el TextField ya refleja el cambio localmente
    _scheduleSaveWithoutNotify(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // SERVICE LIFECYCLE — Recalcula porque puede cambiar isEditable
  // ═══════════════════════════════════════════════════════
  void startService(String timeStr, DateTime date) {
    if (state == null) return;
    final newReport = state!.report.copyWith(
      startTime: timeStr,
      serviceDate: date,
    );
    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
  }

  void endService(String timeStr) {
    if (state == null) return;
    final newReport = state!.report.copyWith(endTime: timeStr);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
  }

  void resumeService() {
    if (state == null) return;
    final newReport = state!.report.copyWith(
      endTime: null, forceNullEndTime: true,
    );
    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
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
    _saveImmediate(newReport);
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

    final newSectionAssignments = Map<String, List<String>>.from(
      report.sectionAssignments,
    );
    newSectionAssignments[defId] = currentAssignments;

    final allTechs = <String>{};
    newSectionAssignments.forEach((_, ids) => allTechs.addAll(ids));

    final newReport = report.copyWith(
      sectionAssignments: newSectionAssignments,
      assignedTechnicianIds: allTechs.toList(),
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // FIREBASE SAVE STRATEGIES
  // ═══════════════════════════════════════════════════════
  ServiceReportModel? _pendingReport;

  void _scheduleSave(ServiceReportModel report) {
    _hasPendingChanges = true;
    _pendingReport = report;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      _flushPendingChanges();
    });
  }

  /// Guarda sin notificar a listeners. Para campos con controller local.
  void _scheduleSaveWithoutNotify(ServiceReportModel report) {
    _hasPendingChanges = true;
    _pendingReport = report;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      _flushPendingChanges();
    });
  }

  void _saveImmediate(ServiceReportModel report) {
    _saveDebounce?.cancel();
    _hasPendingChanges = false;
    _pendingReport = null;
    _repo.saveReport(report);
  }

  void _flushPendingChanges() {
    if (_hasPendingChanges && _pendingReport != null) {
      _hasPendingChanges = false;
      _repo.saveReport(_pendingReport!);
      _pendingReport = null;
    }
  }

  void flushBeforeDispose() => _flushPendingChanges();

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

// ═══════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════
final reportNotifierProvider =
    NotifierProvider<ReportNotifier, ReportState?>(ReportNotifier.new);

// ★ SELECTORES GRANULARES — Cada widget escucha SOLO lo que necesita

/// ReportSummary escucha SOLO esto. Si las stats no cambian → no rebuild.
final reportStatsProvider = Provider<ReportStats?>((ref) {
  return ref.watch(reportNotifierProvider.select((s) => s?.stats));
});

/// ReportControls escucha SOLO esto.
final reportMetaProvider = Provider<_ReportMeta?>((ref) {
  final state = ref.watch(reportNotifierProvider);
  if (state == null) return null;
  return _ReportMeta(
    startTime: state.report.startTime,
    endTime: state.report.endTime,
    serviceDate: state.report.serviceDate,
    assignedTechnicianIds: state.report.assignedTechnicianIds,
    isFullyComplete: state.isFullyComplete,
  );
});

class _ReportMeta {
  final String? startTime;
  final String? endTime;
  final DateTime serviceDate;
  final List<String> assignedTechnicianIds;
  final bool isFullyComplete;

  _ReportMeta({
    required this.startTime,
    required this.endTime,
    required this.serviceDate,
    required this.assignedTechnicianIds,
    required this.isFullyComplete,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ReportMeta &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          serviceDate == other.serviceDate &&
          isFullyComplete == other.isFullyComplete &&
          _listEquals(assignedTechnicianIds, other.assignedTechnicianIds);

  @override
  int get hashCode => Object.hash(
    startTime, endTime, serviceDate, isFullyComplete,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Para una sección específica de dispositivos
final sectionEntriesProvider =
    Provider.family<List<ReportEntry>, String>((ref, defId) {
  final state = ref.watch(reportNotifierProvider);
  if (state == null) return [];
  final group = state.groupedEntries
      .where((e) => e.key == defId)
      .firstOrNull;
  return group?.value ?? [];
});

/// Assignments de una sección
final sectionAssignmentsProvider =
    Provider.family<List<String>, String>((ref, defId) {
  return ref.watch(reportNotifierProvider.select(
    (s) => s?.report.sectionAssignments[defId] ?? [],
  ));
});