import 'package:cloud_firestore/cloud_firestore.dart';

class PolicyDevice {
  String instanceId;
  String definitionId;
  int quantity;
  Map<String, int> scheduleOffsets;

  PolicyDevice({
    required this.instanceId,
    required this.definitionId,
    required this.quantity,
    Map<String, int>? scheduleOffsets,
  }) : scheduleOffsets = scheduleOffsets ?? {};

  Map<String, dynamic> toMap() => {
    'instanceId': instanceId,
    'definitionId': definitionId,
    'quantity': quantity,
    // Cast explícito para Flutter Web
    'scheduleOffsets': Map<String, dynamic>.from(
      scheduleOffsets.map((k, v) => MapEntry(k, v)),
    ),
  };

  factory PolicyDevice.fromMap(Map<String, dynamic> map) {
    return PolicyDevice(
      instanceId: map['instanceId'] as String? ?? '',
      definitionId: map['definitionId'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 1,
      scheduleOffsets: Map<String, int>.from(
        (map['scheduleOffsets'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      ),
    );
  }
}

class PolicyModel {
  String id;
  String clientId;
  DateTime startDate;
  int durationMonths;
  bool includeWeekly;
  List<String> assignedUserIds;
  List<PolicyDevice> devices;
  bool isLocked;

  PolicyModel({
    required this.id,
    required this.clientId,
    required this.startDate,
    this.durationMonths = 12,
    this.includeWeekly = false,
    this.assignedUserIds = const [],
    this.devices = const [],
    this.isLocked = false,
  });

  DateTime get endDate {
    return DateTime(startDate.year, startDate.month + durationMonths, startDate.day)
        .subtract(const Duration(days: 1));
  }

  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'startDate': Timestamp.fromDate(startDate),
      'durationMonths': durationMonths,
      'includeWeekly': includeWeekly,
      // Cast explícito de listas para Flutter Web
      'assignedUserIds': List<String>.from(assignedUserIds),
      'isLocked': isLocked,
      'devices': List<Map<String, dynamic>>.from(
        devices.map((d) => d.toMap()),
      ),
    };
  }

  factory PolicyModel.fromMap(Map<String, dynamic> map, String docId) {
    return PolicyModel(
      id: docId,
      clientId: map['clientId'] as String? ?? '',
      startDate: (map['startDate'] as Timestamp).toDate(),
      durationMonths: map['durationMonths'] as int? ?? 12,
      includeWeekly: map['includeWeekly'] as bool? ?? false,
      isLocked: map['isLocked'] as bool? ?? false,
      assignedUserIds: List<String>.from(map['assignedUserIds'] ?? []),
      devices: List<PolicyDevice>.from(
        (map['devices'] as List<dynamic>? ?? [])
            .map((x) => PolicyDevice.fromMap(x as Map<String, dynamic>)),
      ),
    );
  }
}