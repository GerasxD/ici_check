import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────
// SERVICE SESSION — Registro de una sesión de trabajo
// ─────────────────────────────────────────────────────────────────
class ServiceSession {
  final String id;           // UUID único por sesión
  final DateTime date;       // Fecha de la sesión
  final String startTime;    // "HH:mm"
  final String? endTime;     // "HH:mm" — null si sigue abierta
  final String? technicianId; // Quién inició la sesión

  ServiceSession({
    required this.id,
    required this.date,
    required this.startTime,
    this.endTime,
    this.technicianId,
  });

  bool get isOpen => endTime == null;

  ServiceSession copyWith({
    String? id,
    DateTime? date,
    String? startTime,
    String? endTime,
    bool forceNullEndTime = false,
    String? technicianId,
  }) {
    return ServiceSession(
      id: id ?? this.id,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: forceNullEndTime ? null : (endTime ?? this.endTime),
      technicianId: technicianId ?? this.technicianId,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': Timestamp.fromDate(date),
    'startTime': startTime,
    'endTime': endTime,
    'technicianId': technicianId,
  };

  factory ServiceSession.fromMap(Map<String, dynamic> map) {
    return ServiceSession(
      id: map['id'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'],
      technicianId: map['technicianId'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServiceSession &&
          id == other.id &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode => Object.hash(id, startTime, endTime);
}

class ServiceReportModel {
  final String id;
  final String policyId;
  final String dateStr;
  final DateTime serviceDate;
  final String? startTime;
  final String? endTime;
  // ★ NUEVO: Lista de sesiones de trabajo (historial multi-día)
  final List<ServiceSession> sessions;
  final List<String> assignedTechnicianIds;
  final List<ReportEntry> entries;
  final String generalObservations;
  final String? providerSignature;
  final String? clientSignature;
  final String? providerSignerName;
  final String? clientSignerName;
  final Map<String, List<String>> sectionAssignments;
  final String status;

  ServiceReportModel({
    required this.id,
    required this.policyId,
    required this.dateStr,
    required this.serviceDate,
    this.startTime,
    this.endTime,
    this.sessions = const [],
    required this.assignedTechnicianIds,
    required this.entries,
    this.generalObservations = '',
    this.providerSignature,
    this.clientSignature,
    this.providerSignerName,
    this.clientSignerName,
    this.sectionAssignments = const {},
    this.status = 'draft',
  });

  /// ¿Hay alguna sesión actualmente abierta (sin endTime)?
  bool get hasOpenSession => sessions.any((s) => s.isOpen);

  /// La sesión activa (la más reciente sin endTime), o null
  ServiceSession? get activeSession {
    try {
      return sessions.lastWhere((s) => s.isOpen);
    } catch (_) {
      return null;
    }
  }

  ServiceReportModel copyWith({
    String? id,
    String? policyId,
    String? dateStr,
    DateTime? serviceDate,
    String? startTime,
    String? endTime,
    List<ServiceSession>? sessions,
    List<String>? assignedTechnicianIds,
    List<ReportEntry>? entries,
    String? generalObservations,
    String? providerSignature,
    String? clientSignature,
    String? providerSignerName,
    String? clientSignerName,
    Map<String, List<String>>? sectionAssignments,
    String? status,
    bool forceNullEndTime = false,
  }) {
    return ServiceReportModel(
      id: id ?? this.id,
      policyId: policyId ?? this.policyId,
      dateStr: dateStr ?? this.dateStr,
      serviceDate: serviceDate ?? this.serviceDate,
      startTime: startTime ?? this.startTime,
      endTime: forceNullEndTime ? null : (endTime ?? this.endTime),
      sessions: sessions ?? this.sessions,
      assignedTechnicianIds: assignedTechnicianIds ?? this.assignedTechnicianIds,
      entries: entries ?? this.entries,
      generalObservations: generalObservations ?? this.generalObservations,
      providerSignature: providerSignature ?? this.providerSignature,
      clientSignature: clientSignature ?? this.clientSignature,
      providerSignerName: providerSignerName ?? this.providerSignerName,
      clientSignerName: clientSignerName ?? this.clientSignerName,
      sectionAssignments: sectionAssignments ?? this.sectionAssignments,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'policyId': policyId,
      'dateStr': dateStr,
      'serviceDate': Timestamp.fromDate(serviceDate),
      'startTime': startTime,
      'endTime': endTime,
      'sessions': sessions.map((s) => s.toMap()).toList(),
      'assignedTechnicianIds': assignedTechnicianIds,
      'entries': entries.map((x) => x.toMap()).toList(),
      'generalObservations': generalObservations,
      'providerSignature': providerSignature,
      'clientSignature': clientSignature,
      'providerSignerName': providerSignerName,
      'clientSignerName': clientSignerName,
      'sectionAssignments': sectionAssignments,
      'status': status,
    };
  }

  factory ServiceReportModel.fromMap(Map<String, dynamic> map) {
    return ServiceReportModel(
      id: map['id'] ?? '',
      policyId: map['policyId'] ?? '',
      dateStr: map['dateStr'] ?? '',
      serviceDate: (map['serviceDate'] as Timestamp).toDate(),
      startTime: map['startTime'],
      endTime: map['endTime'],
      sessions: List<ServiceSession>.from(
        (map['sessions'] as List? ?? []).map((x) => ServiceSession.fromMap(x)),
      ),
      assignedTechnicianIds: List<String>.from(map['assignedTechnicianIds'] ?? []),
      entries: List<ReportEntry>.from(
        (map['entries'] as List? ?? []).map((x) => ReportEntry.fromMap(x)),
      ),
      generalObservations: map['generalObservations'] ?? '',
      providerSignature: map['providerSignature'],
      clientSignature: map['clientSignature'],
      providerSignerName: map['providerSignerName'],
      clientSignerName: map['clientSignerName'],
      sectionAssignments: Map<String, List<String>>.from(
        (map['sectionAssignments'] ?? {}).map(
          (k, v) => MapEntry(k, List<String>.from(v)),
        ),
      ),
      status: map['status'] ?? 'draft',
    );
  }
}

class ReportEntry {
  final String? assignedUserId;
  final String instanceId;
  final int deviceIndex;
  final String customId;
  final String area;
  final Map<String, String?> results;
  final String observations;
  final List<String> photoUrls;
  final Map<String, ActivityData> activityData;

  ReportEntry({
    required this.instanceId,
    required this.deviceIndex,
    required this.customId,
    this.area = '',
    required this.results,
    this.observations = '',
    this.photoUrls = const [],
    this.activityData = const {},
    this.assignedUserId,
  });

  ReportEntry copyWith({
    String? instanceId,
    int? deviceIndex,
    String? customId,
    String? area,
    Map<String, String?>? results,
    String? observations,
    List<String>? photoUrls,
    Map<String, ActivityData>? activityData,
    String? assignedUserId,
  }) {
    return ReportEntry(
      instanceId: instanceId ?? this.instanceId,
      deviceIndex: deviceIndex ?? this.deviceIndex,
      customId: customId ?? this.customId,
      area: area ?? this.area,
      results: results ?? this.results,
      observations: observations ?? this.observations,
      photoUrls: photoUrls ?? this.photoUrls,
      activityData: activityData ?? this.activityData,
      assignedUserId: assignedUserId ?? this.assignedUserId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'instanceId': instanceId,
      'deviceIndex': deviceIndex,
      'customId': customId,
      'area': area,
      'results': results,
      'observations': observations,
      'photoUrls': photoUrls,
      'activityData': activityData.map((k, v) => MapEntry(k, v.toMap())),
      'assignedUserId': assignedUserId,
    };
  }

  factory ReportEntry.fromMap(Map<String, dynamic> map) {
    return ReportEntry(
      instanceId: map['instanceId'] ?? '',
      deviceIndex: map['deviceIndex'] ?? 0,
      customId: map['customId'] ?? '',
      area: map['area'] ?? '',
      results: Map<String, String?>.from(map['results'] ?? {}),
      observations: map['observations'] ?? '',
      photoUrls: (map['photoUrls'] as List<dynamic>?)?.cast<String>() ??
                 (map['photos'] as List<dynamic>?)?.cast<String>() ??
                 [],
      activityData: Map<String, ActivityData>.from(
        (map['activityData'] ?? {}).map(
          (k, v) => MapEntry(k, ActivityData.fromMap(v)),
        ),
      ),
      assignedUserId: map['assignedUserId'],
    );
  }
}

class ActivityData {
  final List<String> photoUrls;
  final String observations;

  ActivityData({
    this.photoUrls = const [],
    this.observations = '',
  });

  ActivityData copyWith({
    List<String>? photoUrls,
    String? observations,
  }) {
    return ActivityData(
      photoUrls: photoUrls ?? this.photoUrls,
      observations: observations ?? this.observations,
    );
  }

  Map<String, dynamic> toMap() => {
    'photoUrls': photoUrls,
    'observations': observations,
  };

  factory ActivityData.fromMap(Map<String, dynamic> map) {
    return ActivityData(
      photoUrls: (map['photoUrls'] as List<dynamic>?)?.cast<String>() ??
                 (map['photos'] as List<dynamic>?)?.cast<String>() ??
                 [],
      observations: map['observations'] ?? '',
    );
  }
}