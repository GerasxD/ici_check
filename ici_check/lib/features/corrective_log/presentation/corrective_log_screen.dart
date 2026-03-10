import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ici_check/features/corrective_log/data/corrective_item_model.dart';
import 'package:ici_check/features/corrective_log/data/corrective_log_repository.dart';
import 'package:ici_check/features/corrective_log/services/corrective_log_pdf_service.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/policies/data/policy_model.dart';
import 'package:ici_check/features/clients/data/client_model.dart';
import 'package:ici_check/features/settings/data/settings_repository.dart';
import 'package:ici_check/features/reports/services/photo_storage_service.dart';

class CorrectiveLogScreen extends StatefulWidget {
  final PolicyModel policy;
  final ClientModel client;
  final List<DeviceModel> devices;

  const CorrectiveLogScreen({
    super.key,
    required this.policy,
    required this.client,
    required this.devices,
  });

  @override
  State<CorrectiveLogScreen> createState() => _CorrectiveLogScreenState();
}

class _CorrectiveLogScreenState extends State<CorrectiveLogScreen> {
  final CorrectiveLogRepository _repo = CorrectiveLogRepository();
  final PhotoStorageService _photoService = PhotoStorageService();
  final ImagePicker _picker = ImagePicker();

  List<CorrectiveItemModel> _allItems = [];
  StreamSubscription? _itemsSub;
  bool _isLoading = true;
  bool _isSyncing = false;
  String _filterStatus = 'ALL'; // ALL, PENDING, CORRECTED

  // Colores
  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _dark = Color(0xFF1E293B);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _green = Color(0xFF10B981);
  static const Color _red = Color(0xFFEF4444);
  static const Color _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    // 1. Suscribirse al stream de items
    _itemsSub = _repo.getItemsStream(widget.policy.id).listen((items) {
      if (mounted) {
        setState(() {
          _allItems = items;
          _isLoading = false;
        });
      }
    });

    // 2. Sync automático desde reportes
    _syncFromReports();
  }

  Future<void> _syncFromReports() async {
    setState(() => _isSyncing = true);
    try {
      final newCount = await _repo.syncFromReports(
        policy: widget.policy,
        deviceDefinitions: widget.devices,
      );
      if (newCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$newCount nuevos hallazgos detectados'),
            backgroundColor: _blue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error syncing: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  List<CorrectiveItemModel> get _filteredItems {
    switch (_filterStatus) {
      case 'PENDING':
        return _allItems.where((i) => !i.isCorrected).toList();
      case 'CORRECTED':
        return _allItems.where((i) => i.isCorrected).toList();
      default:
        return _allItems;
    }
  }

  int get _pendingCount => _allItems.where((i) => !i.isCorrected).length;
  int get _correctedCount => _allItems.where((i) => i.isCorrected).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bitácora de Correctivos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _dark,
              ),
            ),
            Text(
              widget.client.name,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          // Sync manual
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync, color: _blue),
              tooltip: 'Sincronizar hallazgos',
              onPressed: _syncFromReports,
            ),
          // Descargar PDF
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: _red),
            tooltip: 'Generar PDF',
            onPressed: _generatePdf,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _dark))
          : Column(
              children: [
                _buildStatsBar(),
                _buildFilterBar(),
                Expanded(
                  child: _filteredItems.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: _filteredItems.length,
                          itemBuilder: (ctx, idx) =>
                              _buildItemCard(_filteredItems[idx], idx + 1),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddManualDialog,
        backgroundColor: _dark,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STATS BAR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildStatsBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatChip(
              label: 'Total', value: _allItems.length, color: _dark),
          const SizedBox(width: 12),
          _StatChip(label: 'Pendientes', value: _pendingCount, color: _amber),
          const SizedBox(width: 12),
          _StatChip(
              label: 'Corregidos', value: _correctedCount, color: _green),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // FILTER BAR
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'Todos',
            isActive: _filterStatus == 'ALL',
            onTap: () => setState(() => _filterStatus = 'ALL'),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Pendientes',
            isActive: _filterStatus == 'PENDING',
            onTap: () => setState(() => _filterStatus = 'PENDING'),
            color: _amber,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Corregidos',
            isActive: _filterStatus == 'CORRECTED',
            onTap: () => setState(() => _filterStatus = 'CORRECTED'),
            color: _green,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ITEM CARD
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildItemCard(CorrectiveItemModel item, int number) {
    final Color levelColor = _getLevelColor(item.level);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isCorrected
              ? _green.withOpacity(0.3)
              : levelColor.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showItemDetail(item),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Header con nivel y estado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: (item.isCorrected ? _green : levelColor)
                    .withOpacity(0.05),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  // Número
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: levelColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '$number',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Nivel
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: levelColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      'NIVEL ${item.level.name}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: levelColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getStatusColor(item.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _getStatusColor(item.status),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Equipo + Área
                  Row(
                    children: [
                      if (item.deviceCustomId.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.deviceCustomId,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _dark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (item.deviceArea.isNotEmpty)
                        Expanded(
                          child: Text(
                            item.deviceArea,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Tipo de dispositivo + Actividad
                  if (item.deviceDefName.isNotEmpty)
                    Text(
                      '${item.deviceDefName} · ${item.activityName}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _dark,
                      ),
                    ),
                  if (item.problemDescription.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.problemDescription,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Footer: fecha y fotos
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(
                        dateFormat.format(item.detectionDate),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                      if (item.problemPhotoUrls.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.camera_alt,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          '${item.problemPhotoUrls.length}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                      if (item.reportedTo != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.person_outline,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          item.reportedTo!,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                      const Spacer(),
                      if (item.isCorrected)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle,
                                size: 14, color: _green),
                            const SizedBox(width: 4),
                            Text(
                              item.actualCorrectionDate != null
                                  ? dateFormat
                                      .format(item.actualCorrectionDate!)
                                  : 'Corregido',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _green,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ITEM DETAIL — Bottom sheet para editar un correctivo
  // ═══════════════════════════════════════════════════════════════════
  void _showItemDetail(CorrectiveItemModel item) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    // Controllers
    final problemCtrl = TextEditingController(text: item.problemDescription);
    final actionCtrl = TextEditingController(text: item.correctionAction);
    final reportedToCtrl = TextEditingController(text: item.reportedTo ?? '');
    final correctedByCtrl =
        TextEditingController(text: item.correctedByName ?? '');
    final observationsCtrl = TextEditingController(text: item.observations);

    // Estado local del modal
    AttentionLevel selectedLevel = item.level;
    CorrectiveStatus selectedStatus = item.status;
    DateTime? estimatedDate = item.estimatedCorrectionDate;
    DateTime? actualDate = item.actualCorrectionDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _getLevelColor(selectedLevel)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.build_circle_outlined,
                                color: _getLevelColor(selectedLevel),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.deviceCustomId.isNotEmpty
                                        ? '${item.deviceCustomId} — ${item.deviceDefName}'
                                        : 'Correctivo Manual',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: _dark,
                                    ),
                                  ),
                                  if (item.activityName.isNotEmpty)
                                    Text(
                                      item.activityName,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Color(0xFF94A3B8)),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Body scrollable
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          children: [
                            // ── SECCIÓN: Nivel de Atención ──
                            _sectionTitle('NIVEL DE ATENCIÓN'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: AttentionLevel.values.map((lvl) {
                                final isSelected = selectedLevel == lvl;
                                final color = _getLevelColor(lvl);
                                return ChoiceChip(
                                  label: Text(
                                    'Nivel ${lvl.name}',
                                    style: TextStyle(
                                      color:
                                          isSelected ? Colors.white : color,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: color,
                                  backgroundColor: color.withOpacity(0.1),
                                  onSelected: (_) {
                                    setModalState(
                                        () => selectedLevel = lvl);
                                  },
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 20),

                            // ── SECCIÓN: Estado ──
                            _sectionTitle('ESTADO'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: CorrectiveStatus.values.map((st) {
                                final isSelected = selectedStatus == st;
                                final color = _getStatusColor(st);
                                return ChoiceChip(
                                  label: Text(
                                    _getStatusLabel(st),
                                    style: TextStyle(
                                      color:
                                          isSelected ? Colors.white : color,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: color,
                                  backgroundColor: color.withOpacity(0.1),
                                  onSelected: (_) {
                                    setModalState(
                                        () => selectedStatus = st);
                                    if (st == CorrectiveStatus.CORRECTED &&
                                        actualDate == null) {
                                      actualDate = DateTime.now();
                                    }
                                  },
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 20),

                            // ── SECCIÓN: Problema ──
                            _sectionTitle('DESCRIPCIÓN DEL PROBLEMA'),
                            const SizedBox(height: 8),
                            _textField(problemCtrl, 'Describe el problema...', 3),

                            const SizedBox(height: 20),

                            // ── SECCIÓN: Acción Correctiva ──
                            _sectionTitle('ACCIÓN CORRECTIVA / SOLUCIÓN'),
                            const SizedBox(height: 8),
                            _textField(actionCtrl,
                                'Describe la acción correctiva...', 3),

                            const SizedBox(height: 20),

                            // ── SECCIÓN: Reportado a ──
                            _sectionTitle('REPORTADO A'),
                            const SizedBox(height: 8),
                            _textField(
                                reportedToCtrl, 'Nombre del responsable...', 1),

                            const SizedBox(height: 20),

                            // ── SECCIÓN: Fechas ──
                            _sectionTitle('FECHAS'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _dateButton(
                                    label: 'Corrección Estimada',
                                    date: estimatedDate,
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            estimatedDate ?? DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setModalState(
                                            () => estimatedDate = picked);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _dateButton(
                                    label: 'Corrección Real',
                                    date: actualDate,
                                    color: _green,
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            actualDate ?? DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setModalState(
                                            () => actualDate = picked);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ── SECCIÓN: Corregido por ──
                            if (selectedStatus == CorrectiveStatus.CORRECTED) ...[
                              _sectionTitle('CORREGIDO POR'),
                              const SizedBox(height: 8),
                              _textField(correctedByCtrl,
                                  'Nombre de quién corrigió...', 1),
                              const SizedBox(height: 20),
                            ],

                            // ── SECCIÓN: Observaciones ──
                            _sectionTitle('OBSERVACIONES'),
                            const SizedBox(height: 8),
                            _textField(
                                observationsCtrl, 'Notas adicionales...', 2),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                      // Footer: Guardar
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Botón eliminar
                            IconButton(
                              onPressed: () => _confirmDelete(ctx, item),
                              icon:
                                  const Icon(Icons.delete_outline, color: _red),
                              tooltip: 'Eliminar',
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 200,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final updated = item.copyWith(
                                    level: selectedLevel,
                                    status: selectedStatus,
                                    problemDescription: problemCtrl.text,
                                    correctionAction: actionCtrl.text,
                                    reportedTo: reportedToCtrl.text.isNotEmpty
                                        ? reportedToCtrl.text
                                        : null,
                                    estimatedCorrectionDate: estimatedDate,
                                    actualCorrectionDate: actualDate,
                                    correctedByName:
                                        correctedByCtrl.text.isNotEmpty
                                            ? correctedByCtrl.text
                                            : null,
                                    observations: observationsCtrl.text,
                                    updatedAt: DateTime.now(),
                                    clearReportedTo:
                                        reportedToCtrl.text.isEmpty,
                                  );
                                  _repo.saveItem(updated);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Correctivo actualizado'),
                                      backgroundColor: _green,
                                    ),
                                  );
                                },
                                icon:
                                    const Icon(Icons.save_outlined, size: 18),
                                label: const Text('Guardar',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _dark,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ADD MANUAL DIALOG
  // ═══════════════════════════════════════════════════════════════════
  void _showAddManualDialog() {
    final areaCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    AttentionLevel level = AttentionLevel.B;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_circle_outline, color: _blue, size: 22),
              SizedBox(width: 10),
              Text('Agregar Correctivo Manual',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('ÁREA / UBICACIÓN'),
              const SizedBox(height: 6),
              _textField(areaCtrl, 'Ej: Cuarto de Bombas, P3', 1),
              const SizedBox(height: 16),
              _sectionTitle('DESCRIPCIÓN DEL PROBLEMA'),
              const SizedBox(height: 6),
              _textField(descCtrl, 'Describe el hallazgo...', 3),
              const SizedBox(height: 16),
              _sectionTitle('NIVEL DE ATENCIÓN'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: AttentionLevel.values.map((lvl) {
                  final isSelected = level == lvl;
                  final color = _getLevelColor(lvl);
                  return ChoiceChip(
                    label: Text(lvl.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : color,
                          fontWeight: FontWeight.w700,
                        )),
                    selected: isSelected,
                    selectedColor: color,
                    backgroundColor: color.withOpacity(0.1),
                    onSelected: (_) => setModalState(() => level = lvl),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () {
                if (descCtrl.text.isEmpty) return;
                _repo.addManualItem(
                  policyId: widget.policy.id,
                  area: areaCtrl.text,
                  problemDescription: descCtrl.text,
                  level: level,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Correctivo agregado'),
                    backgroundColor: _blue,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _dark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Agregar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // DELETE CONFIRMATION
  // ═══════════════════════════════════════════════════════════════════
  void _confirmDelete(BuildContext parentCtx, CorrectiveItemModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _amber, size: 22),
            SizedBox(width: 10),
            Text('Eliminar correctivo', style: TextStyle(fontSize: 15)),
          ],
        ),
        content: const Text('¿Estás seguro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Cerrar confirmación
              Navigator.pop(parentCtx); // Cerrar detail sheet
              _repo.deleteItem(item.policyId, item.id);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // GENERATE PDF
  // ═══════════════════════════════════════════════════════════════════
  Future<void> _generatePdf() async {
    final pendingItems = _allItems.where((i) => !i.isCorrected).toList();

    if (pendingItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay correctivos pendientes para generar el PDF'),
          backgroundColor: _green,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final settings = await SettingsRepository().getSettings();

      await CorrectiveLogPdfService.generateAndOpen(
        items: pendingItems,
        allItems: _allItems,
        policy: widget.policy,
        client: widget.client,
        companySettings: settings,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: _red),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_outline,
                size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text(
            _filterStatus == 'CORRECTED'
                ? 'No hay correctivos finalizados'
                : _filterStatus == 'PENDING'
                    ? 'No hay correctivos pendientes'
                    : 'Sin hallazgos detectados',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los hallazgos NOK de los reportes aparecerán aquí',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════
  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint, int maxLines) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, color: _dark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    Color color = _blue,
  }) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: date != null ? color.withOpacity(0.5) : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 14, color: date != null ? color : Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(
                  date != null ? dateFormat.format(date) : 'Sin definir',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: date != null ? _dark : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(AttentionLevel level) {
    switch (level) {
      case AttentionLevel.A:
        return _red;
      case AttentionLevel.B:
        return _amber;
      case AttentionLevel.C:
        return const Color(0xFF64748B);
    }
  }

  Color _getStatusColor(CorrectiveStatus status) {
    switch (status) {
      case CorrectiveStatus.PENDING:
        return const Color(0xFF64748B);
      case CorrectiveStatus.REPORTED:
        return _amber;
      case CorrectiveStatus.IN_PROGRESS:
        return _blue;
      case CorrectiveStatus.CORRECTED:
        return _green;
    }
  }

  String _getStatusLabel(CorrectiveStatus status) {
    switch (status) {
      case CorrectiveStatus.PENDING:
        return 'Pendiente';
      case CorrectiveStatus.REPORTED:
        return 'Reportado';
      case CorrectiveStatus.IN_PROGRESS:
        return 'En Proceso';
      case CorrectiveStatus.CORRECTED:
        return 'Corregido';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.color = const Color(0xFF1E293B),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}