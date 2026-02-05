import 'package:flutter/material.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';

class DeviceSectionImproved extends StatelessWidget {
  final String defId;
  final DeviceModel deviceDef;
  final List<ReportEntry> entries;
  final List<UserModel> users;
  final List<String> sectionAssignments;
  final bool isEditable;
  final bool allowedToEdit;
  final bool isUserCoordinator;
  final String? currentUserId;
  
  // Callbacks
  final Function(String userId) onToggleAssignment;
  final Function(int index, String customId) onCustomIdChanged;
  final Function(int index, String area) onAreaChanged;
  final Function(int index, String activityId) onToggleStatus;
  final Function(int index, {String? activityId}) onCameraClick;
  final Function(int index, {String? activityId}) onObservationClick;

  const DeviceSectionImproved({
    super.key,
    required this.defId,
    required this.deviceDef,
    required this.entries,
    required this.users,
    required this.sectionAssignments,
    required this.isEditable,
    required this.allowedToEdit,
    required this.isUserCoordinator,
    this.currentUserId,
    required this.onToggleAssignment,
    required this.onCustomIdChanged,
    required this.onAreaChanged,
    required this.onToggleStatus,
    required this.onCameraClick,
    required this.onObservationClick,
  });

  int _getSectionProgress() {
    if (entries.isEmpty) return 0;
    int totalScheduled = 0;
    int completed = 0;
    
    for (var entry in entries) {
      totalScheduled += entry.results.length;
      completed += entry.results.values.where((s) => s != null).length;
    }
    
    if (totalScheduled == 0) return 0;
    return ((completed / totalScheduled) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final scheduledActivityIds = entries.expand((e) => e.results.keys).toSet();
    final relevantActivities = deviceDef.activities
        .where((a) => scheduledActivityIds.contains(a.id))
        .toList();

    if (relevantActivities.isEmpty) return const SizedBox();
    
    final progress = _getSectionProgress();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF1E293B), width: 2), // slate-800
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(progress),
          deviceDef.viewMode == 'table'
              ? _buildTableView(relevantActivities)
              : _buildListView(relevantActivities),
        ],
      ),
    );
  }

  Widget _buildHeader(int progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B), // slate-800
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Nombre del dispositivo
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.devices_other,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceDef.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF475569), // slate-600
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${entries.length} UNIDADES',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Asignaciones (versión compacta)
              if (sectionAssignments.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 12, right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF475569).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, size: 12, color: Colors.white70),
                      const SizedBox(width: 6),
                      ...sectionAssignments.take(3).map((uid) {
                        final user = users.firstWhere(
                          (u) => u.id == uid,
                          orElse: () => UserModel(id: uid, name: '?', email: ''),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: const Color(0xFF3B82F6), // blue-500
                            child: Text(
                              user.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      }),
                      if (sectionAssignments.length > 3)
                        Text(
                          '+${sectionAssignments.length - 3}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              
              // Indicador de progreso
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'PROGRESO',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 3,
                              decoration: BoxDecoration(
                                color: const Color(0xFF475569),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress / 100,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: progress == 100
                                        ? const Color(0xFF10B981) // green-500
                                        : const Color(0xFF3B82F6), // blue-500
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$progress%',
                              style: TextStyle(
                                color: progress == 100
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF60A5FA), // blue-400
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableView(List<ActivityConfig> activities) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 50,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)), // slate-100
        dataRowMinHeight: 48,
        dataRowMaxHeight: 48,
        columnSpacing: 12,
        horizontalMargin: 16,
        dividerThickness: 1,
        border: TableBorder(
          horizontalInside: BorderSide(color: Colors.grey.shade200),
          verticalInside: BorderSide(color: Colors.grey.shade200),
        ),
        columns: [
          DataColumn(
            label: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'ID',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          DataColumn(
            label: Container(
              constraints: const BoxConstraints(minWidth: 150),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'UBICACIÓN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          ...activities.map((act) => DataColumn(
            label: Container(
              constraints: const BoxConstraints(minWidth: 80, maxWidth: 100),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    act.name,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0), // slate-200
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      act.frequency.toString().split('.').last.substring(0, 3),
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B), // slate-500
                      ),
                    ),
                  ),
                  if (act.expectedValue.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Ref: ${act.expectedValue}',
                      style: const TextStyle(
                        fontSize: 7,
                        color: Color(0xFF94A3B8), // slate-400
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          )),
          const DataColumn(
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.camera_alt, size: 16, color: Color(0xFF64748B)),
            ),
          ),
          const DataColumn(
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.comment, size: 16, color: Color(0xFF64748B)),
            ),
          ),
        ],
        rows: entries.asMap().entries.map((entryMap) {
          final index = entryMap.key;
          final entry = entryMap.value;
          
          return DataRow(
            color: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.hovered)) {
                return const Color(0xFFF8FAFC); // slate-50
              }
              return Colors.white;
            }),
            cells: [
              DataCell(
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: entry.customId,
                    enabled: isEditable && allowedToEdit,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                      ),
                    ),
                    onChanged: (val) => onCustomIdChanged(index, val),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    initialValue: entry.area,
                    enabled: isEditable && allowedToEdit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      hintText: '...',
                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                      ),
                    ),
                    onChanged: (val) => onAreaChanged(index, val),
                  ),
                ),
              ),
              ...activities.map((act) {
                if (!entry.results.containsKey(act.id)) {
                  return const DataCell(SizedBox());
                }
                return DataCell(
                  Center(
                    child: InkWell(
                      onTap: (isEditable && allowedToEdit)
                          ? () => onToggleStatus(index, act.id)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      child: _buildStatusBadge(entry.results[act.id]),
                    ),
                  ),
                );
              }),
              DataCell(
                Center(
                  child: IconButton(
                    icon: Icon(
                      entry.photos.isNotEmpty ? Icons.camera_alt : Icons.camera_alt_outlined,
                      size: 18,
                      color: entry.photos.isNotEmpty
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF94A3B8),
                    ),
                    onPressed: (isEditable && allowedToEdit)
                        ? () => onCameraClick(index)
                        : null,
                  ),
                ),
              ),
              DataCell(
                Center(
                  child: IconButton(
                    icon: Icon(
                      entry.observations.isNotEmpty ? Icons.comment : Icons.comment_outlined,
                      size: 18,
                      color: entry.observations.isNotEmpty
                          ? const Color(0xFFF59E0B) // amber-500
                          : const Color(0xFF94A3B8),
                    ),
                    onPressed: (isEditable && allowedToEdit)
                        ? () => onObservationClick(index)
                        : null,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListView(List<ActivityConfig> activities) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: entries.asMap().entries.map((entryMap) {
          final index = entryMap.key;
          final entry = entryMap.value;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header de la tarjeta
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: entry.customId,
                        enabled: isEditable && allowedToEdit,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => onCustomIdChanged(index, val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        initialValue: entry.area,
                        enabled: isEditable && allowedToEdit,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          hintText: 'Ubicación...',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => onAreaChanged(index, val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Actividades
                ...activities.where((act) => entry.results.containsKey(act.id)).map((act) {
                  final status = entry.results[act.id];
                  final hasPhotos = (entry.activityData[act.id]?.photos.length ?? 0) > 0;
                  final hasObs = (entry.activityData[act.id]?.observations ?? '').isNotEmpty;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                act.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      act.frequency.toString().split('.').last,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  if (act.expectedValue.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      'Ref: ${act.expectedValue}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF94A3B8),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                hasPhotos ? Icons.camera_alt : Icons.camera_alt_outlined,
                                size: 16,
                                color: hasPhotos ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8),
                              ),
                              onPressed: (isEditable && allowedToEdit)
                                  ? () => onCameraClick(index, activityId: act.id)
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                hasObs ? Icons.comment : Icons.comment_outlined,
                                size: 16,
                                color: hasObs ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                              ),
                              onPressed: (isEditable && allowedToEdit)
                                  ? () => onObservationClick(index, activityId: act.id)
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              onTap: (isEditable && allowedToEdit)
                                  ? () => onToggleStatus(index, act.id)
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              child: _buildStatusBadge(status),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color bgColor;
    Color borderColor;
    Widget? child;
    
    switch (status) {
      case 'OK':
        bgColor = const Color(0xFF1E293B); // slate-800 (negro en el diseño)
        borderColor = const Color(0xFF1E293B);
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
        bgColor = const Color(0xFFEF4444); // red-500
        borderColor = const Color(0xFFDC2626); // red-600
        child = const Icon(Icons.close, size: 14, color: Colors.white);
        break;
      case 'NA':
        bgColor = const Color(0xFFE2E8F0); // slate-200
        borderColor = const Color(0xFFCBD5E1); // slate-300
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
        bgColor = const Color(0xFFFBBF24); // amber-400
        borderColor = const Color(0xFFF59E0B); // amber-500
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
            border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
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
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}