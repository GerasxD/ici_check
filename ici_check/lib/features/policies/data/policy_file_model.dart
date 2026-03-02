import 'package:cloud_firestore/cloud_firestore.dart';

class PolicyFileModel {
  String id;
  String name;
  String url;           // URL de Firebase Storage
  String folder;        // Carpeta virtual ('' = raíz)
  String contentType;   // 'application/pdf', 'image/jpeg', etc.
  int sizeBytes;
  String uploadedBy;    // userId
  String uploadedByName;
  DateTime createdAt;

  PolicyFileModel({
    required this.id,
    required this.name,
    required this.url,
    this.folder = '',
    this.contentType = '',
    this.sizeBytes = 0,
    this.uploadedBy = '',
    this.uploadedByName = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'folder': folder,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'uploadedBy': uploadedBy,
        'uploadedByName': uploadedByName,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory PolicyFileModel.fromMap(Map<String, dynamic> map, String docId) {
    return PolicyFileModel(
      id: docId,
      name: map['name'] as String? ?? '',
      url: map['url'] as String? ?? '',
      folder: map['folder'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      sizeBytes: map['sizeBytes'] as int? ?? 0,
      uploadedBy: map['uploadedBy'] as String? ?? '',
      uploadedByName: map['uploadedByName'] as String? ?? '',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}