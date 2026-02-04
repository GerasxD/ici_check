import 'dart:convert'; // Para Base64 del logo
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ici_check/features/settings/data/company_settings_model.dart';
import 'package:ici_check/features/settings/data/settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsRepository _repo = SettingsRepository();
  final ImagePicker _picker = ImagePicker();

  // Estado
  late CompanySettingsModel _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controladores
  final _nameCtrl = TextEditingController();
  final _legalNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // Colores Corporativos
  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _accentBlue = const Color(0xFF2563EB);
  final Color _bgLight = const Color(0xFFF1F5F9);
  final Color _textSlate = const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Cargar datos al iniciar
  Future<void> _loadSettings() async {
    try {
      final data = await _repo.getSettings();
      setState(() {
        _settings = data;
        _nameCtrl.text = data.name;
        _legalNameCtrl.text = data.legalName;
        _addressCtrl.text = data.address;
        _phoneCtrl.text = data.phone;
        _emailCtrl.text = data.email;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  // Guardar datos
  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      // Actualizamos el objeto local
      _settings.name = _nameCtrl.text.trim();
      _settings.legalName = _legalNameCtrl.text.trim();
      _settings.address = _addressCtrl.text.trim();
      _settings.phone = _phoneCtrl.text.trim();
      _settings.email = _emailCtrl.text.trim();
      // Nota: _settings.logoUrl ya se actualizó en _handleLogoUpload si hubo cambios

      await _repo.saveSettings(_settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Configuración actualizada correctamente'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al guardar cambios'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Lógica de subir logo (Base64 para simplicidad y rapidez)
  Future<void> _handleLogoUpload() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500, // Optimizamos tamaño
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final String base64Image = base64Encode(bytes);
        
        setState(() {
          _settings.logoUrl = base64Image;
        });
      }
    } catch (e) {
      debugPrint('Error imagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // --- HEADER SUPERIOR ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuración',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _primaryDark, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Personaliza los datos de la empresa para los reportes',
                        style: TextStyle(color: _textSlate, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _handleSave,
                  icon: _isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 20),
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              ],
            ),
            
            const SizedBox(height: 32),

            // --- CONTENEDOR PRINCIPAL (CARD) ---
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))
                ],
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título de Sección
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.business, color: _accentBlue, size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Perfil de la Organización', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _primaryDark)),
                              Text('Esta información aparecerá en el encabezado de tus PDF', style: TextStyle(fontSize: 12, color: _textSlate)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Layout del Formulario (Responsivo)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        bool isDesktop = constraints.maxWidth > 900;

                        // 1. Panel de Inputs (Izquierda en Desktop, Arriba en Móvil)
                        Widget inputsPanel = Column(
                          children: [
                            _buildSectionTitle('Datos Generales'),
                            const SizedBox(height: 16),
                            _ModernInput(label: 'Nombre Comercial (Siglas)', controller: _nameCtrl, hint: 'Ej. ICISI', icon: Icons.storefront),
                            const SizedBox(height: 16),
                            _ModernInput(label: 'Razón Social', controller: _legalNameCtrl, hint: 'Nombre legal completo', icon: Icons.gavel),
                            const SizedBox(height: 16),
                            _ModernInput(label: 'Dirección Fiscal', controller: _addressCtrl, hint: 'Calle, Número, Colonia...', icon: Icons.place_outlined, maxLines: 3),
                            
                            const SizedBox(height: 32),
                            _buildSectionTitle('Información de Contacto'),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: _ModernInput(label: 'Teléfono', controller: _phoneCtrl, hint: '(000) 000-0000', icon: Icons.phone_outlined)),
                                const SizedBox(width: 16),
                                Expanded(child: _ModernInput(label: 'Correo Electrónico', controller: _emailCtrl, hint: 'contacto@empresa.com', icon: Icons.email_outlined)),
                              ],
                            )
                          ],
                        );

                        // 2. Panel de Logo (Derecha en Desktop, Abajo en Móvil)
                        Widget logoPanel = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Identidad Visual'),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: _handleLogoUpload,
                              child: Container(
                                height: 280,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Imagen (si existe)
                                    if (_settings.logoUrl.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: _settings.logoUrl.startsWith('http')
                                          ? Image.network(_settings.logoUrl, fit: BoxFit.contain)
                                          : Image.memory(base64Decode(_settings.logoUrl), fit: BoxFit.contain),
                                      ),
                                    
                                    // Placeholder (si no existe) o Overlay Hover
                                    if (_settings.logoUrl.isEmpty)
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
                                            child: Icon(Icons.cloud_upload_rounded, size: 32, color: _accentBlue),
                                          ),
                                          const SizedBox(height: 16),
                                          Text('Subir Logotipo', style: TextStyle(fontWeight: FontWeight.bold, color: _primaryDark)),
                                          const SizedBox(height: 4),
                                          Text('PNG o JPG (Max 500KB)', style: TextStyle(fontSize: 12, color: _textSlate)),
                                        ],
                                      ),
                                      
                                    // Botón flotante de "Cambiar" si ya hay imagen
                                    if (_settings.logoUrl.isNotEmpty)
                                      Positioned(
                                        bottom: 16,
                                        right: 16,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.9),
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(Icons.edit, size: 14, color: Colors.black87),
                                              SizedBox(width: 6),
                                              Text('Cambiar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      )
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: _accentBlue),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('Recomendamos usar una imagen con fondo transparente para mejores resultados en los reportes.', style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.4))),
                                ],
                              ),
                            )
                          ],
                        );

                        // Layout Lógico
                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: inputsPanel),
                              const SizedBox(width: 40),
                              Container(width: 1, height: 400, color: Colors.grey.shade200), // Línea divisora
                              const SizedBox(width: 40),
                              Expanded(flex: 2, child: logoPanel),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              inputsPanel,
                              const SizedBox(height: 40),
                              const Divider(),
                              const SizedBox(height: 40),
                              logoPanel,
                            ],
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // Espacio final para scroll en móvil
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildSectionTitle(String title) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _textSlate,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ModernInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;

  const _ModernInput({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(icon, size: 20, color: Colors.grey.shade400),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 40),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
            ),
          ),
        ),
      ],
    );
  }
}