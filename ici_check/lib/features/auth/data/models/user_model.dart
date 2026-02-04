enum UserRole {
  TECHNICIAN,
  ADMIN,
  SUPER_USER,
}

class UserModel {
  final String id;
  final String name;
  final String email;
  final UserRole role;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.role = UserRole.TECHNICIAN,
  });

  // Convertir de Map (Firestore) a Objeto Dart
  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      id: docId,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == (map['role'] ?? 'TECHNICIAN'),
        orElse: () => UserRole.TECHNICIAN,
      ),
    );
  }

  // Convertir de Objeto Dart a Map (para guardar en Firestore)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role.toString().split('.').last, // Guarda "TECHNICIAN" como string
    };
  }
}