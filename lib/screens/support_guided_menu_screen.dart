// Chat guiado por categoria (2026-07-14) — pedido Danilo.
// "Sobre o que queres falar?" -> categorias -> sub-opções -> resposta pronta.
// Dados vêm de support_categories/support_category_options (editável no admin).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import 'support_human_chat_screen.dart';

class SupportGuidedMenuScreen extends StatefulWidget {
  const SupportGuidedMenuScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<SupportGuidedMenuScreen> createState() =>
      _SupportGuidedMenuScreenState();
}

class _SupportGuidedMenuScreenState extends State<SupportGuidedMenuScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _selectedCategory;
  List<Map<String, dynamic>> _options = [];
  bool _loadingOptions = false;
  Map<String, dynamic>? _selectedOption;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('support_categories')
          .select('id, slug, label, icon, sort_order')
          .eq('active', true)
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() {
        _categories = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar as categorias.';
        _loading = false;
      });
    }
  }

  Future<void> _openCategory(Map<String, dynamic> category) async {
    setState(() {
      _selectedCategory = category;
      _loadingOptions = true;
      _selectedOption = null;
    });
    try {
      final rows = await _supabase
          .from('support_category_options')
          .select('id, question, answer_md, sort_order')
          .eq('category_id', category['id'])
          .eq('active', true)
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() {
        _options = List<Map<String, dynamic>>.from(rows as List);
        _loadingOptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _options = [];
        _loadingOptions = false;
      });
    }
  }

  void _goBack() {
    if (_selectedOption != null) {
      setState(() => _selectedOption = null);
    } else if (_selectedCategory != null) {
      setState(() {
        _selectedCategory = null;
        _options = [];
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  void _openHumanChat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportHumanChatScreen(orderId: widget.orderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
        title: Text(
          _selectedOption != null
              ? 'Resposta'
              : _selectedCategory != null
                  ? (_selectedCategory!['label'] as String)
                  : 'Sobre o que queres falar?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadCategories);
    }
    if (_selectedOption != null) {
      return _AnswerView(
        option: _selectedOption!,
        onResolved: () => Navigator.of(context).pop(),
        onTalkToHuman: _openHumanChat,
      );
    }
    if (_selectedCategory != null) {
      return _OptionsList(
        loading: _loadingOptions,
        options: _options,
        onSelect: (o) => setState(() => _selectedOption = o),
        onTalkToHuman: _openHumanChat,
      );
    }
    return _CategoriesList(
      categories: _categories,
      onSelect: _openCategory,
      onTalkToHuman: _openHumanChat,
    );
  }
}

const Map<String, IconData> _kIconMap = {
  'restaurant': Icons.restaurant,
  'local_grocery_store': Icons.local_grocery_store,
  'delivery_dining': Icons.delivery_dining,
  'local_taxi': Icons.local_taxi,
  'cleaning_services': Icons.cleaning_services,
  'event_seat': Icons.event_seat,
  'person_outline': Icons.person_outline,
};

IconData _iconFor(String? name) => _kIconMap[name] ?? Icons.help_outline;

class _CategoriesList extends StatelessWidget {
  const _CategoriesList({
    required this.categories,
    required this.onSelect,
    required this.onTalkToHuman,
  });

  final List<Map<String, dynamic>> categories;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onTalkToHuman;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Escolhe uma categoria para veres respostas rápidas:',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        ...categories.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MenuTile(
              icon: _iconFor(c['icon'] as String?),
              label: c['label'] as String,
              onTap: () => onSelect(c),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.support_agent,
          label: 'Falar com um humano',
          highlight: true,
          onTap: onTalkToHuman,
        ),
      ],
    );
  }
}

class _OptionsList extends StatelessWidget {
  const _OptionsList({
    required this.loading,
    required this.options,
    required this.onSelect,
    required this.onTalkToHuman,
  });

  final bool loading;
  final List<Map<String, dynamic>> options;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onTalkToHuman;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (options.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Ainda não há respostas prontas para esta categoria.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ...options.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MenuTile(
                icon: Icons.help_outline,
                label: o['question'] as String,
                onTap: () => onSelect(o),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.support_agent,
          label: 'Nenhuma destas — falar com um humano',
          highlight: true,
          onTap: onTalkToHuman,
        ),
      ],
    );
  }
}

class _AnswerView extends StatelessWidget {
  const _AnswerView({
    required this.option,
    required this.onResolved,
    required this.onTalkToHuman,
  });

  final Map<String, dynamic> option;
  final VoidCallback onResolved;
  final VoidCallback onTalkToHuman;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            option['question'] as String,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text(
              option['answer_md'] as String,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onResolved,
            child: const Text('Resolveu, obrigado!'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onTalkToHuman,
            icon: const Icon(Icons.support_agent),
            label: const Text('Ainda preciso de ajuda — falar com humano'),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.accent : AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlight ? color.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight ? color.withOpacity(0.4) : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }
}
