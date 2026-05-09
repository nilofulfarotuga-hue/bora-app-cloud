import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/restaurant_model.dart';
import '../stores/partner_product_store.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  bool _isAvailable = true;
  bool _isSaving = false;

  File? _selectedImage;
  String? _existingImageUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final parsedPrice = _parsePrice(_priceController.text);
    if (parsedPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduza um preço válido.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final imageUrl = await _uploadImage();
    if (_selectedImage != null && imageUrl == null) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }
    if (!mounted) return;

    try {
      await context.read<PartnerProductStore>().addProduct(
            restaurantId: widget.restaurant.id,
            name: _nameController.text,
            description: _descriptionController.text,
            price: parsedPrice,
            photoUrl: imageUrl ?? '',
            isAvailable: _isAvailable,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível guardar o produto: $error')),
        );
      }
      if (mounted) {
        setState(() => _isSaving = false);
      }
      return;
    }

    if (!mounted) return;

    setState(() => _isSaving = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (photo == null) return;
      if (!mounted) return;
      setState(() {
        _selectedImage = File(photo.path);
        _existingImageUrl = null;
      });
    } catch (e) {
      debugPrint('[AddProduct] takePhoto: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a câmara.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (photo == null) return;
      if (!mounted) return;
      setState(() {
        _selectedImage = File(photo.path);
        _existingImageUrl = null;
      });
    } catch (e) {
      debugPrint('[AddProduct] pickFromGallery: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a galeria.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showUrlDialog() async {
    final ctrl = TextEditingController(text: _existingImageUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colar URL da imagem'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://...',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Usar URL'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (url != null && url.isNotEmpty) {
      setState(() {
        _existingImageUrl = url;
        _selectedImage = null;
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return _existingImageUrl;
    if (mounted) setState(() => _uploading = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = _selectedImage!.path.split('.').last.toLowerCase();
      final fileName = 'products/$ts.$ext';
      final bytes = await _selectedImage!.readAsBytes();

      await Supabase.instance.client.storage
          .from('product-images')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: false,
            ),
          );

      return Supabase.instance.client.storage
          .from('product-images')
          .getPublicUrl(fileName);
    } catch (e) {
      debugPrint('[AddProduct] upload error: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro a enviar foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Foto do produto',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (_selectedImage != null)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _selectedImage!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                  onPressed: () {
                    if (mounted) setState(() => _selectedImage = null);
                  },
                ),
              ),
            ],
          )
        else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _existingImageUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.broken_image,
                      size: 60,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                  onPressed: () {
                    if (mounted) setState(() => _existingImageUrl = null);
                  },
                ),
              ),
            ],
          )
        else
          Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Sem foto', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tirar foto'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeria'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _uploading ? null : _showUrlDialog,
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Ou colar URL'),
          ),
        ),
        if (_uploading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'A enviar imagem...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Adicionar produto',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Novo produto para ${widget.restaurant.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nome do produto',
                      prefixIcon: Icon(Icons.short_text),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Insira o nome do produto';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    minLines: 2,
                    maxLines: 4,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Descreva o produto';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Preço',
                      prefixIcon: Icon(Icons.euro),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Indique o preço';
                      }
                      if (_parsePrice(value) == null) {
                        return 'Preço inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildPhotoSection(),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    title: const Text('Disponível para venda'),
                    value: _isAvailable,
                    onChanged: (value) => setState(() => _isAvailable = value),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label:
                          Text(_isSaving ? 'A guardar...' : 'Guardar produto'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double? _parsePrice(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return null;
  }
  return double.tryParse(normalized);
}
