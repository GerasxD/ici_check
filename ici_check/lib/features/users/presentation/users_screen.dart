import 'package:flutter/material.dart';
import 'package:ici_check/features/auth/data/users_repository.dart';
import 'package:ici_check/features/users/presentation/user_from_dialog.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/data/auth_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final UsersRepository _repo = UsersRepository();
  final AuthService _authService = AuthService();

  // Colores corporativos
  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _slateText = const Color(0xFF64748B);

  // --- LÓGICA DE GUARDADO ---
  void _handleSaveUser(UserModel user, String? password) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Procesando...'), duration: Duration(seconds: 1)),
      );

      if (user.id.isEmpty && password != null) {
        String newUid = await _authService.createUserInAuth(user.email, password);
        final newUserWithId = UserModel(
          id: newUid,
          name: user.name,
          email: user.email,
          role: user.role,
        );
        await _repo.saveUser(newUserWithId);
        if (mounted) _showSuccess('Usuario creado exitosamente');
      } else {
        await _repo.saveUser(user);
        if (mounted) _showSuccess('Usuario actualizado');
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  void _sendResetEmail(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      if (mounted) _showSuccess('Correo de recuperación enviado a $email');
    } catch (e) {
      if (mounted) _showError('Error al enviar correo: $e');
    }
  }

  void _deleteUser(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar Usuario?'),
        content: Text('Se eliminará el acceso para ${user.name}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              _repo.deleteUser(user.id);
              Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showUserModal({UserModel? user}) {
    showDialog(
      context: context,
      builder: (context) => UserFormDialog(
        userToEdit: user,
        onSave: _handleSaveUser,
      ),
    );
  }

  // Helpers de UI
  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700, behavior: SnackBarBehavior.floating),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50 background
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserModal(),
        backgroundColor: const Color(0xFF1E40AF),
        elevation: 4,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Nuevo Usuario', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // --- 1. HEADER MODERNO ---
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Directorio de Usuarios',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _primaryDark, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gestiona accesos y roles del sistema',
                          style: TextStyle(color: _slateText, fontSize: 14),
                        ),
                      ],
                    ),
                    // Icono decorativo de fondo
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.people_alt_outlined, color: Colors.blue.shade700, size: 28),
                    )
                  ],
                ),
                const SizedBox(height: 20),
                // Barra de Búsqueda (Visual)
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o correo...',
                    prefixIcon: Icon(Icons.search, color: _slateText),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- 2. LISTA DE TARJETAS ---
          Expanded(
            child: StreamBuilder<List<UserModel>>(
              stream: _repo.getUsersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final users = snapshot.data ?? [];

                if (users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No hay usuarios registrados', style: TextStyle(color: _slateText)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _UserProCard(
                      user: user,
                      onEdit: () => _showUserModal(user: user),
                      onDelete: () => _deleteUser(user),
                      onResetPassword: () => _sendResetEmail(user.email),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- COMPONENTE: TARJETA PROFESIONAL ---
class _UserProCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onResetPassword;

  const _UserProCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onResetPassword,
  });

  @override
  Widget build(BuildContext context) {
    // Definir colores según rol
    Color roleColor;
    Color roleBg;
    
    switch (user.role) {
      case UserRole.SUPER_USER:
        roleColor = Colors.purple.shade700;
        roleBg = Colors.purple.shade50;
        break;
      case UserRole.ADMIN:
        roleColor = Colors.blue.shade700;
        roleBg = Colors.blue.shade50;
        break;
      case UserRole.TECHNICIAN:
      // ignore: unreachable_switch_default
      default:
        roleColor = Colors.teal.shade700;
        roleBg = Colors.teal.shade50;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // Parte Superior: Información
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar con iniciales
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: roleColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Nombre y Email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Badge de Rol (Pastilla)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: roleBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: roleColor.withOpacity(0.2)),
                            ),
                            child: Text(
                              user.role.toString().split('.').last,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Línea divisora sutil
          Divider(height: 1, color: Colors.grey.shade100),

          // Parte Inferior: Acciones
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: Icons.lock_reset,
                  label: 'Reset Pass',
                  color: Colors.orange.shade700,
                  onTap: onResetPassword,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Editar',
                  color: Colors.blue.shade700,
                  onTap: onEdit,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Borrar',
                  color: Colors.red.shade700,
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget Helper para botones pequeños
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}