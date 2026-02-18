import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:ici_check/features/clients/presentation/clients_screen.dart';
import 'package:ici_check/features/dashboard/presentation/dashboard_screen.dart';
import 'package:ici_check/features/devices/presentation/devices_screen.dart';
import 'package:ici_check/features/policies/presentation/policies_screen.dart';
import 'package:ici_check/features/settings/presentation/settings_screen.dart';
import 'package:ici_check/features/users/presentation/users_screen.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/notifications/presentation/notifications_screen_modal.dart'; 

// --- TEMAS Y COLORES ---
const Color _primaryDark = Color(0xFF0F172A);
const Color _accentBlue = Color(0xFF1E40AF);
const Color _bgGrey = Color(0xFFF1F5F9);
const Color _textSlate = Color(0xFF64748B);
const Color _textPrimary = Color(0xFF0F172A);

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  
  String _userRoleStr = 'Cargando...';
  bool _isLoading = true;
  late bool _isDesktop;

  List<Widget> _pages = [];
  List<Map<String, dynamic>> _menuItems = [];

  @override
  void initState() {
    super.initState();
    _setupMenuBasedOnRole();
  }

  // --- LÓGICA CORE MODIFICADA ---
  Future<void> _setupMenuBasedOnRole() async {
    if (currentUser == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      
      UserRole role = UserRole.TECHNICIAN; 
      String roleStr = 'TECHNICIAN';

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        roleStr = data['role'] ?? 'TECHNICIAN';
        role = UserRole.values.firstWhere(
          (e) => e.toString().split('.').last == roleStr,
          orElse: () => UserRole.TECHNICIAN,
        );
      }
      
      _userRoleStr = roleStr;

      List<Widget> tempPages = [];
      List<Map<String, dynamic>> tempMenu = [];

      // 1. INICIO (Visible para TODOS)
      tempMenu.add({'title': 'Inicio', 'icon': Icons.dashboard_outlined});
     tempPages.add(DashboardScreen(
        onTabChange: onItemTapped, // <--- AQUÍ ESTÁ LA MAGIA
      ));

      // 2. LÓGICA DE FILTRADO ESTRICTO
      if (role == UserRole.TECHNICIAN) {
        // --- SOLO PARA TÉCNICOS ---
        // Solo ven Inicio (agregado arriba) y Pólizas
        
        tempMenu.add({'title': 'Pólizas', 'icon': Icons.description_outlined});
        tempPages.add(const PoliciesScreen());

      } else {
        // --- PARA ADMINS Y SUPER USUARIOS (Ven todo el resto) ---
        
        // Clientes
        tempMenu.add({'title': 'Clientes', 'icon': Icons.people_outline});
        tempPages.add(const ClientsScreen());

        // Dispositivos
        tempMenu.add({'title': 'Dispositivos', 'icon': Icons.devices_other});
        tempPages.add(const DevicesScreen());

        // Pólizas
        tempMenu.add({'title': 'Pólizas', 'icon': Icons.description_outlined});
        tempPages.add(const PoliciesScreen());

        // Usuarios
        tempMenu.add({'title': 'Usuarios', 'icon': Icons.admin_panel_settings_outlined});
        tempPages.add(const UsersScreen());
        
        // Configuración
        tempMenu.add({'title': 'Configuración', 'icon': Icons.settings_outlined});
        tempPages.add(const SettingsScreen());
      }
      
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

  Future<void> _handleLogout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgGrey,
        body: Center(child: CircularProgressIndicator(color: _accentBlue)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _isDesktop = constraints.maxWidth >= 800;

        if (_isDesktop) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: _bgGrey,
            body: Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _buildSidebarContent(_isDesktop),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          child: _pages.isNotEmpty 
                              ? _pages[_selectedIndex < _pages.length ? _selectedIndex : 0]
                              : const Center(child: Text("No hay páginas disponibles")),
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
            key: _scaffoldKey,
            backgroundColor: _bgGrey,
            appBar: AppBar(
              backgroundColor: _primaryDark,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'ICI-CHECK',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              actions: [
                if (currentUser != null)
                  NotificationBadge(
                    userId: currentUser!.uid,
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                      onPressed: () => showNotificationsModal(context),
                      tooltip: 'Notificaciones',
                    ),
                  ),
              ],
            ),
            drawer: Drawer(
              width: 280,
              backgroundColor: _primaryDark,
              child: _buildSidebarContent(_isDesktop),
            ),
            body: _pages.isNotEmpty 
                ? _pages[_selectedIndex < _pages.length ? _selectedIndex : 0]
                : const Center(child: Text("Cargando menú...")),
          );
        }
      },
    );
  }

  Widget _buildSidebarContent(bool isDesktop) {
    return Container(
      color: _primaryDark,
      child: Column(
        children: [
          // LOGO
          Container(
            height: 150,
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
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ICI-CHECK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text('v0.6.0', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),

          // MENÚ
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? _accentBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected ? Border.all(color: Colors.blue.shade400.withOpacity(0.3)) : null,
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

          // FOOTER USER
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
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _userRoleStr,
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
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

  Widget _buildHeader() {
    String title = _menuItems.isNotEmpty 
        ? _menuItems[_selectedIndex < _menuItems.length ? _selectedIndex : 0]['title'] 
        : '';

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
              if (currentUser != null)
                NotificationBadge(
                  userId: currentUser!.uid,
                  child: IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: _textPrimary),
                    onPressed: () => showNotificationsModal(context),
                    tooltip: 'Notificaciones',
                  ),
                ),
              const SizedBox(width: 8),
            ],
          )
        ],
      ),
    );
  }
}