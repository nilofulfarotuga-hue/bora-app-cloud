import '../utils/io_compat.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/safe_image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/allergens.dart';
import '../config/app_colors.dart';
import '../models/partner_product.dart';
import '../models/restaurant_model.dart';
import '../services/partner_price_rules.dart';
import '../stores/partner_product_store.dart';

/// Sentinel do dropdown de categoria — seleciona-lo abre o campo livre para
/// criar uma categoria nova (BUG 1, 2026-07-17).
const String _kNewCategorySentinel = '__nova_categoria__';

/// Criar OU editar um produto do parceiro.
///
/// 2026-09-14 (missão parceiro-edita-preco): o dono da Sabores de Casa não
/// tinha onde mudar preço, nome ou descrição de um produto já criado. O mesmo
/// ecrã passa a abrir em modo de edição quando recebe [product] — reaproveita
/// a foto (câmara/galeria/URL), a categoria e os alergénios.
///
/// Regra de preço (lojas parceiras): o parceiro escreve o preço de balcão —
/// "Preço que recebes" — e a app soma a comissão por cima, sozinha, através de
/// [PartnerPriceRules]. Gravam-se as duas colunas: `partner_shelf_price` (o
/// que ele escreveu) e `price` (o que o cliente vê). Antes gravava-se o número
/// escrito directamente em `price`, e o parceiro recebia menos 14 % sem saber.
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key, required this.restaurant, this.product});

  final RestaurantModel restaurant;

  /// Produto a editar; null = criar novo.
  final PartnerProduct? product;

  bool get isEditing => product != null;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _newCategoryController;
  bool _isAvailable = true;
  bool _isSaving = false;

  // BUG 1 (2026-07-17): categoria do produto — dropdown com as categorias já
  // usadas por esta loja + opção de criar uma nova.
  String? _selectedCategoryOption;

  // B6 (2026-06-12): alergénios UE 1169/2011 selecionados pelo parceiro.
  final Set<String> _selectedAllergens = {};
  // Parte 5 (rodada 2) — farmácia: produto exige receita médica.
  bool _requiresPrescription = false;

  File? _selectedImage;
  String? _existingImageUrl;
  bool _uploading = false;

  // Regra de preço da plataforma (lida do servidor ao abrir o ecrã, para
  // acompanhar sempre a percentagem em vigor). Só interessa a lojas parceiras.
  PartnerPriceRules? _rules;
  bool _rulesLoading = false;

  bool get _isPartnerStore => widget.restaurant.isPartner;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _descriptionController =
        TextEditingController(text: product?.description ?? '');
    _priceController = TextEditingController(
      text: product == null ? '' : _initialPriceText(product),
    );
    _newCategoryController = TextEditingController();
    if (product != null) {
      _isAvailable = product.isAvailable;
      _selectedAllergens.addAll(product.allergens);
      if (product.photoUrl.trim().isNotEmpty) {
        _existingImageUrl = product.photoUrl;
      }
      _preselectCategory(product.category.trim());
    }
    if (_isPartnerStore) _loadRules();
  }

  /// Campo do preço pré-preenchido com o balcão; se o produto antigo ainda não
  /// tiver balcão gravado, cai para o preço actual (numa loja parceira isso
  /// é o preço que o cliente vê — o parceiro confirma-o ao guardar).
  String _initialPriceText(PartnerProduct product) {
    final value = _isPartnerStore
        ? (product.partnerShelfPrice ?? product.price)
        : product.price;
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Em edição, a categoria actual do produto aparece já escolhida no
  /// dropdown; se por acaso não estiver entre as da loja, vai para o campo livre.
  void _preselectCategory(String category) {
    if (category.isEmpty) return;
    final existing = _existingCategories;
    if (existing.contains(category)) {
      _selectedCategoryOption = category;
    } else {
      _selectedCategoryOption = _kNewCategorySentinel;
      _newCategoryController.text = category;
    }
  }

  Future<void> _loadRules() async {
    setState(() => _rulesLoading = true);
    final rules = await PartnerPriceRules.load(
      appMarkupPct: widget.restaurant.appMarkupPct,
    );
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _rulesLoading = false;
    });
  }

  /// Categorias distintas já usadas pelos produtos desta loja (ordem alfabética).
  List<String> get _existingCategories {
    final products = context
        .read<PartnerProductStore>()
        .productsForRestaurant(widget.restaurant.id);
    final set = <String>{};
    for (final product in products) {
      final category = product.category.trim();
      if (category.isNotEmpty) set.add(category);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Categoria final a gravar: a selecionada no dropdown, ou o texto livre
  /// quando a loja não tem categorias ainda / o parceiro escolheu criar nova.
  String _resolveCategory(List<String> existingCategories) {
    if (existingCategories.isEmpty ||
        _selectedCategoryOption == _kNewCategorySentinel) {
      return _newCategoryController.text.trim();
    }
    return _selectedCategoryOption?.trim() ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _newCategoryController.dispose();
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

    // Loja parceira: o número escrito é o balcão; o preço do cliente vem da
    // regra da plataforma. Sem a regra lida do servidor não se grava — antes
    // recusar do que gravar um preço que engana o parceiro.
    double priceToSave = parsedPrice;
    double? shelfToSave;
    if (_isPartnerStore) {
      final rules = _rules;
      if (rules == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível ler as percentagens da '
                'plataforma. Verifica a ligação e tenta outra vez.'),
          ),
        );
        if (!_rulesLoading) _loadRules();
        return;
      }
      shelfToSave = parsedPrice;
      priceToSave = rules.appPriceFromShelf(parsedPrice);
    }

    final category = _resolveCategory(_existingCategories);
    if (category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique a categoria do produto.')),
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

    final store = context.read<PartnerProductStore>();
    final editing = widget.product;
    try {
      if (editing != null) {
        final ok = await store.updateProduct(
          restaurantId: widget.restaurant.id,
          productId: editing.id,
          name: _nameController.text,
          description: _descriptionController.text,
          price: priceToSave,
          partnerShelfPrice: shelfToSave,
          // Vazio = mantém a foto actual (o store trata assim).
          photoUrl: imageUrl,
          isAvailable: _isAvailable,
          category: category,
          allergens: _selectedAllergens.toList(),
        );
        if (!ok) {
          throw StateError('o servidor não aceitou a alteração');
        }
      } else {
        await store.addProduct(
          restaurantId: widget.restaurant.id,
          name: _nameController.text,
          description: _descriptionController.text,
          price: priceToSave,
          partnerShelfPrice: shelfToSave,
          photoUrl: imageUrl ?? '',
          isAvailable: _isAvailable,
          category: category,
          allergens: _selectedAllergens.toList(),
          requiresPrescription: _requiresPrescription,
        );
      }
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
      final photo = await SafeImagePicker.pickImage(
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
      final photo = await SafeImagePicker.pickImage(
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

  /// Duas linhas por baixo do preço, actualizadas a cada tecla:
  ///   Recebes: 8,00 €   O cliente vê: 9,33 €
  /// Sem jargão — o parceiro nunca faz contas nem vê percentagens.
  Widget _buildPricePreview(ThemeData theme) {
    final subtle = theme.textTheme.bodySmall?.color;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _priceController,
      builder: (context, value, _) {
        final rules = _rules;
        if (rules == null) {
          if (_rulesLoading) {
            return Text('A preparar o preço para o cliente…',
                style: theme.textTheme.bodySmall?.copyWith(color: subtle));
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  'Não foi possível ler as percentagens da plataforma.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),
              TextButton(
                onPressed: _rulesLoading ? null : _loadRules,
                child: const Text('Tentar outra vez'),
              ),
            ],
          );
        }
        final shelf = _parsePrice(value.text);
        if (shelf == null || shelf < 0) {
          return Text('Escreve o preço de balcão para veres o que o cliente paga.',
              style: theme.textTheme.bodySmall?.copyWith(color: subtle));
        }
        final clientPrice = rules.appPriceFromShelf(shelf);
        final strong = theme.textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recebes: ${formatEurPt(shelf)}', style: strong),
              const SizedBox(height: 2),
              Text('O cliente vê: ${formatEurPt(clientPrice)}',
                  style: strong),
            ],
          ),
        );
      },
    );
  }

  /// BUG 1 (2026-07-17): campo de categoria — dropdown com as categorias já
  /// usadas por esta loja + "Criar nova categoria"; se a loja ainda não tiver
  /// nenhuma, mostra logo o campo livre. Obrigatório.
  Widget _buildCategorySection() {
    final existingCategories = _existingCategories;
    final showFreeText = existingCategories.isEmpty ||
        _selectedCategoryOption == _kNewCategorySentinel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Categoria',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (existingCategories.isNotEmpty)
          DropdownButtonFormField<String>(
            value: _selectedCategoryOption,
            decoration: const InputDecoration(
              labelText: 'Categoria do produto',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            hint: const Text('Selecione a categoria'),
            items: [
              for (final category in existingCategories)
                DropdownMenuItem(value: category, child: Text(category)),
              const DropdownMenuItem(
                value: _kNewCategorySentinel,
                child: Text('+ Criar nova categoria'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _selectedCategoryOption = value),
          ),
        if (showFreeText) ...[
          if (existingCategories.isNotEmpty) const SizedBox(height: 12),
          TextFormField(
            controller: _newCategoryController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nome da categoria',
              hintText: 'Ex.: Pizzas, Sobremesas, Bebidas...',
              prefixIcon: Icon(Icons.new_label_outlined),
            ),
          ),
        ],
      ],
    );
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
                child: Image(
                  image: boraLocalImage(_selectedImage!.path),
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
                  backgroundColor: AppColors.primary,
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
                  backgroundColor: AppColors.primary,
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
        title: Text(
          widget.isEditing ? 'Editar produto' : 'Adicionar produto',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
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
                    widget.isEditing
                        ? 'Editar ${widget.product!.name}'
                        : 'Novo produto para ${widget.restaurant.name}',
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
                    decoration: InputDecoration(
                      labelText:
                          _isPartnerStore ? 'Preço que recebes' : 'Preço',
                      helperText: _isPartnerStore
                          ? 'O preço de balcão da tua loja. A app soma a '
                              'comissão por cima, sozinha.'
                          : null,
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.euro),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Indique o preço';
                      }
                      final parsed = _parsePrice(value);
                      if (parsed == null || parsed < 0) {
                        return 'Preço inválido';
                      }
                      return null;
                    },
                  ),
                  if (_isPartnerStore) ...[
                    const SizedBox(height: 8),
                    _buildPricePreview(theme),
                  ],
                  const SizedBox(height: 16),
                  _buildCategorySection(),
                  const SizedBox(height: 16),
                  // Parte 5 (rodada 2) — alergénios (comida) SÓ para restaurante.
                  // Uma farmácia/loja não vê declaração de alergénios de comida.
                  if (widget.restaurant.category ==
                      BusinessCategory.restaurant) ...[
                    Text(
                      'Alergénios',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Seleciona os alergénios presentes neste produto '
                      '(Reg. UE 1169/2011).',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSubtle),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in kAllergenLabels.entries)
                          FilterChip(
                            label: Text(entry.value,
                                style: const TextStyle(fontSize: 12)),
                            selected: _selectedAllergens.contains(entry.key),
                            onSelected: (sel) => setState(() {
                              if (sel) {
                                _selectedAllergens.add(entry.key);
                              } else {
                                _selectedAllergens.remove(entry.key);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Parte 5 (rodada 2) — farmácia: marca produtos que exigem
                  // receita médica (badge no cliente; só OTC devem ser vendidos).
                  // Só ao criar: o modelo em memória não carrega esta coluna,
                  // por isso em edição não se mostra um interruptor a mentir.
                  if (!widget.isEditing &&
                      widget.restaurant.category ==
                          BusinessCategory.pharmacy) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Requer receita médica'),
                      subtitle: const Text(
                          'Só medicamentos não sujeitos a receita (OTC) devem ser vendidos aqui.'),
                      value: _requiresPrescription,
                      onChanged: (v) =>
                          setState(() => _requiresPrescription = v),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                      label: Text(_isSaving
                          ? 'A guardar...'
                          : widget.isEditing
                              ? 'Guardar alterações'
                              : 'Guardar produto'),
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
