import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';
import 'package:ici_check/features/reports/services/device_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'report_state.dart';

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
  bool _isSaving = false;
  DateTime? _lastSaveTimestamp;
  DateTime? get lastSaveTimestamp => _lastSaveTimestamp;

  // ═══════════════════════════════════════════════════════
  // DIRTY TRACKING
  // ═══════════════════════════════════════════════════════
  final Map<String, Set<String>> _dirtyResults = {};
  final Set<String> _dirtyEntryFields = {};
  bool _dirtyMeta = false;

  ({
    Map<String, Set<String>> results,
    Set<String> entryFields,
    bool meta,
  }) get dirtyState => (
    results: Map<String, Set<String>>.from(
      _dirtyResults.map((k, v) => MapEntry(k, Set<String>.from(v))),
    ),
    entryFields: Set<String>.from(_dirtyEntryFields),
    meta: _dirtyMeta,
  );

  void _clearDirtyState() {
    _dirtyResults.clear();
    _dirtyEntryFields.clear();
    _dirtyMeta = false;
  }

  @override
  ReportState? build() => null;

  void initialize(ReportState initialState) {
    state = initialState;
  }

  // ═══════════════════════════════════════════════════════
  // ★ PERSISTENCIA OFFLINE LOCAL — 3 métodos nuevos
  // ═══════════════════════════════════════════════════════

  /// Guarda los cambios dirty en SharedPreferences.
  /// Se llama automáticamente cuando falla el save al servidor (offline)
  /// y también desde dispose() para no perder cambios.
  Future<void> _saveLocalDirtyBackup(ServiceReportModel report) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Solo guardar los valores de las actividades que el usuario modificó
      final Map<String, Map<String, String>> dirtyResultValues = {};

      for (final mapEntry in _dirtyResults.entries) {
        final instanceId = mapEntry.key;
        final dirtyActIds = mapEntry.value;

        final entryIdx = report.entries.indexWhere(
          (e) => e.instanceId == instanceId,
        );
        if (entryIdx < 0) continue;

        final entry = report.entries[entryIdx];
        final actValues = <String, String>{};
        for (final actId in dirtyActIds) {
          if (entry.results.containsKey(actId)) {
            // Guardamos el valor como string. null → "__NULL__"
            actValues[actId] = entry.results[actId] ?? '__NULL__';
          }
        }
        if (actValues.isNotEmpty) {
          dirtyResultValues[instanceId] = actValues;
        }
      }

      // También guardar dirty entry fields (observations, customId, area)
      final Map<String, Map<String, String>> dirtyFieldValues = {};
      for (final instanceId in _dirtyEntryFields) {
        final entryIdx = report.entries.indexWhere(
          (e) => e.instanceId == instanceId,
        );
        if (entryIdx < 0) continue;
        final entry = report.entries[entryIdx];
        dirtyFieldValues[instanceId] = {
          'observations': entry.observations,
          'customId': entry.customId,
          'area': entry.area,
        };
      }

      // Si no hay nada dirty, no guardar
      if (dirtyResultValues.isEmpty && dirtyFieldValues.isEmpty && !_dirtyMeta) {
        return;
      }

      final backup = <String, dynamic>{
        'dirtyResults': dirtyResultValues,
        'dirtyFields': dirtyFieldValues,
        'dirtyMeta': _dirtyMeta,
      };

      // Si hay meta dirty, guardar generalObservations
      if (_dirtyMeta) {
        backup['generalObservations'] = report.generalObservations;
      }

      await prefs.setString(
        'offline_dirty_${report.id}',
        jsonEncode(backup),
      );
      debugPrint('💾 Backup local guardado: ${dirtyResultValues.length} entries con results dirty, ${dirtyFieldValues.length} con fields dirty');
    } catch (e) {
      debugPrint('Error guardando backup local: $e');
    }
  }

  /// Restaura cambios dirty desde SharedPreferences.
  /// Llamar DESPUÉS de _initializeNotifier en service_report_screen.
  Future<void> restoreLocalDirtyBackup(String reportId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'offline_dirty_$reportId';
      final jsonStr = prefs.getString(key);
      if (jsonStr == null) return;

      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (state == null) {
        await prefs.remove(key);
        return;
      }

      final report = state!.report;
      final entries = List<ReportEntry>.from(report.entries);
      bool anyChange = false;

      // ── Restaurar dirty results (respuestas OK/NOK/NA/NR) ──
      final dirtyResultsJson = backup['dirtyResults'] as Map<String, dynamic>?;
      if (dirtyResultsJson != null) {
        for (final mapEntry in dirtyResultsJson.entries) {
          final instanceId = mapEntry.key;
          final actValues = Map<String, dynamic>.from(mapEntry.value as Map);

          final entryIdx = entries.indexWhere((e) => e.instanceId == instanceId);
          if (entryIdx < 0) continue;

          final entry = entries[entryIdx];
          final newResults = Map<String, String?>.from(entry.results);

          for (final actEntry in actValues.entries) {
            final actId = actEntry.key;
            final value = actEntry.value == '__NULL__' ? null : actEntry.value as String?;

            // Solo aplicar si realmente es diferente
            if (newResults.containsKey(actId) && newResults[actId] != value) {
              newResults[actId] = value;
              (_dirtyResults[instanceId] ??= {}).add(actId);
              anyChange = true;
            }
          }

          entries[entryIdx] = entry.copyWith(results: newResults);
        }
      }

      // ── Restaurar dirty entry fields (observations, customId, area) ──
      final dirtyFieldsJson = backup['dirtyFields'] as Map<String, dynamic>?;
      if (dirtyFieldsJson != null) {
        for (final mapEntry in dirtyFieldsJson.entries) {
          final instanceId = mapEntry.key;
          final fields = Map<String, dynamic>.from(mapEntry.value as Map);

          final entryIdx = entries.indexWhere((e) => e.instanceId == instanceId);
          if (entryIdx < 0) continue;

          final entry = entries[entryIdx];
          final savedObs = fields['observations'] as String? ?? '';
          final savedCustomId = fields['customId'] as String? ?? '';
          final savedArea = fields['area'] as String? ?? '';

          if (entry.observations != savedObs ||
              entry.customId != savedCustomId ||
              entry.area != savedArea) {
            entries[entryIdx] = entry.copyWith(
              observations: savedObs.isNotEmpty ? savedObs : entry.observations,
              customId: savedCustomId.isNotEmpty ? savedCustomId : entry.customId,
              area: savedArea.isNotEmpty ? savedArea : entry.area,
            );
            _dirtyEntryFields.add(instanceId);
            anyChange = true;
          }
        }
      }

      // ── Restaurar dirty meta ──
      final dirtyMeta = backup['dirtyMeta'] as bool? ?? false;
      String? restoredGeneralObs;
      if (dirtyMeta) {
        _dirtyMeta = true;
        restoredGeneralObs = backup['generalObservations'] as String?;
        anyChange = true;
      }

      // Limpiar el backup (ya lo restauramos)
      await prefs.remove(key);

      if (!anyChange) return;

      // Reconstruir reporte con los cambios restaurados
      ServiceReportModel newReport;
      if (restoredGeneralObs != null &&
          restoredGeneralObs != report.generalObservations) {
        newReport = report.copyWith(
          entries: entries,
          generalObservations: restoredGeneralObs,
        );
      } else {
        newReport = report.copyWith(entries: entries);
      }

      // Recalcular stats
      int ok = 0, nok = 0, na = 0, nr = 0, pending = 0;
      for (final e in entries) {
        for (final v in e.results.values) {
          switch (v) {
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
              if (v != null && v.isNotEmpty) {
                ok++; // valor medido = completado
              } else {
                pending++;
              }
              break;
          }
        }
      }

      final newStats = ReportStats(
        ok: ok,
        nok: nok,
        na: na,
        nr: nr,
        total: ok + nok + na + nr + pending,
        pending: pending,
      );

      state = ReportState(
        report: newReport,
        stats: newStats,
        isFullyComplete: pending == 0,
        instanceIdToGlobalIndex: state!.instanceIdToGlobalIndex,
        groupedEntriesMap: state!.groupedEntriesMap,
        frequencies: state!.frequencies,
      );

      _hasPendingChanges = true;
      _scheduleSave(newReport);

      debugPrint('🔄 Backup local restaurado: cambios offline recuperados y programados para sync');
    } catch (e) {
      debugPrint('Error restaurando backup local: $e');
    }
  }

  /// Limpia el backup local después de un save exitoso al servidor.
  Future<void> _clearLocalDirtyBackup(String reportId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('offline_dirty_$reportId');
    } catch (_) {}
  }

  /// Llamar desde dispose() del screen para persistir cambios pendientes.
  /// Es fire-and-forget (async pero no esperamos).
  void saveLocalBackupOnDispose() {
    if (!_hasPendingChanges) return;
    final report = _pendingReport ?? state?.report;
    if (report == null) return;
    if (_dirtyResults.isEmpty && _dirtyEntryFields.isEmpty && !_dirtyMeta) return;
    // Fire-and-forget — SharedPreferences completará aunque el widget murió
    _saveLocalDirtyBackup(report);
  }

  // ═══════════════════════════════════════════════════════
  // TOGGLE STATUS
  // ═══════════════════════════════════════════════════════
  void toggleStatus(int entryIndex, String activityId, {
    ActivityInputType inputType = ActivityInputType.toggle,
    String? measuredValue,
  }) {
    if (state == null) return;
    final report = state!.report;
    if (entryIndex < 0 || entryIndex >= report.entries.length) return;

    final entry = report.entries[entryIndex];
    if (!entry.results.containsKey(activityId)) return;

    if (inputType == ActivityInputType.value) {
      if (measuredValue == null) return;
      final newResults = Map<String, String?>.from(entry.results);
      newResults[activityId] = measuredValue.isEmpty ? null : measuredValue;

      final currentStats = state!.stats;
      final oldValue = entry.results[activityId];
      int ok = currentStats.ok;
      int pending = currentStats.pending;

      if (oldValue == null || oldValue == 'NR') pending--;
      else ok--;

      if (measuredValue.isEmpty) pending++;
      else ok++;

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

      (_dirtyResults[entry.instanceId] ??= {}).add(activityId);
      _scheduleSave(newReport);
      return;
    }

    final current = entry.results[activityId];
    String? next;
    if (current == null) next = 'OK';
    else if (current == 'OK') next = 'NOK';
    else if (current == 'NOK') next = 'NA';
    else if (current == 'NA') next = 'NR';
    else next = null;

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

    (_dirtyResults[entry.instanceId] ??= {}).add(activityId);
    _scheduleSave(newReport);
  }
  
  // ═══════════════════════════════════════════════════════
  // OBSERVACIONES
  // ═══════════════════════════════════════════════════════
  void updateObservation(int entryIndex, String text) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    _dirtyEntryFields.add(entries[entryIndex].instanceId);
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
    _dirtyEntryFields.add(entries[entryIndex].instanceId);
    entries[entryIndex] = _copyEntry(entries[entryIndex], activityData: activityData);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSave(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // FILL ALL OK
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
          (_dirtyResults[entry.instanceId] ??= {}).add(actId);
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

    final sectionInstanceIds = <String>{};
    final sectionEntries = state!.groupedEntriesMap[defId];
    if (sectionEntries == null || sectionEntries.length < 2) return;

    for (final e in sectionEntries) {
      sectionInstanceIds.add(e.instanceId);
    }

    final List<ReportEntry> thisSectionEntries = [];
    final List<int> sectionPositions = [];

    for (int i = 0; i < report.entries.length; i++) {
      if (sectionInstanceIds.contains(report.entries[i].instanceId)) {
        thisSectionEntries.add(report.entries[i]);
        sectionPositions.add(i);
      }
    }

    thisSectionEntries.sort((a, b) => _compareCustomIds(a.customId, b.customId));

    final newEntries = List<ReportEntry>.from(report.entries);
    for (int i = 0; i < sectionPositions.length; i++) {
      newEntries[sectionPositions[i]] = thisSectionEntries[i];
    }

    final newGroupedMap = Map<String, List<ReportEntry>>.from(state!.groupedEntriesMap);
    newGroupedMap[defId] = thisSectionEntries;

    final newReport = report.copyWith(entries: newEntries);
    state = state!.copyWithFullRecompute(
      newReport,
      newGroupedMap: newGroupedMap,
    );

    _scheduleSave(newReport);
  }

  int _compareCustomIds(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;

    final aParsed = _extractPrefixAndNumber(a);
    final bParsed = _extractPrefixAndNumber(b);

    final prefixCompare = aParsed.prefix.compareTo(bParsed.prefix);
    if (prefixCompare != 0) return prefixCompare;

    if (aParsed.number != null && bParsed.number != null) {
      return aParsed.number!.compareTo(bParsed.number!);
    }

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
  // CUSTOM ID / AREA
  // ═══════════════════════════════════════════════════════
  void updateCustomId(int entryIndex, String customId) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    _dirtyEntryFields.add(entries[entryIndex].instanceId);
    entries[entryIndex] = _copyEntry(entries[entryIndex], customId: customId);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSaveQuiet(newReport);

    _locationService.saveLocation(
      policyId: report.policyId,
      instanceId: entries[entryIndex].instanceId,
      customId: customId,
      area: entries[entryIndex].area, 
    );
  }

  void updateArea(int entryIndex, String area) {
    if (state == null) return;
    final report = state!.report;
    final entries = List<ReportEntry>.from(report.entries);
    _dirtyEntryFields.add(entries[entryIndex].instanceId);
    entries[entryIndex] = _copyEntry(entries[entryIndex], area: area);
    final newReport = report.copyWith(entries: entries);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSaveQuiet(newReport);

    _locationService.saveLocation(
      policyId: report.policyId,
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
    _dirtyEntryFields.add(entries[entryIndex].instanceId);
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
    _dirtyMeta = true;
    final newReport = state!.report.copyWith(generalObservations: text);
    state = state!.copyWithReportOnly(newReport);
    _scheduleSaveQuiet(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // SERVICE LIFECYCLE
  // ═══════════════════════════════════════════════════════
  void startService(String timeStr, DateTime date) {
    if (state == null) return;
    _dirtyMeta = true;
    final report = state!.report;

    final newSession = ServiceSession(
      id: _uuid.v4(),
      date: date,
      startTime: timeStr,
      endTime: null,
    );

    final updatedSessions = [...report.sessions, newSession];

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
    _dirtyMeta = true;
    final report = state!.report;

    final sessions = List<ServiceSession>.from(report.sessions);
    final openIdx = sessions.lastIndexWhere((s) => s.isOpen);

    if (openIdx == -1) {
      final newReport = report.copyWith(endTime: timeStr);
      state = state!.copyWithReportOnly(newReport);
      _saveImmediateAsync(newReport);
      return;
    }

    sessions[openIdx] = sessions[openIdx].copyWith(endTime: timeStr);

    final newReport = report.copyWith(
      sessions: sessions,
      endTime: timeStr,
    );

    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void resumeService() {
    if (state == null) return;
    _dirtyMeta = true;
    final report = state!.report;

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
    _dirtyMeta = true;
    final newReport = state!.report.copyWith(serviceDate: date);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void updateStartTime(String time) {
    if (state == null) return;
    _dirtyMeta = true;
    final newReport = state!.report.copyWith(startTime: time);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void updateEndTime(String time) {
    if (state == null) return;
    _dirtyMeta = true;
    final newReport = state!.report.copyWith(endTime: time);
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  void updateSession(String sessionId, {String? startTime, String? endTime}) {
    if (state == null) return;
    _dirtyMeta = true;
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

  void deleteSession(String sessionId) {
    if (state == null) return;
    _dirtyMeta = true;
    final report = state!.report;

    final exists = report.sessions.any((s) => s.id == sessionId);
    if (!exists) return;

    final remaining = report.sessions.where((s) => s.id != sessionId).toList();

    ServiceReportModel newReport;

    if (remaining.isEmpty) {
      newReport = report.copyWith(
        sessions: remaining,
        forceNullStartTime: true,
        forceNullEndTime: true,
      );
    } else {
      final hasOpenSession = remaining.any((s) => s.isOpen);
      if (hasOpenSession) {
        newReport = report.copyWith(
          sessions: remaining,
          startTime: remaining.first.startTime,
          forceNullEndTime: true,
        );
      } else {
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

  void addManualSession({
    required DateTime date,
    required String startTime,
    required String endTime,
  }) {
    if (state == null) return;
    _dirtyMeta = true;
    final report = state!.report;

    final newSession = ServiceSession(
      id: _uuid.v4(),
      date: date,
      startTime: startTime,
      endTime: endTime,
    );

    final updatedSessions = [...report.sessions, newSession];

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
    _dirtyMeta = true;
    final newReport = state!.report.copyWith(
      providerSignature: providerSignature,
      clientSignature: clientSignature,
      providerSignerName: providerName,
      clientSignerName: clientName,
    );
    state = state!.copyWithReportOnly(newReport);
    _saveImmediateAsync(newReport);
  }

  List<String> getNokWithoutPhotos(List<DeviceModel> deviceDefs) {
    if (state == null) return [];
    final missing = <String>[];

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
    _dirtyMeta = true;
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
    _saveImmediateAsync(newReport);
  }

  // ═══════════════════════════════════════════════════════
  // MERGE SERVER CON LOCAL
  // ═══════════════════════════════════════════════════════
  ServiceReportModel mergeServerWithLocal(ServiceReportModel serverReport) {
    if (state == null) return serverReport;
    final localReport = state!.report;

    final serverEntryMap = <String, ReportEntry>{};
    for (final e in serverReport.entries) {
      serverEntryMap[e.instanceId] = e;
    }

    final mergedEntries = <ReportEntry>[];
    final processedIds = <String>{};

    for (final localEntry in localReport.entries) {
      processedIds.add(localEntry.instanceId);
      final serverEntry = serverEntryMap[localEntry.instanceId];

      if (serverEntry == null) {
        mergedEntries.add(localEntry);
        continue;
      }

      final dirtyActs = _dirtyResults[localEntry.instanceId];
      final hasDirtyFields = _dirtyEntryFields.contains(localEntry.instanceId);

      if (dirtyActs == null && !hasDirtyFields) {
        mergedEntries.add(serverEntry);
        continue;
      }

      final mergedResults = Map<String, String?>.from(serverEntry.results);
      if (dirtyActs != null) {
        for (final actId in dirtyActs) {
          if (localEntry.results.containsKey(actId)) {
            mergedResults[actId] = localEntry.results[actId];
          }
        }
      }

      mergedEntries.add(serverEntry.copyWith(
        results: mergedResults,
        observations: hasDirtyFields ? localEntry.observations : serverEntry.observations,
        photoUrls: hasDirtyFields ? localEntry.photoUrls : serverEntry.photoUrls,
        activityData: hasDirtyFields ? localEntry.activityData : serverEntry.activityData,
        customId: hasDirtyFields ? localEntry.customId : serverEntry.customId,
        area: hasDirtyFields ? localEntry.area : serverEntry.area,
      ));
    }

    for (final serverEntry in serverReport.entries) {
      if (!processedIds.contains(serverEntry.instanceId)) {
        mergedEntries.add(serverEntry);
      }
    }

    if (_dirtyMeta) {
      return localReport.copyWith(entries: mergedEntries);
    } else {
      return serverReport.copyWith(entries: mergedEntries);
    }
  }

  // ═══════════════════════════════════════════════════════
  // SYNC FROM FIREBASE
  // ═══════════════════════════════════════════════════════
  void syncFromFirebase(
    ServiceReportModel updatedReport, {
    required List<MapEntry<String, List<ReportEntry>>> groupedEntries,
    required String frequencies,
  }) {
    if (!_hasPendingChanges || state == null) {
      state = ReportState.fromReport(
        updatedReport,
        groupedEntries: groupedEntries,
        frequencies: frequencies,
      );
      return;
    }

    final merged = mergeServerWithLocal(updatedReport);
    state = ReportState.fromReport(
      merged,
      groupedEntries: groupedEntries,
      frequencies: frequencies,
    );

    _scheduleSave(merged);
  }

  // ═══════════════════════════════════════════════════════
  // SAVE PIPELINE
  // ═══════════════════════════════════════════════════════
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

  void _saveImmediateAsync(ServiceReportModel report) {
    _saveDebounce?.cancel();
    _hasPendingChanges = true;
    _pendingReport = null;
    _saveInIsolate(report);
  }

  void _flushPendingChangesAsync() {
    if (_hasPendingChanges && _pendingReport != null) {
      final report = _pendingReport!;
      _pendingReport = null;
      _saveInIsolate(report);
    }
  }

  // ═══════════════════════════════════════════════════════
  // ★ _saveInIsolate — Ahora con backup/clear local
  // ═══════════════════════════════════════════════════════
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
      final dirty = dirtyState;

      final bool savedToServer = await _repo.saveReportMerged(
        report,
        dirtyResults: dirty.results,
        dirtyEntryFields: dirty.entryFields,
        dirtyMeta: dirty.meta,
      );

      if (savedToServer) {
        _lastSaveTimestamp = DateTime.now();
        // ★ PERSISTENCIA: Limpiar backup local (ya está en servidor)
        _clearLocalDirtyBackup(report.id);
      } else {
        // ★ PERSISTENCIA: Guardar backup local (estamos offline)
        _saveLocalDirtyBackup(report);
        debugPrint('📴 Save offline: backup local guardado');
      }
    } catch (e) {
      debugPrint('Error en _saveInIsolate: $e');
      // En caso de error, también intentar backup local
      _saveLocalDirtyBackup(report);
    } finally {
      _isSaving = false;

      if (_pendingReport != null) {
        _flushPendingChangesAsync();
      } else {
        if (_lastSaveTimestamp != null &&
            DateTime.now().difference(_lastSaveTimestamp!) < const Duration(seconds: 5)) {
          _hasPendingChanges = false;
          _clearDirtyState();
        }
      }
    }
  }

  void flushBeforeDispose() {
    if (_hasPendingChanges && _pendingReport != null) {
      _repo.saveReport(_pendingReport!);
      _hasPendingChanges = false;
      _pendingReport = null;
      _clearDirtyState();
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
// PROVIDERS (sin cambios)
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

final sectionProgressProvider =
    Provider.family<({int total, int completed, double percentage}), String>((ref, defId) {
  
  final state = ref.watch(reportNotifierProvider);
  if (state == null) return (total: 0, completed: 0, percentage: 0.0);

  int totalActivities = 0;
  int completedActivities = 0;

  final groupedEntries = state.groupedEntriesMap[defId] ?? [];
  
  for (final staleEntry in groupedEntries) {
    final globalIndex = state.instanceIdToGlobalIndex[staleEntry.instanceId];
    if (globalIndex == null) continue;
    
    final freshEntry = state.report.entries[globalIndex];
    
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
  
  return (
    total: totalActivities, 
    completed: completedActivities, 
    percentage: percentage
  );
});