import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Necesario para consultar el rol
import 'package:ici_check/features/clients/presentation/clients_screen.dart';
import 'package:ici_check/features/dashboard/presentation/dashboard_screen.dart';
import 'package:ici_check/features/devices/presentation/devices_screen.dart';
import 'package:ici_check/features/policies/presentation/policies_screen.dart';
import 'package:ici_check/features/settings/presentation/settings_screen.dart';
import 'package:ici_check/features/users/presentation/users_screen.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart'; // Importa tu modelo para usar el enum UserRole

// --- TEMAS Y COLORES (Mismos del Login) ---
const Color _primaryDark = Color(0xFF0F172A);
const Color _accentBlue = Color(0xFF1E40AF);
const Color _bgGrey = Color(0xFFF1F5F9);
const Color _textSlate = Color(0xFF64748B);

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  
  // Variables para almacenar el rol y los menús filtrados
  String _userRoleStr = 'Cargando...'; // Texto para mostrar en el footer
  bool _isLoading = true; // Para mostrar un spinner mientras cargamos permisos

  // Listas que llenaremos dinámicamente
  List<Widget> _pages = [];
  List<Map<String, dynamic>> _menuItems = [];

  @override
  void initState() {
    super.initState();
    _setupMenuBasedOnRole();
  }

  // --- LÓGICA CORE: Configurar menú según permisos ---
  Future<void> _setupMenuBasedOnRole() async {
    if (currentUser == null) return;

    try {
      // 1. Obtenemos el documento del usuario desde Firestore
      final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      
      // Default: Técnico si falla algo
      UserRole role = UserRole.TECHNICIAN; 
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Convertimos el string de la BD al Enum
        String roleStr = data['role'] ?? 'TECHNICIAN';
        role = UserRole.values.firstWhere(
          (e) => e.toString().split('.').last == roleStr,
          orElse: () => UserRole.TECHNICIAN,
        );
        _userRoleStr = roleStr; // Para mostrar en el footer
      }

      // 2. Definimos TODAS las páginas posibles
      // Usamos una lista temporal para armar el menú
      List<Widget> tempPages = [];
      List<Map<String, dynamic>> tempMenu = [];

      // -- AÑADIMOS ITEMS COMUNES (Para todos) --
      
      // Index 0: Inicio
      tempMenu.add({'title': 'Inicio', 'icon': Icons.dashboard_outlined});
     tempPages.add(DashboardScreen(
        onTabChange: onItemTapped, // <--- AQUÍ ESTÁ LA MAGIA
      ));

      // Index 1: Clientes (Digamos que todos ven clientes)
      tempMenu.add({'title': 'Clientes', 'icon': Icons.people_outline});
      tempPages.add(const ClientsScreen());

      // Index 2: Dispositivos
      tempMenu.add({'title': 'Dispositivos', 'icon': Icons.devices_other});
        tempPages.add(const DevicesScreen());

      // Index 3: Pólizas
      tempMenu.add({'title': 'Pólizas', 'icon': Icons.description_outlined});
      tempPages.add(const PoliciesScreen());

      // -- AÑADIMOS ITEMS RESTRINGIDOS (Solo Admin/SuperUser) --
      
      if (role == UserRole.ADMIN || role == UserRole.SUPER_USER) {
        // Index X: Usuarios (Solo aparece si eres jefe)
        tempMenu.add({'title': 'Usuarios', 'icon': Icons.admin_panel_settings_outlined});
        tempPages.add(const UsersScreen());
        
        // Index Y: Configuración (Opcional, si quieres restringirla también)
        tempMenu.add({'title': 'Configuración', 'icon': Icons.settings_outlined});
        tempPages.add(const SettingsScreen());
      } else {
        // Si es técnico, quizás ve una configuración limitada o nada.
        // Aquí decidimos NO mostrar configuración a técnicos por ejemplo,
        // o puedes agregar una versión simple.
      }

      // 3. Actualizamos el estado para redibujar la pantalla
      if (mounted) {
        setState(() {
          _menuItems = tempMenu;
          _pages = tempPages;
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint("Error cargando rol: $e");
      if(mounted) setState(() => _isLoading = false);
    }
  }

  void onItemTapped(int index) {  // <- Público (sin _)
    setState(() {
      _selectedIndex = index;
    });
  }

  void _handleLogout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // Si está cargando permisos, mostramos pantalla de carga limpia
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgGrey,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth >= 800;

        if (isDesktop) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: _bgGrey,
            body: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _buildSidebarContent(isDesktop: true),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(isDesktop: true),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          // Protección extra: Si el índice se sale de rango (raro), mostrar el primero
                          child: _pages.isNotEmpty 
                              ? _pages[_selectedIndex < _pages.length ? _selectedIndex : 0]
                              : const SizedBox(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          return Scaffold(
            backgroundColor: _bgGrey,
            appBar: AppBar(
              backgroundColor: _primaryDark,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'ICI-CHECK',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none),
                )
              ],
            ),
            drawer: Drawer(
              width: 280,
              backgroundColor: _primaryDark,
              child: _buildSidebarContent(isDesktop: false),
            ),
            body: _pages.isNotEmpty 
                ? _pages[_selectedIndex < _pages.length ? _selectedIndex : 0]
                : const SizedBox(),
          );
        }
      },
    );
  }

  Widget _buildSidebarContent({required bool isDesktop}) {
    return Container(
      color: _primaryDark,
      child: Column(
        children: [
          // 1. LOGO HEADER
          Container(
            height: isDesktop ? 120 : 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_user_outlined, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ICI-CHECK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'v2.0.001',
                      style: TextStyle(color: Colors.blue[100], fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. LISTA DE NAVEGACIÓN (DINÁMICA)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              itemCount: _menuItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = _menuItems[index];
                final isSelected = _selectedIndex == index;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      onItemTapped(index);
                      if (!isDesktop) Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _accentBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item['icon'],
                            color: isSelected ? Colors.white : _textSlate,
                            size: 22,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            item['title'],
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.blue[50],
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 3. USER PROFILE FOOTER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _accentBlue,
                  radius: 18,
                  child: Text(
                    currentUser?.email?.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentUser?.email ?? 'Usuario',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _userRoleStr, // Mostramos el rol real cargado de la BD
                        style: const TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
                  onPressed: _handleLogout,
                  tooltip: 'Cerrar Sesión',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isDesktop}) {
    // Si la lista está vacía (cargando), mostramos un título default
    String title = _menuItems.isNotEmpty ? _menuItems[_selectedIndex]['title'] : 'Cargando...';

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _primaryDark,
            ),
          ),
          Row(
            children: [
               IconButton(
                onPressed: () {},
                icon: Badge(
                  label: const Text('3'),
                  backgroundColor: Colors.red,
                  child: Icon(Icons.notifications_outlined, color: _textSlate),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}