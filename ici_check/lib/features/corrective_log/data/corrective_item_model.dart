import 'package:cloud_firestore/cloud_firestore.dart';

/// Nivel de atención del correctivo (como en tu PDF)
enum AttentionLevel {
  A, // Daño potencial para el equipo y su funcionamiento
  B, // Riesgo de daño moderado
  C, // Detalle de prevención
}

/// Estado del correctivo
enum CorrectiveStatus {
  PENDING,              // Detectado, sin acción
  IN_PROGRESS,          // En proceso de corrección
  CORRECTED_BY_ICISI,   // Corregido por ICISI
  CORRECTED_BY_THIRD,   // Corregido por Terceros
}

class CorrectiveItemModel {
  final String id;
  final String policyId;

  // ═══════ ORIGEN (Auto-poblado desde el reporte) ═══════
  final String reportId;
  final String reportDateStr;
  final String deviceInstanceId;
  final String deviceCustomId;
  final String deviceArea;
  final String deviceDefId;
  final String deviceDefName;
  final String activityId;
  final String activityName;
  final DateTime detectionDate;

  // ═══════ DESCRIPCIÓN DEL PROBLEMA ═══════
  final String problemDescription;
  final List<String> problemPhotoUrls;

  // ═══════ GESTIÓN DEL CORRECTIVO ═══════
  final AttentionLevel level;
  final CorrectiveStatus status;
  final String? reportedTo;
  final DateTime? estimatedCorrectionDate;
  final String correctionAction;
  final List<String> correctionPhotoUrls;

  // ═══════ CIERRE ═══════
  final DateTime? actualCorrectionDate;
  final String? correctedByUserId;
  final String? correctedByName;
  final String observations;

  // ═══════ META ═══════
  final DateTime createdAt;
  final DateTime updatedAt;

  CorrectiveItemModel({
    required this.id,
    required this.policyId,
    required this.reportId,
    required this.reportDateStr,
    required this.deviceInstanceId,
    required this.deviceCustomId,
    required this.deviceArea,
    required this.deviceDefId,
    required this.deviceDefName,
    required this.activityId,
    required this.activityName,
    required this.detectionDate,
    this.problemDescription = '',
    this.problemPhotoUrls = const [],
    this.level = AttentionLevel.B,
    this.status = CorrectiveStatus.PENDING,
    this.reportedTo,
    this.estimatedCorrectionDate,
    this.correctionAction = '',
    this.correctionPhotoUrls = const [],
    this.actualCorrectionDate,
    this.correctedByUserId,
    this.correctedByName,
    this.observations = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Clave única para evitar duplicados
  String get uniqueKey => '${reportDateStr}_${deviceInstanceId}_$activityId';

  /// Ahora retorna true para ambos estados de corregido
  bool get isCorrected =>
      status == CorrectiveStatus.CORRECTED_BY_ICISI ||
      status == CorrectiveStatus.CORRECTED_BY_THIRD;

  String get levelLabel {
    switch (level) {
      case AttentionLevel.A: return 'A - Daño potencial para el equipo';
      case AttentionLevel.B: return 'B - Riesgo de daño moderado';
      case AttentionLevel.C: return 'C - Detalle de prevención';
    }
  }

  String get statusLabel {
    switch (status) {
      case CorrectiveStatus.PENDING:            return 'Pendiente';
      case CorrectiveStatus.IN_PROGRESS:        return 'En Proceso';
      case CorrectiveStatus.CORRECTED_BY_ICISI: return 'Corregido por ICISI';
      case CorrectiveStatus.CORRECTED_BY_THIRD: return 'Corregido por Terceros';
    }
  }

  CorrectiveItemModel copyWith({
    String? id,
    String? policyId,
    String? reportId,
    String? reportDateStr,
    String? deviceInstanceId,
    String? deviceCustomId,
    String? deviceArea,
    String? deviceDefId,
    String? deviceDefName,
    String? activityId,
    String? activityName,
    DateTime? detectionDate,
    String? problemDescription,
    List<String>? problemPhotoUrls,
    AttentionLevel? level,
    CorrectiveStatus? status,
    String? reportedTo,
    DateTime? estimatedCorrectionDate,
    String? correctionAction,
    List<String>? correctionPhotoUrls,
    DateTime? actualCorrectionDate,
    String? correctedByUserId,
    String? correctedByName,
    String? observations,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearEstimatedDate = false,
    bool clearActualDate = false,
    bool clearReportedTo = false,
  }) {
    return CorrectiveItemModel(
      id: id ?? this.id,
      policyId: policyId ?? this.policyId,
      reportId: reportId ?? this.reportId,
      reportDateStr: reportDateStr ?? this.reportDateStr,
      deviceInstanceId: deviceInstanceId ?? this.deviceInstanceId,
      deviceCustomId: deviceCustomId ?? this.deviceCustomId,
      deviceArea: deviceArea ?? this.deviceArea,
      deviceDefId: deviceDefId ?? this.deviceDefId,
      deviceDefName: deviceDefName ?? this.deviceDefName,
      activityId: activityId ?? this.activityId,
      activityName: activityName ?? this.activityName,
      detectionDate: detectionDate ?? this.detectionDate,
      problemDescription: problemDescription ?? this.problemDescription,
      problemPhotoUrls: problemPhotoUrls ?? this.problemPhotoUrls,
      level: level ?? this.level,
      status: status ?? this.status,
      reportedTo: clearReportedTo ? null : (reportedTo ?? this.reportedTo),
      estimatedCorrectionDate: clearEstimatedDate
          ? null
          : (estimatedCorrectionDate ?? this.estimatedCorrectionDate),
      correctionAction: correctionAction ?? this.correctionAction,
      correctionPhotoUrls: correctionPhotoUrls ?? this.correctionPhotoUrls,
      actualCorrectionDate: clearActualDate
          ? null
          : (actualCorrectionDate ?? this.actualCorrectionDate),
      correctedByUserId: correctedByUserId ?? this.correctedByUserId,
      correctedByName: correctedByName ?? this.correctedByName,
      observations: observations ?? this.observations,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'policyId': policyId,
      'reportId': reportId,
      'reportDateStr': reportDateStr,
      'deviceInstanceId': deviceInstanceId,
      'deviceCustomId': deviceCustomId,
      'deviceArea': deviceArea,
      'deviceDefId': deviceDefId,
      'deviceDefName': deviceDefName,
      'activityId': activityId,
      'activityName': activityName,
      'detectionDate': Timestamp.fromDate(detectionDate),
      'problemDescription': problemDescription,
      'problemPhotoUrls': problemPhotoUrls,
      'level': level.name,
      'status': status.name,
      'reportedTo': reportedTo,
      'estimatedCorrectionDate': estimatedCorrectionDate != null
          ? Timestamp.fromDate(estimatedCorrectionDate!)
          : null,
      'correctionAction': correctionAction,
      'correctionPhotoUrls': correctionPhotoUrls,
      'actualCorrectionDate': actualCorrectionDate != null
          ? Timestamp.fromDate(actualCorrectionDate!)
          : null,
      'correctedByUserId': correctedByUserId,
      'correctedByName': correctedByName,
      'observations': observations,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'uniqueKey': uniqueKey,
    };
  }

  factory CorrectiveItemModel.fromMap(Map<String, dynamic> map) {
    return CorrectiveItemModel(
      id: map['id'] ?? '',
      policyId: map['policyId'] ?? '',
      reportId: map['reportId'] ?? '',
      reportDateStr: map['reportDateStr'] ?? '',
      deviceInstanceId: map['deviceInstanceId'] ?? '',
      deviceCustomId: map['deviceCustomId'] ?? '',
      deviceArea: map['deviceArea'] ?? '',
      deviceDefId: map['deviceDefId'] ?? '',
      deviceDefName: map['deviceDefName'] ?? '',
      activityId: map['activityId'] ?? '',
      activityName: map['activityName'] ?? '',
      detectionDate: map['detectionDate'] != null
          ? (map['detectionDate'] as Timestamp).toDate()
          : DateTime.now(),
      problemDescription: map['problemDescription'] ?? '',
      problemPhotoUrls: List<String>.from(map['problemPhotoUrls'] ?? []),
      level: AttentionLevel.values.firstWhere(
        (e) => e.name == (map['level'] ?? 'B'),
        orElse: () => AttentionLevel.B,
      ),
      status: _parseStatus(map['status']),
      reportedTo: map['reportedTo'],
      estimatedCorrectionDate: map['estimatedCorrectionDate'] != null
          ? (map['estimatedCorrectionDate'] as Timestamp).toDate()
          : null,
      correctionAction: map['correctionAction'] ?? '',
      correctionPhotoUrls: List<String>.from(map['correctionPhotoUrls'] ?? []),
      actualCorrectionDate: map['actualCorrectionDate'] != null
          ? (map['actualCorrectionDate'] as Timestamp).toDate()
          : null,
      correctedByUserId: map['correctedByUserId'],
      correctedByName: map['correctedByName'],
      observations: map['observations'] ?? '',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Migración segura: convierte valores viejos de Firestore al nuevo enum
  static CorrectiveStatus _parseStatus(dynamic raw) {
    switch (raw) {
      case 'CORRECTED_BY_ICISI': return CorrectiveStatus.CORRECTED_BY_ICISI;
      case 'CORRECTED_BY_THIRD': return CorrectiveStatus.CORRECTED_BY_THIRD;
      case 'IN_PROGRESS':        return CorrectiveStatus.IN_PROGRESS;
      // Valores viejos → mapear al más cercano
      case 'CORRECTED':          return CorrectiveStatus.CORRECTED_BY_ICISI;
      case 'REPORTED':           return CorrectiveStatus.IN_PROGRESS;
      case 'PENDING':
      default:                   return CorrectiveStatus.PENDING;
    }
  }
}