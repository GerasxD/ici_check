import 'package:flutter/material.dart';
import 'package:ici_check/features/policies/presentation/new_policy_screen.dart';
import 'package:ici_check/features/scheduler/presentation/scheduler_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart'; // Para formatear fechas
import 'package:uuid/uuid.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/clients/data/clients_repository.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/devices/data/devices_repository.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/policies/data/policies_repository.dart';

class PoliciesScreen extends StatefulWidget {
  const PoliciesScreen({super.key});

  @override
  State<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends State<PoliciesScreen> {
  final PoliciesRepository _policiesRepo = PoliciesRepository();
  final ClientsRepository _clientsRepo = ClientsRepository();
  final DevicesRepository _devicesRepo = DevicesRepository();

  List<ClientModel> _allClients = [];
  List<DeviceModel> _allDeviceDefinitions = [];
  bool _isLoadingData = true;

  final Color _primaryDark = const Color(0xFF0F172A);
  final Color _accentBlue = const Color(0xFF2563EB);
  final Color _bgLight = const Color(0xFFF1F5F9);
  final Color _textSlate = const Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es', null).then((_) => _loadAuxiliaryData());
  }

  Future<void> _loadAuxiliaryData() async {
    try {
      final clients = await _clientsRepo.getClientsStream().first;
      final devices = await _devicesRepo.getDevicesStream().first;

      if (mounted) {
        setState(() {
          _allClients = clients;
          _allDeviceDefinitions = devices;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint("Error cargando datos auxiliares: $e");
    }
  }

  void _openPolicyEditor({PolicyModel? policy}) {
    // CASO 1: EDITAR (Si recibimos una póliza, abrimos el Diálogo rápido)
    if (policy != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PolicyEditorDialog(
          policyToEdit: policy,
          clients: _allClients,
          deviceDefinitions: _allDeviceDefinitions,
          onSave: (p) async {
            await _policiesRepo.savePolicy(p);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Póliza actualizada correctamente'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      );
    } 
    // CASO 2: CREAR NUEVA (Si policy es null, vamos al Wizard paso a paso)
    else {
      Navigator.push(
        context, 
        MaterialPageRoute(builder: (context) => const NewPolicyScreen())
      );
    }
  }

  void _handleDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Póliza?'),
        content: const Text(
          'Se eliminará el contrato y su seguimiento. No afecta reportes históricos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              _policiesRepo.deletePolicy(id);
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _getClientName(String id) {
    final client = _allClients.where((c) => c.id == id).firstOrNull;
    return client?.name ?? 'Cliente Desconocido';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) return const Center(child: CircularProgressIndicator());

    return LayoutBuilder(
      builder: (context, constraints) {
        // Detectamos si es móvil (< 700px)
        bool isMobile = constraints.maxWidth < 700;

        return Scaffold(
          backgroundColor: _bgLight,
          // SOLUCIÓN 1: Botón Flotante en Móvil (Ya lo tienes bien aquí)
          floatingActionButton: isMobile
              ? FloatingActionButton(
                  onPressed: () => _openPolicyEditor(),
                  backgroundColor: _accentBlue,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
          body: Column(
            children: [
              // HEADER RESPONSIVO
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Título Flexible
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pólizas',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _primaryDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Gestión y seguimiento de contratos',
                            style: TextStyle(color: _textSlate),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    
                    // SOLUCIÓN 2: Ocultar botón del Header en Móvil
                    // Solo mostramos este bloque si NO es móvil
                    if (!isMobile) ...[
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openPolicyEditor(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nueva Póliza'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    ],
                  ],
                ),
              ),

              // LISTA (El resto del código sigue igual)
              Expanded(
                child: StreamBuilder<List<PolicyModel>>(
                  stream: _policiesRepo.getPoliciesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting)
                      return const Center(child: CircularProgressIndicator());
                    final policies = snapshot.data ?? [];

                    if (policies.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay pólizas activas',
                              style: TextStyle(color: _textSlate),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      // Padding extra abajo en móvil para que el FAB no tape el último item
                      padding: EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 24,
                        bottom: isMobile ? 80 : 24,
                      ),
                      itemCount: policies.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final policy = policies[index];
                        final clientName = _getClientName(policy.clientId);
                        final startDateStr = DateFormat(
                          'dd MMM yyyy',
                          'es',
                        ).format(policy.startDate);
                        final endDateStr = DateFormat(
                          'dd MMM yyyy',
                          'es',
                        ).format(policy.endDate);

                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icono Cliente
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.business,
                                      color: _accentBlue,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Info Principal
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clientName,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: _primaryDark,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Vigencia: $startDateStr - $endDateStr',
                                          style: TextStyle(
                                            color: _textSlate,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Badges
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            _Badge(
                                              icon: Icons.inventory_2,
                                              text:
                                                  '${policy.devices.length} Tipos de Equipos',
                                            ),
                                            if (policy.includeWeekly)
                                              _Badge(
                                                icon: Icons.repeat,
                                                text: 'Semanal',
                                                color: Colors.purple,
                                              ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                  // Acciones
                                  PopupMenuButton(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: Colors.grey.shade400,
                                    ),
                                    onSelected: (val) {
                                      if (val == 'edit')
                                        _openPolicyEditor(policy: policy);
                                      if (val == 'delete')
                                        _handleDelete(policy.id);
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 18),
                                            SizedBox(width: 8),
                                            Text('Editar'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Eliminar',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(),
                              // Botón Acción Principal
                              SizedBox(
                                width: double.infinity,
                                child: TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context, 
                                      MaterialPageRoute(
                                        builder: (context) => SchedulerScreen(policyId: policy.id)
                                      )
                                    );
                                  },
                                  icon: const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 18,
                                  ),
                                  label: const Text(
                                    'Ver Cronograma de Servicios',
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _primaryDark,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    backgroundColor: Colors.grey.shade50,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final MaterialColor color;

  const _Badge({
    required this.icon,
    required this.text,
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// --- DIALOGO DE EDICIÓN (MODAL AVANZADO) ---
class _PolicyEditorDialog extends StatefulWidget {
  final PolicyModel? policyToEdit;
  final List<ClientModel> clients;
  final List<DeviceModel> deviceDefinitions;
  final Function(PolicyModel) onSave;

  const _PolicyEditorDialog({
    this.policyToEdit,
    required this.clients,
    required this.deviceDefinitions,
    required this.onSave,
  });

  @override
  State<_PolicyEditorDialog> createState() => _PolicyEditorDialogState();
}

class _PolicyEditorDialogState extends State<_PolicyEditorDialog> {
  final _uuid = const Uuid();

  late String _clientId;
  late DateTime _startDate;
  late int _durationMonths;
  late bool _includeWeekly;
  late List<PolicyDevice> _devices;

  String? _selectedDeviceDefId; // Para el dropdown de agregar

  @override
  void initState() {
    super.initState();
    final p = widget.policyToEdit;
    // Si editamos, usamos datos existentes. Si es nuevo, defaults.
    _clientId =
        p?.clientId ??
        (widget.clients.isNotEmpty ? widget.clients.first.id : '');
    _startDate = p?.startDate ?? DateTime.now();
    _durationMonths = p?.durationMonths ?? 12;
    _includeWeekly = p?.includeWeekly ?? false;
    _devices = p != null ? List.from(p.devices) : [];
  }

  void _addDevice() {
    if (_selectedDeviceDefId == null) return;
    setState(() {
      _devices.add(
        PolicyDevice(
          instanceId: _uuid.v4(),
          definitionId: _selectedDeviceDefId!,
          quantity: 1,
        ),
      );
      _selectedDeviceDefId = null; // Reset dropdown
    });
  }

  void _removeDevice(int index) {
    setState(() => _devices.removeAt(index));
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      int newQ = _devices[index].quantity + delta;
      if (newQ > 0) _devices[index].quantity = newQ;
    });
  }

  @override
  Widget build(BuildContext context) {
    final endDate = DateTime(
      _startDate.year,
      _startDate.month + _durationMonths,
      _startDate.day,
    ).subtract(const Duration(days: 1));
    final endDateStr = DateFormat('dd MMM yyyy', 'es').format(endDate);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
        child: Column(
          children: [
            // Header Modal
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.policyToEdit == null
                        ? 'Nueva Póliza'
                        : 'Editar Póliza',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Body Scrollable
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cliente
                    _Label('Cliente Asociado'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _clientId.isEmpty ? null : _clientId,
                          isExpanded: true,
                          hint: const Text('Seleccionar Cliente'),
                          items: widget.clients
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _clientId = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Fechas
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label('Fecha de Inicio'),
                              InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (d != null) setState(() => _startDate = d);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat(
                                          'dd/MM/yyyy',
                                        ).format(_startDate),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label('Duración (Meses)'),
                              TextFormField(
                                initialValue: _durationMonths.toString(),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => setState(
                                  () => _durationMonths = int.tryParse(v) ?? 12,
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Finaliza el: $endDateStr',
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),
                    // Checkbox Semanal
                    SwitchListTile(
                      title: const Text(
                        'Habilitar Frecuencia Semanal',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: const Text(
                        'Permite gestionar revisiones cada semana en el cronograma.',
                      ),
                      value: _includeWeekly,
                      onChanged: (v) => setState(() => _includeWeekly = v),
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF2563EB),
                    ),

                    const Divider(height: 40),

                    // DISPOSITIVOS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Label('Dispositivos en Póliza'),
                        // Dropdown mini para agregar
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedDeviceDefId,
                                      hint: const Text('+ Agregar Dispositivo'),
                                      isExpanded: true,
                                      items: widget.deviceDefinitions
                                          .map(
                                            (d) => DropdownMenuItem(
                                              value: d.id,
                                              child: Text(d.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) {
                                        setState(
                                          () => _selectedDeviceDefId = v,
                                        );
                                        _addDevice(); // Auto agregar al seleccionar
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_devices.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No hay dispositivos asignados',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),

                          // Lista de agregados
                          ..._devices.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final def = widget.deviceDefinitions.firstWhere(
                              (d) => d.id == item.definitionId,
                              orElse: () => DeviceModel(
                                id: '',
                                name: 'Desc.',
                                description: '',
                                activities: [],
                              ),
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      def.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        _QtyBtn(
                                          Icons.remove,
                                          () => _updateQuantity(index, -1),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Text(
                                            '${item.quantity}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        _QtyBtn(
                                          Icons.add,
                                          () => _updateQuantity(index, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _removeDevice(index),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_clientId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Selecciona un cliente'),
                          ),
                        );
                        return;
                      }
                      final newPolicy = PolicyModel(
                        id: widget.policyToEdit?.id ?? 'temp',
                        clientId: _clientId,
                        startDate: _startDate,
                        durationMonths: _durationMonths,
                        includeWeekly: _includeWeekly,
                        devices: _devices,
                        assignedUserIds:
                            widget.policyToEdit?.assignedUserIds ?? [],
                      );
                      widget.onSave(newPolicy);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('Guardar Póliza'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
      ),
    ),
  );
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 14),
    ),
  );
}
