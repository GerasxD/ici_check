// lib/features/reports/state/report_providers.dart
//
// ═══════════════════════════════════════════════════════════════════
// PROVIDERS GRANULARES — Cada widget escucha SOLO lo que necesita
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';
import 'report_state.dart';

// ─────────────────────────────────────────────────────────────────
// NOTIFIER CENTRAL
// ─────────────────────────────────────────────────────────────────
class ReportNotifier extends Notifier<ReportState?> {
  final ReportsRepository _repo = ReportsRepository();
  Timer? _saveDebounce;
  bool _hasPendingChanges = false;
  ServiceReportModel? _pendingReport;

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
    entries[entryIndex] = _copyEntry(entries[entryIndex], observations: text);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // ACTIVITY DATA (fotos/obs de actividad)
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
    _scheduleSaveQuiet(newReport);
  }

  void updateArea(int entryIndex, String area) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    entries[entryIndex] = _copyEntry(entries[entryIndex], area: area);
    final newReport = report.copyWith(entries: entries);
    _scheduleSaveQuiet(newReport);
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
    _scheduleSaveQuiet(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // SERVICE LIFECYCLE
  // ═══════════════════════════════════════════════════════
  void startService(String timeStr, DateTime date) {
    if (state == null) return;
    final newReport = state!.report.copyWith(startTime: timeStr, serviceDate: date);
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
    final newReport = state!.report.copyWith(endTime: null, forceNullEndTime: true);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
  }

  void updateServiceDate(DateTime date) {
    if (state == null) return;
    final newReport = state!.report.copyWith(serviceDate: date);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
  }

  void updateStartTime(String time) {
    if (state == null) return;
    final newReport = state!.report.copyWith(startTime: time);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediate(newReport);
  }

  void updateEndTime(String time) {
    if (state == null) return;
    final newReport = state!.report.copyWith(endTime: time);
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

    final newSectionAssignments = Map<String, List<String>>.from(report.sectionAssignments);
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
  // FULL REPORT UPDATE (para sync con Firebase stream)
  // ═══════════════════════════════════════════════════════
  void syncFromFirebase(
    ServiceReportModel updatedReport, {
    required List<MapEntry<String, List<ReportEntry>>> groupedEntries,
    required String frequencies,
  }) {
    if (_hasPendingChanges) return; // No pisar cambios locales
    state = ReportState.fromReport(
      updatedReport,
      groupedEntries: groupedEntries,
      frequencies: frequencies,
    );
  }

  // ═══════════════════════════════════════════════════════
  // SAVE STRATEGIES
  // ═══════════════════════════════════════════════════════
  void _scheduleSave(ServiceReportModel report) {
    _hasPendingChanges = true;
    _pendingReport = report;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _flushPendingChanges);
  }

  /// Guarda sin notificar a listeners. Para campos con controller local.
  void _scheduleSaveQuiet(ServiceReportModel report) {
    _hasPendingChanges = true;
    _pendingReport = report;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _flushPendingChanges);
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

/// Provider central del estado del reporte
final reportNotifierProvider =
    NotifierProvider<ReportNotifier, ReportState?>(ReportNotifier.new);

/// ★ ReportSummary escucha SOLO esto.
/// Si ok/nok/na/nr no cambiaron → build() NO se ejecuta.
final reportStatsProvider = Provider<ReportStats?>((ref) {
  return ref.watch(reportNotifierProvider.select((s) => s?.stats));
});

/// ★ ReportControls escucha SOLO esto.
/// Si startTime/endTime/isComplete no cambiaron → NO rebuild.
final reportMetaProvider = Provider<ReportMeta?>((ref) {
  return ref.watch(reportNotifierProvider.select((s) => s?.meta));
});

/// Para una sección específica de dispositivos
final sectionEntriesProvider =
    Provider.family<List<ReportEntry>, String>((ref, defId) {
  final state = ref.watch(reportNotifierProvider);
  if (state == null) return [];
  final group = state.groupedEntries.where((e) => e.key == defId).firstOrNull;
  return group?.value ?? [];
});

/// Assignments de una sección
final sectionAssignmentsProvider =
    Provider.family<List<String>, String>((ref, defId) {
  return ref.watch(
    reportNotifierProvider.select((s) => s?.report.sectionAssignments[defId] ?? []),
  );
});

/// Provider de una sola entry por índice global
final singleEntryProvider = Provider.family<ReportEntry?, int>((ref, index) {
  return ref.watch(reportNotifierProvider.select((s) {
    if (s == null || index < 0 || index >= s.report.entries.length) return null;
    return s.report.entries[index];
  }));
});