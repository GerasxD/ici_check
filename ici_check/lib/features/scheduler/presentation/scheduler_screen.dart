import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/auth/data/users_repository.dart';
import 'package:ici_check/features/notifications/data/notification_model.dart';
import 'package:ici_check/features/notifications/data/notification_service.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/presentation/service_report_screen.dart';
import 'package:ici_check/features/reports/services/pdf_generator_service.dart';
import 'package:ici_check/features/reports/services/schedule_pdf_service.dart';
import 'package:ici_check/features/settings/data/settings_repository.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/policies/data/policies_repository.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/clients/data/clients_repository.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/devices/data/devices_repository.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

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

  final ScrollController _headerScrollCtrl = ScrollController();
  final ScrollController _bodyScrollCtrl = ScrollController();

  bool _isLoading = true;
  bool _isEditing = false;
  bool _hasChanges = false;
  String _viewMode = 'monthly';

  late PolicyModel _policy;
  ClientModel? _client;
  List<DeviceModel> _deviceDefinitions = [];

  final UsersRepository _usersRepo = UsersRepository();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

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

    // ✅ SINCRONIZACIÓN BIDIRECCIONAL
    _bodyScrollCtrl.addListener(() {
      if (_headerScrollCtrl.hasClients &&
          !_headerScrollCtrl.position.isScrollingNotifier.value) {
        _headerScrollCtrl.jumpTo(_bodyScrollCtrl.offset);
      }
    });

    _headerScrollCtrl.addListener(() {
      if (_bodyScrollCtrl.hasClients &&
          !_bodyScrollCtrl.position.isScrollingNotifier.value) {
        _bodyScrollCtrl.jumpTo(_headerScrollCtrl.offset);
      }
    });

    _loadAllData();
  }

  @override
  void dispose() {
    _headerScrollCtrl.dispose();
    _bodyScrollCtrl.dispose();
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

      List<UserModel> allUsers = [];
      try {
        // ✅ getUsers() con .get() directo — no depende de caché del stream
        allUsers = await _usersRepo.getUsers();
        debugPrint("✅ Usuarios cargados directamente: ${allUsers.length}");
      } catch (e) {
        debugPrint("❌ Error con getUsers(), intentando stream: $e");
        try {
          allUsers = await _usersRepo.getUsersStream().first;
        } catch (e2) {
          debugPrint("❌ Error también con stream: $e2");
        }
      }

      // Filtro más flexible - incluir cualquier usuario que NO sea solo lectura
      final techs = allUsers
          .where(
            (u) =>
                u.role == UserRole.TECHNICIAN ||
                u.role == UserRole.ADMIN ||
                u.role == UserRole.SUPER_USER,
          )
          .toList();

      // ✅ DEBUG: Verificar cuántos técnicos se cargaron
      debugPrint("✅ Técnicos cargados: ${techs.length}");
      for (var tech in techs) {
        debugPrint("  - ${tech.name} (${tech.role})");
      }

      // ⚠️ ALERTA SI NO SE CARGARON TÉCNICOS
      if (techs.isEmpty && allUsers.isNotEmpty) {
        debugPrint(
          "⚠️ Se cargaron ${allUsers.length} usuarios pero NINGUNO es técnico/admin",
        );
        for (var u in allUsers) {
          debugPrint("   Usuario: ${u.name} - Rol: ${u.role}");
        }
      }

      _reportsSub?.cancel();
      _reportsSub = FirebaseFirestore.instance
          .collection('reports')
          .where('policyId', isEqualTo: widget.policyId)
          .snapshots()
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
          _allTechnicians = techs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error loading scheduler: $e");
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

  // ✅ NUEVO MÉTODO: Determinar el estado de una actividad en un reporte
  String _getActivityStatusForReport(
    Map<String, dynamic>? report,
    PolicyDevice devInstance,
    ActivityConfig activity,
  ) {
    // Paso 1: Si no hay reporte, está vacío
    if (report == null) return 'empty';

    // Paso 2: Verificar si el servicio fue iniciado
    final String? startTime = report['startTime'];
    final bool serviceInitiated = startTime != null && startTime.isNotEmpty;
    if (!serviceInitiated) return 'empty';

    // Paso 3: Verificar entries
    if (report['entries'] == null || report['entries'] is! List) {
      return 'partial';
    }

    final entries = report['entries'] as List;

    // Filtrar TODAS las entradas que corresponden a este tipo de dispositivo
    final entryList = entries
        .where((e) => e['instanceId'] == devInstance.instanceId)
        .toList();

    if (entryList.isEmpty) return 'partial';

    // ✅ FIX: Contadores para el estado REAL
    int totalWithActivity = 0;
    int answeredCount = 0;

    for (var entry in entryList) {
      if (entry['results'] == null || entry['results'] is! Map) continue;

      final results = entry['results'] as Map;

      // Solo contar si esta actividad existe en los results de esta entrada
      if (!results.containsKey(activity.id)) continue;

      totalWithActivity++;

      final resValue = results[activity.id];

      // Verificación estricta: null y 'NR' NO son respuestas válidas
      if (resValue != null &&
          resValue != 'NR' &&
          (resValue == 'OK' || resValue == 'NOK' || resValue == 'NA')) {
        answeredCount++;
      }
    }

    // Paso 4: Estado basado en contadores
    if (totalWithActivity == 0) return 'partial';

    if (answeredCount == 0) {
      return 'partial';                          // Ninguna respondida
    } else if (answeredCount == totalWithActivity) {
      return 'full';                             // ✅ TODAS respondidas → completo
    } else {
      return 'partial';                          // Algunas respondidas → incompleto
    }
  }

  double _getFrequencyMonths(Frequency freq) {
    switch (freq) {
      case Frequency.DIARIO:
        return 0;
      case Frequency.SEMANAL:
        return 0.25;
      case Frequency.MENSUAL:
        return 1.0;
      case Frequency.TRIMESTRAL:
        return 3.0;
      case Frequency.CUATRIMESTRAL: // <--- AGREGA ESTO
        return 4.0; // <--- 4.0 Meses
      case Frequency.SEMESTRAL:
        return 6.0;
      case Frequency.ANUAL:
        return 12.0;
      // ignore: unreachable_switch_default
      default:
        return 12.0;
    }
  }

  bool _isScheduled(
    PolicyDevice devInstance,
    String activityId,
    int timeIndex,
  ) {
    try {
      final def = _deviceDefinitions.firstWhere(
        (d) => d.id == devInstance.definitionId,
      );
      final activity = def.activities.firstWhere((a) => a.id == activityId);

      // Ahora freqMonths es double (ej: 0.25 para semanal)
      double freqMonths = _getFrequencyMonths(activity.frequency);

      // Si es 0 (ej: diario), retornamos false para evitar errores
      if (freqMonths == 0) return false;

      double offset = (devInstance.scheduleOffsets[activityId] ?? 0).toDouble();

      // En mensual: timeIndex es 0, 1, 2... (Meses)
      // En semanal: timeIndex es 0, 1, 2... dividimos entre 4 para obtener "Meses" (0, 0.25, 0.5...)
      double currentTime = _viewMode == 'monthly'
          ? timeIndex.toDouble()
          : timeIndex / 4.0;

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
      final def = _deviceDefinitions.firstWhere(
        (d) => d.id == dev.definitionId,
      );
      final activity = def.activities.firstWhere((a) => a.id == activityId);

      double freqMonths = _getFrequencyMonths(activity.frequency);

      if (freqMonths == 0) return;

      double timeValue = _viewMode == 'monthly'
          ? timeIdx.toDouble()
          : timeIdx / 4.0;

      double minDiff = 1000;
      double bestBase = 0;

      // Buscamos el múltiplo de frecuencia más cercano al clic
      for (int k = -5; k < 50; k++) {
        // Aumenté el rango por si acaso
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

  Future<void> _showScheduleDialog(
    DateTime baseDate,
    String label,
    String dateKey,
  ) async {
    // Variables locales para el estado del diálogo
    DateTime selectedDate = baseDate;
    List<String> selectedTechIds = [];
    bool isSaving = false;

    // Intentar buscar datos existentes en Firebase para pre-llenar
    try {
      final qSnapshot = await _db
          .collection('reports')
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 450, // Ancho máximo similar a max-w-md
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- HEADER ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC), // slate-50
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1E293B),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF94A3B8),
                            ),
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
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 1,
                              ),
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
                                        colorScheme: ColorScheme.fromSeed(
                                          seedColor: _primaryBlue,
                                        ),
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
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 18,
                                      color: _primaryBlue,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      DateFormat(
                                        'dd MMMM yyyy',
                                        'es',
                                      ).format(selectedDate),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // 2. TÉCNICOS ASIGNADOS
                            const Text(
                              "TÉCNICOS ASIGNADOS",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: _allTechnicians.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final tech = _allTechnicians[index];
                                  final isAssigned = selectedTechIds.contains(
                                    tech.id,
                                  );

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
                                        color: isAssigned
                                            ? const Color(0xFFEFF6FF)
                                            : Colors.white, // blue-50
                                        border: Border.all(
                                          color: isAssigned
                                              ? const Color(0xFF60A5FA)
                                              : Colors.grey.shade200,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          // Avatar
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor:
                                                Colors.grey.shade200,
                                            child: Text(
                                              tech.name.isNotEmpty
                                                  ? tech.name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Nombre y Estado
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tech.name,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF1E293B),
                                                  ),
                                                ),
                                                // Mostrar estado si no está asignado
                                                if (!isAssigned && !isAvailable)
                                                  // ignore: dead_code
                                                  const Text(
                                                    "OCUPADO EN OTRO SERVICIO",
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.redAccent,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (isAssigned)
                                            Icon(
                                              Icons.check_circle,
                                              color: _primaryBlue,
                                              size: 18,
                                            ),
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
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              "CANCELAR",
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF0F172A,
                              ), // slate-900
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            onPressed: (selectedTechIds.isEmpty || isSaving)
                                ? null
                                : () async {
                                    setModalState(() => isSaving = true);

                                    await _saveScheduleToFirebase(
                                      dateKey,
                                      selectedDate,
                                      selectedTechIds,
                                    );

                                    if (mounted) {
                                      Navigator.pop(ctx); // Cerrar modal
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                            "Programación guardada exitosamente",
                                          ),
                                          backgroundColor: _successGreen,
                                        ),
                                      );
                                    }
                                  },
                            child: isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    "GUARDAR PROGRAMACIÓN",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
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

  Future<void> _saveScheduleToFirebase(
    String dateKey,
    DateTime serviceDate,
    List<String> techIds,
  ) async {
    try {
      final reportsRef = _db.collection('reports');

      // Verificar si ya existe
      final qSnapshot = await reportsRef
          .where('policyId', isEqualTo: _policy.id)
          .where('dateStr', isEqualTo: dateKey)
          .limit(1)
          .get();

      if (qSnapshot.docs.isNotEmpty) {
        // --- ACTUALIZAR EXISTENTE ---
        final docId = qSnapshot.docs.first.id;
        await reportsRef.doc(docId).update({
          'serviceDate': Timestamp.fromDate(serviceDate),
          'assignedTechnicianIds': techIds,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // --- CREAR NUEVO CON ENTRIES GENERADAS ---

        // ✅ CALCULAR SI ES SEMANAL Y EL ÍNDICE DE TIEMPO
        bool isWeekly = dateKey.contains('W');
        int timeIndex = 0;

        if (!isWeekly) {
          // Para mensual: calcular meses desde el inicio
          try {
            final parts = dateKey.split('-');
            if (parts.length == 2) {
              final reportYear = int.parse(parts[0]);
              final reportMonth = int.parse(parts[1]);
              timeIndex =
                  (reportYear - _policy.startDate.year) * 12 +
                  (reportMonth - _policy.startDate.month);
            }
          } catch (e) {
            debugPrint('Error parseando dateStr: $e');
          }
        } else {
          // Para semanal: extraer número de semana
          try {
            final weekNum = int.tryParse(dateKey.split('W').last) ?? 1;
            timeIndex = weekNum - 1;
          } catch (e) {
            debugPrint('Error parseando semana: $e');
          }
        }

        // ✅ GENERAR ENTRIES USANDO LA LÓGICA EXISTENTE DEL REPOSITORIO
        List<Map<String, dynamic>> generatedEntries = [];

        for (var devInstance in _policy.devices) {
          final def = _deviceDefinitions.firstWhere(
            (d) => d.id == devInstance.definitionId,
            orElse: () => DeviceModel(
              id: 'err',
              name: 'Unknown',
              description: '',
              activities: [],
            ),
          );

          if (def.id == 'err') continue;

          for (int i = 1; i <= devInstance.quantity; i++) {
            Map<String, String?> activityResults = {};

            for (var act in def.activities) {
              bool isDue = false;

              if (isWeekly) {
                if (act.frequency == Frequency.SEMANAL) {
                  isDue = true;
                }
              } else {
                if (act.frequency != Frequency.SEMANAL) {
                  double freqMonths = _getFrequencyMonths(act.frequency);
                  int offset = devInstance.scheduleOffsets[act.id] ?? 0;
                  double adjustedTime = timeIndex - offset.toDouble();
                  const double epsilon = 0.05;

                  if (adjustedTime >= -epsilon) {
                    double remainder = (adjustedTime % freqMonths).abs();
                    if (remainder < epsilon ||
                        (remainder - freqMonths).abs() < epsilon) {
                      isDue = true;
                    }
                  }
                }
              }

              if (isDue) {
                activityResults[act.id] = null;
              }
            }

            // Agregar entrada
            generatedEntries.add({
              'instanceId': devInstance.instanceId,
              'deviceIndex': i,
              'customId': "${def.name.substring(0, 3).toUpperCase()}-$i",
              'area': '',
              'results': activityResults,
              'observations': '',
              'photoUrls': [],
              'activityData': {},
              'assignedUserId': null,
            });
          }
        }

        // ✅ CREAR REPORTE COMPLETO
        await reportsRef.add({
          'policyId': _policy.id,
          'dateStr': dateKey,
          'serviceDate': Timestamp.fromDate(serviceDate),
          'startTime': null, // Sin iniciar aún
          'endTime': null,
          'assignedTechnicianIds': techIds,
          'entries': generatedEntries, // ✅ ESTO ES LO QUE FALTABA
          'generalObservations': '',
          'providerSignature': null,
          'clientSignature': null,
          'providerSignerName': null,
          'clientSignerName': null,
          'sectionAssignments': {},
          'status': 'draft',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // ✅ ENVIAR NOTIFICACIONES A LOS TÉCNICOS ASIGNADOS
        if (techIds.isNotEmpty) {
          final serviceDate_ = DateFormat('dd/MM/yyyy').format(serviceDate);
          await _notificationService.notifyServiceAssigned(
            technicianUserId: '',
            clientName: _client?.name ?? 'Cliente',
            policyId: _policy.id,
            serviceDate: serviceDate_,
          );

          for (final techId in techIds) {
            try {
              await _notificationService.createNotification(
                recipientUserId: techId,
                title: '🔧 Nuevo Servicio Asignado',
                body: 'Se te ha asignado un servicio para ${_client?.name ?? 'Cliente'} el $serviceDate_',
                type: NotificationType.SERVICE_ASSIGNED,
                data: {
                  'policyId': _policy.id,
                  'clientName': _client?.name ?? 'Cliente',
                  'dateStr': serviceDate_,
                },
              );
            } catch (e) {
              debugPrint('Error enviando notificación a técnico $techId: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error guardando programación: $e");
      rethrow;
    }
  }

  void _handleHeaderReportClick(int index) {
    DateTime columnDate;
    if (_viewMode == 'monthly') {
      columnDate = DateTime(
        _policy.startDate.year,
        _policy.startDate.month + index,
        1,
      );
    } else {
      columnDate = _policy.startDate.add(Duration(days: index * 7));
    }

    String dateKey = _viewMode == 'monthly'
        ? DateFormat('yyyy-MM').format(columnDate)
        : "${columnDate.year}-W${index + 1}";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceReportScreen(
          policyId: widget.policyId,
          dateStr: dateKey,
          policy: _policy,
          devices: _deviceDefinitions,
          users: _allTechnicians,
          client: _client!, // Agregamos el cliente
        ),
      ),
    );
  }

  Future<void> _handleHeaderDownloadClick(int index) async {
    try {
      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Obtener el reporte
      final report = _getReportForColumn(index);
      if (report == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay reporte disponible para este periodo'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Convertir el Map a ServiceReportModel
      final reportModel = ServiceReportModel.fromMap(report);

      // Obtener configuración de empresa
      final companySettings = await SettingsRepository().getSettings();

      // Generar PDF
      final pdfBytes = await PdfGeneratorService.generateServiceReport(
        report: reportModel,
        client: _client!,
        companySettings: companySettings,
        deviceDefinitions: _deviceDefinitions,
        technicians: _allTechnicians,
        policyDevices: _policy.devices,
      );

      // Cerrar indicador de carga
      Navigator.pop(context);

      // 2. Obtener directorio temporal
      if (kIsWeb) {
        // 🟢 OPCIÓN WEB: Usamos Printing.sharePdf (El navegador maneja la descarga)
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'Reporte_${_client!.name}_${reportModel.dateStr}.pdf',
        );
      } else {
        // 📱 OPCIÓN MÓVIL: Guardamos y abrimos directo
        final output = await getTemporaryDirectory();
        final fileName = 'Reporte_${_client!.name}_${reportModel.dateStr}.pdf';
        final file = File("${output.path}/$fileName");

        await file.writeAsBytes(pdfBytes);

        // Abrimos el archivo
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done) {
          throw "No se pudo abrir: ${result.message}";
        }
      }
      // --------------------------------------

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF generado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Cerrar indicador de carga si está abierto
      if (Navigator.canPop(context)) Navigator.pop(context);

      debugPrint('Error generando PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ NUEVO: Bottom sheet de acciones para tablet/mobile
  void _showColumnActionsBottomSheet(BuildContext context, int index) {
    // Calcular label de la columna para mostrarlo en el título
    DateTime date;
    if (_viewMode == 'monthly') {
      date = DateTime(
        _policy.startDate.year,
        _policy.startDate.month + index,
        _policy.startDate.day,
      );
    } else {
      date = _policy.startDate.add(Duration(days: index * 7));
    }

    String label = _viewMode == 'monthly'
        ? DateFormat('MMMM yyyy', 'es').format(date).toUpperCase()
        : "Semana ${index + 1} · ${DateFormat('dd MMM', 'es').format(date)}";

    final report = _getReportForColumn(index);
    final bool hasReport = report != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 8,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Título
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.calendar_month,
                      color: _primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          "Selecciona una acción",
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Acción 1: Programar
              _BottomSheetAction(
                icon: Icons.calendar_today_rounded,
                color: const Color(0xFF3B82F6),
                title: "Programar Servicio",
                subtitle: "Asignar fecha y técnicos para este periodo",
                onTap: () {
                  Navigator.pop(ctx);
                  _handleHeaderCalendarClick(index);
                },
              ),
              const SizedBox(height: 12),
              // Acción 2: Ver Reporte
              _BottomSheetAction(
                icon: Icons.assignment_outlined,
                color: hasReport
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFF94A3B8),
                title: "Ver / Llenar Reporte",
                subtitle: hasReport
                    ? "Reporte disponible · Toca para abrir"
                    : "Sin reporte aún · Se creará al abrir",
                badge: hasReport ? "ACTIVO" : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _handleHeaderReportClick(index);
                },
              ),
              const SizedBox(height: 12),
              // Acción 3: Descargar PDF
              _BottomSheetAction(
                icon: Icons.picture_as_pdf_rounded,
                color: const Color(0xFF10B981),
                title: "Descargar PDF",
                subtitle: hasReport
                    ? "Generar reporte en PDF"
                    : "Requiere reporte completado",
                onTap: hasReport
                    ? () {
                        Navigator.pop(ctx);
                        _handleHeaderDownloadClick(index);
                      }
                    : null, // Deshabilitado si no hay reporte
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgLight,
        body: Center(child: CircularProgressIndicator(color: _primaryBlue)),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        // ✅ SCROLL VERTICAL PRINCIPAL - Todo se mueve junto
        child: Column(
          children: [_buildHeaderInfo(), _buildGrid(), _buildLegend()],
        ),
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
        // --- NUEVO BOTÓN DE DESCARGAR CRONOGRAMA ---
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: Icon(Icons.picture_as_pdf, color: _primaryDark),
            tooltip: "Descargar Cronograma PDF",
            onPressed: () async {
              // 1. Mostrar carga
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) =>
                    const Center(child: CircularProgressIndicator()),
              );

              try {
                // 2. Obtener configuración de empresa
                final companySettings = await SettingsRepository()
                    .getSettings();

                // 3. Generar el PDF usando el servicio
                final pdfBytes = await SchedulePdfService.generateSchedule(
                  policy: _policy,
                  client: _client!,
                  deviceDefinitions: _deviceDefinitions,
                  reports:
                      _reports, // <--- Pasamos la lista cruda de mapas, no modelos
                  viewMode: _viewMode,
                  companySettings: companySettings, // Nuevo parámetro
                );

                // 4. Cerrar carga
                if (mounted) Navigator.pop(context);

                if (kIsWeb) {
                  // 🟢 WEB
                  await Printing.sharePdf(
                    bytes: pdfBytes,
                    filename: 'Cronograma_${_client?.name ?? "Cliente"}.pdf',
                  );
                } else {
                  // 📱 MÓVIL
                  final output = await getTemporaryDirectory();
                  final fileName =
                      'Cronograma_${_client?.name ?? "Cliente"}.pdf';
                  final file = File("${output.path}/$fileName");

                  await file.writeAsBytes(pdfBytes);
                  await OpenFilex.open(file.path);
                }
              } catch (e) {
                if (mounted) Navigator.pop(context); // Cerrar carga si falla
                debugPrint("Error PDF Cronograma: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Error generando PDF: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ),

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
                    SnackBar(
                      content: const Text("Guardado exitosamente"),
                      backgroundColor: _successGreen,
                    ),
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

    // 1. Calcular fecha final real (Inicio + Duración)
    // DateTime maneja el desbordamiento de años automáticamente (mes 13 = enero sig año)
    final endDate =
        DateTime(
          _policy.startDate.year,
          _policy.startDate.month + _policy.durationMonths,
          _policy.startDate.day,
        ).subtract(
          const Duration(days: 1),
        ); // Restamos 1 día para que sea exacto (ej: 1 Feb a 31 Ene)

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
                    Text(
                      "Vista del Cronograma",
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // --- AQUÍ ESTÁ EL CAMBIO DE VISIBILIDAD ---
                    // Si _policy.includeWeekly es false, mostramos solo texto o un botón deshabilitado.
                    // Si es true, mostramos el selector.
                    if (_policy.includeWeekly)
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'monthly',
                            label: Text("MENSUAL"),
                            icon: Icon(Icons.calendar_view_month, size: 16),
                          ),
                          ButtonSegment(
                            value: 'weekly',
                            label: Text("SEMANAL"),
                            icon: Icon(Icons.view_week, size: 16),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (val) =>
                            setState(() => _viewMode = val.first),
                        style: ButtonStyle(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? _primaryBlue
                                    : Colors.transparent,
                              ),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : _textSecondary,
                              ),
                        ),
                      )
                    else
                      // Si no tiene semanal, mostramos un indicador estático de "Solo Mensual"
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _primaryBlue.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_view_month,
                              size: 16,
                              color: _primaryBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "VISTA MENSUAL (Fija)",
                              style: TextStyle(
                                color: _primaryBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "PERIODO DE VIGENCIA",
                    style: TextStyle(
                      color: _primaryBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${dateFormat.format(_policy.startDate)} - ${dateFormat.format(endDate)}",
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_isEditing)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Modo edición activado: Toca las celdas para programar.",
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                    ),
                  ),
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
      // ✅ ALTURA FIJA para la tabla (ajusta según necesites)
      height: 600, // Puedes ajustar este valor o hacerlo dinámico
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
            // --- ENCABEZADO (HEADER) ---
            Container(
              color: _primaryDark,
              child: Scrollbar(
                controller: _headerScrollCtrl,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8,
                child: SingleChildScrollView(
                  controller: _headerScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(100),
                    columnWidths: const {0: FixedColumnWidth(280)},
                    children: [
                      TableRow(
                        children: [
                          TableCell(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: const Text(
                                "DISPOSITIVOS Y ACTIVIDADES",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            colCount,
                            (i) => _buildTimeHeader(i),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // --- CUERPO (BODY) ---
            Expanded(
              child: Scrollbar(
                controller: _bodyScrollCtrl,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 10,
                radius: const Radius.circular(10),
                child: SingleChildScrollView(
                  // ✅ SCROLL VERTICAL dentro de la tabla
                  scrollDirection: Axis.vertical,
                  child: Scrollbar(
                    controller: _bodyScrollCtrl,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 8,
                    notificationPredicate: (notification) =>
                        notification.depth == 1,
                    child: SingleChildScrollView(
                      controller: _bodyScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Table(
                        defaultColumnWidth: const FixedColumnWidth(100),
                        columnWidths: const {0: FixedColumnWidth(280)},
                        border: TableBorder.all(color: _borderLight, width: 1),
                        children: _buildDataRows(),
                      ),
                    ),
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

    // 1. Calcular fecha exacta de inicio de la columna
    if (_viewMode == 'monthly') {
      date = DateTime(
        _policy.startDate.year,
        _policy.startDate.month + index,
        _policy.startDate.day,
      );
    } else {
      date = _policy.startDate.add(Duration(days: index * 7));
    }

    // 2. Buscar si hay Reporte Real
    final report = _getReportForColumn(index);

    // 3. Determinar si mostramos la fecha real
    // CONDICIÓN CLAVE: Solo mostramos la fecha real si el servicio fue REALMENTE INICIADO.
    // Esto se verifica si el reporte tiene una hora de inicio (startTime).
    bool showRealDate = false;
    DateTime? serviceDate;

    if (report != null && report['serviceDate'] != null) {
      // Verificamos si el reporte fue iniciado (tiene startTime)
      String? startTime = report['startTime'];
      if (startTime != null && startTime.isNotEmpty) {
        showRealDate = true;
        serviceDate = (report['serviceDate'] as Timestamp).toDate();
      }
    }

    String labelMain = "";
    String labelSub = "";

    if (_viewMode == 'monthly') {
      // --- VISTA MENSUAL ---
      labelMain = DateFormat(
        'MMM yyyy',
        'es',
      ).format(date).toUpperCase().replaceAll('.', '');

      if (showRealDate && serviceDate != null) {
        labelSub = "Día ${DateFormat('d').format(serviceDate)}";
      } else {
        labelSub = "Día ${DateFormat('d').format(date)}";
      }
    } else {
      // --- VISTA SEMANAL ---
      labelMain = DateFormat('MMMM', 'es').format(date).toUpperCase();

      DateTime weekEnd = date.add(const Duration(days: 6));
      String startDay = DateFormat('d').format(date);
      String endDay = DateFormat('d').format(weekEnd);
      int weekNumber = index + 1;

      if (showRealDate && serviceDate != null) {
        // Solo si fue programado explícitamente (tiene técnicos) mostramos "Real"
        labelSub =
            "S$weekNumber ($startDay-$endDay) \nReal: ${DateFormat('d MMM').format(serviceDate)}";
      } else {
        // Si no, mostramos el rango estándar
        labelSub = "S$weekNumber ($startDay-$endDay)";
      }
    }

    // Color de fondo sutil para separar visualmente las semanas en el header
    Color headerBgColor = _viewMode == 'monthly'
        ? Colors.transparent
        : Colors.white.withOpacity(0.05);

    return TableCell(
      child: Container(
        color: headerBgColor,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ETIQUETA PRINCIPAL
            Text(
              labelMain,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: _viewMode == 'monthly' ? 11 : 10,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),

            // ETIQUETA SECUNDARIA
            Container(
              padding: showRealDate
                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                  : EdgeInsets.zero,
              decoration: showRealDate
                  ? BoxDecoration(
                      color: _successGreen,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                labelSub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: showRealDate
                      ? Colors.white
                      : Colors.white.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = MediaQuery.of(context).size.width;
                final isMobileOrTablet = screenWidth <= 1000;

                if (isMobileOrTablet) {
                  // 📱 MÓVIL/TABLET: Un solo botón grande que abre el bottom sheet
                  return GestureDetector(
                    onTap: () => _showColumnActionsBottomSheet(context, index),
                    child: Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "ACCIONES",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withOpacity(0.9),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 🖥️ DESKTOP: Los 3 botones originales
                return Row(
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<TableRow> _buildDataRows() {
    List<TableRow> rows = [];
    int colCount = _viewMode == 'monthly'
        ? _policy.durationMonths
        : _policy.durationMonths * 4;

    for (int dIdx = 0; dIdx < _policy.devices.length; dIdx++) {
      final devInstance = _policy.devices[dIdx];
      final def = _deviceDefinitions.firstWhere(
        (d) => d.id == devInstance.definitionId,
      );

      // Fila de dispositivo (Encabezado gris) - SE QUEDA IGUAL
      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: _primaryDark.withOpacity(0.05),
            border: Border(top: BorderSide(color: _borderLight, width: 2)),
          ),
          children: [
            TableCell(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.devices_outlined,
                        size: 16,
                        color: _primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            def.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _textSecondary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _borderLight),
                            ),
                            child: Text(
                              "${devInstance.quantity} UNIDADES",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...List.generate(
              colCount,
              (index) => TableCell(
                child: Container(color: _primaryDark.withOpacity(0.02)),
              ),
            ),
          ],
        ),
      );

      // Filas de actividades
      for (var activity in def.activities) {
        if (_viewMode == 'monthly' && activity.frequency == Frequency.SEMANAL)
          continue;
        if (_viewMode == 'weekly' && activity.frequency != Frequency.SEMANAL)
          continue;

        rows.add(
          TableRow(
            children: [
              // Celda del Nombre de la Actividad
              TableCell(
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 48,
                    top: 10,
                    bottom: 10,
                    right: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        activity.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: _textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _getActivityColor(activity.type),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            activity.type
                                    .toString()
                                    .split('.')
                                    .last
                                    .substring(0, 1)
                                    .toUpperCase() +
                                activity.type
                                    .toString()
                                    .split('.')
                                    .last
                                    .substring(1)
                                    .toLowerCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: _textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Celdas de Tiempo (Puntos)
              ...List.generate(colCount, (tIdx) {
                bool active = _isScheduled(devInstance, activity.id, tIdx);

                String status = 'empty'; // Por defecto: Vacío (no programado)

                if (active) {
                  final report = _getReportForColumn(tIdx);

                  // ✅ Usar el nuevo método simplificado
                  status = _getActivityStatusForReport(
                    report,
                    devInstance,
                    activity,
                  );
                }

                return TableCell(
                  child: InkWell(
                    onTap: () => _handleCellClick(dIdx, activity.id, tIdx),
                    hoverColor: _isEditing
                        ? _primaryBlue.withOpacity(0.05)
                        : Colors.transparent,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? _getActivityColor(activity.type).withOpacity(0.08)
                            : Colors.transparent,
                      ),
                      child: active
                          ? _buildStatusCircle(activity.type, status)
                          : (_isEditing
                                ? Icon(
                                    Icons.add_circle_outline,
                                    size: 14,
                                    color: _textSecondary.withOpacity(0.3),
                                  )
                                : null),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }
    }
    return rows;
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.INSPECCION:
        return const Color(0xFF3B82F6);
      case ActivityType.PRUEBA:
        return const Color(0xFFF59E0B);
      case ActivityType.MANTENIMIENTO:
        return const Color(0xFFEC4899);
    }
  }

  Widget _buildStatusCircle(ActivityType type, String status) {
    Color color = _getActivityColor(type);

    // Configuraciones visuales según el estado
    Color fillColor;
    Widget? internalWidget;
    double borderWidth;

    switch (status) {
      case 'full':
        // COMPLETO: Relleno sólido del color de la actividad
        fillColor = color;
        borderWidth = 0; // Sin borde cuando está completo
        break;

      case 'partial':
        // INCOMPLETO (Programado pero sin respuesta válida): Medio relleno
        fillColor = Colors.white;
        borderWidth = 2;
        internalWidget = ClipOval(
          child: Container(
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    color: color.withOpacity(
                      0.5,
                    ), // Mitad izquierda semi-coloreada
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.transparent, // Mitad derecha vacía
                  ),
                ),
              ],
            ),
          ),
        );
        break;

      default:
        // VACÍO (Proyectado): Solo borde, fondo blanco
        fillColor = Colors.white;
        borderWidth = 1.5;
    }

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: fillColor,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: borderWidth),
        boxShadow: [
          if (status == 'full') // Sombra más fuerte si está completo
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: internalWidget,
    );
  }

  Widget _buildLegend() {
    return Container(
      // Mismos márgenes que el grid para que "llegue hasta donde llega el dibujo"
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        // CENTRA EL CONTENIDO DENTRO DE LA CAJA
        child: Wrap(
          alignment: WrapAlignment.center, // Centra los items si bajan de línea
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24, // Espacio entre grupos
          runSpacing: 12,
          children: [
            // GRUPO 1: TIPOS DE ACTIVIDAD
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "ACTIVIDAD:",
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                _CompactLegendItem(
                  color: _getActivityColor(ActivityType.INSPECCION),
                  text: "Insp.",
                  icon: Icons.search,
                ),
                const SizedBox(width: 8),
                _CompactLegendItem(
                  color: _getActivityColor(ActivityType.PRUEBA),
                  text: "Prueba",
                  icon: Icons.science,
                ),
                const SizedBox(width: 8),
                _CompactLegendItem(
                  color: _getActivityColor(ActivityType.MANTENIMIENTO),
                  text: "Mant.",
                  icon: Icons.build,
                ),
              ],
            ),

            // GRUPO 2: ESTADOS (Separador visual opcional)
            Container(width: 1, height: 12, color: const Color(0xFFE2E8F0)),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "ESTADO:",
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                _CompactStatusItem(type: 'empty', text: "Vacío"),
                const SizedBox(width: 8),
                _CompactStatusItem(type: 'partial', text: "Incompleto"),
                const SizedBox(width: 8),
                _CompactStatusItem(type: 'full', text: "Completo"),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactLegendItem extends StatelessWidget {
  final Color color;
  final String text;
  final IconData icon;

  const _CompactLegendItem({
    required this.color,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color), // Icono muy pequeño
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _CompactStatusItem extends StatelessWidget {
  final String type;
  final String text;

  const _CompactStatusItem({required this.type, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10, // Círculo muy pequeño (10px)
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: type == 'full' ? const Color(0xFF64748B) : Colors.white,
            border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
          ),
          child: type == 'partial'
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(color: const Color(0xFF94A3B8)),
                      ),
                      Expanded(child: Container(color: Colors.white)),
                    ],
                  ),
                )
              : null,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
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
          padding: const EdgeInsets.all(
            4,
          ), // Padding pequeño para el touch area
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

// ignore: unused_element
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  final IconData icon;

  const _LegendItem({
    required this.color,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomSheetAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? badge;

  const _BottomSheetAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onTap == null;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDisabled ? Colors.grey.shade50 : color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDisabled
                  ? Colors.grey.shade200
                  : color.withOpacity(0.25),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDisabled
                    ? Colors.grey.shade300
                    : color.withOpacity(0.6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
