import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Resultado del diálogo de re-numeración
class RenumberConfig {
  final String prefix;
  final int startNumber;
  final int padding;

  const RenumberConfig({
    required this.prefix,
    required this.startNumber,
    required this.padding,
  });

  /// Genera el ID para un offset dado (0-based)
  String generateId(int offset) {
    final number = startNumber + offset;
    final numberStr = number.toString().padLeft(padding, '0');
    return prefix.isEmpty ? numberStr : '$prefix$numberStr';
  }
}

Future<RenumberConfig?> showRenumberDialog({
  required BuildContext context,
  required String currentId,
  required int remainingCount,
}) {
  return showDialog<RenumberConfig>(
    context: context,
    builder: (ctx) => _RenumberDialogContent(
      currentId: currentId,
      remainingCount: remainingCount,
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// DIALOG CONTENT (StatefulWidget para manejar preview en tiempo real)
// ═══════════════════════════════════════════════════════════════════════

class _RenumberDialogContent extends StatefulWidget {
  final String currentId;
  final int remainingCount;

  const _RenumberDialogContent({
    required this.currentId,
    required this.remainingCount,
  });

  @override
  State<_RenumberDialogContent> createState() =>
      _RenumberDialogContentState();
}

class _RenumberDialogContentState extends State<_RenumberDialogContent> {
  late final TextEditingController _prefixController;
  late final TextEditingController _startController;
  late final TextEditingController _paddingController;

  @override
  void initState() {
    super.initState();

    // ★ Intentar parsear el ID actual para pre-llenar los campos
    final parsed = _parseExistingId(widget.currentId);
    _prefixController = TextEditingController(text: parsed.prefix);
    _startController =
        TextEditingController(text: parsed.startNumber.toString());
    _paddingController =
        TextEditingController(text: parsed.padding.toString());
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _startController.dispose();
    _paddingController.dispose();
    super.dispose();
  }

  /// Intenta extraer prefijo, número y padding de un ID existente.
  /// Ejemplo: "EXT-003" → prefix="EXT-", start=3, padding=3
  ///          "AA01"    → prefix="AA", start=1, padding=2
  ///          "42"      → prefix="", start=42, padding=2
  ({String prefix, int startNumber, int padding}) _parseExistingId(
      String id) {
    if (id.isEmpty) {
      return (prefix: '', startNumber: 1, padding: 3);
    }

    // Buscar desde el final la parte numérica
    int numStart = id.length;
    while (numStart > 0 && _isDigit(id[numStart - 1])) {
      numStart--;
    }

    if (numStart == id.length) {
      // No hay números al final → todo es prefijo, empezar desde 1
      return (prefix: id, startNumber: 1, padding: 3);
    }

    final prefix = id.substring(0, numStart);
    final numberPart = id.substring(numStart);
    final number = int.tryParse(numberPart) ?? 1;
    final padding = numberPart.length.clamp(1, 6);

    return (prefix: prefix, startNumber: number, padding: padding);
  }

  bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  /// Genera la configuración actual basada en los campos del diálogo
  RenumberConfig? _currentConfig() {
    final start = int.tryParse(_startController.text);
    final padding = int.tryParse(_paddingController.text);
    if (start == null || padding == null || padding < 1) return null;
    return RenumberConfig(
      prefix: _prefixController.text.toUpperCase(),
      startNumber: start,
      padding: padding.clamp(1, 6),
    );
  }

  /// Preview de los primeros N IDs que se generarán
  List<String> _generatePreview() {
    final config = _currentConfig();
    if (config == null) return [];
    final previewCount = widget.remainingCount.clamp(0, 5);
    return List.generate(previewCount, (i) => config.generateId(i));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── HEADER ───
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF1F5F9)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.format_list_numbered_rounded,
                      color: Color(0xFF3B82F6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Re-numerar desde aquí',
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${widget.remainingCount} dispositivos serán renumerados',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            ),

            // ─── CAMPOS ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                children: [
                  // Prefijo
                  _buildField(
                    label: 'PREFIJO',
                    hint: 'EXT-, AA-, PISO1-...',
                    controller: _prefixController,
                    icon: Icons.text_fields,
                    inputFormatters: [UpperCaseTextFormatter()],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Número inicio
                      Expanded(
                        flex: 3,
                        child: _buildField(
                          label: 'NÚMERO INICIO',
                          hint: '1',
                          controller: _startController,
                          icon: Icons.pin,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Padding (dígitos)
                      Expanded(
                        flex: 2,
                        child: _buildField(
                          label: 'DÍGITOS',
                          hint: '3',
                          controller: _paddingController,
                          icon: Icons.format_indent_increase,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ─── PREVIEW ───
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildPreviewSection(),
            ),

            // ─── BOTONES ───
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: const Color(0xFF64748B),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final config = _currentConfig();
                        if (config == null) return;
                        Navigator.pop(context, config);
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text(
                        'Aplicar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 0,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
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
              borderSide: const BorderSide(
                color: Color(0xFF3B82F6),
                width: 1.5,
              ),
            ),
          ),
          onChanged: (_) => setState(() {}), // Refresh preview
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    final preview = _generatePreview();
    final config = _currentConfig();
    final isValid = config != null && preview.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isValid ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid ? const Color(0xFFBBF7D0) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isValid ? Icons.visibility : Icons.warning_amber_rounded,
                size: 14,
                color: isValid
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 6),
              Text(
                isValid ? 'VISTA PREVIA' : 'CONFIGURA LOS CAMPOS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isValid
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFF59E0B),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (isValid) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ...preview.map((id) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD1FAE5)),
                      ),
                      child: Text(
                        id,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                          fontFamily: 'monospace',
                        ),
                      ),
                    )),
                if (widget.remainingCount > 5)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      '... +${widget.remainingCount - 5} más',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER: UpperCaseTextFormatter (ya existe en device_section_improved,
//         pero lo incluimos aquí por si se usa independientemente)
// ═══════════════════════════════════════════════════════════════════════

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}