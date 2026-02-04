// ENUMS (Tal cual tu código React)
enum ActivityType { 
  MANTENIMIENTO,      // MAINTENANCE
  INSPECCION,         // INSPECTION
  PRUEBA,           // REPLACEMENT
}

enum Frequency { 
  DIARIO,            // DAILY
  SEMANAL,           // WEEKLY
  MENSUAL,           // MONTHLY
  TRIMESTRAL,        // QUARTERLY
  SEMESTRAL,         // BIANNUAL
  ANUAL,              // ANNUAL
}

// --- MODELO ACTIVIDAD (Hija) ---
class ActivityConfig {
  String id;
  String name;
  ActivityType type;
  Frequency frequency;
  String expectedValue;

  ActivityConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.frequency,
    this.expectedValue = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.toString().split('.').last,
      'frequency': frequency.toString().split('.').last,
      'expectedValue': expectedValue,
    };
  }

  factory ActivityConfig.fromMap(Map<String, dynamic> map) {
    return ActivityConfig(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: ActivityType.values.firstWhere(
          (e) => e.toString().split('.').last == map['type'],
          orElse: () => ActivityType.MANTENIMIENTO),
      frequency: Frequency.values.firstWhere(
          (e) => e.toString().split('.').last == map['frequency'],
          orElse: () => Frequency.MENSUAL),
      expectedValue: map['expectedValue'] ?? '',
    );
  }
}

// --- MODELO DISPOSITIVO (Padre) ---
class DeviceModel {
  String id;
  String name;
  String description;
  String viewMode; // 'table' or 'list'
  List<ActivityConfig> activities;

  DeviceModel({
    required this.id,
    required this.name,
    required this.description,
    this.viewMode = 'table',
    required this.activities,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'viewMode': viewMode,
      // Convertimos la lista de objetos a lista de Mapas para Firebase
      'activities': activities.map((x) => x.toMap()).toList(),
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map, String docId) {
    return DeviceModel(
      id: docId,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      viewMode: map['viewMode'] ?? 'table',
      activities: List<ActivityConfig>.from(
        (map['activities'] ?? []).map((x) => ActivityConfig.fromMap(x)),
      ),
    );
  }
}