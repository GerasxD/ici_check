import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ici_check/features/auth/presentation/main_layout_screen.dart';
import 'firebase_options.dart'; // Generado por flutterfire configure

// Importamos la pantalla de login que creamos en el paso anterior
import 'features/auth/presentation/login_screen.dart';

void main() async {
  // 1. Aseguramos que el motor de Flutter esté listo antes de llamar código nativo
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inicializamos Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistema de Inspecciones', // Nombre de tu App
      debugShowCheckedModeBanner: false, // Quitamos la etiqueta "Debug"

      // 3. Tema Global (Basado en tu CSS de React: Slate y Blue-600)
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB), // blue-600
          background: const Color(0xFFF8FAFC), // slate-50 background
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF1E293B)), // slate-800
          titleTextStyle: TextStyle(
            color: Color(0xFF1E293B), // slate-800
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // 4. Rutas Nombradas
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const MainLayoutScreen(), // Placeholder temporal
      },

      // 5. AuthWrapper: Decide qué pantalla mostrar al inicio
      home: const AuthWrapper(),
    );
  }
}

/// ---------------------------------------------------------------------
/// WIDGET ESPECIAL: AUTH WRAPPER
/// Escucha los cambios en la autenticación de Firebase en tiempo real.
/// ---------------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Si está cargando la conexión...
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Si hay datos (snapshot.hasData), el usuario está logueado -> Dashboard
        if (snapshot.hasData) {
          return const MainLayoutScreen(); 
        }

        // Si no hay datos, no está logueado -> Login
        return const LoginScreen();
      },
    );
  }
}


class DashboardPlaceholder extends StatelessWidget {
  const DashboardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // El AuthWrapper detectará el cambio y nos mandará al Login automáticamente
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('Bienvenido al Sistema de Inspecciones'),
      ),
    );
  }
}