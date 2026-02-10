import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/clients/data/clients_repository.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final ClientsRepository _repo = ClientsRepository();
  // ignore: unused_field
  final ImagePicker _picker = ImagePicker();

  String _searchQuery = '';

  // Paleta Profesional
  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _accentBlue = const Color(0xFF2563EB);
  final Color _bgLight = const Color(0xFFF1F5F9);
  final Color _textSlate = const Color(0xFF64748B);

  // --- LÓGICA DEL FORMULARIO ---
  void _showClientModal({ClientModel? client}) {
    showDialog(
      context: context,
      builder: (context) => _ClientFormDialog(
        clientToEdit: client,
        onSave: (newClient, imageBytes, fileName) async { // ← CAMBIADO
          try {
            await _repo.saveClient(
              newClient, 
              newLogoBytes: imageBytes,  // ← CAMBIADO
              fileName: fileName,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Cliente guardado exitosamente'),
                  backgroundColor: Colors.green.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _handleDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Cliente?'),
        content: const Text(
          'Esta acción borrará al cliente y su historial asociado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _repo.deleteClient(id);
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detectamos si es móvil usando el ancho de la pantalla
    bool isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: _bgLight,
      // SOLUCIÓN 1: Botón Flotante en Móvil (Evita overflow en header)
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showClientModal(),
              backgroundColor: _accentBlue,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          // --- HEADER MODERNO ---
          Container(
            padding: const EdgeInsets.all(24),
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
                    // Título (Usamos Expanded para que ocupe el espacio disponible sin empujar)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cartera de Clientes',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: _primaryDark,
                              letterSpacing: -0.5,
                            ),
                            overflow: TextOverflow
                                .ellipsis, // Cortar con ... si es muy largo
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Administra empresas y contactos',
                            style: TextStyle(color: _textSlate, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    // Botón Desktop (Solo visible si NO es móvil)
                    if (!isMobile)
                      ElevatedButton.icon(
                        onPressed: () => _showClientModal(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nuevo Cliente'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // BUSCADOR ESTILIZADO
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, correo o dirección...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: _bgLight,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _accentBlue, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- GRID DE CLIENTES ---
          Expanded(
            child: StreamBuilder<List<ClientModel>>(
              stream: _repo.getClientsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var clients = snapshot.data ?? [];

                if (_searchQuery.isNotEmpty) {
                  clients = clients
                      .where(
                        (c) =>
                            c.name.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ) ||
                            c.email.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ),
                      )
                      .toList();
                }

                if (clients.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No hay clientes registrados'
                              : 'No se encontraron resultados',
                          style: TextStyle(color: _textSlate),
                        ),
                      ],
                    ),
                  );
                }

                // Grid Responsivo
                return LayoutBuilder(
                  builder: (context, constraints) {
                    double width = constraints.maxWidth;
                    // Ajuste de columnas
                    int crossAxisCount = width > 1200
                        ? 3
                        : (width > 800 ? 2 : 1);

                    // SOLUCIÓN 2: Aspect Ratio Dinámico
                    // En móvil (1 columna), damos más altura a la tarjeta para evitar overflow vertical
                    double aspectRatio = width > 800
                        ? 1.6
                        : 1.4; // 1.4 es más alto que 1.6

                    return GridView.builder(
                      // Importante: padding inferior extra para que el FAB no tape el último elemento en móvil
                      padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 24,
                        bottom: isMobile ? 80 : 24,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                        childAspectRatio: aspectRatio,
                      ),
                      itemCount: clients.length,
                      itemBuilder: (context, index) {
                        return _ClientProCard(
                          client: clients[index],
                          onEdit: () =>
                              _showClientModal(client: clients[index]),
                          onDelete: () => _handleDelete(clients[index].id),
                        );
                      },
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

// --- FORMULARIO MODERNO ---
class _ClientFormDialog extends StatefulWidget {
  final ClientModel? clientToEdit;
  final Function(ClientModel, Uint8List?, String?) onSave;
  
  const _ClientFormDialog({this.clientToEdit, required this.onSave});

  @override
  State<_ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<_ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _contactCtrl;
  late TextEditingController _emailCtrl;
  
  // ====== CAMBIADO: Usar Uint8List en lugar de File ======
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isLogoDeleted = false; // <--- AGREGA ESTA VARIABLE
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.clientToEdit?.name ?? '');
    _addressCtrl = TextEditingController(text: widget.clientToEdit?.address ?? '');
    _contactCtrl = TextEditingController(text: widget.clientToEdit?.contact ?? '');
    _emailCtrl = TextEditingController(text: widget.clientToEdit?.email ?? '');
  }

  // ====== CORREGIDO: Seleccionar imagen multiplataforma ======
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes(); // ← Leer como bytes
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = image.name;
          _isLogoDeleted = false; // <--- IMPORTANTE: Si elige nueva, ya no está borrada
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ====== CORREGIDO: Tomar foto multiplataforma ======
  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes(); // ← Leer como bytes
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = image.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al tomar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF2563EB)),
              title: const Text('Elegir de galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2563EB)),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            if (_selectedImageBytes != null || (widget.clientToEdit?.logoUrl.isNotEmpty ?? false))
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar logo'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImageBytes = null;
                    _selectedImageName = null;
                    _isLogoDeleted = true; // <--- AHORA SÍ SABEMOS QUE SE BORRÓ
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isEditing = widget.clientToEdit != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header del Modal
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Editar Cliente' : 'Nuevo Cliente',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEditing ? 'Modificar datos existentes' : 'Registrar nueva empresa',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),

            // Cuerpo del Formulario
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ====== CORREGIDO: Avatar con MemoryImage para Web ======
                      Center(
                        child: GestureDetector(
                          onTap: _showImageOptions,
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.grey.shade200),
                                  image: _selectedImageBytes != null
                                      ? DecorationImage(
                                          image: MemoryImage(_selectedImageBytes!), // ← Usar MemoryImage
                                          fit: BoxFit.cover,
                                        )
                                      : (!_isLogoDeleted && (widget.clientToEdit?.logoUrl.isNotEmpty ?? false))
                                        ? DecorationImage(
                                            image: NetworkImage(widget.clientToEdit!.logoUrl),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                ),
                                child: (_selectedImageBytes == null && 
                                       (widget.clientToEdit?.logoUrl.isEmpty ?? true))
                                    ? const Icon(Icons.business_outlined, size: 40, color: Colors.grey)
                                    : null,
                              ),
                              Positioned(
                                bottom: -4,
                                right: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'Toca para cambiar logo',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 24),

                      _buildProInput('Nombre Empresa', _nameCtrl, Icons.business, required: true),
                      const SizedBox(height: 16),
                      _buildProInput('Dirección Fiscal', _addressCtrl, Icons.place_outlined),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildProInput('Teléfono', _contactCtrl, Icons.phone_outlined),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildProInput('Email', _emailCtrl, Icons.email_outlined),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Botones
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isUploading ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Guardar Datos'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== CORREGIDO: Guardar con bytes ======
  Future<void> _handleSave() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isUploading = true);

      try {
        final newClient = ClientModel(
          id: widget.clientToEdit?.id ?? '',
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          contact: _contactCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          logoUrl: _isLogoDeleted ? '' : (widget.clientToEdit?.logoUrl ?? ''),
        );

        // ← Pasar bytes en lugar de File
        await widget.onSave(newClient, _selectedImageBytes, _selectedImageName);
        
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al guardar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isUploading = false);
        }
      }
    }
  }

  Widget _buildProInput(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          validator: required ? (v) => v!.isEmpty ? 'Requerido' : null : null,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Ingresar $label...',
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// --- TARJETA DE CLIENTE PRO ---
class _ClientProCard extends StatelessWidget {
  final ClientModel client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClientProCard({
    required this.client,
    required this.onEdit,
    required this.onDelete,
  });

  Color _getAvatarColor(String name) {
    final colors = [
      Colors.blue.shade700,
      Colors.teal.shade700,
      Colors.purple.shade700,
      Colors.orange.shade800,
      Colors.indigo.shade700,
      Colors.pink.shade700,
    ];
    return colors[name.length % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = _getAvatarColor(client.name);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Tarjeta: Avatar y Nombre
            Row(
              children: [
                // ====== CORREGIDO: Avatar con mejor manejo de errores ======
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: avatarColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: client.logoUrl.isNotEmpty
                        ? Image.network(
                            client.logoUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                    color: avatarColor,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              // Si falla la carga, mostrar inicial
                              debugPrint('Error cargando logo: $error');
                              return Center(
                                child: Text(
                                  client.name.isNotEmpty
                                      ? client.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: avatarColor,
                                  ),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              client.name.isNotEmpty
                                  ? client.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: avatarColor,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        client.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ACTIVO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Info
            _InfoRowPro(
              Icons.place_outlined,
              client.address.isEmpty ? 'Sin dirección' : client.address,
            ),
            const SizedBox(height: 8),
            _InfoRowPro(
              Icons.email_outlined,
              client.email.isEmpty ? 'Sin email' : client.email,
            ),
            const SizedBox(height: 8),
            _InfoRowPro(
              Icons.phone_outlined,
              client.contact.isEmpty ? 'Sin teléfono' : client.contact,
            ),

            const Spacer(),
            const Divider(),

            // Acciones Rápidas
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                  ),
                ),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRowPro extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRowPro(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
