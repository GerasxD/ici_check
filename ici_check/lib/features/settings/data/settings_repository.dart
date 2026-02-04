import 'package:cloud_firestore/cloud_firestore.dart';
import 'company_settings_model.dart';

class SettingsRepository {
  final DocumentReference _docRef = 
      FirebaseFirestore.instance.collection('settings').doc('company_profile');

  // Obtener configuración (Future, no Stream, porque se carga una vez al entrar)
  Future<CompanySettingsModel> getSettings() async {
    final doc = await _docRef.get();
    if (doc.exists) {
      return CompanySettingsModel.fromMap(doc.data() as Map<String, dynamic>);
    }
    return CompanySettingsModel(); // Retorna vacío si no existe aún
  }

  // Guardar configuración
  Future<void> saveSettings(CompanySettingsModel settings) async {
    await _docRef.set(settings.toMap(), SetOptions(merge: true));
  }
}