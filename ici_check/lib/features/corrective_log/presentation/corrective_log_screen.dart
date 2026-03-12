import 'dart:async';
  import 'dart:io';
  import 'package:flutter/foundation.dart';
  import 'package:flutter/material.dart';
  import 'package:gal/gal.dart';
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
    // ignore: unused_field
    bool _isUploadingPhoto = false;
    String _filterStatus = 'ALL';

    static const Color _bg = Color(0xFFF8FAFC);
    static const Color _dark = Color(0xFF1E293B);
    static const Color _blue = Color(0xFF3B82F6);
    static const Color _green = Color(0xFF10B981);
    static const Color _red = Color(0xFFEF4444);
    static const Color _amber = Color(0xFFF59E0B);
    // Color extra para "Corregido por Terceros"
    static const Color _purple = Color(0xFF8B5CF6);

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
      _itemsSub = _repo.getItemsStream(widget.policy.id).listen((items) {
        if (mounted) setState(() { _allItems = items; _isLoading = false; });
      });
      _syncFromReports();
    }

    Future<void> _syncFromReports() async {
      setState(() => _isSyncing = true);
      try {
        final newCount = await _repo.syncFromReports(policy: widget.policy, deviceDefinitions: widget.devices);
        if (newCount > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$newCount nuevos hallazgos detectados'), backgroundColor: _blue));
        }
      } catch (e) { debugPrint('Error syncing: $e'); }
      finally { if (mounted) setState(() => _isSyncing = false); }
    }

    List<CorrectiveItemModel> get _filteredItems {
      switch (_filterStatus) {
        case 'PENDING': return _allItems.where((i) => !i.isCorrected).toList();
        case 'CORRECTED': return _allItems.where((i) => i.isCorrected).toList();
        default: return _allItems;
      }
    }

    int get _pendingCount => _allItems.where((i) => !i.isCorrected).length;
    int get _correctedCount => _allItems.where((i) => i.isCorrected).length;

    // ═══════════════════════════════════════════════════════════════════
    // PHOTO UPLOAD
    // ═══════════════════════════════════════════════════════════════════
    Future<List<String>> _pickAndUploadPhotos(String itemId, String folder) async {
      final List<String> uploadedUrls = [];

      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: Wrap(children: [
            ListTile(leading: const Icon(Icons.camera_alt, color: _blue), title: const Text('Tomar Foto'), onTap: () => Navigator.pop(ctx, 'camera')),
            ListTile(leading: const Icon(Icons.photo_library, color: _blue), title: const Text('Seleccionar de Galería'), onTap: () => Navigator.pop(ctx, 'gallery')),
          ]),
        ),
      );
      if (source == null) return [];

      setState(() => _isUploadingPhoto = true);

      try {
        List<XFile> images = [];
        if (source == 'camera') {
          final XFile? image = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 85);
          if (image != null) {
            if (!kIsWeb) { try { await Gal.putImage(image.path, album: "ICI Check"); } catch (_) {} }
            images = [image];
          }
        } else {
          images = await _picker.pickMultiImage(maxWidth: 1200, imageQuality: 85);
        }

        for (int i = 0; i < images.length; i++) {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Row(children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: 12),
                Text('Subiendo ${i + 1} de ${images.length}...'),
              ]),
              duration: const Duration(seconds: 10),
            ));
          }
          final bytes = await images[i].readAsBytes();
          try {
            final url = await _photoService.uploadPhoto(
              photoBytes: bytes,
              reportId: 'corrective_${widget.policy.id}',
              deviceInstanceId: itemId,
              activityId: folder,
            );
            uploadedUrls.add(url);
          } catch (e) { debugPrint('Error subiendo foto: $e'); }
        }

        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (uploadedUrls.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${uploadedUrls.length} foto(s) subidas'), backgroundColor: _green));
        }
      } catch (e) {
        if (mounted) { ScaffoldMessenger.of(context).hideCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: _red)); }
      } finally { if (mounted) setState(() => _isUploadingPhoto = false); }

      return uploadedUrls;
    }

    // ═══════════════════════════════════════════════════════════════════
    // BUILD
    // ═══════════════════════════════════════════════════════════════════
    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 20), onPressed: () => Navigator.pop(context)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bitácora de Correctivos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _dark)),
            Text(widget.client.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
          actions: [
            if (_isSyncing) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _blue)))
            else IconButton(icon: const Icon(Icons.sync, color: _blue), tooltip: 'Sincronizar', onPressed: _syncFromReports),
            IconButton(icon: const Icon(Icons.picture_as_pdf, color: _red), tooltip: 'Generar PDF', onPressed: _generatePdf),
            const SizedBox(width: 8),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _dark))
            : Column(children: [
                _buildStatsBar(),
                _buildFilterBar(),
                Expanded(
                  child: _filteredItems.isEmpty
                      ? _buildEmptyState()
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisExtent: 185,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredItems.length,
                          itemBuilder: (ctx, idx) => _buildItemCard(_filteredItems[idx], idx + 1),
                        ),
                ),
              ]),
      );
    }

    Widget _buildStatsBar() {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Row(children: [
          _StatChip(label: 'Total', value: _allItems.length, color: _dark), const SizedBox(width: 8),
          _StatChip(label: 'Pendientes', value: _pendingCount, color: _amber), const SizedBox(width: 8),
          _StatChip(label: 'Corregidos', value: _correctedCount, color: _green),
        ]),
      );
    }

    Widget _buildFilterBar() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          _FilterChip(label: 'Todos', isActive: _filterStatus == 'ALL', onTap: () => setState(() => _filterStatus = 'ALL')),
          const SizedBox(width: 8),
          _FilterChip(label: 'Pendientes', isActive: _filterStatus == 'PENDING', onTap: () => setState(() => _filterStatus = 'PENDING'), color: _amber),
          const SizedBox(width: 8),
          _FilterChip(label: 'Corregidos', isActive: _filterStatus == 'CORRECTED', onTap: () => setState(() => _filterStatus = 'CORRECTED'), color: _green),
        ]),
      );
    }

    // ═══════════════════════════════════════════════════════════════════
    // ITEM CARD
    // ═══════════════════════════════════════════════════════════════════
    Widget _buildItemCard(CorrectiveItemModel item, int number) {
      final Color levelColor = _getLevelColor(item.level);
      final dateFormat = DateFormat('dd/MM/yy');
      final int totalPhotos = item.problemPhotoUrls.length + item.correctionPhotoUrls.length;

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: item.isCorrected ? _green.withOpacity(0.4) : levelColor.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: InkWell(
          onTap: () => _showItemDetail(item),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ═══ Header ═══
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: (item.isCorrected ? _green : levelColor).withOpacity(0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                child: Row(children: [
                  CircleAvatar(
                    radius: 12, backgroundColor: levelColor,
                    child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('NIVEL ${item.level.name}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: levelColor))),
                  Icon(item.isCorrected ? Icons.check_circle : Icons.pending, size: 16, color: _getStatusColor(item.status)),
                ]),
              ),

              // ═══ Body ═══
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (item.deviceCustomId.isNotEmpty) ...[
                          Text('${item.deviceCustomId} ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _dark)),
                        ],
                        Expanded(child: Text(item.deviceArea, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                      ]),
                      const SizedBox(height: 6),
                      Text(item.deviceDefName.isNotEmpty ? item.deviceDefName : 'Manual',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _dark),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      // ← ACTIVIDAD VISIBLE EN EL CARD
                      if (item.activityName.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _blue.withOpacity(0.2)),
                          ),
                          child: Text(
                            item.activityName,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _blue),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(item.problemDescription,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ),

                      // ═══ Footer ═══
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade400), const SizedBox(width: 4),
                            Text(dateFormat.format(item.detectionDate), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                          ]),
                          if (totalPhotos > 0)
                            Row(children: [
                              Icon(Icons.camera_alt, size: 12, color: Colors.grey.shade400), const SizedBox(width: 4),
                              Text('$totalPhotos', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                            ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ═══════════════════════════════════════════════════════════════════
    // ITEM DETAIL
    // ═══════════════════════════════════════════════════════════════════
    void _showItemDetail(CorrectiveItemModel item) {
      final problemCtrl = TextEditingController(text: item.problemDescription);
      final actionCtrl = TextEditingController(text: item.correctionAction);
      final reportedToCtrl = TextEditingController(text: item.reportedTo ?? '');
      final correctedByCtrl = TextEditingController(text: item.correctedByName ?? '');
      final observationsCtrl = TextEditingController(text: item.observations);

      AttentionLevel selectedLevel = item.level;
      CorrectiveStatus selectedStatus = item.status;
      DateTime? estimatedDate = item.estimatedCorrectionDate;
      DateTime? actualDate = item.actualCorrectionDate;
      List<String> problemPhotos = List<String>.from(item.problemPhotoUrls);
      List<String> correctionPhotos = List<String>.from(item.correctionPhotoUrls);

      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.88, maxChildSize: 0.95, minChildSize: 0.5,
            builder: (context, scrollController) => Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                // Header
                Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Row(children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _getLevelColor(selectedLevel).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.build_circle_outlined, color: _getLevelColor(selectedLevel), size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.deviceCustomId.isNotEmpty ? '${item.deviceCustomId} — ${item.deviceDefName}' : 'Correctivo Manual', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
                    if (item.activityName.isNotEmpty) Text(item.activityName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ])),
                  IconButton(icon: const Icon(Icons.close, color: Color(0xFF94A3B8)), onPressed: () => Navigator.pop(ctx)),
                ])),
                const Divider(height: 1),

                Expanded(child: ListView(controller: scrollController, padding: const EdgeInsets.all(20), children: [
                  // ═══ FOTOS DEL PROBLEMA (ANTES) ═══
                  _PhotoSection(
                    title: 'EVIDENCIA DEL PROBLEMA (ANTES)',
                    icon: Icons.report_problem_outlined,
                    accentColor: _red,
                    photoUrls: problemPhotos,
                    emptyMessage: 'Sin fotos del hallazgo',
                    onAddPhotos: () async {
                      final urls = await _pickAndUploadPhotos(item.id, 'problem');
                      if (urls.isNotEmpty) setModalState(() => problemPhotos.addAll(urls));
                    },
                    onDeletePhoto: (index) async {
                      final url = problemPhotos[index];
                      setModalState(() => problemPhotos.removeAt(index));
                      try { await _photoService.deletePhoto(url); } catch (_) {}
                    },
                    onViewPhoto: (url) => _showFullScreenPhoto(url),
                  ),
                  const SizedBox(height: 20),

                  // ═══ FOTOS DE CORRECCIÓN (DESPUÉS) ═══
                  _PhotoSection(
                    title: 'EVIDENCIA DE CORRECCIÓN (DESPUÉS)',
                    icon: Icons.check_circle_outline,
                    accentColor: _green,
                    photoUrls: correctionPhotos,
                    emptyMessage: 'Sin fotos de corrección',
                    onAddPhotos: () async {
                      final urls = await _pickAndUploadPhotos(item.id, 'correction');
                      if (urls.isNotEmpty) setModalState(() => correctionPhotos.addAll(urls));
                    },
                    onDeletePhoto: (index) async {
                      final url = correctionPhotos[index];
                      setModalState(() => correctionPhotos.removeAt(index));
                      try { await _photoService.deletePhoto(url); } catch (_) {}
                    },
                    onViewPhoto: (url) => _showFullScreenPhoto(url),
                  ),
                  const SizedBox(height: 24),

                  // ═══ NIVEL ═══
                  _sectionTitle('NIVEL DE ATENCIÓN'), const SizedBox(height: 8),
                  Wrap(spacing: 8, children: AttentionLevel.values.map((lvl) {
                    final sel = selectedLevel == lvl; final c = _getLevelColor(lvl);
                    return ChoiceChip(label: Text('Nivel ${lvl.name}', style: TextStyle(color: sel ? Colors.white : c, fontWeight: FontWeight.w700, fontSize: 12)), selected: sel, selectedColor: c, backgroundColor: c.withOpacity(0.1), onSelected: (_) => setModalState(() => selectedLevel = lvl));
                  }).toList()),
                  const SizedBox(height: 20),

                  // ═══ ESTADO — 4 opciones sin "Reportado" ═══
                  _sectionTitle('ESTADO'), const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: CorrectiveStatus.values.map((st) {
                      final sel = selectedStatus == st;
                      final c = _getStatusColor(st);
                      return ChoiceChip(
                        label: Text(
                          _getStatusLabel(st),
                          style: TextStyle(color: sel ? Colors.white : c, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        selected: sel,
                        selectedColor: c,
                        backgroundColor: c.withOpacity(0.1),
                        onSelected: (_) {
                          setModalState(() => selectedStatus = st);
                          // Si se marca cualquier variante de "Corregido", registrar fecha real
                          if ((st == CorrectiveStatus.CORRECTED_BY_ICISI || st == CorrectiveStatus.CORRECTED_BY_THIRD) && actualDate == null) {
                            actualDate = DateTime.now();
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  _sectionTitle('DESCRIPCIÓN DEL PROBLEMA'), const SizedBox(height: 8), _textField(problemCtrl, 'Describe el problema...', 3), const SizedBox(height: 20),
                  _sectionTitle('ACCIÓN CORRECTIVA / SOLUCIÓN'), const SizedBox(height: 8), _textField(actionCtrl, 'Describe la acción correctiva...', 3), const SizedBox(height: 20),
                  _sectionTitle('REPORTADO POR'), const SizedBox(height: 8),
                  _textField(reportedToCtrl, 'Nombre de quien reporto...', 1), const SizedBox(height: 20),

                  _sectionTitle('FECHAS'), const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _dateButton(label: 'Corrección Estimada', date: estimatedDate, onTap: () async {
                      final p = await showDatePicker(context: context, initialDate: estimatedDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (p != null) setModalState(() => estimatedDate = p);
                    })),
                    const SizedBox(width: 12),
                    Expanded(child: _dateButton(label: 'Corrección Real', date: actualDate, color: _green, onTap: () async {
                      final p = await showDatePicker(context: context, initialDate: actualDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (p != null) setModalState(() => actualDate = p);
                    })),
                  ]),
                  const SizedBox(height: 20),

                  // Mostrar "Corregido por" si el estado es cualquier variante de corregido
                  if (selectedStatus == CorrectiveStatus.CORRECTED_BY_ICISI || selectedStatus == CorrectiveStatus.CORRECTED_BY_THIRD) ...[
                    _sectionTitle('CORREGIDO POR'), const SizedBox(height: 8), _textField(correctedByCtrl, 'Nombre de quién corrigió...', 1), const SizedBox(height: 20),
                  ],

                  _sectionTitle('OBSERVACIONES'), const SizedBox(height: 8), _textField(observationsCtrl, 'Notas adicionales...', 2), const SizedBox(height: 32),
                ])),

                // Footer — Guardar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
                  child: Row(children: [
                    IconButton(onPressed: () => _confirmDelete(ctx, item), icon: const Icon(Icons.delete_outline, color: _red), tooltip: 'Eliminar'),
                    const Spacer(),
                    SizedBox(width: 200, child: ElevatedButton.icon(
                      onPressed: () {
                        final updated = item.copyWith(
                          level: selectedLevel, status: selectedStatus,
                          problemDescription: problemCtrl.text, problemPhotoUrls: problemPhotos,
                          correctionAction: actionCtrl.text, correctionPhotoUrls: correctionPhotos,
                          reportedTo: reportedToCtrl.text.isNotEmpty ? reportedToCtrl.text : null,
                          estimatedCorrectionDate: estimatedDate, actualCorrectionDate: actualDate,
                          correctedByName: correctedByCtrl.text.isNotEmpty ? correctedByCtrl.text : null,
                          observations: observationsCtrl.text, updatedAt: DateTime.now(),
                          clearReportedTo: reportedToCtrl.text.isEmpty,
                        );
                        _repo.saveItem(updated);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Correctivo actualizado'), backgroundColor: _green));
                      },
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(backgroundColor: _dark, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
                    )),
                  ]),
                ),
              ]),
            ),
          );
        }),
      );
    }

    void _showFullScreenPhoto(String url) {
      showDialog(context: context, builder: (ctx) => Dialog(
        backgroundColor: Colors.black, insetPadding: const EdgeInsets.all(16),
        child: Stack(children: [
          Center(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain,
            loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48))))),
          Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => Navigator.pop(ctx))),
        ]),
      ));
    }

    void _confirmDelete(BuildContext parentCtx, CorrectiveItemModel item) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.warning_amber_rounded, color: _amber, size: 22), SizedBox(width: 10), Text('Eliminar correctivo', style: TextStyle(fontSize: 15))]),
        content: const Text('¿Estás seguro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () { Navigator.pop(ctx); Navigator.pop(parentCtx); _repo.deleteItem(item.policyId, item.id); },
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white), child: const Text('Eliminar')),
        ],
      ));
    }

  Future<void> _generatePdf() async {
    // Verificar que haya datos
    if (_allItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay correctivos registrados'),
          backgroundColor: Color(0xFF64748B),
        ),
      );
      return;
    }

    final pendingCount = _allItems.where((i) =>
        i.status == CorrectiveStatus.PENDING ||
        i.status == CorrectiveStatus.IN_PROGRESS).length;

    final correctedCount =
        _allItems.where((i) => i.isCorrected).length;

    // Dialogo de seleccion
    final CorrectivePdfType? selected = await showDialog<CorrectivePdfType>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 10),
            Text(
              'Generar PDF',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Qué tipo de reporte deseas generar?',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),

            // Opcion 1: Pendientes
            _PdfOptionTile(
              icon: Icons.pending_actions,
              color: const Color(0xFFF59E0B),
              title: 'Pendientes y En Proceso',
              subtitle: '$pendingCount hallazgos sin resolver',
              enabled: pendingCount > 0,
              onTap: () => Navigator.pop(ctx, CorrectivePdfType.pending),
            ),
            const SizedBox(height: 10),

            // Opcion 2: Corregidos
            _PdfOptionTile(
              icon: Icons.check_circle_outline,
              color: const Color(0xFF10B981),
              title: 'Corregidos',
              subtitle: '$correctedCount hallazgos resueltos',
              enabled: correctedCount > 0,
              onTap: () => Navigator.pop(ctx, CorrectivePdfType.corrected),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );

    if (selected == null) return;

    // Generar el PDF seleccionado
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final settings = await SettingsRepository().getSettings();

      await CorrectiveLogPdfService.generateAndOpen(
        allItems: _allItems,
        policy: widget.policy,
        client: widget.client,
        companySettings: settings,
        pdfType: selected,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

    Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle), child: Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400)),
      const SizedBox(height: 16),
      Text(_filterStatus == 'CORRECTED' ? 'No hay correctivos finalizados' : _filterStatus == 'PENDING' ? 'No hay correctivos pendientes' : 'Sin hallazgos detectados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      Text('Los hallazgos NOK de los reportes aparecerán aquí', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
    ]));

    Widget _sectionTitle(String t) => Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), letterSpacing: 0.5));

    Widget _textField(TextEditingController c, String h, int m) => TextField(controller: c, maxLines: m, style: const TextStyle(fontSize: 13, color: _dark),
      decoration: InputDecoration(hintText: h, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12), filled: true, fillColor: const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _blue, width: 1.5))));

    Widget _dateButton({required String label, required DateTime? date, required VoidCallback onTap, Color color = _blue}) {
      final df = DateFormat('dd/MM/yyyy');
      return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: date != null ? color.withOpacity(0.5) : Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))), const SizedBox(height: 4),
          Row(children: [Icon(Icons.calendar_today, size: 14, color: date != null ? color : Colors.grey.shade400), const SizedBox(width: 6),
            Text(date != null ? df.format(date) : 'Sin definir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: date != null ? _dark : Colors.grey.shade400))]),
        ])));
    }

    Color _getLevelColor(AttentionLevel l) {
      switch (l) {
        case AttentionLevel.A: return _red;
        case AttentionLevel.B: return _amber;
        case AttentionLevel.C: return const Color(0xFF64748B);
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    // ESTADOS: Pendiente · En Proceso · Corregido por ICISI · Corregido por Terceros
    // ═══════════════════════════════════════════════════════════════════
    Color _getStatusColor(CorrectiveStatus s) {
      switch (s) {
        case CorrectiveStatus.PENDING:             return const Color(0xFF64748B); // Gris
        case CorrectiveStatus.IN_PROGRESS:         return _blue;                   // Azul
        case CorrectiveStatus.CORRECTED_BY_ICISI:  return _green;                  // Verde
        case CorrectiveStatus.CORRECTED_BY_THIRD:  return _purple;                 // Morado
      }
    }

    String _getStatusLabel(CorrectiveStatus s) {
      switch (s) {
        case CorrectiveStatus.PENDING:             return 'Pendiente';
        case CorrectiveStatus.IN_PROGRESS:         return 'En Proceso';
        case CorrectiveStatus.CORRECTED_BY_ICISI:  return 'Corregido por ICISI';
        case CorrectiveStatus.CORRECTED_BY_THIRD:  return 'Corregido por Terceros';
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // _PhotoSection
  // ═══════════════════════════════════════════════════════════════════════
  class _PhotoSection extends StatelessWidget {
    final String title;
    final IconData icon;
    final Color accentColor;
    final List<String> photoUrls;
    final String emptyMessage;
    final VoidCallback onAddPhotos;
    final Function(int) onDeletePhoto;
    final Function(String) onViewPhoto;

    const _PhotoSection({required this.title, required this.icon, required this.accentColor, required this.photoUrls, required this.emptyMessage, required this.onAddPhotos, required this.onDeletePhoto, required this.onViewPhoto});

    @override
    Widget build(BuildContext context) {
      return Container(
        decoration: BoxDecoration(color: accentColor.withOpacity(0.03), borderRadius: BorderRadius.circular(14), border: Border.all(color: accentColor.withOpacity(0.15))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: accentColor.withOpacity(0.06), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
            child: Row(children: [
              Icon(icon, size: 16, color: accentColor), const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.3))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('${photoUrls.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: accentColor))),
              const SizedBox(width: 8),
              InkWell(onTap: onAddPhotos, borderRadius: BorderRadius.circular(8),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_a_photo, size: 13, color: Colors.white), SizedBox(width: 4), Text('Agregar', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))]))),
            ]),
          ),
          if (photoUrls.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Center(child: Column(children: [
              Icon(Icons.image_not_supported_outlined, size: 32, color: Colors.grey.shade300), const SizedBox(height: 8),
              Text(emptyMessage, style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            ])))
          else
            Padding(padding: const EdgeInsets.all(10), child: Wrap(spacing: 8, runSpacing: 8,
              children: List.generate(photoUrls.length, (i) => _PhotoTile(url: photoUrls[i], index: i, borderColor: accentColor, onTap: () => onViewPhoto(photoUrls[i]), onDelete: () => onDeletePhoto(i))))),
        ]),
      );
    }
  }

// ═══════════════════════════════════════════════════════════════════════
  // _PhotoTile
  // ═══════════════════════════════════════════════════════════════════════
  class _PhotoTile extends StatelessWidget {
    final String url; final int index; final Color borderColor; final VoidCallback onTap; final VoidCallback onDelete;
    const _PhotoTile({required this.url, required this.index, required this.borderColor, required this.onTap, required this.onDelete});

    @override
    Widget build(BuildContext context) {
      return GestureDetector(onTap: onTap, child: Container(width: 80, height: 80,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor.withOpacity(0.4), width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Stack(fit: StackFit.expand, children: [
          
          // ▼ CÓDIGO CORREGIDO ▼
          url.startsWith('local://') 
            ? (kIsWeb 
                ? Image.network(url.replaceFirst('local://', ''), fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, __, ___) => _err())
                : Image.file(File(url.replaceFirst('local://', '')), fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, __, ___) => _err()))
            : Image.network(url, fit: BoxFit.cover, cacheWidth: 200, loadingBuilder: (c, ch, p) => p == null ? ch : Container(color: const Color(0xFFF1F5F9), child: const Center(child: CircularProgressIndicator(strokeWidth: 2))), errorBuilder: (_, __, ___) => _err()),
          // ▲ CÓDIGO CORREGIDO ▲

          Positioned(bottom: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(4)),
            child: Text('#${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
          Positioned(top: 2, right: 2, child: GestureDetector(onTap: onDelete, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.close, size: 12, color: Colors.white)))),
        ]))));
    }

    Widget _err() => Container(color: const Color(0xFFFEE2E2), child: const Center(child: Icon(Icons.broken_image, color: Color(0xFFEF4444), size: 20)));
  }
  // ═══════════════════════════════════════════════════════════════════════
  // _MiniThumbnail
  // ═══════════════════════════════════════════════════════════════════════
  // ignore: unused_element
  class _MiniThumbnail extends StatelessWidget {
    final String url; final Color borderColor; final String label;
    const _MiniThumbnail({required this.url, required this.borderColor, required this.label});

    @override
    Widget build(BuildContext context) {
      return Container(width: 48, height: 48, margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor, width: 1.5)),
        child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Stack(fit: StackFit.expand, children: [
          Image.network(url, fit: BoxFit.cover, cacheWidth: 100, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF1F5F9), child: const Icon(Icons.image, size: 16, color: Color(0xFFCBD5E1)))),
          Positioned(bottom: 0, left: 0, right: 0, child: Container(color: borderColor.withOpacity(0.85), padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white)))),
        ])));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CHIPS
  // ═══════════════════════════════════════════════════════════════════════
  class _StatChip extends StatelessWidget {
    final String label; final int value; final Color color;
    const _StatChip({required this.label, required this.value, required this.color});
    @override
    Widget build(BuildContext context) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.15))),
      child: Column(children: [Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)), Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color.withOpacity(0.8)))])));
  }

  class _FilterChip extends StatelessWidget {
    final String label; final bool isActive; final VoidCallback onTap; final Color color;
    const _FilterChip({required this.label, required this.isActive, required this.onTap, this.color = const Color(0xFF1E293B)});
    @override
    Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: isActive ? color : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: isActive ? color : Colors.grey.shade300)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isActive ? Colors.white : Colors.grey.shade600))));
  }

// ─── Widget auxiliar para las opciones del diálogo ──────────────────────────
// Pégalo al final del archivo, fuera de la clase _CorrectiveLogScreenState,
// junto a los otros widgets como _StatChip, _FilterChip, etc.

class _PdfOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _PdfOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: enabled ? const Color(0xFF1E293B) : Colors.grey)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: enabled ? color : Colors.grey)),
                ],
              ),
            ),
            if (enabled)
              Icon(Icons.arrow_forward_ios, size: 14, color: color),
          ]),
        ),
      ),
    );
  }
}