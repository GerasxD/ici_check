import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class ReportSignatures extends StatelessWidget {
  final SignatureController providerController;
  final SignatureController clientController;
  final String? providerName;
  final String? clientName;
  final bool isEditable;
  final Function(String) onProviderNameChanged;
  final Function(String) onClientNameChanged;

  const ReportSignatures({
    super.key,
    required this.providerController,
    required this.clientController,
    this.providerName,
    this.clientName,
    required this.isEditable,
    required this.onProviderNameChanged,
    required this.onClientNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
      child: Column(
        children: [
          _buildSignatureBox(
            "NOMBRE Y FIRMA DEL RESPONSABLE (PROVEEDOR)",
            providerController,
            providerName,
            onProviderNameChanged,
          ),
          const Divider(),
          _buildSignatureBox(
            "NOMBRE Y FIRMA DEL RESPONSABLE (CLIENTE)",
            clientController,
            clientName,
            onClientNameChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureBox(
    String title,
    SignatureController controller,
    String? name,
    Function(String) onNameChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Signature(controller: controller, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 8),
          TextField(
            enabled: isEditable,
            controller: TextEditingController(text: name),
            decoration: const InputDecoration(
              hintText: 'Nombre del firmante',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: onNameChanged,
          ),
          if (isEditable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => controller.clear(),
                child: const Text('Borrar Firma'),
              ),
            )
        ],
      ),
    );
  }
}