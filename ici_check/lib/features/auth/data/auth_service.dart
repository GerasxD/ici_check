import 'package:firebase_core/firebase_core.dart'; // Necesario para la instancia secundaria
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserModel?> login(String email, String password) async {
    // ... (Tu código de login existente) ...
    UserCredential result = await _auth.signInWithEmailAndPassword(
      email: email, 
      password: password
    );
    DocumentSnapshot doc = await _db.collection('users').doc(result.user!.uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }
    throw Exception("Usuario no encontrado en base de datos.");
  }

  // --- NUEVO: CREAR USUARIO EN AUTH SIN DESLOGUEAR AL ADMIN ---
  Future<String> createUserInAuth(String email, String password) async {
    FirebaseApp? secondaryApp;
    try {
      // 1. Inicializamos una app secundaria temporal
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp',
        options: Firebase.app().options, // Usamos la misma config que la app principal
      );

      // 2. Obtenemos la instancia de Auth de esa app secundaria
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      // 3. Creamos el usuario (Esto no afecta tu sesión actual)
      UserCredential userCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 4. Retornamos el UID generado para usarlo en Firestore
      return userCredential.user!.uid;

    } catch (e) {
      throw e; // Reenviamos el error para mostrarlo en pantalla
    } finally {
      // 5. IMPORTANTE: Borrar la app secundaria para liberar memoria
      await secondaryApp?.delete();
    }
  }

  // --- NUEVO: ENVIAR CORREO DE RECUPERACIÓN ---
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}