import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class ReportSignatures extends StatelessWidget {
  final SignatureController providerController;
  final SignatureController clientController;
  final String? providerName;
  final String? clientName;
  
  final String? providerSignatureData;
  final String? clientSignatureData;
  
  final bool isEditable;
  final Function(String) onProviderNameChanged;
  final Function(String) onClientNameChanged;

  const ReportSignatures({
    super.key,
    required this.providerController,
    required this.clientController,
    this.providerName,
    this.clientName,
    this.providerSignatureData,
    this.clientSignatureData,
    required this.isEditable,
    required this.onProviderNameChanged,
    required this.onClientNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // CABECERA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                Icon(Icons.draw_outlined, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  "CONFORMIDAD DEL SERVICIO",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade600, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          
          // CUERPO DE FIRMAS (Horizontal)
          Padding(
            padding: const EdgeInsets.all(20),
            child: IntrinsicHeight( // Asegura que ambas cajas tengan la misma altura si una crece
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FIRMA 1: PROVEEDOR
                  Expanded(
                    child: _SignatureCanvas(
                      title: "RESPONSABLE TÉCNICO (PROVEEDOR)",
                      controller: providerController,
                      name: providerName,
                      savedSignature: providerSignatureData,
                      isEditable: isEditable,
                      onNameChanged: onProviderNameChanged,
                      icon: Icons.engineering,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),

                  // Separador Vertical
                  const SizedBox(width: 20),
                  
                  // FIRMA 2: CLIENTE
                  Expanded(
                    child: _SignatureCanvas(
                      title: "RESPONSABLE DEL SITIO (CLIENTE)",
                      controller: clientController,
                      name: clientName,
                      savedSignature: clientSignatureData,
                      isEditable: isEditable,
                      onNameChanged: onClientNameChanged,
                      icon: Icons.business,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// === EL WIDGET INTELIGENTE SE MANTIENE IGUAL ===
class _SignatureCanvas extends StatefulWidget {
  final String title;
  final SignatureController controller;
  final String? name;
  final String? savedSignature;
  final bool isEditable;
  final Function(String) onNameChanged;
  final IconData icon;
  final Color color;

  const _SignatureCanvas({
    required this.title,
    required this.controller,
    required this.name,
    this.savedSignature,
    required this.isEditable,
    required this.onNameChanged,
    required this.icon,
    required this.color,
  });

  @override
  State<_SignatureCanvas> createState() => _SignatureCanvasState();
}

class _SignatureCanvasState extends State<_SignatureCanvas> {
  bool _showSavedImage = false;

  @override
  void initState() {
    super.initState();
    if (widget.savedSignature != null && widget.savedSignature!.isNotEmpty) {
      _showSavedImage = true;
    }
  }

  void _resetSignature() {
    setState(() {
      _showSavedImage = false;
    });
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título (Ajustado para ser más compacto si es necesario)
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: widget.color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Icon(widget.icon, size: 14, color: widget.color),
            ),
            const SizedBox(width: 10),
            Expanded( // Expanded aquí por si el texto es muy largo en pantallas pequeñas
              child: Text(
                widget.title, 
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ÁREA DE FIRMA
        Container(
          height: 120, // Reduje un poco la altura para que se vea más panorámico como en la imagen
          decoration: BoxDecoration(
            color: widget.isEditable ? const Color(0xFFF8FAFC) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isEditable ? const Color(0xFFE2E8F0) : Colors.transparent, 
              width: 1.5
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (_showSavedImage && widget.savedSignature != null)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white,
                      child: Image.memory(
                        base64Decode(widget.savedSignature!),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => 
                            const Center(child: Text("Error", style: TextStyle(fontSize: 10, color: Colors.red))),
                      ),
                    ),
                  ),

                if (!_showSavedImage)
                  Signature(
                    controller: widget.controller,
                    backgroundColor: Colors.transparent,
                    width: double.infinity,
                    height: 120,
                  ),

                if (!_showSavedImage && widget.isEditable && widget.controller.isEmpty)
                  Positioned(
                    bottom: 8, left: 0, right: 0,
                    child: Center(child: Text("Firme aquí", style: TextStyle(color: Colors.grey.shade300, fontSize: 10, fontWeight: FontWeight.bold))),
                  ),

                if (widget.isEditable)
                  Positioned(
                    top: 4, right: 4,
                    child: _showSavedImage 
                      ? InkWell(
                          onTap: _resetSignature,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black12)]),
                            child: Icon(Icons.edit, size: 14, color: widget.color),
                          ),
                        )
                      : InkWell(
                          onTap: () => widget.controller.clear(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black12)]),
                            child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                          ),
                        ),
                  ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 8),

        // INPUT NOMBRE
        SizedBox(
          height: 40, // Altura fija para alinear ambos inputs
          child: TextFormField(
            key: ValueKey("input_${widget.title}"),
            initialValue: widget.name,
            enabled: widget.isEditable,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            decoration: InputDecoration(
              hintText: 'Nombre del Firmante',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 10),
              prefixIcon: Icon(Icons.person_outline, size: 14, color: Colors.grey.shade400),
              filled: true,
              fillColor: widget.isEditable ? Colors.white : Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.color, width: 1.5)),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
            ),
            onChanged: widget.onNameChanged,
          ),
        ),
      ],
    );
  }
}