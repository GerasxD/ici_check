import 'package:flutter/material.dart';
import '../../auth/data/models/user_model.dart';

class UserFormDialog extends StatefulWidget {
  final UserModel? userToEdit;
  final Function(UserModel user, String? password) onSave;

  const UserFormDialog({super.key, this.userToEdit, required this.onSave});

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();
  
  UserRole _selectedRole = UserRole.TECHNICIAN;
  bool _isPasswordVisible = false;

  // Colores corporativos
  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _accentBlue = const Color(0xFF1E40AF);
  final Color _slateText = const Color(0xFF64748B);
  final Color _inputBg = const Color(0xFFF8FAFC); // Slate 50

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userToEdit?.name ?? '');
    _emailController = TextEditingController(text: widget.userToEdit?.email ?? '');
    _selectedRole = widget.userToEdit?.role ?? UserRole.TECHNICIAN;
  }

  @override
  Widget build(BuildContext context) {
    bool isEditing = widget.userToEdit != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 10,
      child: Container(
        // Limitamos el ancho para que en Web/Tablet no se vea gigante
        constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- 1. HEADER MODERNO ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: _primaryDark,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isEditing ? Icons.edit_outlined : Icons.person_add_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        isEditing ? 'Editar Perfil' : 'Nuevo Colaborador',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
              ),

              // --- 2. FORMULARIO ---
              Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // NOMBRE
                      _buildLabel('Nombre Completo'),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: _primaryDark, fontWeight: FontWeight.w500),
                        decoration: _modernInputDecoration('Ej. Juan Pérez', Icons.person_outline),
                        validator: (v) => v!.isEmpty ? 'El nombre es requerido' : null,
                      ),
                      const SizedBox(height: 20),
                      
                      // EMAIL
                      _buildLabel('Correo Corporativo'),
                      TextFormField(
                        controller: _emailController,
                        enabled: !isEditing,
                        style: TextStyle(color: isEditing ? Colors.grey : _primaryDark),
                        decoration: _modernInputDecoration('ejemplo@icicheck.com', Icons.email_outlined),
                        validator: (v) => !v!.contains('@') ? 'Ingresa un correo válido' : null,
                      ),
                      
                      // PASSWORD (SOLO SI ES NUEVO)
                      if (!isEditing) ...[
                        const SizedBox(height: 20),
                        _buildLabel('Contraseña Temporal'),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          style: TextStyle(color: _primaryDark),
                          decoration: _modernInputDecoration('Mínimo 6 caracteres', Icons.lock_outline).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                color: _slateText,
                              ),
                              onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                            ),
                          ),
                          validator: (v) {
                            if (!isEditing && (v == null || v.length < 6)) {
                              return 'La contraseña es muy corta';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 20),
                      
                      // ROL
                      _buildLabel('Rol y Permisos'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _inputBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.transparent),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<UserRole>(
                            value: _selectedRole,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.shield_outlined, color: Color(0xFF64748B)),
                            ),
                            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
                            dropdownColor: Colors.white,
                            items: UserRole.values.map((role) {
                              return DropdownMenuItem(
                                value: role,
                                child: Text(
                                  role.toString().split('.').last,
                                  style: TextStyle(color: _primaryDark, fontWeight: FontWeight.w500),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedRole = val!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // --- 3. FOOTER BOTONES ---
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Cancelar', style: TextStyle(color: _slateText)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            final newUser = UserModel(
                              id: widget.userToEdit?.id ?? '',
                              name: _nameController.text.trim(),
                              email: _emailController.text.trim(),
                              role: _selectedRole,
                            );
                            widget.onSave(newUser, _passwordController.text.trim());
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(isEditing ? 'Guardar Cambios' : 'Crear Usuario'),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER: Estilo de Inputs ---
  InputDecoration _modernInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIcon: Icon(icon, color: _slateText, size: 22),
      filled: true,
      fillColor: _inputBg,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _accentBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade100, width: 1),
      ),
    );
  }

  // --- HELPER: Etiquetas de Texto ---
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: _slateText,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}