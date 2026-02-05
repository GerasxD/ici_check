import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/reports/data/reports_repository.dart';
import 'package:signature/signature.dart'; // PAQUETE EXTERNO REQUERIDO

class ServiceReportScreen extends StatefulWidget {
  final String policyId;
  final String dateStr; // "2025-02"
  final PolicyModel policy; // Pasados desde la pantalla anterior para no recargar
  final List<DeviceModel> devices;
  final List<UserModel> users;

  const ServiceReportScreen({
    super.key,
    required this.policyId,
    required this.dateStr,
    required this.policy,
    required this.devices,
    required this.users,
  });

  @override
  State<ServiceReportScreen> createState() => _ServiceReportScreenState();
}

class _ServiceReportScreenState extends State<ServiceReportScreen> {
  final ReportsRepository _repo = ReportsRepository();
  ServiceReportModel? _report;
  bool _isLoading = true;
  bool _adminOverride = false;
  
  // Controladores de firma
  final SignatureController _providerSigController = SignatureController(penStrokeWidth: 2, penColor: Colors.black);
  final SignatureController _clientSigController = SignatureController(penStrokeWidth: 2, penColor: Colors.black);

  @override
  void initState() {
    super.initState();
    _loadOrCreateReport();
  }

  Future<void> _loadOrCreateReport() async {
    // 1. Intentar cargar
    final stream = _repo.getReportStream(widget.policyId, widget.dateStr);
    
    stream.listen((existingReport) {
      if (existingReport != null) {
        if (mounted) setState(() { _report = existingReport; _isLoading = false; });
      } else {
        // 2. Si no existe, inicializar lógica de programación
        _initializeNewReport();
      }
    });
  }

  void _initializeNewReport() {
    // Calcular índice de tiempo como en React
    bool isWeekly = widget.dateStr.contains('W');
    int timeIndex = 0;
    
    if (!isWeekly) {
      DateTime pStart = DateTime(widget.policy.startDate.year, widget.policy.startDate.month, 1);
      DateTime rDate = DateFormat('yyyy-MM').parse(widget.dateStr);
      timeIndex = (rDate.year - pStart.year) * 12 + (rDate.month - pStart.month);
    } else {
      // Lógica semanal simplificada para el ejemplo
      timeIndex = int.tryParse(widget.dateStr.split('W').last) ?? 0;
    }

    final newReport = _repo.initializeReport(widget.policy, widget.dateStr, widget.devices, isWeekly, timeIndex);
    
    // Guardar inmediatamente en Firestore
    _repo.saveReport(newReport);
    setState(() { _report = newReport; _isLoading = false; });
  }

  // --- LÓGICA DE ESTADOS Y ACTUALIZACIÓN ---

  Future<void> _saveReport() async {
    if (_report == null) return;
    
    // Convertir firmas a Base64 si fueron editadas (Lógica simplificada, idealmente subir a Storage)
    if (_providerSigController.isNotEmpty) {
      // ignore: unused_local_variable
      final bytes = await _providerSigController.toPngBytes();
      // Aquí deberías subir 'bytes' a Firebase Storage y obtener URL.
      // Por simplicidad en este ejemplo, no lo implemento completo.
    }
    
    await _repo.saveReport(_report!);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Guardado")));
  }

  void _toggleStatus(int entryIndex, String activityId) {
    if (_report == null) return;
    // Copiar estructura
    final entries = List<ReportEntry>.from(_report!.entries);
    final entry = entries[entryIndex];
    final currentResults = Map<String, String?>.from(entry.results);
    
    String? current = currentResults[activityId];
    String? next;
    
    if (current == null) next = 'OK';
    else if (current == 'OK') next = 'NOK';
    else if (current == 'NOK') next = 'NA';
    else if (current == 'NA') next = 'NR';
    else next = null;

    currentResults[activityId] = next;
    
    entries[entryIndex] = ReportEntry(
      instanceId: entry.instanceId,
      deviceIndex: entry.deviceIndex,
      customId: entry.customId,
      area: entry.area,
      results: currentResults,
      observations: entry.observations,
      photos: entry.photos,
      activityData: entry.activityData,
    );

    final updatedReport = ServiceReportModel(
      id: _report!.id,
      policyId: _report!.policyId,
      dateStr: _report!.dateStr,
      serviceDate: _report!.serviceDate,
      startTime: _report!.startTime,
      endTime: _report!.endTime,
      assignedTechnicianIds: _report!.assignedTechnicianIds,
      entries: entries,
      generalObservations: _report!.generalObservations,
      providerSignature: _report!.providerSignature,
      clientSignature: _report!.clientSignature,
      sectionAssignments: _report!.sectionAssignments,
    );

    setState(() => _report = updatedReport);
    _repo.saveReport(updatedReport); // Auto-save
  }

  void _toggleTime() {
    if (_report == null) return;
    final nowStr = DateFormat('HH:mm').format(DateTime.now());
    
    ServiceReportModel updated;
    if (_report!.startTime == null) {
      updated = ServiceReportModel(
        id: _report!.id, policyId: _report!.policyId, dateStr: _report!.dateStr, serviceDate: _report!.serviceDate,
        assignedTechnicianIds: _report!.assignedTechnicianIds, entries: _report!.entries,
        generalObservations: _report!.generalObservations, sectionAssignments: _report!.sectionAssignments,
        startTime: nowStr,
        endTime: null
      );
    } else {
      updated = ServiceReportModel(
        id: _report!.id, policyId: _report!.policyId, dateStr: _report!.dateStr, serviceDate: _report!.serviceDate,
        assignedTechnicianIds: _report!.assignedTechnicianIds, entries: _report!.entries,
        generalObservations: _report!.generalObservations, sectionAssignments: _report!.sectionAssignments,
        startTime: _report!.startTime,
        endTime: nowStr
      );
    }
    setState(() => _report = updated);
    _repo.saveReport(updated);
  }

  // --- UI BUILDING BLOCKS ---

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _report == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Agrupar por definición para mostrar secciones
    Map<String, List<ReportEntry>> grouped = {};
    for (var entry in _report!.entries) {
      final dev = widget.policy.devices.firstWhere((d) => d.instanceId == entry.instanceId);
      final defId = dev.definitionId;
      if (!grouped.containsKey(defId)) grouped[defId] = [];
      grouped[defId]!.add(entry);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Reporte de Servicio", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.dateStr, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_adminOverride ? Icons.lock_open : Icons.lock),
            onPressed: () => setState(() => _adminOverride = !_adminOverride),
            tooltip: "Modo Supervisor",
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveReport),
        ],
      ),
      body: Column(
        children: [
          _buildHeaderStatus(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...grouped.entries.map((group) => _buildSection(group.key, group.value)),
                _buildGeneralObs(),
                _buildSignatures(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatus() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text("Inicio: ${_report!.startTime ?? '--:--'}"),
              const SizedBox(width: 16),
              Text("Fin: ${_report!.endTime ?? '--:--'}"),
            ],
          ),
          ElevatedButton.icon(
            onPressed: _toggleTime,
            icon: Icon(_report!.startTime == null ? Icons.play_arrow : Icons.stop),
            label: Text(_report!.startTime == null ? "INICIAR" : "FINALIZAR"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _report!.startTime == null ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSection(String defId, List<ReportEntry> entries) {
    final def = widget.devices.firstWhere((d) => d.id == defId, orElse: () => DeviceModel(id: 'u', name: 'Unknown', description: '', activities: []));
    
    // Filtrar actividades relevantes (las que tienen scheduled results)
    final allKeys = entries.expand((e) => e.results.keys).toSet();
    final relevantActs = def.activities.where((a) => allKeys.contains(a.id)).toList();

    if (relevantActs.isEmpty) return const SizedBox();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(def.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text("${entries.length} Unidades", style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          // Tabla de dispositivos
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 48,
              columnSpacing: 20,
              columns: [
                const DataColumn(label: Text("ID", style: TextStyle(fontWeight: FontWeight.bold))),
                const DataColumn(label: Text("Ubicación", style: TextStyle(fontWeight: FontWeight.bold))),
                ...relevantActs.map((a) => DataColumn(
                  label: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(a.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(a.frequency.toString().split('.').last, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                    ],
                  )
                )),
                const DataColumn(label: Text("Obs", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: entries.asMap().entries.map((entryItem) {
                int idx = _report!.entries.indexOf(entryItem.value); // Buscar indice real en lista completa
                final e = entryItem.value;
                
                return DataRow(cells: [
                  DataCell(Text(e.customId, style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        initialValue: e.area,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: "..."),
                        onChanged: (val) {
                          // Actualizar area (similar a updateEntry)
                        },
                      ),
                    ),
                  ),
                  ...relevantActs.map((a) {
                    final status = e.results[a.id];
                    // Si no está programado para este dispositivo, celda vacía
                    if (!e.results.containsKey(a.id)) return const DataCell(SizedBox());
                    
                    return DataCell(
                      Center(
                        child: InkWell(
                          onTap: () => _toggleStatus(idx, a.id),
                          child: _buildStatusBadge(status),
                        ),
                      ),
                    );
                  }),
                  DataCell(
                    IconButton(
                      icon: Icon(e.observations.isNotEmpty ? Icons.comment : Icons.add_comment_outlined),
                      color: e.observations.isNotEmpty ? Colors.amber[700] : Colors.grey,
                      onPressed: () {
                        // Abrir modal de observaciones
                      },
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String text;
    
    switch (status) {
      case 'OK': color = Colors.black; text = "OK"; break;
      case 'NOK': color = Colors.red; text = "NOK"; break;
      case 'NA': color = Colors.grey; text = "N/A"; break;
      case 'NR': color = Colors.amber; text = "N/R"; break;
      default: return Container(
        width: 24, height: 24, 
        decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), shape: BoxShape.circle),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGeneralObs() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("OBSERVACIONES GENERALES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              controller: TextEditingController(text: _report!.generalObservations),
              onChanged: (val) {
                // Actualizar state local y guardar (debounce recomendado)
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatures() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text("FIRMAS", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text("Proveedor", style: TextStyle(fontSize: 11)),
                      Container(
                        height: 100,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                        child: Signature(controller: _providerSigController, backgroundColor: Colors.white),
                      ),
                      TextButton(onPressed: () => _providerSigController.clear(), child: const Text("Borrar")),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      const Text("Cliente", style: TextStyle(fontSize: 11)),
                      Container(
                        height: 100,
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                        child: Signature(controller: _clientSigController, backgroundColor: Colors.white),
                      ),
                      TextButton(onPressed: () => _clientSigController.clear(), child: const Text("Borrar")),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}