import 'package:cloud_firestore/cloud_firestore.dart';

class PolicyDevice {
  String instanceId;
  String definitionId;
  int quantity;
  // NUEVO: Mapa para guardar el desplazamiento de cada actividad
  // Key: ID de la actividad, Value: mes/semana de inicio (offset)
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
    'scheduleOffsets': scheduleOffsets, // Se guarda en Firestore
  };

  factory PolicyDevice.fromMap(Map<String, dynamic> map) {
    return PolicyDevice(
      instanceId: map['instanceId'] ?? '',
      definitionId: map['definitionId'] ?? '',
      quantity: map['quantity'] ?? 1,
      // Mapeo seguro del JSON/Map a Map<String, int>
      scheduleOffsets: Map<String, int>.from(map['scheduleOffsets'] ?? {}),
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
  bool isLocked; // NUEVO: Para saber si el cronograma ya fue guardado/bloqueado

  PolicyModel({
    required this.id,
    required this.clientId,
    required this.startDate,
    this.durationMonths = 12,
    this.includeWeekly = false,
    this.assignedUserIds = const [],
    this.devices = const [],
    this.isLocked = false, // Por defecto está abierto a edición
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
      'assignedUserIds': assignedUserIds,
      'isLocked': isLocked,
      'devices': devices.map((d) => d.toMap()).toList(),
    };
  }

  factory PolicyModel.fromMap(Map<String, dynamic> map, String docId) {
    return PolicyModel(
      id: docId,
      clientId: map['clientId'] ?? '',
      startDate: (map['startDate'] as Timestamp).toDate(),
      durationMonths: map['durationMonths'] ?? 12,
      includeWeekly: map['includeWeekly'] ?? false,
      isLocked: map['isLocked'] ?? false,
      assignedUserIds: List<String>.from(map['assignedUserIds'] ?? []),
      devices: List<PolicyDevice>.from(
        (map['devices'] ?? []).map((x) => PolicyDevice.fromMap(x)),
      ),
    );
  }
}