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

  bool get _canEdit {
    if (!isEditable || !allowedToEdit) return false;
    
    if (sectionAssignments.isNotEmpty) {
      return currentUserId != null && sectionAssignments.contains(currentUserId);
    }
    
    return true;
  }

  // ✅ NUEVO: Calcular progreso de la sección
  Map<String, dynamic> _calculateProgress() {
    int totalActivities = 0;
    int completedActivities = 0;

    for (var entry in entries) {
      for (var activityId in entry.results.keys) {
        totalActivities++;
        final value = entry.results[activityId];
        // Consideramos completo si tiene OK, NOK o NA (respuestas válidas)
        if (value == 'OK' || value == 'NOK' || value == 'NA') {
          completedActivities++;
        }
      }
    }

    double percentage = totalActivities > 0 
        ? (completedActivities / totalActivities) * 100 
        : 0.0;

    return {
      'total': totalActivities,
      'completed': completedActivities,
      'percentage': percentage,
    };
  }

  void _showAssignmentDialog(BuildContext context) {
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
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: 400,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              color: Color(0xFF1E293B),
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
                                    activeColor: const Color(0xFF3B82F6),
                                    checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    
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
                                      onToggleAssignment(user.id);
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
                            backgroundColor: const Color(0xFF0F172A),
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
        border: Border.all(color: const Color(0xFF1E293B), width: 2),
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
              ? _buildTableViewOptimized(context, relevantActivities)
              : _buildListViewOptimized(context, relevantActivities),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final assignedUsersList = sectionAssignments.map((uid) {
      return users.firstWhere(
        (u) => u.id == uid,
        orElse: () => UserModel(id: uid, name: 'Usuario', email: ''),
      );
    }).toList();

    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    
    // ✅ CALCULAR PROGRESO
    final progress = _calculateProgress();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: [
          // Primera fila: Nombre y badge de cantidad
          isSmallScreen 
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  _buildResponsiblesRow(context, assignedUsersList, isSmall: true),
                ],
              )
            : Row(
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
          
          // ✅ NUEVA SEGUNDA FILA: BARRA DE PROGRESO
          const SizedBox(height: 12),
          _buildProgressBar(progress),
        ],
      ),
    );
  }

  // ✅ NUEVO WIDGET: Barra de progreso
  Widget _buildProgressBar(Map<String, dynamic> progress) {
    final percentage = progress['percentage'] as double;
    final completed = progress['completed'] as int;
    final total = progress['total'] as int;
    
    // Determinar color según el progreso
    Color progressColor;
    if (percentage == 0) {
      progressColor = const Color(0xFF64748B); // Gris - Sin iniciar
    } else if (percentage < 50) {
      progressColor = const Color(0xFFEF4444); // Rojo - Bajo
    } else if (percentage < 80) {
      progressColor = const Color(0xFFF59E0B); // Amarillo - Medio
    } else if (percentage < 100) {
      progressColor = const Color(0xFF3B82F6); // Azul - Alto
    } else {
      progressColor = const Color(0xFF10B981); // Verde - Completo
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.trending_up, size: 12, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            const Text(
              'PROGRESO:',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: progressColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: progressColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    percentage == 100 ? Icons.check_circle : Icons.schedule,
                    size: 11,
                    color: progressColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$completed/$total',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: progressColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      // Barra de fondo (vacía)
                      Container(color: const Color(0xFF334155)),
                      
                      // Barra de progreso (relleno)
                      FractionallySizedBox(
                        widthFactor: percentage / 100,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                progressColor,
                                progressColor.withOpacity(0.8),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

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

  Widget _buildResponsiblesRow(BuildContext context, List<UserModel> assignedUsersList, {required bool isSmall}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isSmall)
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Text(
              "RESPONSABLES:",
              style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        
        Flexible(
          fit: isSmall ? FlexFit.loose : FlexFit.tight,
          flex: isSmall ? 1 : 0,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...assignedUsersList.take(3).map((user) => _buildUserChip(user)),
                
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
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(20),
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
            user.name.split(' ').first,
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

  Widget _buildTableViewOptimized(BuildContext context, List<ActivityConfig> activities) {
    // Ajustamos el ancho total para dar un poco más de aire si es necesario
    final double totalWidth = 230.0 + (activities.length * 100.0) + 110.0; // +10px extra al final

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            // ... (El Container del Header se queda igual) ...
            Container(
              height: 48,
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  _buildHeaderCell('ID', 80),
                  _buildHeaderCell('UBICACIÓN', 150),
                  ...activities.map((act) => _buildHeaderCell(act.name, 100)),
                  _buildHeaderCell('FOTO/OBS', 110), // Aumentamos un poco el ancho aquí
                ],
              ),
            ),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Container(
                  height: 52,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 80, child: Center(child: _buildInputCell(index, entry.customId, 'id', 60, onCustomIdChanged))),
                      SizedBox(width: 150, child: Center(child: _buildInputCell(index, entry.area, 'area', 130, onAreaChanged, hint: '...'))),
                      
                      // Celdas de estado (OK/NOK)
                      ...activities.map((act) {
                        if (!entry.results.containsKey(act.id)) return const SizedBox(width: 100);
                        return SizedBox(
                          width: 100,
                          child: Center(
                            child: InkWell(
                              onTap: _canEdit ? () => onToggleStatus(index, act.id) : null,
                              borderRadius: BorderRadius.circular(12),
                              child: _buildStatusBadge(entry.results[act.id]),
                            ),
                          ),
                        );
                      }),

                      // --- AQUÍ ESTÁ LA CORRECCIÓN DEL OVERFLOW ---
                      SizedBox(
                        width: 110, // Un poco más de espacio
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Usamos el widget compacto en lugar de IconButton
                            _buildCompactActionIcon(
                              icon: entry.photoUrls.isNotEmpty ? Icons.camera_alt : Icons.camera_alt_outlined,
                              isActive: entry.photoUrls.isNotEmpty,
                              activeColor: const Color(0xFF3B82F6),
                              onTap: _canEdit ? () => onCameraClick(index) : null,
                            ),
                            
                            const SizedBox(width: 8), // Reducimos espacio de 12 a 8
                            
                            // Icono de Observaciones
                            _buildCompactActionIcon(
                              icon: entry.observations.isNotEmpty ? Icons.comment : Icons.comment_outlined,
                              isActive: entry.observations.isNotEmpty,
                              activeColor: const Color(0xFFF59E0B), // Color ámbar para resaltar si hay obs
                              onTap: _canEdit ? () => onObservationClick(index) : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildInputCell(int index, String? value, String keyPrefix, double width, Function(int, String) onChanged, {String? hint}) {
    return SizedBox(
      width: width,
      height: 32,
      child: TextFormField(
        key: ValueKey('${keyPrefix}_$index'), 
        initialValue: value,
        enabled: _canEdit,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5)),
        ),
        onChanged: (val) => onChanged(index, val),
      ),
    );
  }

  Widget _buildListViewOptimized(BuildContext context, List<ActivityConfig> activities) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          mainAxisExtent: 130,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 70, child: _buildInputCell(index, entry.customId, 'grid_id', 70, onCustomIdChanged, hint: 'ID')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildInputCell(index, entry.area, 'grid_area', 100, onAreaChanged, hint: 'Ubicación...')),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: activities.where((act) => entry.results.containsKey(act.id)).map((act) {
                        final status = entry.results[act.id];
                        final hasPhotos = (entry.activityData[act.id]?.photoUrls.length ?? 0) > 0;
                        final hasObs = (entry.activityData[act.id]?.observations ?? '').isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            // El Expanded obliga al texto a encogerse si no hay espacio
                            Expanded(
                              child: Text(
                                act.name, 
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)), 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis
                              ),
                            ),
                            const SizedBox(width: 4), // Pequeño espacio seguro
                            
                            // Iconos compactos
                            _buildCompactActionIcon(
                              icon: hasPhotos ? Icons.camera_alt : Icons.camera_alt_outlined,
                              isActive: hasPhotos,
                              activeColor: const Color(0xFF3B82F6),
                              onTap: _canEdit ? () => onCameraClick(index, activityId: act.id) : null,
                            ),
                            
                            // Sin SizedBox extra o muy pequeño entre iconos
                            _buildCompactActionIcon(
                              icon: hasObs ? Icons.comment : Icons.comment_outlined,
                              isActive: hasObs,
                              activeColor: const Color(0xFFF59E0B),
                              onTap: _canEdit ? () => onObservationClick(index, activityId: act.id) : null,
                            ),
                            
                            const SizedBox(width: 4),
                            
                            InkWell(
                              onTap: _canEdit ? () => onToggleStatus(index, act.id) : null,
                              child: _buildCompactStatusBadge(status),
                            ),
                          ],
                        ),
                      );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactActionIcon({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    VoidCallback? onTap
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6), // Borde un poco más redondeado
      child: Container(
        // Agregamos un contenedor invisible para garantizar área de toque mínima sin padding excesivo
        width: 32, 
        height: 32,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18, // Tamaño controlado
          color: isActive ? activeColor : const Color(0xFF94A3B8), // Color gris más suave si está inactivo
        ),
      ),
    );
  }

  Widget _buildCompactStatusBadge(String? status) {
    Color color;
    Widget child;

    switch (status) {
      case 'OK':
        color = const Color(0xFF1E293B);
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