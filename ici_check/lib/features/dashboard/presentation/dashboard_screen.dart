import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int) onTabChange;

  const DashboardScreen({
    super.key, 
    // AGREGA ESTA LÍNEA: Ahora es obligatorio pasar la función
    required this.onTabChange, 
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Datos del Dashboard
  int _clientsCount = 0;
  int _policiesCount = 0;
  int _devicesCount = 0;
  int _reportsCount = 0;
  bool _isLoading = true;

  // Colores corporativos
  final Color _primaryDark = const Color(0xFF0F172A);
  // ignore: unused_field
  final Color _accentBlue = const Color(0xFF3B82F6);
  final Color _bgLight = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    // Inicializar localización en español
    initializeDateFormatting('es', null).then((_) {
      _loadDashboardData();
    });
  }

  Future<void> _loadDashboardData() async {
    try {
      // Cargar datos en paralelo
      final results = await Future.wait([
        _db.collection('clients').get(),
        _db.collection('policies').get(),
        _db.collection('devices').get(),
        _db.collection('reports').get(),
      ]);

      if (mounted) {
        setState(() {
          _clientsCount = results[0].docs.length;
          _policiesCount = results[1].docs.length;
          _devicesCount = results[2].docs.length;
          _reportsCount = results[3].docs.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgLight,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Detectar tamaño de pantalla
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: _bgLight,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === 1. HERO HEADER ===
            _buildHeroHeader(isMobile),
            
            SizedBox(height: isMobile ? 24 : 40),

            // === 2. ESTADÍSTICAS PRINCIPALES ===
            _buildStatsGrid(isMobile),

            SizedBox(height: isMobile ? 24 : 40),

            // === 3. SECCIÓN DE ACCIONES RÁPIDAS ===
            _buildQuickActions(isMobile),

            SizedBox(height: isMobile ? 24 : 40),

            // === 4. BANNER INFORMATIVO ===
            _buildFeatureBanner(isMobile),

            SizedBox(height: isMobile ? 24 : 40),

            // === 5. ACTIVIDAD RECIENTE ===
            _buildRecentActivity(isMobile),
          ],
        ),
      ),
    );
  }

  // ========================================
  // 1. HERO HEADER
  // ========================================
  Widget _buildHeroHeader(bool isMobile) {
    final hour = DateTime.now().hour;
    String greeting = 'Buenos días';
    if (hour >= 12 && hour < 18) greeting = 'Buenas tardes';
    if (hour >= 18) greeting = 'Buenas noches';

    final userName = currentUser?.email?.split('@').first ?? 'Usuario';

    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryDark,
            const Color(0xFF1E3A8A), // Blue-900
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _primaryDark.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Saludo personalizado
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.wb_sunny_outlined,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      userName.split('.').map((s) => s[0].toUpperCase() + s.substring(1)).join(' '),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 24 : 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Fecha actual
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, d \'de\' MMMM yyyy', 'es').format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // 2. GRID DE ESTADÍSTICAS
  // ========================================
  Widget _buildStatsGrid(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsivo: 1 columna en móvil, 2 en tablet, 4 en desktop
        int columns = 1;
        if (constraints.maxWidth > 600) columns = 2;
        if (constraints.maxWidth > 1200) columns = 4;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: isMobile ? 1.5 : 1.3,
          children: [
            _StatCard(
              title: 'Clientes',
              value: _clientsCount.toString(),
              icon: Icons.business_outlined,
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
              ),
              trend: '+12%',
            ),
            _StatCard(
              title: 'Pólizas Activas',
              value: _policiesCount.toString(),
              icon: Icons.description_outlined,
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              trend: '+8%',
            ),
            _StatCard(
              title: 'Dispositivos',
              value: _devicesCount.toString(),
              icon: Icons.devices_other_outlined,
              gradient: const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
              ),
              trend: '+5%',
            ),
            _StatCard(
              title: 'Reportes',
              value: _reportsCount.toString(),
              icon: Icons.assignment_outlined,
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
              ),
              trend: '+23%',
            ),
          ],
        );
      },
    );
  }

  // ========================================
  // 3. ACCIONES RÁPIDAS
  // ========================================
  Widget _buildQuickActions(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acciones Rápidas',
          style: TextStyle(
            fontSize: isMobile ? 20 : 24,
            fontWeight: FontWeight.w800,
            color: _primaryDark,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickActionButton(
              icon: Icons.person_add_outlined,
              label: 'Nuevo Cliente',
              color: const Color(0xFF3B82F6),
              onTap: () => _navigateToTab(1), // Índice de Clientes
            ),
            _QuickActionButton(
              icon: Icons.description_outlined,
              label: 'Nueva Póliza',
              color: const Color(0xFF10B981),
              onTap: () => _navigateToTab(3), // Índice de Pólizas
            ),
            _QuickActionButton(
              icon: Icons.devices_other_outlined,
              label: 'Agregar Dispositivo',
              color: const Color(0xFFF59E0B),
              onTap: () => _navigateToTab(2), // Índice de Dispositivos
            ),
            _QuickActionButton(
              icon: Icons.verified_user_sharp,
              label: 'Usuarios',
              color: const Color(0xFF8B5CF6),
              onTap: () => _navigateToTab(4), // Índice de Usuarios
            ),
          ],
        ),
      ],
    );
  }

  // ========================================
  // MÉTODO PARA CAMBIAR DE PESTAÑA
  // ========================================
  void _navigateToTab(int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onTabChange(index); // Llamamos a la función pasada desde MainLayoutScreen
  }

  // ========================================
  // 4. BANNER INFORMATIVO
  // ========================================
  Widget _buildFeatureBanner(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3B82F6),
            Color(0xFF2563EB),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Decoración de fondo
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          // Contenido
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Sistema Inteligente',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Configure dispositivos, asigne frecuencias de mantenimiento y deje que ICI-CHECK organice automáticamente su cronograma anual de inspecciones.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: isMobile ? 14 : 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _buildFeaturePoint('Programación automática'),
                  const SizedBox(width: 16),
                  _buildFeaturePoint('Reportes en PDF'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePoint(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            color: Colors.white,
            size: 12,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ========================================
  // 5. ACTIVIDAD RECIENTE
  // ========================================
  Widget _buildRecentActivity(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Actividad Reciente',
              style: TextStyle(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w800,
                color: _primaryDark,
              ),
            ),
            TextButton(
              onPressed: () {
                // TODO: Ver todo
              },
              child: const Text('Ver todo'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade100,
            ),
            itemBuilder: (context, index) {
              return _ActivityItem(
                icon: index % 2 == 0 ? Icons.person_add : Icons.edit,
                title: index % 2 == 0 
                    ? 'Nuevo cliente registrado' 
                    : 'Póliza actualizada',
                subtitle: '${index + 1} hora${index == 0 ? '' : 's'} atrás',
                color: index % 2 == 0 
                    ? const Color(0xFF3B82F6) 
                    : const Color(0xFF10B981),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ========================================
// COMPONENTES AUXILIARES
// ========================================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Gradient gradient;
  final String? trend;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trend!,
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}