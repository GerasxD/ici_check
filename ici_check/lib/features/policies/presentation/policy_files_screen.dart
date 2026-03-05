import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ici_check/features/policies/data/policy_file_model.dart';
import 'package:ici_check/features/policies/data/policy_files_repository.dart';

class PolicyFilesScreen extends StatefulWidget {
  final String policyId;
  final String clientName;

  const PolicyFilesScreen({
    super.key,
    required this.policyId,
    required this.clientName,
  });

  @override
  State<PolicyFilesScreen> createState() => _PolicyFilesScreenState();
}

class _PolicyFilesScreenState extends State<PolicyFilesScreen>
    with SingleTickerProviderStateMixin {
  final PolicyFilesRepository _repo = PolicyFilesRepository();
  String _currentFolder = '';
  bool _isUploading = false;
  double _uploadProgress = 0;

  late AnimationController _fabController;
  late Animation<double> _fabScale;

  // ═══ PALETA DE COLORES REFINADA ═══
  static const Color _navy = Color(0xFF0A1628);
  static const Color _slate = Color(0xFF334155);
  static const Color _slateLight = Color(0xFF94A3B8);
  static const Color _accent = Color(0xFF2563EB);
  static const Color _accentLight = Color(0xFFDBEAFE);
  static const Color _surface = Color(0xFFF8FAFC);
  static const Color _card = Colors.white;
  static const Color _success = Color(0xFF059669);
  static const Color _danger = Color(0xFFDC2626);
  static const Color _warning = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  // SUBIR ARCHIVOS
  // ════════════════════════════════════════════

  Future<void> _pickAndUploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      int uploaded = 0;
      for (final file in result.files) {
        if (file.bytes == null || file.name.isEmpty) continue;

        await _repo.uploadFile(
          policyId: widget.policyId,
          fileName: file.name,
          fileBytes: file.bytes!,
          contentType: _getContentType(file.name),
          folder: _currentFolder,
        );

        uploaded++;
        if (mounted) {
          setState(() {
            _uploadProgress = uploaded / result.files.length;
          });
        }
      }

      if (mounted) {
        setState(() => _isUploading = false);
        _showToast('$uploaded archivo(s) subidos correctamente', _success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        _showToast('Error al subir: $e', _danger);
      }
    }
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        elevation: 8,
      ),
    );
  }

  // ════════════════════════════════════════════
  // CREAR CARPETA
  // ════════════════════════════════════════════

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => _StyledDialog(
        icon: Icons.create_new_folder_rounded,
        iconColor: _accent,
        title: 'Nueva Carpeta',
        content: _StyledTextField(
          controller: controller,
          hint: 'Nombre de la carpeta',
          autofocus: true,
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () async {
          final name = controller.text.trim();
          if (name.isNotEmpty) {
            await _repo.createFolder(
              policyId: widget.policyId,
              folderName: name,
            );
            if (ctx.mounted) Navigator.pop(ctx);
          }
        },
        confirmText: 'Crear',
      ),
    );
  }

  // ════════════════════════════════════════════
  // RENOMBRAR CARPETA
  // ════════════════════════════════════════════

  void _showRenameFolderDialog(String folderName) {
    final controller = TextEditingController(text: folderName);
    showDialog(
      context: context,
      builder: (ctx) => _StyledDialog(
        icon: Icons.drive_file_rename_outline_rounded,
        iconColor: _accent,
        title: 'Renombrar Carpeta',
        content: _StyledTextField(
          controller: controller,
          hint: 'Nuevo nombre',
          autofocus: true,
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () async {
          final newName = controller.text.trim();
          if (newName.isNotEmpty && newName != folderName) {
            await _repo.renameFolder(
              policyId: widget.policyId,
              oldName: folderName,
              newName: newName,
            );
            if (mounted && _currentFolder == folderName) {
              setState(() => _currentFolder = newName);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          }
        },
        confirmText: 'Guardar',
      ),
    );
  }

  // ════════════════════════════════════════════
  // ELIMINAR CARPETA
  // ════════════════════════════════════════════

  void _showDeleteFolderDialog(String folderName, int fileCount) {
    if (fileCount > 0) {
      _showToast(
        'Mueve los $fileCount archivo(s) antes de eliminar "$folderName"',
        _warning,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _StyledDialog(
        icon: Icons.folder_delete_rounded,
        iconColor: _danger,
        title: '¿Eliminar carpeta?',
        content: Text(
          'Se eliminará "$folderName" permanentemente.',
          style: TextStyle(fontSize: 14, color: _slate.withOpacity(0.7)),
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () async {
          await _repo.deleteFolder(
            policyId: widget.policyId,
            folderName: folderName,
          );
          if (mounted && _currentFolder == folderName) {
            setState(() => _currentFolder = '');
          }
          if (ctx.mounted) Navigator.pop(ctx);
        },
        confirmText: 'Eliminar',
        confirmColor: _danger,
      ),
    );
  }

  // ════════════════════════════════════════════
  // MOVER ARCHIVO
  // ════════════════════════════════════════════

  void _showMoveDialog(PolicyFileModel file, List<String> folders) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _accentLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.drive_file_move_rounded,
                          color: _accent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Mover archivo',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          Text(
                            file.name,
                            style: TextStyle(fontSize: 12, color: _slateLight),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: _slateLight, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: _surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              // Opciones
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      _MoveOption(
                        label: 'Sin carpeta',
                        icon: Icons.home_rounded,
                        isSelected: file.folder.isEmpty,
                        onTap: () async {
                          await _repo.moveToFolder(
                            policyId: widget.policyId,
                            fileId: file.id,
                            newFolder: '',
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                      ...folders.map((folder) => _MoveOption(
                            label: folder,
                            icon: Icons.folder_rounded,
                            isSelected: file.folder == folder,
                            onTap: () async {
                              await _repo.moveToFolder(
                                policyId: widget.policyId,
                                fileId: file.id,
                                newFolder: folder,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // RENOMBRAR ARCHIVO
  // ════════════════════════════════════════════

  void _showRenameDialog(PolicyFileModel file) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (ctx) => _StyledDialog(
        icon: Icons.edit_rounded,
        iconColor: _accent,
        title: 'Renombrar',
        content: _StyledTextField(
          controller: controller,
          hint: 'Nuevo nombre',
          autofocus: true,
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () async {
          final newName = controller.text.trim();
          if (newName.isNotEmpty) {
            await _repo.renameFile(
              policyId: widget.policyId,
              fileId: file.id,
              newName: newName,
            );
            if (ctx.mounted) Navigator.pop(ctx);
          }
        },
        confirmText: 'Guardar',
      ),
    );
  }

  // ════════════════════════════════════════════
  // ELIMINAR ARCHIVO
  // ════════════════════════════════════════════

  void _showDeleteDialog(PolicyFileModel file) {
    showDialog(
      context: context,
      builder: (ctx) => _StyledDialog(
        icon: Icons.delete_rounded,
        iconColor: _danger,
        title: '¿Eliminar archivo?',
        content: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: _slate.withOpacity(0.7)),
            children: [
              const TextSpan(text: 'Se eliminará '),
              TextSpan(
                text: '"${file.name}"',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' permanentemente.'),
            ],
          ),
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () async {
          Navigator.pop(ctx);
          await _repo.deleteFile(
            policyId: widget.policyId,
            fileId: file.id,
            fileUrl: file.url,
          );
          if (mounted) _showToast('Archivo eliminado', _warning);
        },
        confirmText: 'Eliminar',
        confirmColor: _danger,
      ),
    );
  }

  // ════════════════════════════════════════════
  // ABRIR ARCHIVO
  // ════════════════════════════════════════════

  Future<void> _openFile(PolicyFileModel file) async {
    final uri = Uri.parse(file.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) _showToast('No se puede abrir el archivo', _danger);
    }
  }

  // ════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════

  String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const map = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/msword',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.ms-excel',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.ms-powerpoint',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'txt': 'text/plain',
      'zip': 'application/zip',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  _FileStyle _getFileStyle(String contentType) {
    if (contentType.startsWith('image/')) {
      return _FileStyle(Icons.image_rounded, const Color(0xFF7C3AED), const Color(0xFFEDE9FE));
    }
    if (contentType.startsWith('video/')) {
      return _FileStyle(Icons.play_circle_rounded, const Color(0xFFDB2777), const Color(0xFFFCE7F3));
    }
    if (contentType.contains('pdf')) {
      return _FileStyle(Icons.picture_as_pdf_rounded, const Color(0xFFDC2626), const Color(0xFFFEE2E2));
    }
    if (contentType.contains('word') || contentType.contains('document')) {
      return _FileStyle(Icons.description_rounded, const Color(0xFF2563EB), const Color(0xFFDBEAFE));
    }
    if (contentType.contains('excel') || contentType.contains('spreadsheet')) {
      return _FileStyle(Icons.table_chart_rounded, const Color(0xFF059669), const Color(0xFFD1FAE5));
    }
    if (contentType.contains('presentation') || contentType.contains('powerpoint')) {
      return _FileStyle(Icons.slideshow_rounded, const Color(0xFFEA580C), const Color(0xFFFFF7ED));
    }
    if (contentType.contains('zip') || contentType.contains('compressed')) {
      return _FileStyle(Icons.folder_zip_rounded, const Color(0xFF6366F1), const Color(0xFFE0E7FF));
    }
    return _FileStyle(Icons.insert_drive_file_rounded, const Color(0xFF64748B), const Color(0xFFF1F5F9));
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'Hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays}d';
    return DateFormat('dd MMM yy', 'es').format(date);
  }

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: Column(
        children: [
          // ═══ HEADER CUSTOM ═══
          _buildHeader(),

          // ═══ BARRA DE PROGRESO ═══
          if (_isUploading)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _uploadProgress),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                backgroundColor: _accentLight,
                color: _accent,
                minHeight: 3,
              ),
            ),

          // ═══ CONTENIDO ═══
          Expanded(
            child: StreamBuilder<List<String>>(
              stream: _repo.getFoldersStream(widget.policyId),
              builder: (context, foldersSnapshot) {
                final savedFolders = foldersSnapshot.data ?? [];

                return StreamBuilder<List<PolicyFileModel>>(
                  stream: _repo.getFilesStream(widget.policyId),
                  builder: (context, filesSnapshot) {
                    if (foldersSnapshot.connectionState == ConnectionState.waiting &&
                        filesSnapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: _accent,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('Cargando archivos...',
                                style: TextStyle(color: _slateLight, fontSize: 13)),
                          ],
                        ),
                      );
                    }

                    final allFiles = filesSnapshot.data ?? [];
                    final folderSet = <String>{...savedFolders};
                    for (final f in allFiles) {
                      if (f.folder.isNotEmpty) folderSet.add(f.folder);
                    }
                    final sortedFolders = folderSet.toList()..sort();

                    if (allFiles.isEmpty && sortedFolders.isEmpty) {
                      return _buildEmptyState();
                    }

                    final rootFiles = allFiles.where((f) => f.folder.isEmpty).toList();
                    final currentFiles = _currentFolder.isEmpty
                        ? allFiles
                        : allFiles.where((f) => f.folder == _currentFolder).toList();

                    return CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        // Chips de carpetas
                        SliverToBoxAdapter(
                          child: _buildFolderChips(sortedFolders, allFiles),
                        ),

                        // Estadística rápida
                        SliverToBoxAdapter(
                          child: _buildStats(allFiles, sortedFolders),
                        ),

                        // Contenido
                        if (_currentFolder.isEmpty) ...[
                          // Carpetas
                          if (sortedFolders.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final folder = sortedFolders[index];
                                    final folderFiles = allFiles
                                        .where((f) => f.folder == folder)
                                        .toList();
                                    return _buildFolderCard(folder, folderFiles);
                                  },
                                  childCount: sortedFolders.length,
                                ),
                              ),
                            ),

                          // Separador
                          if (sortedFolders.isNotEmpty && rootFiles.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: _slateLight.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'SIN CARPETA',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _slateLight,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Archivos sin carpeta
                          if (rootFiles.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) =>
                                      _buildFileCard(rootFiles[index], sortedFolders),
                                  childCount: rootFiles.length,
                                ),
                              ),
                            ),

                          if (rootFiles.isEmpty)
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 100)),
                        ] else ...[
                          // Dentro de carpeta
                          if (currentFiles.isEmpty)
                            SliverFillRemaining(child: _buildEmptyFolder())
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) =>
                                      _buildFileCard(currentFiles[index], sortedFolders),
                                  childCount: currentFiles.length,
                                ),
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: _card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
            child: Row(
              children: [
                // Botón atrás
                IconButton(
                  onPressed: () {
                    if (_currentFolder.isNotEmpty) {
                      setState(() => _currentFolder = '');
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  icon: Icon(
                    _currentFolder.isNotEmpty
                        ? Icons.arrow_back_rounded
                        : Icons.arrow_back_rounded,
                    color: _navy,
                    size: 22,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: _surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),

                // Título
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_currentFolder.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => setState(() => _currentFolder = ''),
                              child: Text(
                                'Archivos',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.chevron_right_rounded,
                                  size: 18, color: _slateLight),
                            ),
                          ],
                          Flexible(
                            child: Text(
                              _currentFolder.isEmpty
                                  ? 'Archivos'
                                  : _currentFolder,
                              style: TextStyle(
                                fontSize: _currentFolder.isEmpty ? 20 : 16,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.clientName,
                        style: TextStyle(
                          fontSize: 12,
                          color: _slateLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Botón nueva carpeta
                Material(
                  color: _accentLight,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _showCreateFolderDialog,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(Icons.create_new_folder_rounded,
                          color: _accent, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // ESTADÍSTICAS
  // ════════════════════════════════════════════

  Widget _buildStats(List<PolicyFileModel> allFiles, List<String> folders) {
    final totalSize = allFiles.fold<int>(0, (sum, f) => sum + f.sizeBytes);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          _StatBadge(
            icon: Icons.insert_drive_file_rounded,
            value: '${allFiles.length}',
            label: 'archivos',
          ),
          const SizedBox(width: 10),
          _StatBadge(
            icon: Icons.folder_rounded,
            value: '${folders.length}',
            label: 'carpetas',
          ),
          const SizedBox(width: 10),
          _StatBadge(
            icon: Icons.data_usage_rounded,
            value: _formatFileSize(totalSize),
            label: 'total',
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // CHIPS DE CARPETAS
  // ════════════════════════════════════════════

  Widget _buildFolderChips(List<String> folders, List<PolicyFileModel> allFiles) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        children: [
          _FolderChip(
            label: 'Todos',
            count: allFiles.length,
            icon: Icons.grid_view_rounded,
            isSelected: _currentFolder.isEmpty,
            onTap: () => setState(() => _currentFolder = ''),
          ),
          const SizedBox(width: 8),
          ...folders.map((folder) {
            final count = allFiles.where((f) => f.folder == folder).length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FolderChip(
                label: folder,
                count: count,
                icon: Icons.folder_rounded,
                isSelected: _currentFolder == folder,
                onTap: () => setState(() => _currentFolder = folder),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // TARJETA DE CARPETA
  // ════════════════════════════════════════════

  Widget _buildFolderCard(String folderName, List<PolicyFileModel> files) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _currentFolder = folderName),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Ícono de carpeta con gradiente
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _accent.withOpacity(0.12),
                        _accent.withOpacity(0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.folder_rounded, color: _accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        files.isEmpty
                            ? 'Carpeta vacía'
                            : '${files.length} archivo(s) · ${_formatFileSize(files.fold<int>(0, (s, f) => s + f.sizeBytes))}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _slateLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Menú
                _buildFolderMenu(folderName, files.length),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: _slateLight, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderMenu(String folderName, int fileCount) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, color: _slateLight, size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 8,
      color: Colors.white,
      onSelected: (val) {
        if (val == 'rename') _showRenameFolderDialog(folderName);
        if (val == 'delete') _showDeleteFolderDialog(folderName, fileCount);
      },
      itemBuilder: (ctx) => [
        _buildMenuItem('rename', Icons.edit_rounded, 'Renombrar', _slate),
        _buildMenuItem(
          'delete',
          Icons.delete_rounded,
          'Eliminar',
          fileCount == 0 ? _danger : _slateLight,
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  // TARJETA DE ARCHIVO
  // ════════════════════════════════════════════

  Widget _buildFileCard(PolicyFileModel file, List<String> folders) {
    final style = _getFileStyle(file.contentType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0).withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openFile(file),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Ícono estilizado
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: style.bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(style.icon, color: style.color, size: 22),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: _navy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Tamaño
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatFileSize(file.sizeBytes),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _slateLight,
                              ),
                            ),
                          ),
                          // Carpeta (si estamos en raíz)
                          if (file.folder.isNotEmpty &&
                              _currentFolder.isEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _accentLight.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.folder_rounded,
                                      size: 10, color: _accent.withOpacity(0.7)),
                                  const SizedBox(width: 3),
                                  Text(
                                    file.folder,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: _accent.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Text(
                            _formatDate(file.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: _slateLight.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Menú
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded,
                      color: _slateLight, size: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 8,
                  color: Colors.white,
                  onSelected: (val) {
                    if (val == 'rename') _showRenameDialog(file);
                    if (val == 'move') _showMoveDialog(file, folders);
                    if (val == 'delete') _showDeleteDialog(file);
                  },
                  itemBuilder: (ctx) => [
                    _buildMenuItem('rename', Icons.edit_rounded, 'Renombrar', _slate),
                    _buildMenuItem('move', Icons.drive_file_move_rounded,
                        'Mover a carpeta', _slate),
                    _buildMenuItem(
                        'delete', Icons.delete_rounded, 'Eliminar', _danger),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // FAB
  // ════════════════════════════════════════════

  Widget _buildFAB() {
    return ScaleTransition(
      scale: _fabScale,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _isUploading ? null : _pickAndUploadFiles,
          backgroundColor: _isUploading ? _slateLight : _accent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: _isUploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add_rounded, color: Colors.white, size: 22),
          label: Text(
            _isUploading ? 'Subiendo...' : 'Subir',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // EMPTY STATES
  // ════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _accentLight.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accentLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cloud_upload_rounded,
                    size: 40, color: _accent),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Sin archivos aún',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sube documentos, fotos o cualquier\narchivo relacionado a esta póliza',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _slateLight,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _pickAndUploadFiles,
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Subir primer archivo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFolder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Icon(Icons.folder_open_rounded,
                  size: 36, color: _slateLight),
            ),
            const SizedBox(height: 20),
            Text(
              'Carpeta vacía',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sube archivos aquí o mueve\narchivos desde otra ubicación',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _slateLight, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════
// MODELOS AUXILIARES
// ════════════════════════════════════════════

class _FileStyle {
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _FileStyle(this.icon, this.color, this.bgColor);
}

// ════════════════════════════════════════════
// WIDGETS REUTILIZABLES
// ════════════════════════════════════════════

class _FolderChip extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FolderChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? const Color(0xFF2563EB) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: isSelected ? 2 : 0,
      shadowColor: const Color(0xFF2563EB).withOpacity(0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.2)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color:
                        isSelected ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0).withOpacity(0.6)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
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

class _MoveOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _MoveOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected
            ? const Color(0xFFDBEAFE)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: isSelected ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                      color: isSelected
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF334155),
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyledDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget content;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmText;
  final Color? confirmColor;

  const _StyledDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.content,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmText,
    this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = confirmColor ?? const Color(0xFF2563EB);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon + Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Content
            Align(
              alignment: Alignment.centerLeft,
              child: content,
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: const Text('Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: btnColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(confirmText,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool autofocus;

  const _StyledTextField({
    required this.controller,
    required this.hint,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: const Color(0xFF94A3B8).withOpacity(0.8),
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
      ),
    );
  }
}