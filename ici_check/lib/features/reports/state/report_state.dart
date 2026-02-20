// lib/features/reports/state/report_state.dart

import 'package:ici_check/features/reports/data/report_model.dart';

// ─────────────────────────────────────────────────────────────────
// 1. ReportStats
// ─────────────────────────────────────────────────────────────────
class ReportStats {
  final int ok;
  final int nok;
  final int na;
  final int nr;
  final int total;
  final int pending;

  const ReportStats({
    required this.ok,
    required this.nok,
    required this.na,
    required this.nr,
    required this.total,
    required this.pending,
  });

  factory ReportStats.compute(List<ReportEntry> entries) {
    int ok = 0, nok = 0, na = 0, nr = 0, pending = 0;
    for (final entry in entries) {
      for (final status in entry.results.values) {
        switch (status) {
          case 'OK':
            ok++;
            break;
          case 'NOK':
            nok++;
            break;
          case 'NA':
            na++;
            break;
          case 'NR':
            nr++;
            break;
          default:
            pending++;
            break;
        }
      }
    }
    return ReportStats(
      ok: ok,
      nok: nok,
      na: na,
      nr: nr,
      total: ok + nok + na + nr + pending,
      pending: pending,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportStats &&
          ok == other.ok &&
          nok == other.nok &&
          na == other.na &&
          nr == other.nr &&
          pending == other.pending;

  @override
  int get hashCode => Object.hash(ok, nok, na, nr, pending);
}

// ─────────────────────────────────────────────────────────────────
// 2. ReportMeta
// ─────────────────────────────────────────────────────────────────
class ReportMeta {
  final String? startTime;
  final String? endTime;
  final DateTime serviceDate;
  final List<String> assignedTechnicianIds;
  final Map<String, List<String>> sectionAssignments;
  final bool isFullyComplete;

  const ReportMeta({
    required this.startTime,
    required this.endTime,
    required this.serviceDate,
    required this.assignedTechnicianIds,
    required this.sectionAssignments,
    required this.isFullyComplete,
  });

  bool get isInProgress => startTime != null && endTime == null;
  bool get isFinished => startTime != null && endTime != null;
  bool get isNotStarted => startTime == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportMeta &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          serviceDate == other.serviceDate &&
          isFullyComplete == other.isFullyComplete &&
          _listEquals(assignedTechnicianIds, other.assignedTechnicianIds);

  @override
  int get hashCode => Object.hash(
        startTime, endTime, serviceDate, isFullyComplete,
        assignedTechnicianIds.length,
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─────────────────────────────────────────────────────────────────
// 3. ReportState — Con Map para O(1) lookups de secciones
// ─────────────────────────────────────────────────────────────────
class ReportState {
  final ServiceReportModel report;
  final ReportStats stats;
  final bool isFullyComplete;
  final Map<String, int> instanceIdToGlobalIndex;
  final String frequencies;

  /// ★ FIX: Map para O(1) lookups en providers
  final Map<String, List<ReportEntry>> groupedEntriesMap;

  /// Lista para iterar en build() del screen (derivada del map)
  late final List<MapEntry<String, List<ReportEntry>>> groupedEntries =
      groupedEntriesMap.entries.toList();

  ReportState({
    required this.report,
    required this.stats,
    required this.isFullyComplete,
    required this.instanceIdToGlobalIndex,
    required this.groupedEntriesMap,
    required this.frequencies,
  });

  factory ReportState.fromReport(
    ServiceReportModel report, {
    required List<MapEntry<String, List<ReportEntry>>> groupedEntries,
    required String frequencies,
  }) {
    // Convertir la lista a mapa
    final map = <String, List<ReportEntry>>{};
    for (final entry in groupedEntries) {
      map[entry.key] = entry.value;
    }

    return ReportState(
      report: report,
      stats: ReportStats.compute(report.entries),
      isFullyComplete: _computeIsComplete(report.entries),
      instanceIdToGlobalIndex: _buildIndexMap(report.entries),
      groupedEntriesMap: map,
      frequencies: frequencies,
    );
  }

  /// Copia BARATA: solo cambia el report, NO recalcula stats.
  ReportState copyWithReportOnly(ServiceReportModel newReport) {
    return ReportState(
      report: newReport,
      stats: stats,
      isFullyComplete: isFullyComplete,
      instanceIdToGlobalIndex: instanceIdToGlobalIndex,
      groupedEntriesMap: groupedEntriesMap,
      frequencies: frequencies,
    );
  }

  /// Copia COMPLETA: recalcula stats e isComplete.
  ReportState copyWithFullRecompute(
    ServiceReportModel newReport, {
    Map<String, List<ReportEntry>>? newGroupedMap,
    String? newFrequencies,
  }) {
    return ReportState(
      report: newReport,
      stats: ReportStats.compute(newReport.entries),
      isFullyComplete: _computeIsComplete(newReport.entries),
      instanceIdToGlobalIndex: _buildIndexMap(newReport.entries),
      groupedEntriesMap: newGroupedMap ?? groupedEntriesMap,
      frequencies: newFrequencies ?? frequencies,
    );
  }

  ReportMeta get meta => ReportMeta(
        startTime: report.startTime,
        endTime: report.endTime,
        serviceDate: report.serviceDate,
        assignedTechnicianIds: report.assignedTechnicianIds,
        sectionAssignments: report.sectionAssignments,
        isFullyComplete: isFullyComplete,
      );

  static Map<String, int> _buildIndexMap(List<ReportEntry> entries) {
    final map = <String, int>{};
    for (int i = 0; i < entries.length; i++) {
      map[entries[i].instanceId] = i;
    }
    return map;
  }

  static bool _computeIsComplete(List<ReportEntry> entries) {
    for (final entry in entries) {
      for (final status in entry.results.values) {
        if (status == null || status == 'NR') return false;
      }
    }
    return true;
  }
}