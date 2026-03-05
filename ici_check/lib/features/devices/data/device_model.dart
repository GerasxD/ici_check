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

enum ActivityInputType {
  toggle,  // OK / NOK / NA / NR  (comportamiento actual)
  value,   // Texto libre / número medido (RPM, voltaje, etc.)
}

// --- MODELO ACTIVIDAD (Sin cambios necesarios, funciona automático) ---
class ActivityConfig {
  String id;
  String name;
  ActivityType type;
  Frequency frequency;
  String expectedValue;
  ActivityInputType inputType; // ★ NUEVO

  ActivityConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.frequency,
    this.expectedValue = '',
    this.inputType = ActivityInputType.toggle,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      // Esto convertirá CUATRIMESTRAL a string automáticamente
      'type': type.toString().split('.').last,
      'frequency': frequency.toString().split('.').last,
      'expectedValue': expectedValue,
      'inputType': inputType.toString().split('.').last, // ★ NUEVO
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
      inputType: ActivityInputType.values.firstWhere(
          (e) => e.toString().split('.').last == (map['inputType'] ?? 'toggle'),
          orElse: () => ActivityInputType.toggle),
    );
  }
}

// --- MODELO DISPOSITIVO (Sin cambios) ---
class DeviceModel {
  String id;
  String name;
  String description;
  String viewMode;
  bool isCumulative;    
  List<ActivityConfig> activities;

  DeviceModel({
    required this.id,
    required this.name,
    required this.description,
    this.viewMode = 'table',
    this.isCumulative = false,
    required this.activities,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'viewMode': viewMode,
      'isCumulative': isCumulative,
      'activities': activities.map((x) => x.toMap()).toList(),
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map, String docId) {
    return DeviceModel(
      id: docId,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      viewMode: map['viewMode'] ?? 'table',
      isCumulative: map['isCumulative'] ?? false,
      activities: List<ActivityConfig>.from(
        (map['activities'] ?? []).map((x) => ActivityConfig.fromMap(x)),
      ),
    );
  }
}