import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/reports/services/location_import_service.dart';

class ImportLocationsWidget extends StatefulWidget {
  final String? selectedClientId;
  final List<dynamic> selectedDevices;
  final Map<String, String> definitionNames;
  final Function(Map<String, Map<int, LocationData>>?) onImportChanged;

  const ImportLocationsWidget({
    super.key,
    required this.selectedClientId,
    required this.selectedDevices,
    required this.definitionNames,
    required this.onImportChanged,
  });

  @override
  State<ImportLocationsWidget> createState() => _ImportLocationsWidgetState();
}

// Modelo para el panel de confirmación
class _EquipmentMatch {
  final String definitionId;
  final String deviceName;
  final int unitsInNewPolicy;    // cuántas unidades tiene el usuario en la nueva póliza
  final int unitsToImport;       // cuántas unidades tienen datos para importar
  final bool hasMatch;           // si existe en la póliza fuente con datos

  _EquipmentMatch({
    required this.definitionId,
    required this.deviceName,
    required this.unitsInNewPolicy,
    required this.unitsToImport,
    required this.hasMatch,
  });
}

class _ImportLocationsWidgetState extends State<ImportLocationsWidget> {
  final LocationImportService _importService = LocationImportService();

  bool _isLoading = false;
  bool _isLoadingPreview = false;
  List<Map<String, dynamic>> _previousPolicies = [];
  // ignore: unused_field
  String? _selectedPolicyId;
  Map<String, Map<int, LocationData>>? _importedLocations;
  List<LocationPreviewItem> _preview = [];
  bool _hasSearched = false;

  // ── NUEVO: estado de confirmación pendiente ──
  String? _pendingPolicyId;
  Map<String, Map<int, LocationData>>? _pendingLocations;
  List<LocationPreviewItem> _pendingPreview = [];
  List<_EquipmentMatch> _confirmationMatches = [];

  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _primaryDark = Color(0xFF0F172A);
  static const Color _textSlate = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _bgLight = Color(0xFFF8FAFC);

  @override
  void didUpdateWidget(covariant ImportLocationsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Si cambió el cliente, resetear todo
    if (widget.selectedClientId != oldWidget.selectedClientId) {
      setState(() {
        _previousPolicies = [];
        _selectedPolicyId = null;
        _importedLocations = null;
        _preview = [];
        _hasSearched = false;
        _pendingPolicyId = null;
        _pendingLocations = null;
        _pendingPreview = [];
        _confirmationMatches = [];
      });
      widget.onImportChanged(null);
      return;
    }

    // ── NUEVO: Si cambiaron las cantidades/devices, recalcular matches sin resetear ──
    final oldIds = oldWidget.selectedDevices
        .map((d) => '${d.definitionId}:${d.quantity}')
        .join(',');
    final newIds = widget.selectedDevices
        .map((d) => '${d.definitionId}:${d.quantity}')
        .join(',');

    if (oldIds != newIds) {
      // Recalcular preview con los nuevos quantities
      if (_pendingLocations != null) {
        setState(() {
          _confirmationMatches = _buildConfirmationMatches(_pendingLocations!);
        });
      }
      // Recalcular también si ya hay importación confirmada
      if (_importedLocations != null) {
        _recalculateConfirmedPreview();
      }
    }
  }

  Future<void> _recalculateConfirmedPreview() async {
    if (_importedLocations == null) return;
    final preview = await _importService.getImportPreview(
      importedLocations: _importedLocations!,
      newDevices: widget.selectedDevices,
      definitionNames: widget.definitionNames,
    );
    if (mounted) {
      setState(() => _preview = preview);
    }
  }

  Future<void> _searchPreviousPolicies() async {
    if (widget.selectedClientId == null) return;
    setState(() => _isLoading = true);
    final policies = await _importService.getPreviousPoliciesForClient(
      widget.selectedClientId!,
    );
    if (mounted) {
      setState(() {
        _previousPolicies = policies;
        _isLoading = false;
        _hasSearched = true;
      });
    }
  }

  // ── MODIFICADO: ahora solo carga datos y construye el panel de confirmación ──
  Future<void> _selectPolicyForPreview(String policyId) async {
    setState(() {
      _pendingPolicyId = policyId;
      _isLoadingPreview = true;
    });

    try {
      final locations = await _importService.extractLocationsFromPolicy(policyId);
      final preview = await _importService.getImportPreview(
        importedLocations: locations,
        newDevices: widget.selectedDevices,
        definitionNames: widget.definitionNames,
      );

      // Construir lista de coincidencias por equipo
      final matches = _buildConfirmationMatches(locations);

      if (mounted) {
        setState(() {
          _pendingLocations = locations;
          _pendingPreview = preview;
          _confirmationMatches = matches;
          _isLoadingPreview = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando preview: $e');
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _pendingPolicyId = null;
        });
      }
    }
  }

  // ── NUEVO: construye la lista de equipos con/sin coincidencia agrupada ──
  List<_EquipmentMatch> _buildConfirmationMatches(
    Map<String, Map<int, LocationData>> locations,
  ) {
    final List<_EquipmentMatch> result = [];

    // 1. Agrupar los dispositivos por definitionId para sumar sus cantidades totales
    // Esto previene que salgan filas separadas (ej. 1/1) si el mismo equipo se agregó en lotes.
    final Map<String, int> groupedQuantities = {};
    for (final device in widget.selectedDevices) {
      final defId = device.definitionId as String;
      final qty = device.quantity as int;
      groupedQuantities[defId] = (groupedQuantities[defId] ?? 0) + qty;
    }

    // 2. Construir los matches basados en los equipos ya agrupados
    for (final entry in groupedQuantities.entries) {
      final defId = entry.key;
      final totalQty = entry.value;
      final name = widget.definitionNames[defId] ?? 'Desconocido';

      final defLocations = locations[defId];
      int unitsWithData = 0;

      if (defLocations != null) {
        // 3. Contar de manera segura iterando sobre los valores reales
        // ignorando si las llaves en la póliza fuente son secuenciales o no.
        final validOldLocations = defLocations.values.where((loc) {
          return (loc.customId.isNotEmpty || loc.area.isNotEmpty);
        }).length;
        
        // Topamos la cantidad a importar con la cantidad total requerida en la nueva póliza
        unitsWithData = validOldLocations > totalQty ? totalQty : validOldLocations;
      }

      result.add(_EquipmentMatch(
        definitionId: defId,
        deviceName: name,
        unitsInNewPolicy: totalQty,
        unitsToImport: unitsWithData,
        hasMatch: unitsWithData > 0,
      ));
    }

    // Ordenar: primero los que tienen coincidencia
    result.sort((a, b) {
      if (a.hasMatch && !b.hasMatch) return -1;
      if (!a.hasMatch && b.hasMatch) return 1;
      return a.deviceName.compareTo(b.deviceName);
    });

    return result;
  }

  // ── NUEVO: confirmar y aplicar importación ──
  void _confirmImport() {
    if (_pendingLocations == null) return;
    setState(() {
      _selectedPolicyId = _pendingPolicyId;
      _importedLocations = _pendingLocations;
      _preview = _pendingPreview;
      _pendingPolicyId = null;
      _pendingLocations = null;
      _pendingPreview = [];
      _confirmationMatches = [];
    });
    widget.onImportChanged(_importedLocations);
  }

  // ── NUEVO: cancelar selección pendiente ──
  void _cancelPending() {
    setState(() {
      _pendingPolicyId = null;
      _pendingLocations = null;
      _pendingPreview = [];
      _confirmationMatches = [];
    });
  }

  void _clearImport() {
    setState(() {
      _selectedPolicyId = null;
      _importedLocations = null;
      _preview = [];
      _pendingPolicyId = null;
      _pendingLocations = null;
      _pendingPreview = [];
      _confirmationMatches = [];
    });
    widget.onImportChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Divider(height: 1, color: _borderColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade50, Colors.transparent],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.history_rounded, color: Colors.amber.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importar Ubicaciones',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _primaryDark),
                ),
                Text(
                  'Reutiliza IDs y ubicaciones de una póliza anterior',
                  style: TextStyle(fontSize: 12, color: _textSlate),
                ),
              ],
            ),
          ),
          if (_importedLocations != null)
            IconButton(
              onPressed: _clearImport,
              icon: Icon(Icons.close, color: _textSlate, size: 20),
              tooltip: 'Quitar importación',
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (widget.selectedClientId == null) {
      return _buildInfoMessage(
        Icons.info_outline,
        'Selecciona un cliente en el Paso 1 para buscar pólizas anteriores.',
        Colors.blue,
      );
    }

    // Importación ya confirmada
    if (_importedLocations != null && _preview.isNotEmpty) {
      return _buildImportSummary();
    }

    // ── NUEVO: panel de confirmación pendiente ──
    if (_pendingPolicyId != null && _confirmationMatches.isNotEmpty) {
      return _buildConfirmationPanel();
    }

    if (_hasSearched && _previousPolicies.isEmpty) {
      return _buildInfoMessage(
        Icons.folder_off_outlined,
        'No se encontraron pólizas anteriores para este cliente.',
        Colors.grey,
      );
    }

    if (_previousPolicies.isNotEmpty) {
      return _buildPolicySelector();
    }

    return _buildSearchButton();
  }

  // ── NUEVO: panel de confirmación con coincidencias ──
  Widget _buildConfirmationPanel() {
    final matchCount = _confirmationMatches.where((m) => m.hasMatch).length;
    final noMatchCount = _confirmationMatches.where((m) => !m.hasMatch).length;
    final totalUnits = _confirmationMatches.fold<int>(0, (s, m) => s + m.unitsToImport);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner resumen
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revisa qué se importará',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalUnits unidades con datos · $matchCount tipo${matchCount != 1 ? 's' : ''} con coincidencia'
                      '${noMatchCount > 0 ? ' · $noMatchCount sin datos' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Lista de equipos con/sin coincidencia
        Text(
          'Equipos en tu nueva póliza:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _textSlate,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),

        ..._confirmationMatches.map((match) => _buildMatchRow(match)),

        const SizedBox(height: 16),

        // Botones de acción
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cancelPending,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Cambiar póliza'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textSlate,
                  side: BorderSide(color: _borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: totalUnits > 0 ? _confirmImport : null,
                icon: const Icon(Icons.download_done_rounded, size: 16),
                label: Text('Importar $totalUnits ubicaciones'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── NUEVO: fila individual de equipo con indicador visual ──
  Widget _buildMatchRow(_EquipmentMatch match) {
    final bool full = match.unitsToImport == match.unitsInNewPolicy;
    final bool partial = match.unitsToImport > 0 && !full;
    final bool none = !match.hasMatch;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (full) {
      statusColor = Colors.green.shade600;
      statusIcon = Icons.check_circle_rounded;
      statusLabel = '${match.unitsToImport}/${match.unitsInNewPolicy} unidades';
    } else if (partial) {
      statusColor = Colors.orange.shade600;
      statusIcon = Icons.info_rounded;
      statusLabel = '${match.unitsToImport}/${match.unitsInNewPolicy} unidades';
    } else {
      statusColor = Colors.grey.shade400;
      statusIcon = Icons.cancel_rounded;
      statusLabel = 'Sin datos anteriores';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: none ? _bgLight : statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: none ? _borderColor : statusColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              match.deviceName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: none ? _textSlate : _primaryDark,
              ),
            ),
          ),
          // Barra de progreso mini
          if (!none) ...[
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: match.unitsInNewPolicy > 0
                      ? match.unitsToImport / match.unitsInNewPolicy
                      : 0,
                  backgroundColor: statusColor.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isLoading ? null : _searchPreviousPolicies,
        icon: _isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accentBlue),
              )
            : const Icon(Icons.search, size: 18),
        label: Text(_isLoading ? 'Buscando...' : 'Buscar pólizas anteriores de este cliente'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accentBlue,
          side: BorderSide(color: _accentBlue.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildPolicySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecciona la póliza fuente:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primaryDark),
        ),
        const SizedBox(height: 12),
        ..._previousPolicies.map((policy) {
          final isSelected = _pendingPolicyId == policy['id'];
          final isLoading = _isLoadingPreview && isSelected;
          final startDate = policy['startDate'] as DateTime;
          final durationMonths = policy['durationMonths'] as int;
          final endDate = DateTime(
            startDate.year,
            startDate.month + durationMonths,
            startDate.day,
          ).subtract(const Duration(days: 1));

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isLoadingPreview ? null : () => _selectPolicyForPreview(policy['id']),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? _accentBlue.withOpacity(0.08) : _bgLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _accentBlue : _borderColor,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? _accentBlue.withOpacity(0.15) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.description_outlined,
                        size: 18,
                        color: isSelected ? _accentBlue : _textSlate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(startDate)} — ${DateFormat('dd/MM/yyyy').format(endDate)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _primaryDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${policy['deviceTypes']} tipos de equipo · ${policy['totalUnits']} unidades',
                            style: TextStyle(fontSize: 11, color: _textSlate),
                          ),
                        ],
                      ),
                    ),
                    if (isLoading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _accentBlue),
                      )
                    else
                      Icon(
                        isSelected ? Icons.chevron_right : Icons.chevron_right,
                        color: isSelected ? _accentBlue : Colors.grey.shade400,
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        TextButton.icon(
          onPressed: _searchPreviousPolicies,
          icon: Icon(Icons.refresh, size: 14, color: _textSlate),
          label: Text('Volver a buscar', style: TextStyle(fontSize: 12, color: _textSlate)),
        ),
      ],
    );
  }

  Widget _buildImportSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_preview.length} ubicaciones listas para importar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Se aplicarán automáticamente al crear la póliza',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(
            'Ver detalle de importación',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accentBlue),
          ),
          leading: Icon(Icons.list_alt, color: _accentBlue, size: 20),
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _preview.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: _borderColor),
                itemBuilder: (ctx, i) {
                  final item = _preview[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: _accentBlue.withOpacity(0.1),
                      child: Text(
                        '${item.unitIndex}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _accentBlue),
                      ),
                    ),
                    title: Text(
                      item.customId.isNotEmpty ? item.customId : 'Sin ID',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _primaryDark),
                    ),
                    subtitle: Text(
                      '${item.deviceName} · ${item.area.isNotEmpty ? item.area : "Sin ubicación"}',
                      style: TextStyle(fontSize: 11, color: _textSlate),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoMessage(IconData icon, String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.withOpacity(0.6), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: color.withOpacity(0.8)),
            ),
          ),
        ],
      ),
    );
  }
}