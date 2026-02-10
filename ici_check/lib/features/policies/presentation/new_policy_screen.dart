import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/clients/data/clients_repository.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/devices/data/devices_repository.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/policies/data/policies_repository.dart';
import 'package:intl/date_symbol_data_local.dart';

class NewPolicyScreen extends StatefulWidget {
  const NewPolicyScreen({super.key});

  @override
  State<NewPolicyScreen> createState() => _NewPolicyScreenState();
}

class _NewPolicyScreenState extends State<NewPolicyScreen> {
  // Repositorios
  final ClientsRepository _clientsRepo = ClientsRepository();
  final DevicesRepository _devicesRepo = DevicesRepository();
  final PoliciesRepository _policiesRepo = PoliciesRepository();
  final _uuid = const Uuid();

  // Data Loading
  bool _isLoading = true;
  List<ClientModel> _clients = [];
  List<DeviceModel> _devices = [];
  List<Map<String, dynamic>> _users = [];

  // State del Wizard
  int _currentStep = 1;
  
  // State del Formulario (Paso 1)
  String? _selectedClientId;
  DateTime _startDate = DateTime.now();
  int _durationMonths = 12;
  bool _includeWeekly = false;

  // State de Dispositivos (Paso 2)
  final Map<String, _SelectedDeviceItem> _selectedDevices = {};
  final Map<String, TextEditingController> _controllers = {};

  // State de Personal (Paso 3)
  String? _selectedUserId;

  // Colores mejorados
  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _accentBlue = const Color(0xFF3B82F6);
  final Color _bgLight = const Color(0xFFF8FAFC);
  final Color _textSlate = const Color(0xFF64748B);
  final Color _borderColor = const Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es', null).then((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _clientsRepo.getClientsStream().first,
        _devicesRepo.getDevicesStream().first,
        FirebaseFirestore.instance.collection('users').get(),
      ]);

      if (mounted) {
        setState(() {
          _clients = results[0] as List<ClientModel>;
          _devices = results[1] as List<DeviceModel>;
          
          _users = (results[2] as QuerySnapshot).docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {
              'id': d.id,
              'name': data['name'] ?? 'Usuario',
              'role': data['role'] ?? 'staff',
            };
          }).toList();
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando datos: $e');
    }
  }

  void _toggleDevice(DeviceModel def) {
    setState(() {
      if (_selectedDevices.containsKey(def.id)) {
        _selectedDevices.remove(def.id);
        _controllers.remove(def.id); // Limpiamos el controlador
      } else {
        _selectedDevices[def.id] = _SelectedDeviceItem(def: def, qty: 1);
        // Creamos el controlador inicializado en "1"
        _controllers[def.id] = TextEditingController(text: '1');
      }
    });
  }

  void _updateQty(String defId, int delta) {
    if (!_selectedDevices.containsKey(defId)) return;
    setState(() {
      final item = _selectedDevices[defId]!;
      int newQty = item.qty + delta;
      if (newQty < 1) newQty = 1;
      
      _selectedDevices[defId] = _SelectedDeviceItem(def: item.def, qty: newQty);
      
      // Actualizamos el texto visualmente para que coincida con el botón
      if (_controllers.containsKey(defId)) {
        _controllers[defId]!.text = newQty.toString();
      }
    });
  }

  // Función para manejar la escritura manual del número
  void _setManualQty(String defId, String value) {
    if (!_selectedDevices.containsKey(defId)) return;
    
    int? newQty = int.tryParse(value);
    
    if (newQty != null && newQty > 0) {
      // IMPORTANTE: Aquí NO llamamos a setState para evitar que 
      // el teclado se cierre mientras escribes. Solo actualizamos el valor lógico.
      final item = _selectedDevices[defId]!;
      _selectedDevices[defId] = _SelectedDeviceItem(def: item.def, qty: newQty);
    }
  }

  Future<void> _createPolicy() async {
    if (_selectedClientId == null || _selectedDevices.isEmpty || _selectedUserId == null) return;

    setState(() => _isLoading = true);

    try {
      // 1. Limpiar la fecha (quitar horas y minutos) para evitar desfases
      final cleanStartDate = DateTime(_startDate.year, _startDate.month, _startDate.day);

      final devicesList = _selectedDevices.values.map((item) {
        // 2. Inicializar los offsets en 0 para todas las actividades
        // Esto garantiza que la actividad comience el día exacto de la 'cleanStartDate'
        Map<String, int> initialOffsets = {};
        for (var activity in item.def.activities) {
          initialOffsets[activity.id] = 0; 
        }

        return PolicyDevice(
          instanceId: _uuid.v4(),
          definitionId: item.def.id,
          quantity: item.qty,
          scheduleOffsets: initialOffsets, // <--- AGREGAR ESTO
        );
      }).toList();

      final newPolicy = PolicyModel(
        id: _uuid.v4(),
        clientId: _selectedClientId!,
        startDate: cleanStartDate, // <--- USAR LA FECHA LIMPIA
        durationMonths: _durationMonths,
        includeWeekly: _includeWeekly,
        assignedUserIds: [_selectedUserId!],
        devices: devicesList,
      );

      await _policiesRepo.savePolicy(newPolicy);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Póliza creada exitosamente'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error creando póliza: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Error al crear póliza'),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bgLight,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: _accentBlue),
              const SizedBox(height: 16),
              Text('Cargando...', style: TextStyle(color: _textSlate)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: Text(
          'Nueva Póliza',
          style: TextStyle(
            color: _primaryDark,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: _primaryDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _borderColor, height: 1),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              // INDICADOR DE PASOS MEJORADO
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  return Container(
                    color: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 16 : 24,
                      horizontal: isMobile ? 12 : 20,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepIndicator(
                          num: 1,
                          label: 'Información',
                          isActive: _currentStep >= 1,
                          isCompleted: _currentStep > 1,
                          isMobile: isMobile,
                        ),
                        _StepLine(isCompleted: _currentStep > 1, isMobile: isMobile),
                        _StepIndicator(
                          num: 2,
                          label: 'Equipos',
                          isActive: _currentStep >= 2,
                          isCompleted: _currentStep > 2,
                          isMobile: isMobile,
                        ),
                        _StepLine(isCompleted: _currentStep > 2, isMobile: isMobile),
                        _StepIndicator(
                          num: 3,
                          label: 'Personal',
                          isActive: _currentStep >= 3,
                          isCompleted: false,
                          isMobile: isMobile,
                        ),
                      ],
                    ),
                  );
                },
              ),
              
              Divider(height: 1, color: _borderColor),

              // CONTENIDO DEL PASO
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 16 : 32),
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.1, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: _buildCurrentStep(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // FOOTER DE NAVEGACIÓN MEJORADO
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  return Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 32,
                      vertical: isMobile ? 12 : 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: _borderColor)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                if (_currentStep > 1) {
                                  setState(() => _currentStep--);
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                              icon: Icon(
                                _currentStep == 1 ? Icons.close : Icons.arrow_back,
                                size: 18,
                              ),
                              label: Text(_currentStep == 1 ? 'Cancelar' : 'Atrás'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textSlate,
                                side: BorderSide(color: _borderColor),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 12 : 24,
                                  vertical: isMobile ? 12 : 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            
                            if (_currentStep < 3)
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (_currentStep == 1 && _selectedClientId == null) {
                                    _showErrorSnackBar('Seleccione un cliente');
                                    return;
                                  }
                                  if (_currentStep == 2 && _selectedDevices.isEmpty) {
                                    _showErrorSnackBar('Seleccione al menos un equipo');
                                    return;
                                  }
                                  setState(() => _currentStep++);
                                },
                                icon: const Icon(Icons.arrow_forward, size: 18),
                                label: const Text('Siguiente'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentBlue,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 16 : 32,
                                    vertical: isMobile ? 12 : 16,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: _selectedUserId == null ? null : _createPolicy,
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Crear Póliza'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 12 : 32,
                                    vertical: isMobile ? 12 : 16,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      default: return const SizedBox();
    }
  }

  // --- PASO 1: INFORMACIÓN GENERAL ---
  Widget _buildStep1() {
    final endDate = DateTime(
      _startDate.year,
      _startDate.month + _durationMonths,
      _startDate.day,
    ).subtract(const Duration(days: 1));
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        return Container(
          key: const ValueKey(1),
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accentBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.info_outline, color: _accentBlue, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Información General',
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.w700,
                            color: _primaryDark,
                          ),
                        ),
                        Text(
                          'Configura los datos básicos de la póliza',
                          style: TextStyle(color: _textSlate, fontSize: isMobile ? 12 : 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 20 : 32),
              
              _Label('Cliente *'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor, width: 1.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedClientId,
                    isExpanded: true,
                    hint: Text('Seleccione un cliente', style: TextStyle(color: _textSlate)),
                    icon: Icon(Icons.keyboard_arrow_down, color: _textSlate),
                    items: _clients.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, style: TextStyle(color: _primaryDark)),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedClientId = v),
                  ),
                ),
              ),
              if (_clients.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade400, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'No hay clientes registrados',
                          style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: isMobile ? 16 : 24),
              
              isMobile
                  ? Column(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Fecha de Inicio *'),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(primary: _accentBlue),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (d != null) setState(() => _startDate = d);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: _borderColor, width: 1.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 18, color: _accentBlue),
                                    const SizedBox(width: 12),
                                    Text(
                                      DateFormat('dd/MM/yyyy').format(_startDate),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: _primaryDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Duración (Meses) *'),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: _durationMonths.toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                setState(() => _durationMonths = int.tryParse(v) ?? 12);
                              },
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: _primaryDark,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.all(16),
                                suffixIcon: Icon(Icons.event_repeat, color: _accentBlue),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _borderColor, width: 1.5),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _borderColor, width: 1.5),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: _accentBlue, width: 2),
                                ),
                              ),
                            )
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label('Fecha de Inicio *'),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                    builder: (context, child) {
                                      return Theme(
                                        data: Theme.of(context).copyWith(
                                          colorScheme: ColorScheme.light(primary: _accentBlue),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (d != null) setState(() => _startDate = d);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: _borderColor, width: 1.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 18, color: _accentBlue),
                                      const SizedBox(width: 12),
                                      Text(
                                        DateFormat('dd/MM/yyyy').format(_startDate),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: _primaryDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label('Duración (Meses) *'),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: _durationMonths.toString(),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  setState(() => _durationMonths = int.tryParse(v) ?? 12);
                                },
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: _primaryDark,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.all(16),
                                  suffixIcon: Icon(Icons.event_repeat, color: _accentBlue),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: _borderColor, width: 1.5),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: _borderColor, width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: _accentBlue, width: 2),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    ),

              SizedBox(height: isMobile ? 16 : 24),
              
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor, width: 1.5),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 4 : 8,
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.schedule, color: _accentBlue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Frecuencia Semanal',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isMobile ? 14 : 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(left: 32, top: 4),
                    child: Text(
                      'Habilitar revisiones semanales además de las mensuales',
                      style: TextStyle(color: _textSlate, fontSize: isMobile ? 11 : 13),
                    ),
                  ),
                  value: _includeWeekly,
                  onChanged: (v) => setState(() => _includeWeekly = v),
                  activeColor: _accentBlue,
                ),
              ),

              SizedBox(height: isMobile ? 20 : 28),
              
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accentBlue.withOpacity(0.1),
                      _accentBlue.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accentBlue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _accentBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.event_available, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vigencia Estimada',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _accentBlue,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd MMMM yyyy', 'es').format(endDate),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _accentBlue,
                              fontSize: isMobile ? 16 : 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // --- PASO 2: SELECCIÓN DE EQUIPOS ---
  Widget _buildStep2() {
    return Container(
      key: const ValueKey(2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 700;
          
          Widget catalogList = Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor, width: 1.5),
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_accentBlue.withOpacity(0.08), Colors.transparent],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: _accentBlue, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Catálogo Disponible',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _accentBlue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_devices.length}',
                          style: TextStyle(
                            color: _accentBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _borderColor),
                SizedBox(
                  height: 380,
                  child: _devices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: _textSlate.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              Text(
                                'No hay equipos disponibles',
                                style: TextStyle(color: _textSlate),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _devices.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 4),
                          itemBuilder: (ctx, i) {
                            final dev = _devices[i];
                            final isSelected = _selectedDevices.containsKey(dev.id);
                            return Material(
                              color: isSelected ? _accentBlue.withOpacity(0.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _toggleDevice(dev),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? _accentBlue.withOpacity(0.15)
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.devices_other,
                                          size: 18,
                                          color: isSelected ? _accentBlue : _textSlate,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          dev.name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                            color: isSelected ? _primaryDark : _textSlate,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? _accentBlue : Colors.grey.shade400,
                                        size: 22,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );

          Widget selectedList = Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor, width: 1.5),
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade50, Colors.transparent],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_check, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Seleccionados en Póliza',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_selectedDevices.length}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _borderColor),
                SizedBox(
                  height: 380,
                  child: _selectedDevices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 48,
                                color: _textSlate.withOpacity(0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Selecciona equipos del catálogo',
                                style: TextStyle(color: _textSlate),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _selectedDevices.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 4),
                          itemBuilder: (ctx, i) {
                            final item = _selectedDevices.values.elementAt(i);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      item.def.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _borderColor),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Botón Menos (-)
                                        IconButton(
                                          onPressed: () => _updateQty(item.def.id, -1),
                                          icon: const Icon(Icons.remove, size: 18),
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          color: _textSlate,
                                        ),
                                        // CAMBIO PRINCIPAL: Campo de texto en lugar de Text
                                        SizedBox(
                                          width: 50,
                                          child: TextFormField(
                                            // USAMOS EL CONTROLADOR
                                            controller: _controllers[item.def.id],
                                            
                                            // IMPORTANTE: Key estática (solo ID) para que no pierda el foco al escribir
                                            key: ValueKey(item.def.id), 
                                            
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(vertical: 8),
                                              border: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                            ),
                                            // AHORA SE GUARDA MIENTRAS ESCRIBES
                                            onChanged: (val) => _setManualQty(item.def.id, val),
                                          ),
                                        ),                                    
                                        // Botón Más (+)
                                        IconButton(
                                          onPressed: () => _updateQty(item.def.id, 1),
                                          icon: const Icon(Icons.add, size: 18),
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          color: _accentBlue,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: catalogList),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 200),
                  child: Icon(Icons.arrow_forward, color: _textSlate, size: 28),
                ),
                Expanded(child: selectedList),
              ],
            );
          } else {
            return Column(
              children: [
                catalogList,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Icon(Icons.arrow_downward, color: _textSlate, size: 28),
                ),
                selectedList,
              ],
            );
          }
        },
      ),
    );
  }

  // --- PASO 3: PERSONAL ---
  Widget _buildStep3() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final crossAxisCount = constraints.maxWidth < 500 ? 1 : constraints.maxWidth < 800 ? 2 : 3;
        
        return Container(
          key: const ValueKey(3),
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.people_outline, color: Colors.purple.shade600, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Asignar Responsable',
                          style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.w700,
                            color: _primaryDark,
                          ),
                        ),
                        Text(
                          'Selecciona al coordinador de mantenimiento',
                          style: TextStyle(
                            color: _textSlate,
                            fontSize: isMobile ? 12 : 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 20 : 32),
              
              if (_users.isEmpty)
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.person_off_outlined, size: 64, color: _textSlate.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'No hay usuarios registrados',
                        style: TextStyle(color: _textSlate, fontSize: 16),
                      ),
                    ],
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 1.3,
                    crossAxisSpacing: isMobile ? 12 : 16,
                    mainAxisSpacing: isMobile ? 12 : 16,
                  ),
                  itemCount: _users.length,
                  itemBuilder: (ctx, i) {
                    final u = _users[i];
                    final isSelected = _selectedUserId == u['id'];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedUserId = u['id']),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? _accentBlue.withOpacity(0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? _accentBlue : _borderColor,
                            width: isSelected ? 2.5 : 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: _accentBlue.withOpacity(0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        padding: EdgeInsets.all(isMobile ? 12 : 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isSelected
                                      ? _accentBlue
                                      : Colors.grey.shade200,
                                  foregroundColor: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                  radius: isMobile ? 24 : 32,
                                  child: Text(
                                    (u['name'] as String)[0].toUpperCase(),
                                    style: TextStyle(
                                      fontSize: isMobile ? 18 : 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade500,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        size: isMobile ? 12 : 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: isMobile ? 8 : 12),
                            Text(
                              u['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: isMobile ? 13 : 14,
                                color: isSelected ? _accentBlue : _primaryDark,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: isMobile ? 2 : 4),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 8 : 10,
                                vertical: isMobile ? 3 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _accentBlue.withOpacity(0.15)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                u['role'],
                                style: TextStyle(
                                  color: isSelected ? _accentBlue : _textSlate,
                                  fontSize: isMobile ? 10 : 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                )
            ],
          ),
        );
      },
    );
  }
}

// --- CLASE AUXILIAR LOCAL PARA STATE ---
class _SelectedDeviceItem {
  final DeviceModel def;
  final int qty;
  _SelectedDeviceItem({required this.def, required this.qty});
}

// --- WIDGETS UI MEJORADOS ---
class _StepIndicator extends StatelessWidget {
  final int num;
  final String label;
  final bool isActive;
  final bool isCompleted;
  final bool isMobile;
  
  const _StepIndicator({
    required this.num,
    required this.label,
    required this.isActive,
    required this.isCompleted,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = const Color(0xFF3B82F6);
    final Color completedColor = Colors.green.shade600;
    final Color inactiveColor = Colors.grey.shade300;
    
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isMobile ? 32 : 36,
          height: isMobile ? 32 : 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? completedColor
                : isActive
                    ? activeColor
                    : Colors.white,
            border: Border.all(
              color: isCompleted
                  ? completedColor
                  : isActive
                      ? activeColor
                      : inactiveColor,
              width: 2,
            ),
            boxShadow: isActive || isCompleted
                ? [
                    BoxShadow(
                      color: (isCompleted ? completedColor : activeColor).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, color: Colors.white, size: isMobile ? 16 : 18)
                : Text(
                    '$num',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w700,
                      fontSize: isMobile ? 14 : 16,
                    ),
                  ),
          ),
        ),
        SizedBox(width: isMobile ? 6 : 10),
        Text(
          label,
          style: TextStyle(
            color: isCompleted
                ? completedColor
                : isActive
                    ? activeColor
                    : Colors.grey,
            fontWeight: FontWeight.w600,
            fontSize: isMobile ? 12 : 14,
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool isCompleted;
  final bool isMobile;
  
  const _StepLine({this.isCompleted = false, this.isMobile = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isMobile ? 30 : 60,
      height: 3,
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.shade600 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(2),
      ),
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
        letterSpacing: 0.3,
      ),
    );
  }
}