import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceReportModel {
  final String id;
  final String policyId;
  final String dateStr; // "2025-02" o "2025-W05"
  final DateTime serviceDate;
  final String? startTime;
  final String? endTime;
  final List<String> assignedTechnicianIds;
  final List<ReportEntry> entries;
  final String generalObservations;
  final String? providerSignature; // Base64 o URL
  final String? clientSignature;   // Base64 o URL
  final String? providerSignerName;
  final String? clientSignerName;
  final Map<String, List<String>> sectionAssignments; // {defId: [userIds]}
  final String status; // 'draft', 'completed'

  ServiceReportModel({
    required this.id,
    required this.policyId,
    required this.dateStr,
    required this.serviceDate,
    this.startTime,
    this.endTime,
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

  ServiceReportModel copyWith({
    String? id,
    String? policyId,
    String? dateStr,
    DateTime? serviceDate,
    String? startTime,
    String? endTime,
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
  final List<String> photoUrls; // ✅ CAMBIO: photos → photoUrls
  final Map<String, ActivityData> activityData;

  ReportEntry({
    required this.instanceId,
    required this.deviceIndex,
    required this.customId,
    this.area = '',
    required this.results,
    this.observations = '',
    this.photoUrls = const [], // ✅ CAMBIO
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
    List<String>? photoUrls, // ✅ CAMBIO
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
      photoUrls: photoUrls ?? this.photoUrls, // ✅ CAMBIO
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
      'photoUrls': photoUrls, // ✅ CAMBIO: Guardamos URLs
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
      // ✅ MIGRACIÓN AUTOMÁTICA: Intenta cargar photoUrls, si no existe usa photos (retrocompatibilidad)
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
  final List<String> photoUrls; // ✅ CAMBIO: photos → photoUrls
  final String observations;

  ActivityData({
    this.photoUrls = const [], // ✅ CAMBIO
    this.observations = '',
  });

  ActivityData copyWith({
    List<String>? photoUrls, // ✅ CAMBIO
    String? observations,
  }) {
    return ActivityData(
      photoUrls: photoUrls ?? this.photoUrls, // ✅ CAMBIO
      observations: observations ?? this.observations,
    );
  }

  Map<String, dynamic> toMap() => {
    'photoUrls': photoUrls, // ✅ CAMBIO
    'observations': observations,
  };

  factory ActivityData.fromMap(Map<String, dynamic> map) {
    return ActivityData(
      // ✅ MIGRACIÓN AUTOMÁTICA: Intenta cargar photoUrls, si no existe usa photos
      photoUrls: (map['photoUrls'] as List<dynamic>?)?.cast<String>() ?? 
                 (map['photos'] as List<dynamic>?)?.cast<String>() ?? 
                 [],
      observations: map['observations'] ?? '',
    );
  }
}