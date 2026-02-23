// ═══════════════════════════════════════════════════════════════════════
// DeviceSectionImproved — Refactorizado para VIRTUALIZACIÓN REAL
//
// ANTES: Widget monolítico que contenía un ListView/GridView interno
//        con NeverScrollableScrollPhysics + SizedBox de altura fija.
//        → Flutter construía TODAS las filas de golpe = lag en móvil.
//
// DESPUÉS: Expone widgets individuales (header + filas) que el
//          CustomScrollView padre virtualiza directamente.
//          Solo se construyen las ~10-15 filas visibles en pantalla.
//
// ARQUITECTURA:
//   - DeviceSectionHeader: widget sticky del header de sección
//   - DeviceSectionTableRow: ConsumerWidget para una fila de tabla
//   - DeviceSectionListCard: ConsumerWidget para una card de lista
//   - buildFlatSliverItems(): función que genera los slivers aplanados
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/reports/state/report_providers.dart';

// ═══════════════════════════════════════════════════════════════════════
// FUNCIÓN PRINCIPAL: Genera los slivers aplanados para una sección
//
// Retorna una lista de widgets que se insertan directamente en el
// SliverList del CustomScrollView padre. Esto permite virtualización
// real: solo se construyen las filas visibles en pantalla.
// ═══════════════════════════════════════════════════════════════════════

class FlatSectionData {
  final String defId;
  final DeviceModel deviceDef;
  final List<ReportEntry> entries;
  final List<String> assignments;
  final List<ActivityConfig> relevantActivities;
  final List<UserModel> users;
  final bool isEditable;
  final bool isUserCoordinator;
  final bool adminOverride;
  final String? currentUserId;
  final Map<String, int> indexMap;
  final Function(int globalIndex, {String? activityId}) onCameraClick;
  final Function(int globalIndex, {String? activityId}) onObservationClick;

  FlatSectionData({
    required this.defId,
    required this.deviceDef,
    required this.entries,
    required this.assignments,
    required this.relevantActivities,
    required this.users,
    required this.isEditable,
    required this.isUserCoordinator,
    required this.adminOverride,
    this.currentUserId,
    required this.indexMap,
    required this.onCameraClick,
    required this.onObservationClick,
  });

  bool get canEdit {
    if (!isEditable) return false;
    if (adminOverride && isUserCoordinator) return true;
    if (assignments.isNotEmpty) {
      return currentUserId != null && assignments.contains(currentUserId);
    }
    return true;
  }
}

/// Genera una lista plana de widgets para insertar en un SliverList.
/// Cada widget es independiente y puede ser virtualizado por el CustomScrollView.
List<Widget> buildFlatWidgetsForSection(FlatSectionData data, ReportNotifier notifier) {
  if (data.entries.isEmpty || data.relevantActivities.isEmpty) return [];

  final List<Widget> widgets = [];

  // 1. HEADER DE SECCIÓN (siempre visible cuando la sección está en pantalla)
  widgets.add(
    DeviceSectionHeader(
      key: ValueKey('header_${data.defId}'),
      defId: data.defId,
      deviceDef: data.deviceDef,
      entries: data.entries,
      assignments: data.assignments,
      users: data.users,
      notifier: notifier,
      isFirst: true,
    ),
  );

  final isTableView = data.deviceDef.viewMode == 'table';

  if (isTableView) {
    // 2a. TABLE VIEW: Header de columnas + filas individuales
    widgets.add(
      _TableColumnHeader(
        key: ValueKey('colheader_${data.defId}'),
        activities: data.relevantActivities,
      ),
    );

    for (int i = 0; i < data.entries.length; i++) {
      final entry = data.entries[i];
      final globalIndex = data.indexMap[entry.instanceId] ?? -1;
      if (globalIndex == -1) continue;

      widgets.add(
        RepaintBoundary(
          child: DeviceSectionTableRow(
            key: ValueKey('trow_${entry.instanceId}'),
            globalIndex: globalIndex,
            activities: data.relevantActivities,
            canEdit: data.canEdit,
            notifier: notifier,
            onCameraClick: data.onCameraClick,
            onObservationClick: data.onObservationClick,
          ),
        ),
      );
    }
  } else {
    // 2b. LIST VIEW: Cards individuales (en filas de 1-3 según ancho)
    // Como no podemos hacer GridView virtualizado dentro de Slivers fácilmente,
    // agrupamos las cards en filas manuales
    for (int i = 0; i < data.entries.length; i++) {
      final entry = data.entries[i];
      final globalIndex = data.indexMap[entry.instanceId] ?? -1;
      if (globalIndex == -1) continue;

      widgets.add(
        RepaintBoundary(
          child: DeviceSectionListCard(
            key: ValueKey('card_${entry.instanceId}'),
            globalIndex: globalIndex,
            activities: data.relevantActivities,
            canEdit: data.canEdit,
            notifier: notifier,
            onCameraClick: data.onCameraClick,
            onObservationClick: data.onObservationClick,
          ),
        ),
      );
    }
  }

  // 3. SPACER al final de la sección
  widgets.add(const SizedBox(height: 16));

  return widgets;
}


// ═══════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════
class DeviceSectionHeader extends ConsumerWidget {
  final String defId;
  final DeviceModel deviceDef;
  final List<ReportEntry> entries;
  final List<String> assignments;
  final List<UserModel> users;
  final ReportNotifier notifier;
  final bool isFirst;

  const DeviceSectionHeader({
    super.key,
    required this.defId,
    required this.deviceDef,
    required this.entries,
    required this.assignments,
    required this.users,
    required this.notifier,
    this.isFirst = false,
  });


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedUsersList = assignments.map((uid) {
      return users.firstWhere(
        (u) => u.id == uid,
        orElse: () => UserModel(id: uid, name: 'Usuario', email: ''),
      );
    }).toList();

    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final progress = ref.watch(sectionProgressProvider(defId));

    return Container(
      margin: EdgeInsets.fromLTRB(16, isFirst ? 0 : 0, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: const Color(0xFF1E293B), width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          isSmallScreen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            deviceDef.name.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _CountBadge(count: entries.length),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ResponsiblesRow(
                      assignedUsersList: assignedUsersList,
                      isSmall: true,
                      defId: defId,
                      users: users,
                      assignments: assignments,
                      notifier: notifier,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              deviceDef.name.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _CountBadge(count: entries.length),
                        ],
                      ),
                    ),
                    _ResponsiblesRow(
                      assignedUsersList: assignedUsersList,
                      isSmall: false,
                      defId: defId,
                      users: users,
                      assignments: assignments,
                      notifier: notifier,
                    ),
                  ],
                ),
          const SizedBox(height: 12),
          _ProgressBar(progress: progress),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE COLUMN HEADER (cabecera de columnas para vista tabla)
// ═══════════════════════════════════════════════════════════════════════
class _TableColumnHeader extends StatelessWidget {
  final List<ActivityConfig> activities;

  const _TableColumnHeader({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF1E293B), width: 2),
      ),
      child: _DragScrollable(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 230.0 + (activities.length * 100.0) + 110.0,
            child: Container(
              color: const Color(0xFFF1F5F9),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeaderCell(text: 'ID', width: 80),
                    _HeaderCell(text: 'UBICACIÓN', width: 150),
                    ...activities
                        .map((act) => _HeaderCell(text: act.name, width: 100)),
                    _HeaderCell(text: 'FOTO/OBS', width: 110),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TABLE ENTRY ROW — ConsumerWidget que escucha SOLO SU entry
// ═══════════════════════════════════════════════════════════════════════
class DeviceSectionTableRow extends ConsumerWidget {
  final int globalIndex;
  final List<ActivityConfig> activities;
  final bool canEdit;
  final ReportNotifier notifier;
  final Function(int, {String? activityId}) onCameraClick;
  final Function(int, {String? activityId}) onObservationClick;

  const DeviceSectionTableRow({
    super.key,
    required this.globalIndex,
    required this.activities,
    required this.canEdit,
    required this.notifier,
    required this.onCameraClick,
    required this.onObservationClick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(singleEntryProvider(globalIndex));
    if (entry == null) return const SizedBox(height: 52);

    final double totalWidth = 230.0 + (activities.length * 100.0) + 110.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: const BorderSide(color: Color(0xFF1E293B), width: 2),
          right: const BorderSide(color: Color(0xFF1E293B), width: 2),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: _DragScrollable(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            height: 52.0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // CustomId
                SizedBox(
                  width: 80,
                  child: Center(
                    child: SizedBox(
                      width: 60,
                      height: 32,
                      child: _IsolatedTextField(
                        key: ValueKey('id_${entry.instanceId}'),
                        initialValue: entry.customId,
                        enabled: canEdit,
                        onChanged: (val) =>
                            notifier.updateCustomId(globalIndex, val),
                      ),
                    ),
                  ),
                ),
                // Area
                SizedBox(
                  width: 150,
                  child: Center(
                    child: SizedBox(
                      width: 130,
                      height: 32,
                      child: _IsolatedTextField(
                        key: ValueKey('area_${entry.instanceId}'),
                        initialValue: entry.area,
                        hint: '...',
                        enabled: canEdit,
                        onChanged: (val) =>
                            notifier.updateArea(globalIndex, val),
                      ),
                    ),
                  ),
                ),
                // Status toggles
                ...activities.map((act) {
                  if (!entry.results.containsKey(act.id)) {
                    return const SizedBox(width: 100);
                  }
                  return SizedBox(
                    width: 100,
                    child: Center(
                      child: InkWell(
                        onTap: canEdit
                            ? () => notifier.toggleStatus(globalIndex, act.id)
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: _CompactStatusBadge(status: entry.results[act.id]),
                      ),
                    ),
                  );
                }),
                // Photo/Obs actions
                SizedBox(
                  width: 110,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CompactActionIcon(
                        icon: entry.photoUrls.isNotEmpty
                            ? Icons.camera_alt
                            : Icons.camera_alt_outlined,
                        isActive: entry.photoUrls.isNotEmpty,
                        activeColor: const Color(0xFF3B82F6),
                        onTap: canEdit
                            ? () => onCameraClick(globalIndex)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      _CompactActionIcon(
                        icon: entry.observations.isNotEmpty
                            ? Icons.comment
                            : Icons.comment_outlined,
                        isActive: entry.observations.isNotEmpty,
                        activeColor: const Color(0xFFF59E0B),
                        onTap: canEdit
                            ? () => onObservationClick(globalIndex)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LIST ENTRY CARD — ConsumerWidget que escucha SOLO SU entry
// ═══════════════════════════════════════════════════════════════════════
class DeviceSectionListCard extends ConsumerWidget {
  final int globalIndex;
  final List<ActivityConfig> activities;
  final bool canEdit;
  final ReportNotifier notifier;
  final Function(int, {String? activityId}) onCameraClick;
  final Function(int, {String? activityId}) onObservationClick;

  const DeviceSectionListCard({
    super.key,
    required this.globalIndex,
    required this.activities,
    required this.canEdit,
    required this.notifier,
    required this.onCameraClick,
    required this.onObservationClick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(singleEntryProvider(globalIndex));
    if (entry == null) return const SizedBox();

    final entryActivities = activities
        .where((act) => entry.results.containsKey(act.id))
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: const BorderSide(color: Color(0xFF1E293B), width: 2),
          right: const BorderSide(color: Color(0xFF1E293B), width: 2),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ID + Area row
          Row(
            children: [
              SizedBox(
                width: 60,
                height: 32,
                child: _IsolatedTextField(
                  key: ValueKey('grid_id_${entry.instanceId}'),
                  initialValue: entry.customId,
                  hint: 'ID',
                  enabled: canEdit,
                  onChanged: (val) =>
                      notifier.updateCustomId(globalIndex, val),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: _IsolatedTextField(
                    key: ValueKey('grid_area_${entry.instanceId}'),
                    initialValue: entry.area,
                    hint: 'Ubicación...',
                    enabled: canEdit,
                    onChanged: (val) =>
                        notifier.updateArea(globalIndex, val),
                  ),
                ),
              ),
            ],
          ),

          if (entryActivities.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
          ],

          // Activity rows
          ...entryActivities.map((act) {
            final status = entry.results[act.id];
            final hasPhotos =
                (entry.activityData[act.id]?.photoUrls.length ?? 0) > 0;
            final hasObs =
                (entry.activityData[act.id]?.observations ?? '').isNotEmpty;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      act.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _CompactActionIcon(
                    icon: hasPhotos
                        ? Icons.camera_alt
                        : Icons.camera_alt_outlined,
                    isActive: hasPhotos,
                    activeColor: const Color(0xFF3B82F6),
                    onTap: canEdit
                        ? () =>
                            onCameraClick(globalIndex, activityId: act.id)
                        : null,
                  ),
                  _CompactActionIcon(
                    icon: hasObs ? Icons.comment : Icons.comment_outlined,
                    isActive: hasObs,
                    activeColor: const Color(0xFFF59E0B),
                    onTap: canEdit
                        ? () => onObservationClick(globalIndex,
                            activityId: act.id)
                        : null,
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: canEdit
                        ? () => notifier.toggleStatus(globalIndex, act.id)
                        : null,
                    child: _CompactStatusBadge(status: status),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════
// PROGRESS BAR
// ═══════════════════════════════════════════════════════════════════════
class _ProgressBar extends StatelessWidget {

  final ({int total, int completed, double percentage}) progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final percentage = progress.percentage;
    final completed = progress.completed;
    final total = progress.total;

    Color progressColor;
    if (percentage == 0) {
      progressColor = const Color(0xFF64748B);
    } else if (percentage < 50) {
      progressColor = const Color(0xFFEF4444);
    } else if (percentage < 80) {
      progressColor = const Color(0xFFF59E0B);
    } else if (percentage < 100) {
      progressColor = const Color(0xFF3B82F6);
    } else {
      progressColor = const Color(0xFF10B981);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.trending_up, size: 12, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            const Text(
              'PROGRESO:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: progressColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: progressColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    percentage == 100 ? Icons.check_circle : Icons.schedule,
                    size: 11,
                    color: progressColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$completed/$total',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: progressColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(color: const Color(0xFF334155)),
                      FractionallySizedBox(
                        widthFactor: (percentage / 100).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                progressColor,
                                progressColor.withOpacity(0.8),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// COUNT BADGE
// ═══════════════════════════════════════════════════════════════════════
class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Text(
        '$count UNIDADES',
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RESPONSABLES ROW + ASSIGNMENT DIALOG
// ═══════════════════════════════════════════════════════════════════════
class _ResponsiblesRow extends StatelessWidget {
  final List<UserModel> assignedUsersList;
  final bool isSmall;
  final String defId;
  final List<UserModel> users;
  final List<String> assignments;
  final ReportNotifier notifier;

  const _ResponsiblesRow({
    required this.assignedUsersList,
    required this.isSmall,
    required this.defId,
    required this.users,
    required this.assignments,
    required this.notifier,
  });

  void _showAssignmentDialog(BuildContext context) {
    final Set<String> localAssignments = Set<String>.from(assignments);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: 400,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF1F5F9)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Asignar Responsables',
                            style: TextStyle(
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.close,
                                size: 20,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: users.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.group_off_outlined,
                                    size: 48,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No hay personal disponible",
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              itemCount: users.length,
                              separatorBuilder: (ctx, i) => const Divider(
                                height: 1,
                                indent: 60,
                                endIndent: 20,
                                color: Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (ctx, i) {
                                final user = users[i];
                                final isAssigned =
                                    localAssignments.contains(user.id);
                                return Material(
                                  color: Colors.transparent,
                                  child: CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    dense: true,
                                    activeColor: const Color(0xFF3B82F6),
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    secondary: CircleAvatar(
                                      backgroundColor: isAssigned
                                          ? const Color(0xFFEFF6FF)
                                          : const Color(0xFFF1F5F9),
                                      foregroundColor: isAssigned
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFF64748B),
                                      child: Text(
                                        user.name.isNotEmpty
                                            ? user.name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      user.name,
                                      style: TextStyle(
                                        fontWeight: isAssigned
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 14,
                                        color: const Color(0xFF1E293B),
                                      ),
                                    ),
                                    subtitle: Text(
                                      user.email,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                    value: isAssigned,
                                    onChanged: (val) {
                                      setModalState(() {
                                        if (isAssigned) {
                                          localAssignments.remove(user.id);
                                        } else {
                                          localAssignments.add(user.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFF1F5F9)),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final initialSet =
                                Set<String>.from(assignments);
                            final finalSet =
                                Set<String>.from(localAssignments);
                            final removed = initialSet.difference(finalSet);
                            final added = finalSet.difference(initialSet);
                            for (var userId in removed) {
                              notifier.toggleSectionAssignment(
                                  defId, userId);
                            }
                            for (var userId in added) {
                              notifier.toggleSectionAssignment(
                                  defId, userId);
                            }
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "LISTO",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isSmall)
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Text(
              "RESPONSABLES:",
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Flexible(
          fit: isSmall ? FlexFit.loose : FlexFit.tight,
          flex: isSmall ? 1 : 0,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...assignedUsersList
                    .take(3)
                    .map((user) => _UserChip(user: user)),
                if (assignedUsersList.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      "+${assignedUsersList.length - 3}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => _showAssignmentDialog(context),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF334155).withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Icon(
              assignedUsersList.isEmpty
                  ? Icons.person_add_alt_1
                  : Icons.edit,
              color: Colors.white70,
              size: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// USER CHIP
// ═══════════════════════════════════════════════════════════════════════
class _UserChip extends StatelessWidget {
  final UserModel user;
  const _UserChip({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: Colors.white,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            user.name.split(' ').first,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════
// DRAG TO SCROLL — Habilita scroll horizontal con click+drag en web
// ═══════════════════════════════════════════════════════════════════════
class _DragScrollable extends StatefulWidget {
  final Widget child;
  const _DragScrollable({required this.child});

  @override
  State<_DragScrollable> createState() => _DragScrollableState();
}

class _DragScrollableState extends State<_DragScrollable> {
  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
        },
      ),
      child: widget.child,
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final double width;
  const _HeaderCell({required this.text, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1E293B),
          ),
          textAlign: TextAlign.center,
          softWrap: true,
          overflow: TextOverflow.visible,
          maxLines: null,
        ),
      ),
    );
  }
}

class _CompactActionIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _CompactActionIcon({
    required this.icon,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: isActive ? activeColor : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class _CompactStatusBadge extends StatelessWidget {
  final String? status;
  const _CompactStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color borderColor;
    Widget? child;

    switch (status) {
      case 'OK':
        bgColor = const Color(0xFF10B981);
        borderColor = const Color(0xFF059669);
        child = Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        );
        break;
      case 'NOK':
        bgColor = const Color(0xFFEF4444);
        borderColor = const Color(0xFFDC2626);
        child = const Icon(Icons.close, size: 14, color: Colors.white);
        break;
      case 'NA':
        bgColor = const Color(0xFFE2E8F0);
        borderColor = const Color(0xFFCBD5E1);
        child = const Text(
          'N/A',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Color(0xFF64748B),
          ),
        );
        break;
      case 'NR':
        bgColor = const Color(0xFFFBBF24);
        borderColor = const Color(0xFFF59E0B);
        child = const Text(
          'N/R',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        );
        break;
      default:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            color: Colors.white,
          ),
        );
    }

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Center(child: child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ISOLATED TEXT FIELD — Controller local con debounce
// ═══════════════════════════════════════════════════════════════════════
class _IsolatedTextField extends StatefulWidget {
  final String initialValue;
  final String hint;
  final bool enabled;
  final Function(String) onChanged;

  const _IsolatedTextField({
    super.key,
    required this.initialValue,
    this.hint = '',
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_IsolatedTextField> createState() => _IsolatedTextFieldState();
}

class _IsolatedTextFieldState extends State<_IsolatedTextField> {
  late TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _IsolatedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_controller.text != widget.initialValue) {
      widget.onChanged(_controller.text);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        hintText: widget.hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
      ),
      onChanged: (val) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), () {
          widget.onChanged(val);
        });
      },
    );
  }
}