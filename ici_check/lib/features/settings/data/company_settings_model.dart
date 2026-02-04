class CompanySettingsModel {
  String name;      // Nombre Comercial (Siglas)
  String legalName; // Razón Social
  String address;
  String phone;
  String email;
  String logoUrl;   // URL o Base64

  CompanySettingsModel({
    this.name = '',
    this.legalName = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.logoUrl = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'legalName': legalName,
      'address': address,
      'phone': phone,
      'email': email,
      'logoUrl': logoUrl,
    };
  }

  factory CompanySettingsModel.fromMap(Map<String, dynamic> map) {
    return CompanySettingsModel(
      name: map['name'] ?? '',
      legalName: map['legalName'] ?? '',
      address: map['address'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      logoUrl: map['logoUrl'] ?? '',
    );
  }
}