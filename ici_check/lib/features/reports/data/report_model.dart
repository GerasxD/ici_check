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

  // --- NUEVO: Método copyWith para actualizaciones inmutables ---
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
    // Parámetro especial para permitir limpiar el endTime (ponerlo en null)
    bool forceNullEndTime = false, 
  }) {
    return ServiceReportModel(
      id: id ?? this.id,
      policyId: policyId ?? this.policyId,
      dateStr: dateStr ?? this.dateStr,
      serviceDate: serviceDate ?? this.serviceDate,
      startTime: startTime ?? this.startTime,
      // Lógica para permitir 'null' en endTime si se requiere reiniciar (ej. reanudar servicio)
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
  final String? assignedUserId; // <--- LO AGREGASTE AQUÍ
  final String instanceId;
  final int deviceIndex;
  final String customId;
  final String area;
  final Map<String, String?> results;
  final String observations;
  final List<String> photos;
  final Map<String, ActivityData> activityData;

  ReportEntry({
    required this.instanceId,
    required this.deviceIndex,
    required this.customId,
    this.area = '',
    required this.results,
    this.observations = '',
    this.photos = const [],
    this.activityData = const {},
    this.assignedUserId, // Bien
  });

  ReportEntry copyWith({
    String? instanceId,
    int? deviceIndex,
    String? customId,
    String? area,
    Map<String, String?>? results,
    String? observations,
    List<String>? photos,
    Map<String, ActivityData>? activityData,
    String? assignedUserId, // <--- FALTABA AQUÍ
  }) {
    return ReportEntry(
      instanceId: instanceId ?? this.instanceId,
      deviceIndex: deviceIndex ?? this.deviceIndex,
      customId: customId ?? this.customId,
      area: area ?? this.area,
      results: results ?? this.results,
      observations: observations ?? this.observations,
      photos: photos ?? this.photos,
      activityData: activityData ?? this.activityData,
      assignedUserId: assignedUserId ?? this.assignedUserId, // <--- FALTABA AQUÍ
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
      'photos': photos,
      'activityData': activityData.map((k, v) => MapEntry(k, v.toMap())),
      'assignedUserId': assignedUserId, // <--- FALTABA AQUÍ PARA GUARDAR EN FIREBASE
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
      photos: List<String>.from(map['photos'] ?? []),
      activityData: Map<String, ActivityData>.from(
        (map['activityData'] ?? {}).map(
          (k, v) => MapEntry(k, ActivityData.fromMap(v)),
        ),
      ),
      assignedUserId: map['assignedUserId'], // <--- FALTABA AQUÍ PARA LEER DE FIREBASE
    );
  }
}

class ActivityData {
  final List<String> photos;
  final String observations;

  ActivityData({this.photos = const [], this.observations = ''});

  // --- NUEVO: Método copyWith ---
  ActivityData copyWith({
    List<String>? photos,
    String? observations,
  }) {
    return ActivityData(
      photos: photos ?? this.photos,
      observations: observations ?? this.observations,
    );
  }

  Map<String, dynamic> toMap() => {'photos': photos, 'observations': observations};

  factory ActivityData.fromMap(Map<String, dynamic> map) {
    return ActivityData(
      photos: List<String>.from(map['photos'] ?? []),
      observations: map['observations'] ?? '',
    );
  }
}