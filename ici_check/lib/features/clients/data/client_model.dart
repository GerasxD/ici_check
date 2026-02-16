class ClientModel {
  String id;
  String name;
  String razonSocial; // ← NUEVO CAMPO
  String nombreContacto; // ← NUEVO CAMPO
  String address;
  String contact;
  String email;
  String logoUrl;

  ClientModel({
    required this.id,
    required this.name,
    this.razonSocial = '', // ← NUEVO
    this.nombreContacto = '', // ← NUEVO
    this.address = '',
    this.contact = '',
    this.email = '',
    this.logoUrl = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'razonSocial': razonSocial, // ← NUEVO
      'nombreContacto': nombreContacto, // ← NUEVO
      'address': address,
      'contact': contact,
      'email': email,
      'logoUrl': logoUrl,
    };
  }

  factory ClientModel.fromMap(Map<String, dynamic> map, String docId) {
    return ClientModel(
      id: docId,
      name: map['name'] ?? '',
      razonSocial: map['razonSocial'] ?? '', // ← NUEVO
      nombreContacto: map['nombreContacto'] ?? '', // ← NUEVO
      address: map['address'] ?? '',
      contact: map['contact'] ?? '',
      email: map['email'] ?? '',
      logoUrl: map['logoUrl'] ?? '',
    );
  }
}