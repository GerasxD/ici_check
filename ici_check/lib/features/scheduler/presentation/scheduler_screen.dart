import 'package:flutter/material.dart';
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

  // Paleta de colores mejorada
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

  Future<void> _loadAllData() async {
    try {
      final pList = await _policiesRepo.getPoliciesStream().first;
      final p = pList.firstWhere((element) => element.id == widget.policyId);
      
      final cList = await _clientsRepo.getClientsStream().first;
      final c = cList.firstWhere((element) => element.id == p.clientId);
      
      final devs = await _devicesRepo.getDevicesStream().first;

      if (mounted) {
        setState(() {
          _policy = p;
          _client = c;
          _deviceDefinitions = devs;
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

  int _getFrequencyMonths(Frequency freq) {
    switch (freq) {
      case Frequency.DIARIO:
      case Frequency.SEMANAL:
        return 0;
      case Frequency.MENSUAL:
        return 1;
      case Frequency.TRIMESTRAL:
        return 3;
      case Frequency.SEMESTRAL:
        return 6;
      case Frequency.ANUAL:
        return 12;
      // ignore: unreachable_switch_default
      default:
        return 12;
    }
  }

  bool _isScheduled(PolicyDevice devInstance, String activityId, int timeIndex) {
    try {
      final def = _deviceDefinitions.firstWhere((d) => d.id == devInstance.definitionId);
      final activity = def.activities.firstWhere((a) => a.id == activityId);

      int freqMonths = _getFrequencyMonths(activity.frequency);
      double offset = (devInstance.scheduleOffsets[activityId] ?? 0).toDouble();
      double currentTime = _viewMode == 'monthly' ? timeIndex.toDouble() : timeIndex / 4.0;
      double adjustedTime = currentTime - offset;

      if (adjustedTime < -0.05) return false;
      double remainder = adjustedTime % freqMonths;
      return remainder < 0.05 || (remainder - freqMonths).abs() < 0.05;
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
      int freqMonths = _getFrequencyMonths(activity.frequency);

      if (freqMonths == 0) return;

      double timeValue = _viewMode == 'monthly' ? timeIdx.toDouble() : timeIdx / 4.0;

      double minDiff = 1000;
      double bestBase = 0;
      for (int k = -5; k < 20; k++) {
        double base = k * freqMonths.toDouble();
        double diff = (timeValue - base).abs();
        if (diff < minDiff) {
          minDiff = diff;
          bestBase = base;
        }
      }

      dev.scheduleOffsets[activityId] = (timeValue - bestBase).toInt();
      _hasChanges = true;
    });
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
              CircularProgressIndicator(color: _primaryBlue),
              const SizedBox(height: 16),
              Text(
                'Cargando cronograma...',
                style: TextStyle(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
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
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black12,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: _textPrimary, size: 20),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Volver',
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
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.business_outlined, size: 12, color: _textSecondary),
              const SizedBox(width: 4),
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
        ],
      ),
      actions: [
        if (_hasChanges)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_successGreen, _successGreen.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _successGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await _policiesRepo.savePolicy(_policy);
                    setState(() {
                      _hasChanges = false;
                      _isEditing = false;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 12),
                              Text("Cambios guardados exitosamente"),
                            ],
                          ),
                          backgroundColor: _successGreen,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.save_outlined, size: 18, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          "GUARDAR",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
            tooltip: _isEditing ? 'Desactivar edición' : 'Activar edición',
            style: IconButton.styleFrom(
              backgroundColor: _isEditing
                  ? _primaryBlue.withOpacity(0.1)
                  : Colors.transparent,
            ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'monthly',
                          label: const Text("MENSUAL"),
                          icon: const Icon(Icons.calendar_view_month_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: 'weekly',
                          label: const Text("SEMANAL"),
                          icon: const Icon(Icons.view_week_outlined, size: 18),
                        ),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (val) => setState(() => _viewMode = val.first),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) {
                            if (states.contains(WidgetState.selected)) {
                              return _primaryBlue;
                            }
                            return Colors.transparent;
                          },
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith<Color>(
                          (states) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.white;
                            }
                            return _textSecondary;
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 14, color: _primaryBlue),
                        const SizedBox(width: 6),
                        Text(
                          "PERIODO",
                          style: TextStyle(
                            color: _primaryBlue,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${dateFormat.format(_policy.startDate)} - ${dateFormat.format(_policy.startDate.add(Duration(days: _policy.durationMonths * 30)))}",
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${_policy.durationMonths} meses",
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isEditing) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Modo edición activado. Haz clic en las celdas para programar actividades.",
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            // Header fijo
            Container(
              color: _primaryDark,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(80),
                  columnWidths: const {0: FixedColumnWidth(280)},
                  children: [
                    TableRow(
                      children: [
                        TableCell(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: const Text(
                              "DISPOSITIVOS Y ACTIVIDADES",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
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
            // Contenido con scroll
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(80),
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

  Widget _buildTimeHeader(int index) {
    DateTime date = _policy.startDate.add(
        Duration(days: _viewMode == 'monthly' ? (index * 30) : (index * 7)));
    String label = _viewMode == 'monthly'
        ? DateFormat('MMM', 'es').format(date).toUpperCase()
        : "S${index + 1}";

    return TableCell(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "'${date.year.toString().substring(2)}",
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TableRow> _buildDataRows() {
    List<TableRow> rows = [];

    for (int dIdx = 0; dIdx < _policy.devices.length; dIdx++) {
      final devInstance = _policy.devices[dIdx];
      final def = _deviceDefinitions.firstWhere((d) => d.id == devInstance.definitionId);

      // Fila de dispositivo
      rows.add(TableRow(
        decoration: BoxDecoration(
          color: _primaryDark.withOpacity(0.05),
          border: Border(
            top: BorderSide(color: _borderLight, width: 2),
          ),
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
                    child: Icon(
                      Icons.devices_outlined,
                      size: 16,
                      color: _primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      def.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...List.generate(
            _viewMode == 'monthly' ? _policy.durationMonths : _policy.durationMonths * 4,
            (index) => TableCell(
              child: Container(
                color: _primaryDark.withOpacity(0.02),
              ),
            ),
          ),
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
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _getActivityColor(activity.type),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activity.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: _textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...List.generate(
              _viewMode == 'monthly' ? _policy.durationMonths : _policy.durationMonths * 4,
              (tIdx) {
                bool active = _isScheduled(devInstance, activity.id, tIdx);
                return TableCell(
                  child: InkWell(
                    onTap: () => _handleCellClick(dIdx, activity.id, tIdx),
                    hoverColor: _isEditing ? _primaryBlue.withOpacity(0.05) : Colors.transparent,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? _getActivityColor(activity.type).withOpacity(0.08)
                            : Colors.transparent,
                      ),
                      child: active
                          ? _buildStatusCircle(activity.type)
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
              },
            ),
          ],
        ));
      }
    }
    return rows;
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.INSPECCION:
        return const Color(0xFF3B82F6); // Azul
      case ActivityType.PRUEBA:
        return const Color(0xFFF59E0B); // Ámbar
      case ActivityType.MANTENIMIENTO:
        return const Color(0xFFEC4899); // Rosa
    }
  }

  Widget _buildStatusCircle(ActivityType type) {
    Color color = _getActivityColor(type);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TIPOS DE ACTIVIDAD",
            style: TextStyle(
              color: _textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _LegendItem(
                color: _getActivityColor(ActivityType.INSPECCION),
                text: "Inspección",
                icon: Icons.search_outlined,
              ),
              _LegendItem(
                color: _getActivityColor(ActivityType.PRUEBA),
                text: "Prueba",
                icon: Icons.science_outlined,
              ),
              _LegendItem(
                color: _getActivityColor(ActivityType.MANTENIMIENTO),
                text: "Mantenimiento",
                icon: Icons.build_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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