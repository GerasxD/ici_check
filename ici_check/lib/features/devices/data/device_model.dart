// ENUMS
enum ActivityType { 
  MANTENIMIENTO,
  INSPECCION,
  PRUEBA,
}

enum Frequency { 
  DIARIO,
  SEMANAL,
  QUINCENAL, // <--- AGREGADO AQUÍ (Cada 15 días)
  MENSUAL,
  TRIMESTRAL,
  CUATRIMESTRAL, // <--- AGREGADO AQUÍ (4 Meses)
  SEMESTRAL,
  ANUAL,
}

// --- MODELO ACTIVIDAD (Sin cambios necesarios, funciona automático) ---
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
      // Esto convertirá CUATRIMESTRAL a string automáticamente
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
          // Si encuentra 'CUATRIMESTRAL' en la base de datos, lo mapea correctamente aquí
          orElse: () => Frequency.MENSUAL),
      expectedValue: map['expectedValue'] ?? '',
    );
  }
}

// --- MODELO DISPOSITIVO (Sin cambios) ---
class DeviceModel {
  String id;
  String name;
  String description;
  String viewMode;
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