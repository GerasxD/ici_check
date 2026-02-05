import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/auth/data/users_repository.dart';
import 'package:ici_check/features/reports/presentation/service_report_screen.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/policies/data/policies_repository.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/clients/data/clients_repository.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/devices/data/devices_repository.dart';

class SchedulerScreen extends StatefulWidget {
  final String policyId;
  const SchedulerScreen({super.key, required this.policyId});

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  final PoliciesRepository _policiesRepo = PoliciesRepository();
  final ClientsRepository _clientsRepo = ClientsRepository();
  final DevicesRepository _devicesRepo = DevicesRepository();

  bool _isLoading = true;
  bool _isEditing = false;
  bool _hasChanges = false;
  String _viewMode = 'monthly';

  late PolicyModel _policy;
  ClientModel? _client;
  List<DeviceModel> _deviceDefinitions = [];

  final UsersRepository _usersRepo = UsersRepository();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ESTADO PARA TÉCNICOS
  List<UserModel> _allTechnicians = [];
  
  // CACHÉ DE DISPONIBILIDAD (Para no saturar Firebase)
  // Key: "userId_date", Value: Status ('AVAILABLE', 'BUSY_OTHER', etc)
  // ignore: unused_field
  Map<String, String> _availabilityCache = {};

  List<Map<String, dynamic>> _reports = []; // LISTA PARA GUARDAR REPORTES
  StreamSubscription? _reportsSub;

  // Paleta de colores
  final Color _primaryDark = const Color(0xFF1E293B);
  final Color _primaryBlue = const Color(0xFF3B82F6);
  final Color _bgLight = const Color(0xFFF8FAFC);
  final Color _cardWhite = const Color(0xFFFFFFFF);
  final Color _textPrimary = const Color(0xFF0F172A);
  final Color _textSecondary = const Color(0xFF64748B);
  final Color _borderLight = const Color(0xFFE2E8F0);
  final Color _successGreen = const Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _reportsSub?.cancel(); // IMPORTANTE: Cancelar al salir
    super.dispose();
  }

  Future<void> _loadAllData() async {
    try {
      final pList = await _policiesRepo.getPoliciesStream().first;
      final p = pList.firstWhere((element) => element.id == widget.policyId);
      final cList = await _clientsRepo.getClientsStream().first;
      final c = cList.firstWhere((element) => element.id == p.clientId);
      final devs = await _devicesRepo.getDevicesStream().first;

      final allUsers = await _usersRepo.getUsersStream().first;
      final techs = allUsers.where((u) => 
        u.role == UserRole.TECHNICIAN || 
        u.role == UserRole.ADMIN || 
        u.role == UserRole.SUPER_USER
      ).toList();

      _reportsSub?.cancel(); // Cancelar anterior si existe
      _reportsSub = FirebaseFirestore.instance
          .collection('reports')
          .where('policyId', isEqualTo: widget.policyId)
          .snapshots() // <--- Esto es lo que permite la actualización automática
          .listen((snapshot) {
            if (mounted) {
              setState(() {
                _reports = snapshot.docs.map((d) => d.data()).toList();
              });
            }
          });

      if (mounted) {
        setState(() {
          _policy = p;
          _client = c;
          _deviceDefinitions = devs;
          _allTechnicians = techs; // <--- Guardamos los técnicos
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading scheduler: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al cargar datos: $e"),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  double _getFrequencyMonths(Frequency freq) {
    switch (freq) {
      case Frequency.DIARIO:
        return 0; // Diario no se suele graficar en este tipo de cronogramas
      case Frequency.SEMANAL:
        return 0.25; // <--- LA CLAVE: 1 semana es 0.25 meses
      case Frequency.MENSUAL:
        return 1.0;
      case Frequency.TRIMESTRAL:
        return 3.0;
      case Frequency.SEMESTRAL:
        return 6.0;
      case Frequency.ANUAL:
        return 12.0;
      // ignore: unreachable_switch_default
      default:
        return 12.0;
    }
  }

  bool _isScheduled(PolicyDevice devInstance, String activityId, int timeIndex) {
    try {
      final def = _deviceDefinitions.firstWhere((d) => d.id == devInstance.definitionId);
      final activity = def.activities.firstWhere((a) => a.id == activityId);

      // Ahora freqMonths es double (ej: 0.25 para semanal)
      double freqMonths = _getFrequencyMonths(activity.frequency);
      
      // Si es 0 (ej: diario), retornamos false para evitar errores
      if (freqMonths == 0) return false;

      double offset = (devInstance.scheduleOffsets[activityId] ?? 0).toDouble();
      
      // En mensual: timeIndex es 0, 1, 2... (Meses)
      // En semanal: timeIndex es 0, 1, 2... dividimos entre 4 para obtener "Meses" (0, 0.25, 0.5...)
      double currentTime = _viewMode == 'monthly' ? timeIndex.toDouble() : timeIndex / 4.0;
      
      double adjustedTime = currentTime - offset;

      // Tolerancia para comparaciones de punto flotante
      double epsilon = 0.05; 

      if (adjustedTime < -epsilon) return false;
      
      // Operación Modulo (%) con decimales
      double remainder = adjustedTime % freqMonths;
      
      // Si el residuo es cercano a 0 o cercano a la frecuencia, toca actividad
      return remainder < epsilon || (remainder - freqMonths).abs() < epsilon;
    } catch (e) {
      return false;
    }
  }

  void _handleCellClick(int devIdx, String activityId, int timeIdx) {
    if (!_isEditing) return;

    setState(() {
      final dev = _policy.devices[devIdx];
      final def = _deviceDefinitions.firstWhere((d) => d.id == dev.definitionId);
      final activity = def.activities.firstWhere((a) => a.id == activityId);
      
      double freqMonths = _getFrequencyMonths(activity.frequency);

      if (freqMonths == 0) return;

      double timeValue = _viewMode == 'monthly' ? timeIdx.toDouble() : timeIdx / 4.0;

      double minDiff = 1000;
      double bestBase = 0;
      
      // Buscamos el múltiplo de frecuencia más cercano al clic
      for (int k = -5; k < 50; k++) { // Aumenté el rango por si acaso
        double base = k * freqMonths;
        double diff = (timeValue - base).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestBase = base;
        }
      }

      // Guardamos el desfase (offset) calculado
      // Nota: Para Semanal generalmente el offset será 0, pero esto permite "saltar" semanas si fuera necesario
      dev.scheduleOffsets[activityId] = (timeValue - bestBase).round(); 
      _hasChanges = true;
    });
  }
  
  // Busca si hay un reporte para una fecha específica (columna)
  Map<String, dynamic>? _getReportForColumn(int index) {
    DateTime columnDate;

    // 1. CÁLCULO EXACTO (Igual que en el Header)
    if (_viewMode == 'monthly') {
      // Sumamos meses directamente al año/mes
      columnDate = DateTime(
        _policy.startDate.year,
        _policy.startDate.month + index,
        1, // Forzamos día 1 para generar la clave 'yyyy-MM' correctamente
      );
    } else {
      // Para semanas sumamos 7 días exactos
      columnDate = _policy.startDate.add(Duration(days: index * 7));
    }

    // 2. Generar la clave (dateStr) para buscar en la lista _reports
    String dateKey = _viewMode == 'monthly' 
        ? DateFormat('yyyy-MM').format(columnDate) 
        : "${columnDate.year}-W${index + 1}";

    // 3. Buscar en la lista de reportes cargados
    try {
      return _reports.firstWhere((r) => r['dateStr'] == dateKey);
    } catch (e) {
      return null;
    }
  }

  void _handleHeaderCalendarClick(int index) {
    DateTime columnDate;

    // 1. CÁLCULO DE FECHA CORREGIDO
    if (_viewMode == 'monthly') {
      // Suma lógica de meses (Evita el problema de los 30 días)
      // Si startDate es 5 de Enero, index 1 dará 5 de Febrero, index 2 dará 5 de Marzo, etc.
      columnDate = DateTime(
        _policy.startDate.year,
        _policy.startDate.month + index,
        _policy.startDate.day,
      );
    } else {
      // Para semanas, sumar 7 días es seguro y exacto
      columnDate = _policy.startDate.add(Duration(days: index * 7));
    }

    // 2. Normalización (Mantener tu lógica de bucket mensual)
    // Si estamos en modo mensual, forzamos al día 1 para generar el ID del reporte (YYYY-MM)
    // y que todos los eventos de ese mes caigan en el mismo reporte.
    if (_viewMode == 'monthly') {
      columnDate = DateTime(columnDate.year, columnDate.month, 1);
    }

    // 3. Generar Etiquetas
    String label = _viewMode == 'monthly'
        ? DateFormat('MMMM yyyy', 'es').format(columnDate).toUpperCase()
        : "Semana ${index + 1} (${DateFormat('dd MMM', 'es').format(columnDate)})";

    // 4. Generar Key única para Firebase
    String dateKey = _viewMode == 'monthly'
        ? DateFormat('yyyy-MM').format(columnDate)
        : "${columnDate.year}-W${index + 1}";

    // 5. Abrir el Diálogo
    _showScheduleDialog(columnDate, label, dateKey);
  }

  Future<void> _showScheduleDialog(DateTime baseDate, String label, String dateKey) async {
    // Variables locales para el estado del diálogo
    DateTime selectedDate = baseDate;
    List<String> selectedTechIds = [];
    bool isSaving = false;

    // Intentar buscar datos existentes en Firebase para pre-llenar
    try {
      final qSnapshot = await _db.collection('reports')
          .where('policyId', isEqualTo: _policy.id)
          .where('dateStr', isEqualTo: dateKey)
          .limit(1)
          .get();

      if (qSnapshot.docs.isNotEmpty) {
        final data = qSnapshot.docs.first.data();
        // Si ya hay reporte, tomamos la fecha real de servicio y los técnicos
        if (data['serviceDate'] != null) {
          selectedDate = (data['serviceDate'] as Timestamp).toDate();
        }
        if (data['assignedTechnicianIds'] != null) {
          selectedTechIds = List<String>.from(data['assignedTechnicianIds']);
        }
      }
    } catch (e) {
      debugPrint("Error buscando reporte existente: $e");
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false, // Obligar a usar botones
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 450, // Ancho máximo similar a max-w-md
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- HEADER ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC), // slate-50
                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "PROGRAMAR SERVICIO",
                                  style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w900, 
                                    color: Color(0xFF1E293B), letterSpacing: -0.5
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  label,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    // --- BODY ---
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. FECHA DEL SERVICIO
                            const Text(
                              "FECHA DEL SERVICIO",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.light().copyWith(
                                        colorScheme: ColorScheme.fromSeed(seedColor: _primaryBlue),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setModalState(() => selectedDate = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 18, color: _primaryBlue),
                                    const SizedBox(width: 10),
                                    Text(
                                      DateFormat('dd MMMM yyyy', 'es').format(selectedDate),
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // 2. TÉCNICOS ASIGNADOS
                            const Text(
                              "TÉCNICOS ASIGNADOS",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 1),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: _allTechnicians.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final tech = _allTechnicians[index];
                                  final isAssigned = selectedTechIds.contains(tech.id);
                                  
                                  // TODO: Aquí iría la lógica real de disponibilidad (getTechStatus)
                                  // Por ahora asumimos disponible para simplificar la UI
                                  bool isAvailable = true; 

                                  return InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        if (isAssigned) {
                                          selectedTechIds.remove(tech.id);
                                        } else {
                                          selectedTechIds.add(tech.id);
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isAssigned ? const Color(0xFFEFF6FF) : Colors.white, // blue-50
                                        border: Border.all(
                                          color: isAssigned ? const Color(0xFF60A5FA) : Colors.grey.shade200,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          // Avatar
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: Colors.grey.shade200,
                                            child: Text(
                                              tech.name.isNotEmpty ? tech.name[0].toUpperCase() : '?',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Nombre y Estado
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tech.name,
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                                ),
                                                // Mostrar estado si no está asignado
                                                if (!isAssigned && !isAvailable)
                                                   // ignore: dead_code
                                                   const Text(
                                                    "OCUPADO EN OTRO SERVICIO",
                                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (isAssigned)
                                            Icon(Icons.check_circle, color: _primaryBlue, size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- FOOTER (BOTONES) ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("CANCELAR", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A), // slate-900
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            onPressed: (selectedTechIds.isEmpty || isSaving) ? null : () async {
                              setModalState(() => isSaving = true);
                              
                              await _saveScheduleToFirebase(dateKey, selectedDate, selectedTechIds);
                              
                              if (mounted) {
                                Navigator.pop(ctx); // Cerrar modal
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text("Programación guardada exitosamente"),
                                    backgroundColor: _successGreen,
                                  )
                                );
                              }
                            },
                            child: isSaving 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text("GUARDAR PROGRAMACIÓN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveScheduleToFirebase(String dateKey, DateTime serviceDate, List<String> techIds) async {
    try {
      final reportsRef = _db.collection('reports');
      
      // 1. Verificar si ya existe un reporte para esta póliza y este periodo (dateKey)
      final qSnapshot = await reportsRef
          .where('policyId', isEqualTo: _policy.id)
          .where('dateStr', isEqualTo: dateKey)
          .limit(1)
          .get();

      if (qSnapshot.docs.isNotEmpty) {
        // --- ACTUALIZAR EXISTENTE ---
        final docId = qSnapshot.docs.first.id;
        await reportsRef.doc(docId).update({
          'serviceDate': Timestamp.fromDate(serviceDate), // Guardar como Timestamp
          'assignedTechnicianIds': techIds,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // --- CREAR NUEVO (Logic from React 'handleSaveSchedule') ---
        // Aquí deberíamos generar las entradas vacías ('entries') basadas en los dispositivos
        // pero para simplificar la programación, crearemos el esqueleto básico del reporte.
        
        await reportsRef.add({
          'policyId': _policy.id,
          'clientId': _policy.clientId, // Útil para búsquedas rápidas
          'dateStr': dateKey, // "2025-01" o "2025-W01"
          'serviceDate': Timestamp.fromDate(serviceDate),
          'assignedTechnicianIds': techIds,
          'status': 'draft', // Estado inicial
          'createdAt': FieldValue.serverTimestamp(),
          // Nota: Las 'entries' se pueden generar aquí o al abrir el reporte por primera vez.
          // Si quieres replicar React exacto, necesitarías un bucle sobre _policy.devices aquí.
        });
      }
      
      // Opcional: Enviar notificaciones a los técnicos (como en tu React)
      // _sendNotifications(techIds, serviceDate);

    } catch (e) {
      debugPrint("Error guardando programación: $e");
      throw e; // Re-lanzar para que el botón muestre error si quieres
    }
  }
  
  void _handleHeaderReportClick(int index) {
    // 1. Calcular la fecha de la columna (mismo cálculo que en el header)
    DateTime columnDate;
    if (_viewMode == 'monthly') {
      columnDate = DateTime(
        _policy.startDate.year,
        _policy.startDate.month + index,
        1, // Forzamos día 1 para clave mensual
      );
    } else {
      columnDate = _policy.startDate.add(Duration(days: index * 7));
    }

    // 2. Generar la clave (dateStr) para buscar el reporte
    String dateKey = _viewMode == 'monthly'
        ? DateFormat('yyyy-MM').format(columnDate)
        : "${columnDate.year}-W${index + 1}";

    // 3. Navegar a la pantalla de reportes
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceReportScreen(
          policyId: widget.policyId,
          dateStr: dateKey,
          policy: _policy, // Pasamos la póliza para no recargarla
          devices: _deviceDefinitions, // Pasamos las definiciones de equipos
          users: _allTechnicians, // Pasamos los usuarios
        ),
      ),
    );
  }

  void _handleHeaderDownloadClick(int index) {
    // Lógica para descargar PDF
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Descargando PDF del periodo...")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgLight,
        body: Center(
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildHeaderInfo(),
          Expanded(child: _buildGrid()),
          _buildLegend(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _cardWhite,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: _textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Cronograma de Mantenimiento",
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          Text(
            _client?.name ?? "Cliente",
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        if (_hasChanges)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FloatingActionButton.small(
              backgroundColor: _successGreen,
              elevation: 0,
              onPressed: () async {
                await _policiesRepo.savePolicy(_policy);
                setState(() {
                  _hasChanges = false;
                  _isEditing = false;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text("Guardado exitosamente"), backgroundColor: _successGreen),
                  );
                }
              },
              child: const Icon(Icons.save, color: Colors.white),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            icon: Icon(
              _isEditing ? Icons.edit : Icons.edit_off,
              color: _isEditing ? _primaryBlue : _textSecondary,
            ),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderInfo() {
    final dateFormat = DateFormat('dd MMM yyyy', 'es');
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Vista del Cronograma", style: TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'monthly', label: Text("MENSUAL"), icon: Icon(Icons.calendar_view_month, size: 16)),
                        ButtonSegment(value: 'weekly', label: Text("SEMANAL"), icon: Icon(Icons.view_week, size: 16)),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (val) => setState(() => _viewMode = val.first),
                      style: ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.selected) ? _primaryBlue : Colors.transparent,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) => states.contains(WidgetState.selected) ? Colors.white : _textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("PERIODO", style: TextStyle(color: _primaryBlue, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(
                    "${dateFormat.format(_policy.startDate)} - ${dateFormat.format(_policy.startDate.add(Duration(days: _policy.durationMonths * 30)))}",
                    style: TextStyle(color: _textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (_isEditing)
             Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Text("Modo edición activado", style: TextStyle(color: Colors.orange.shade900, fontSize: 12)),
                ],
              ),
             ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    int duration = _policy.durationMonths;
    int colCount = _viewMode == 'monthly' ? duration : duration * 4;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              color: _primaryDark,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  // AUMENTÉ EL ANCHO A 100 PARA QUE QUEPAN LOS BOTONES
                  defaultColumnWidth: const FixedColumnWidth(100), 
                  columnWidths: const {0: FixedColumnWidth(280)},
                  children: [
                    TableRow(
                      children: [
                        TableCell(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: const Text(
                              "DISPOSITIVOS Y ACTIVIDADES",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ),
                        ...List.generate(colCount, (i) => _buildTimeHeader(i)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(100), // AUMENTÉ EL ANCHO A 100
                    columnWidths: const {0: FixedColumnWidth(280)},
                    border: TableBorder.all(color: _borderLight, width: 1),
                    children: _buildDataRows(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- MODIFICADO: AHORA INCLUYE LOS BOTONES DE ACCIÓN ---
  Widget _buildTimeHeader(int index) {
    DateTime date;
    
    // 1. Calcular fecha exacta de la columna
    if (_viewMode == 'monthly') {
      date = DateTime(
        _policy.startDate.year, 
        _policy.startDate.month + index, 
        _policy.startDate.day // Mantiene el día original (ej: 5)
      );
    } else {
      date = _policy.startDate.add(Duration(days: index * 7));
    }
        
    // 2. Buscar si hay Reporte Real
    final report = _getReportForColumn(index);
    
    // 3. Determinar etiquetas
    String labelMain = "";
    String labelSub = "";
    bool hasScheduledDate = false;

    if (_viewMode == 'monthly') {
      labelMain = DateFormat('MMM', 'es').format(date).toUpperCase().replaceAll('.', '');
      
      if (report != null && report['serviceDate'] != null) {
        // CASO 1: YA HAY REPORTE -> Muestra fecha real (Ej: 12)
        DateTime serviceDate = (report['serviceDate'] as Timestamp).toDate();
        labelSub = DateFormat('d', 'es').format(serviceDate); 
        hasScheduledDate = true;
      } else {
        // CASO 2: NO HAY REPORTE -> Muestra el día programado (Ej: 05)
        // ANTES MOSTRABA EL AÑO: labelSub = "'${date.year.toString().substring(2)}"; 
        labelSub = DateFormat('d', 'es').format(date); 
      }
    } else {
      // Lógica Semanal
      labelMain = "S${index + 1}";
      if (report != null && report['serviceDate'] != null) {
        DateTime serviceDate = (report['serviceDate'] as Timestamp).toDate();
        labelSub = DateFormat('d MMM', 'es').format(serviceDate);
        hasScheduledDate = true;
      } else {
        // Muestra rango o día inicial de la semana
        labelSub = DateFormat('d', 'es').format(date);
      }
    }

    return TableCell(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2), 
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              labelMain,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.white, letterSpacing: 0.5),
            ),
            const SizedBox(height: 2),
            Container(
              padding: hasScheduledDate 
                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) 
                  : EdgeInsets.zero,
              decoration: hasScheduledDate 
                  ? BoxDecoration(color: _primaryBlue, borderRadius: BorderRadius.circular(4)) 
                  : null,
              child: Text(
                labelSub,
                style: TextStyle(
                  color: hasScheduledDate ? Colors.white : Colors.white.withOpacity(0.7),
                  fontSize: hasScheduledDate ? 10 : 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // ... (Tus botones de acción siguen igual aquí) ...
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HeaderActionButton(
                  icon: Icons.calendar_today,
                  color: const Color(0xFF60A5FA),
                  onTap: () => _handleHeaderCalendarClick(index),
                  tooltip: "Programar",
                ),
                const SizedBox(width: 4),
                _HeaderActionButton(
                  icon: Icons.assignment_outlined,
                  color: const Color(0xFF94A3B8),
                  onTap: () => _handleHeaderReportClick(index),
                  tooltip: "Ver Reporte",
                ),
                const SizedBox(width: 4),
                _HeaderActionButton(
                  icon: Icons.download_rounded,
                  color: const Color(0xFF4ADE80),
                  onTap: () => _handleHeaderDownloadClick(index),
                  tooltip: "Descargar PDF",
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  List<TableRow> _buildDataRows() {
    List<TableRow> rows = [];
    int colCount = _viewMode == 'monthly' ? _policy.durationMonths : _policy.durationMonths * 4;

    for (int dIdx = 0; dIdx < _policy.devices.length; dIdx++) {
      final devInstance = _policy.devices[dIdx];
      final def = _deviceDefinitions.firstWhere((d) => d.id == devInstance.definitionId);

      // Fila de dispositivo
      rows.add(TableRow(
        decoration: BoxDecoration(
          color: _primaryDark.withOpacity(0.05),
          border: Border(top: BorderSide(color: _borderLight, width: 2)),
        ),
        children: [
          TableCell(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.devices_outlined, size: 16, color: _primaryBlue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      def.name,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...List.generate(colCount, (index) => TableCell(child: Container(color: _primaryDark.withOpacity(0.02)))),
        ],
      ));

      // Filas de actividades
      for (var activity in def.activities) {
        if (_viewMode == 'monthly' && activity.frequency == Frequency.SEMANAL) continue;
        if (_viewMode == 'weekly' && activity.frequency != Frequency.SEMANAL) continue;

        rows.add(TableRow(
          children: [
            TableCell(
              child: Container(
                padding: const EdgeInsets.only(left: 48, top: 12, bottom: 12, right: 12),
                child: Row(
                  children: [
                    Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(color: _getActivityColor(activity.type), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activity.name,
                        style: TextStyle(fontSize: 12, color: _textPrimary, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...List.generate(colCount, (tIdx) {
              bool active = _isScheduled(devInstance, activity.id, tIdx);
              return TableCell(
                child: InkWell(
                  onTap: () => _handleCellClick(dIdx, activity.id, tIdx),
                  hoverColor: _isEditing ? _primaryBlue.withOpacity(0.05) : Colors.transparent,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? _getActivityColor(activity.type).withOpacity(0.08) : Colors.transparent,
                    ),
                    child: active
                        ? _buildStatusCircle(activity.type)
                        : (_isEditing ? Icon(Icons.add_circle_outline, size: 14, color: _textSecondary.withOpacity(0.3)) : null),
                  ),
                ),
              );
            }),
          ],
        ));
      }
    }
    return rows;
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.INSPECCION: return const Color(0xFF3B82F6);
      case ActivityType.PRUEBA: return const Color(0xFFF59E0B);
      case ActivityType.MANTENIMIENTO: return const Color(0xFFEC4899);
    }
  }

  Widget _buildStatusCircle(ActivityType type) {
    Color color = _getActivityColor(type);
    return Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("TIPOS DE ACTIVIDAD", style: TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24, runSpacing: 12,
            children: [
              _LegendItem(color: _getActivityColor(ActivityType.INSPECCION), text: "Inspección", icon: Icons.search_outlined),
              _LegendItem(color: _getActivityColor(ActivityType.PRUEBA), text: "Prueba", icon: Icons.science_outlined),
              _LegendItem(color: _getActivityColor(ActivityType.MANTENIMIENTO), text: "Mantenimiento", icon: Icons.build_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

// --- WIDGET AUXILIAR PARA LOS BOTONES DEL HEADER ---
class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _HeaderActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(4), // Padding pequeño para el touch area
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), // Fondo muy suave
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3), width: 0.5),
          ),
          child: Icon(
            icon,
            size: 14, // Icono pequeño
            color: color,
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  final IconData icon;
  
  const _LegendItem({required this.color, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: color, width: 3))),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}