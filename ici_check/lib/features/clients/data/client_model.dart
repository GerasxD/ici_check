class ClientModel {
  String id;
  String name;
  String address;
  String contact;
  String email;
  String logoUrl; // URL de la imagen en Storage o Base64

  ClientModel({
    required this.id,
    required this.name,
    this.address = '',
    this.contact = '',
    this.email = '',
    this.logoUrl = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
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
      address: map['address'] ?? '',
      contact: map['contact'] ?? '',
      email: map['email'] ?? '',
      logoUrl: map['logoUrl'] ?? '',
    );
  }
}