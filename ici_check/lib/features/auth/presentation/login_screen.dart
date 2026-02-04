import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para controlar la barra de estado del celular
import '../data/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // --- PALETA DE COLORES ICI-CHECK (PROFESIONAL) ---
  // Azul Marino Profundo (Base)
  final Color _primaryDark = const Color(0xFF0F172A); 
  // Azul Corporativo Intenso (Acentos/Botones)
  final Color _accentBlue = const Color(0xFF1E40AF); 
  // Gris suave para fondos
  final Color _bgGrey = const Color(0xFFF1F5F9); 
  // Texto secundario
  final Color _textSlate = const Color(0xFF64748B); 

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final user = await _authService.login(
        _emailController.text.trim(), 
        _passwordController.text.trim()
      );

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard'); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bienvenido a ICI-CHECK, ${user?.name}'),
            backgroundColor: _primaryDark,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(e.toString().replaceAll('Exception:', ''))),
              ],
            ),
            backgroundColor: Colors.red[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hacemos que la barra de estado (donde está la batería) se vea acorde al diseño
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    return Scaffold(
      backgroundColor: _bgGrey,
      body: Stack(
        children: [
          // 1. FONDO SUPERIOR (HEADER)
          // Ocupa el 45% superior de la pantalla con el color oscuro
          Container(
            height: MediaQuery.of(context).size.height * 0.45,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _primaryDark,
              // Un gradiente sutil para darle profundidad
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0F172A), // Slate 900
                  const Color(0xFF1E3A8A), // Blue 900
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1), // Translucido
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined, // Icono de seguridad/check
                    size: 64,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                // Nombre de la App
                const Text(
                  'ICI-CHECK',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900, // Extra Bold
                    color: Colors.white,
                    letterSpacing: 2.0, // Espaciado elegante
                    fontFamily: 'Roboto', // O la fuente que prefieras
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sistema Integral de Inspecciones',
                  style: TextStyle(
                    color: Colors.blue[100],
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                // Espacio extra para que la tarjeta no tape el texto
                const SizedBox(height: 40), 
              ],
            ),
          ),

          // 2. TARJETA DE LOGIN (Flotante)
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  // Espacio invisible para empujar la tarjeta hacia abajo y ver el logo
                  SizedBox(height: MediaQuery.of(context).size.height * 0.35),
                  
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _primaryDark.withOpacity(0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Iniciar Sesión',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _primaryDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ingresa tus credenciales para acceder al panel.',
                            style: TextStyle(color: _textSlate, fontSize: 14),
                          ),
                          const SizedBox(height: 32),

                          // INPUT EMAIL
                          _buildLabel('Correo Corporativo'),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: _primaryDark, fontWeight: FontWeight.w500),
                            decoration: _modernInputDecoration(Icons.email_outlined),
                            validator: (value) => 
                                (value == null || !value.contains('@')) ? 'Correo inválido' : null,
                          ),
                          const SizedBox(height: 24),

                          // INPUT PASSWORD
                          _buildLabel('Contraseña'),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            style: TextStyle(color: _primaryDark, fontWeight: FontWeight.w500),
                            decoration: _modernInputDecoration(Icons.lock_outline).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  color: _textSlate,
                                ),
                                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                              ),
                            ),
                            validator: (value) => 
                                (value == null || value.length < 6) ? 'Mínimo 6 caracteres' : null,
                          ),
                          
                          const SizedBox(height: 32),

                          // BOTÓN GRANDE
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentBlue, // Azul más vivo para el botón
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24, width: 24,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                    )
                                  : const Text(
                                      'ACCEDER',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'ICI-CHECK v1.0.2',
                    style: TextStyle(color: _textSlate.withOpacity(0.5), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper para etiquetas de texto pequeñas arriba de los inputs
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: _textSlate,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Helper para el estilo de los inputs
  InputDecoration _modernInputDecoration(IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: _textSlate),
      filled: true,
      fillColor: const Color(0xFFF8FAFC), // Fondo muy sutil dentro del input
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accentBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade200),
      ),
    );
  }
}