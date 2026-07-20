import '../utils/io_compat.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/order_photo_upload_service.dart';
import '../utils/safe_image_picker.dart';

/// Reusable mandatory photo picker used by sendPackage and carryGroceries
/// forms (BR §7.5, §7.6).
///
/// BUG #7 (2026-05-13) — upload via Edge Function `upload-order-photo`
/// (service_role bypassa RLS storage) em vez de `storage.from(...)` directo
/// que dava erro 403. Calls [onUploaded] com a URL pública retornada.
class MandatoryPhotoPicker extends StatefulWidget {
  const MandatoryPhotoPicker({
    super.key,
    required this.label,
    required this.hint,
    required this.pathPrefix,
    required this.onUploaded,
  });

  final String label;
  final String hint;
  final String pathPrefix; // e.g. 'package' or 'groceries'
  final void Function(String? url) onUploaded;

  @override
  State<MandatoryPhotoPicker> createState() => _MandatoryPhotoPickerState();
}

class _MandatoryPhotoPickerState extends State<MandatoryPhotoPicker> {
  XFile? _local;
  bool _uploading = false;
  String? _uploadedUrl;

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await SafeImagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _local = picked;
        _uploading = true;
        _uploadedUrl = null;
      });
      widget.onUploaded(null);

      // BUG #7 (2026-05-13) — upload via Edge Function (service_role).
      // OrderPhotoUploadService faz base64 + invoke('upload-order-photo')
      // e devolve a URL pública. Auth + size validados server-side.
      final tmpFile = File(picked.path);
      final url = await OrderPhotoUploadService.uploadOrderPhoto(
        photoFile: tmpFile,
        pathPrefix: widget.pathPrefix,
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadedUrl = url;
      });
      widget.onUploaded(url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      widget.onUploaded(null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro a enviar foto: $e')),
      );
    }
  }

  void _show() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = _local != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        Text(widget.hint,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _uploading ? null : _show,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
              image: hasLocal
                  ? DecorationImage(
                      image: boraLocalImage(_local!.path),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: _uploading
                ? const CircularProgressIndicator()
                : hasLocal
                    ? (_uploadedUrl == null
                        ? const SizedBox.shrink()
                        : const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.check_circle,
                                  color: Colors.green, size: 28),
                            ),
                          ))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              color: Colors.grey.shade600),
                          const SizedBox(height: 6),
                          Text('Tocar para adicionar foto',
                              style:
                                  TextStyle(color: Colors.grey.shade700)),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}
