import 'package:flutter/material.dart';
import 'package:ici_check/features/devices/data/device_model.dart';
import 'package:ici_check/features/reports/data/report_model.dart';
import 'package:ici_check/features/auth/data/models/user_model.dart';

class DeviceSectionImproved extends StatelessWidget {
  final String defId;
  final DeviceModel deviceDef;
  final List<ReportEntry> entries;
  final List<UserModel> users;
  final List<String> sectionAssignments;
  final bool isEditable;
  final bool allowedToEdit;
  final bool isUserCoordinator;
  final String? currentUserId;
  
  // Callbacks
  final Function(String userId) onToggleAssignment;
  final Function(int index, String customId) onCustomIdChanged;
  final Function(int index, String area) onAreaChanged;
  final Function(int index, String activityId) onToggleStatus;
  final Function(int index, {String? activityId}) onCameraClick;
  final Function(int index, {String? activityId}) onObservationClick;

  const DeviceSectionImproved({
    super.key,
    required this.defId,
    required this.deviceDef,
    required this.entries,
    required this.users,
    required this.sectionAssignments,
    required this.isEditable,
    required this.allowedToEdit,
    required this.isUserCoordinator,
    this.currentUserId,
    required this.onToggleAssignment,
    required this.onCustomIdChanged,
    required this.onAreaChanged,
    required this.onToggleStatus,
    required this.onCameraClick,
    required this.onObservationClick,
  });

  /// Determina si el usuario actual puede editar los campos de respuesta.
  /// Se mantiene la restricción aquí: Solo puedes escribir si estás en modo edición Y (no hay asignaciones O estás asignado).
  bool get _canEdit {
    if (!isEditable || !allowedToEdit) return false;
    
    // Si hay personas asignadas específicamente a esta sección
    if (sectionAssignments.isNotEmpty) {
      // El usuario actual debe estar en esa lista para poder editar
      return currentUserId != null && sectionAssignments.contains(currentUserId);
    }
    
    // Si no hay nadie asignado específicamente, todos los autorizados pueden editar
    return true;
  }

  void _showAssignmentDialog(BuildContext context) {
    // Usamos un Set local para visualización optimista
    final Set<String> localAssignments = Set.from(sectionAssignments);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                // Limitamos la altura para que no ocupe toda la pantalla en listas largas
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: 400,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- 1. HEADER ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Asignar Responsables',
                            style: TextStyle(
                              color: Color(0xFF1E293B), // Slate-800
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- 2. LISTA DE USUARIOS ---
                    Flexible(
                      child: users.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.group_off_outlined, size: 48, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text(
                                    "No hay personal disponible",
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              itemCount: users.length,
                              separatorBuilder: (ctx, i) => const Divider(height: 1, indent: 60, endIndent: 20, color: Color(0xFFF1F5F9)),
                              itemBuilder: (ctx, i) {
                                final user = users[i];
                                final isAssigned = localAssignments.contains(user.id);

                                return Material(
                                  color: Colors.transparent,
                                  child: CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    dense: true,
                                    activeColor: const Color(0xFF3B82F6), // Blue-500
                                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    
                                    // Avatar del usuario
                                    secondary: CircleAvatar(
                                      backgroundColor: isAssigned ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                                      foregroundColor: isAssigned ? const Color(0xFF3B82F6) : const Color(0xFF64748B),
                                      child: Text(
                                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                    
                                    title: Text(
                                      user.name,
                                      style: TextStyle(
                                        fontWeight: isAssigned ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 14,
                                        color: const Color(0xFF1E293B),
                                      ),
                                    ),
                                    subtitle: Text(
                                      user.email,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                    ),
                                    value: isAssigned,
                                    onChanged: (val) {
                                      // Actualizar lógica padre
                                      onToggleAssignment(user.id);
                                      // Actualizar UI local
                                      setModalState(() {
                                        if (isAssigned) {
                                          localAssignments.remove(user.id);
                                        } else {
                                          localAssignments.add(user.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),

                    // --- 3. FOOTER (BOTÓN LISTO) ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A), // Slate-900
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text("LISTO", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final scheduledActivityIds = entries.expand((e) => e.results.keys).toSet();
    final relevantActivities = deviceDef.activities
        .where((a) => scheduledActivityIds.contains(a.id))
        .toList();

    if (relevantActivities.isEmpty) return const SizedBox();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF1E293B), width: 2), // Borde oscuro elegante
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(context),
          deviceDef.viewMode == 'table'
              ? _buildTableView(relevantActivities)
              : _buildListView(context,relevantActivities),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // Obtenemos los objetos User completos de los IDs asignados
    final assignedUsersList = sectionAssignments.map((uid) {
      return users.firstWhere(
        (u) => u.id == uid,
        orElse: () => UserModel(id: uid, name: 'Usuario', email: ''),
      );
    }).toList();

    // Detección de pantalla pequeña (Móvil vs Tablet/PC)
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity, // Asegurar que ocupe todo el ancho
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B), // Fondo oscuro
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: isSmallScreen 
        ? Column( // DISEÑO MÓVIL (Vertical)
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fila Superior: Título y Contador
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      deviceDef.name.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildCountBadge(entries.length),
                ],
              ),
              const SizedBox(height: 12),
              // Fila Inferior: Responsables (Con scroll si son muchos)
              _buildResponsiblesRow(context, assignedUsersList, isSmall: true),
            ],
          )
        : Row( // DISEÑO TABLET/PC (Horizontal)
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        deviceDef.name.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildCountBadge(entries.length),
                  ],
                ),
              ),
              _buildResponsiblesRow(context, assignedUsersList, isSmall: false),
            ],
          ),
    );
  }

  // Helper para el badge de "X UNIDADES"
  Widget _buildCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Text(
        '$count UNIDADES',
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }

  // Helper para la fila de responsables (Reutilizable)
  Widget _buildResponsiblesRow(BuildContext context, List<UserModel> assignedUsersList, {required bool isSmall}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isSmall) // En móvil ocultamos la etiqueta "RESPONSABLES:" para ahorrar espacio
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Text(
              "RESPONSABLES:",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        
        // Usamos Flexible o Expanded en móvil para permitir scroll si se desborda
        Flexible(
          fit: isSmall ? FlexFit.loose : FlexFit.tight, // En PC tight para empujar, en móvil loose
          flex: isSmall ? 1 : 0, // En PC no queremos que crezca infinitamente
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...assignedUsersList.take(3).map((user) => _buildUserChip(user)), // Mostrar hasta 3
                
                if (assignedUsersList.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      "+${assignedUsersList.length - 3}",
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Botón de Editar (Siempre al final)
        const SizedBox(width: 4),
        InkWell(
          onTap: () => _showAssignmentDialog(context),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF334155).withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Icon(
              assignedUsersList.isEmpty ? Icons.person_add_alt_1 : Icons.edit, 
              color: Colors.white70, 
              size: 14
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserChip(UserModel user) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4), // Padding asimétrico para el avatar
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB), // Azul brillante (blue-600)
        borderRadius: BorderRadius.circular(20), // Borde muy redondeado
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: Colors.white,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            user.name.split(' ').first, // Solo primer nombre para ahorrar espacio
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableView(List<ActivityConfig> activities) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 50,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 48,
        columnSpacing: 12,
        horizontalMargin: 16,
        dividerThickness: 1,
        border: TableBorder(
          horizontalInside: BorderSide(color: Colors.grey.shade200),
          verticalInside: BorderSide(color: Colors.grey.shade200),
        ),
        columns: [
          DataColumn(
            label: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'ID',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          DataColumn(
            label: Container(
              constraints: const BoxConstraints(minWidth: 150),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'UBICACIÓN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          ...activities.map((act) => DataColumn(
            label: Container(
              constraints: const BoxConstraints(minWidth: 80, maxWidth: 100),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    act.name,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // ... (Resto de tu lógica de columnas se mantiene igual)
                ],
              ),
            ),
          )),
          const DataColumn(
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.camera_alt, size: 16, color: Color(0xFF64748B)),
            ),
          ),
          const DataColumn(
            label: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.comment, size: 16, color: Color(0xFF64748B)),
            ),
          ),
        ],
        rows: entries.asMap().entries.map((entryMap) {
          final index = entryMap.key;
          final entry = entryMap.value;
          
          return DataRow(
            color: WidgetStateProperty.resolveWith<Color>((states) {
              if (states.contains(WidgetState.hovered)) {
                return const Color(0xFFF8FAFC);
              }
              return Colors.white;
            }),
            cells: [
              DataCell(
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: entry.customId,
                    enabled: _canEdit,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                      ),
                    ),
                    onChanged: (val) => onCustomIdChanged(index, val),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    initialValue: entry.area,
                    enabled: _canEdit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      hintText: '...',
                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                      ),
                    ),
                    onChanged: (val) => onAreaChanged(index, val),
                  ),
                ),
              ),
              ...activities.map((act) {
                if (!entry.results.containsKey(act.id)) {
                  return const DataCell(SizedBox());
                }
                return DataCell(
                  Center(
                    child: InkWell(
                      onTap: _canEdit
                          ? () => onToggleStatus(index, act.id)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      child: _buildStatusBadge(entry.results[act.id]),
                    ),
                  ),
                );
              }),
              DataCell(
                Center(
                  child: IconButton(
                    icon: Icon(
                      entry.photos.isNotEmpty ? Icons.camera_alt : Icons.camera_alt_outlined,
                      size: 18,
                      color: entry.photos.isNotEmpty
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF94A3B8),
                    ),
                    onPressed: _canEdit
                        ? () => onCameraClick(index)
                        : null,
                  ),
                ),
              ),
              DataCell(
                Center(
                  child: IconButton(
                    icon: Icon(
                      entry.observations.isNotEmpty ? Icons.comment : Icons.comment_outlined,
                      size: 18,
                      color: entry.observations.isNotEmpty
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF94A3B8),
                    ),
                    onPressed: _canEdit
                        ? () => onObservationClick(index)
                        : null,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListView(BuildContext context, List<ActivityConfig> activities) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topLeft, // ← FORZAR ALINEACIÓN A LA IZQUIERDA
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: entries.asMap().entries.map((entryMap) {
            final index = entryMap.key;
            final entry = entryMap.value;
            
            // ANCHO MÁXIMO FIJO para las cards (no calculado por pantalla)
            const double maxCardWidth = 380; // Ancho máximo de cada card
            
            return ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: maxCardWidth, // Ancho máximo
                minWidth: 300, // Ancho mínimo para móviles
              ),
              child: Container(
                width: double.infinity, // Ocupa todo el ancho disponible hasta maxWidth
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- HEADER: ID Y UBICACIÓN ---
                    Row(
                      children: [
                        // ID (Caja compacta estilo "EXT-1")
                        SizedBox(
                          width: 70,
                          height: 32,
                          child: TextFormField(
                            initialValue: entry.customId,
                            enabled: _canEdit,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              hintText: 'ID',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (val) => onCustomIdChanged(index, val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Ubicación (solo texto, sin caja visible)
                        Expanded(
                          child: TextFormField(
                            initialValue: entry.area,
                            enabled: _canEdit,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Ubicación...',
                              hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                              border: InputBorder.none,
                            ),
                            onChanged: (val) => onAreaChanged(index, val),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),

                    // --- LISTA DE ACTIVIDADES (Horizontal y Compacta) ---
                    ...activities.where((act) => entry.results.containsKey(act.id)).map((act) {
                      final status = entry.results[act.id];
                      final hasPhotos = (entry.activityData[act.id]?.photos.length ?? 0) > 0;
                      final hasObs = (entry.activityData[act.id]?.observations ?? '').isNotEmpty;
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            // 1. Nombre de la actividad y frecuencia
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    act.name,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  // Badge de frecuencia
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
                                    ),
                                    child: Text(
                                      act.frequency.toString().split('.').last.length > 3
                                          ? act.frequency.toString().split('.').last.substring(0, 3)
                                          : act.frequency.toString().split('.').last,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(width: 8),

                            // 2. Iconos de Foto y Observaciones
                            _buildCompactActionIcon(
                              icon: hasPhotos ? Icons.camera_alt : Icons.camera_alt_outlined,
                              isActive: hasPhotos,
                              activeColor: const Color(0xFF3B82F6),
                              onTap: _canEdit ? () => onCameraClick(index, activityId: act.id) : null,
                            ),
                            const SizedBox(width: 4),
                            _buildCompactActionIcon(
                              icon: hasObs ? Icons.comment : Icons.comment_outlined,
                              isActive: hasObs,
                              activeColor: const Color(0xFFF59E0B),
                              onTap: _canEdit ? () => onObservationClick(index, activityId: act.id) : null,
                            ),

                            const SizedBox(width: 8),

                            // 3. Badge de Estado (círculo)
                            InkWell(
                              onTap: _canEdit ? () => onToggleStatus(index, act.id) : null,
                              borderRadius: BorderRadius.circular(16),
                              child: _buildCompactStatusBadge(status),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Helper para íconos compactos
  Widget _buildCompactActionIcon({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    VoidCallback? onTap
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 16,
          color: isActive ? activeColor : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }

  // Helper para badge de estado compacto
  Widget _buildCompactStatusBadge(String? status) {
    Color color;
    Widget child;

    switch (status) {
      case 'OK':
        color = const Color(0xFF1E293B);
        // CAMBIO AQUÍ: Reemplazamos el Icono de Check por el círculo blanco
        child = Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        );
        break;
      case 'NOK':
        color = const Color(0xFFEF4444);
        child = const Icon(Icons.close, color: Colors.white, size: 12);
        break;
      case 'NA':
        color = const Color(0xFFE2E8F0);
        child = const SizedBox();
        break;
      case 'NR':
        color = const Color(0xFFFBBF24);
        child = const Text(
          "N/R",
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        );
        break;
      default:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
            color: Colors.white,
          ),
        );
    }

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Center(child: child),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color bgColor;
    Color borderColor;
    Widget? child;
    
    switch (status) {
      case 'OK':
        bgColor = const Color(0xFF1E293B);
        borderColor = const Color(0xFF1E293B);
        child = Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        );
        break;
      case 'NOK':
        bgColor = const Color(0xFFEF4444);
        borderColor = const Color(0xFFDC2626);
        child = const Icon(Icons.close, size: 14, color: Colors.white);
        break;
      case 'NA':
        bgColor = const Color(0xFFE2E8F0);
        borderColor = const Color(0xFFCBD5E1);
        child = const Text(
          'N/A',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Color(0xFF64748B),
          ),
        );
        break;
      case 'NR':
        bgColor = const Color(0xFFFBBF24);
        borderColor = const Color(0xFFF59E0B);
        child = const Text(
          'N/R',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        );
        break;
      default:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
            color: Colors.white,
          ),
        );
    }
    
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}