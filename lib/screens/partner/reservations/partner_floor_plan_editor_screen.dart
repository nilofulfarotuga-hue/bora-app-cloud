import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../models/floor_plan.dart';
import '../../../models/restaurant_table.dart';
import '../../../stores/partner_reservas_store.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import 'partner_table_form_screen.dart';

/// Reservas PRO F4 — editor visual planta de sala.
///
/// Drag&drop com Stack + Positioned + GestureDetector (sem packages
/// externos). InteractiveViewer para zoom 0.5x..3x. Persist no
/// onPanEnd para evitar saturar BD.
///
/// Layout inspirado em Resy Manager floor plan.
class PartnerFloorPlanEditorScreen extends StatefulWidget {
  const PartnerFloorPlanEditorScreen({
    super.key,
    required this.restaurantId,
  });

  final String restaurantId;

  @override
  State<PartnerFloorPlanEditorScreen> createState() =>
      _PartnerFloorPlanEditorScreenState();
}

class _PartnerFloorPlanEditorScreenState
    extends State<PartnerFloorPlanEditorScreen> {
  static const double _scale = 0.5; // 1cm = 0.5px.

  List<FloorPlan> _floorPlans = const [];
  List<RestaurantTable> _tables = const [];
  FloorPlan? _selectedPlan;
  bool _loading = true;
  String? _draggingTableId;
  final Map<String, Offset> _localPositions = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final store = context.read<PartnerReservasStore>();
      final plans = await store.fetchFloorPlans(widget.restaurantId);
      if (!mounted) return;
      _floorPlans = plans;
      _selectedPlan = plans.isNotEmpty ? plans.first : null;
      if (_selectedPlan != null) {
        _tables = await store.fetchTables(
          restaurantId: widget.restaurantId,
          floorPlanId: _selectedPlan!.id,
        );
      } else {
        _tables = const [];
      }
      _localPositions.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchPlan(FloorPlan plan) async {
    setState(() => _loading = true);
    try {
      _selectedPlan = plan;
      _tables = await context.read<PartnerReservasStore>().fetchTables(
            restaurantId: widget.restaurantId,
            floorPlanId: plan.id,
          );
      _localPositions.clear();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createDefaultPlan() async {
    try {
      await context.read<PartnerReservasStore>().createFloorPlan(
            restaurantId: widget.restaurantId,
            name: 'Sala principal',
            isDefault: true,
          );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _createNewPlan() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo plano'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Nome do plano',
            hintText: 'Ex: Esplanada de Verão',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await context.read<PartnerReservasStore>().createFloorPlan(
            restaurantId: widget.restaurantId,
            name: name,
            isDefault: _floorPlans.isEmpty,
          );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _addTable() async {
    if (_selectedPlan == null) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PartnerTableFormScreen(
          restaurantId: widget.restaurantId,
          floorPlanId: _selectedPlan!.id,
        ),
      ),
    );
    if (ok == true) {
      await _loadAll();
    }
  }

  Future<void> _editTable(RestaurantTable t) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PartnerTableFormScreen(
          restaurantId: widget.restaurantId,
          floorPlanId: t.floorPlanId,
          existing: t,
        ),
      ),
    );
    if (ok == true) {
      await _loadAll();
    }
  }

  Future<void> _confirmDelete(RestaurantTable t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar mesa?'),
        content: Text('Mesa ${t.numero} será removida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<PartnerReservasStore>().deleteTable(t.id);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Planta de sala',
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'new') _createNewPlan();
              if (v.startsWith('plan:')) {
                final id = v.substring(5);
                final plan = _floorPlans.firstWhere(
                  (p) => p.id == id,
                  orElse: () => _selectedPlan!,
                );
                _switchPlan(plan);
              }
            },
            itemBuilder: (_) => [
              for (final p in _floorPlans)
                PopupMenuItem(
                  value: 'plan:${p.id}',
                  child: Row(
                    children: [
                      if (_selectedPlan?.id == p.id)
                        const Icon(Icons.check,
                            size: 18, color: AppColors.primary)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text(p.name),
                    ],
                  ),
                ),
              if (_floorPlans.isNotEmpty) const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 18),
                    SizedBox(width: 8),
                    Text('Novo plano'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _selectedPlan == null
          ? null
          : FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _addTable,
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _selectedPlan == null
              ? _emptyState()
              : _buildEditor(),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Sem planos de sala',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cria o primeiro plano para começar a configurar mesas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _createDefaultPlan,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Criar plano padrão'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final plan = _selectedPlan!;
    final canvasW = plan.widthCm * _scale;
    final canvasH = plan.heightCm * _scale;
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 3.0,
      boundaryMargin: const EdgeInsets.all(80),
      child: Center(
        child: Container(
          width: canvasW,
          height: canvasH,
          decoration: BoxDecoration(
            color: const Color(0xFFE8EAED),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Stack(
            children: [
              for (final t in _tables) _buildTableWidget(t),
              if (_tables.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Plano vazio.\nUsa o + para adicionar mesas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableWidget(RestaurantTable t) {
    final pos = _localPositions[t.id] ?? Offset(t.posX, t.posY);
    final w = _tableWidth(t.capacity);
    final h = _tableHeight(t.capacity);
    final isDragging = _draggingTableId == t.id;
    return Positioned(
      left: pos.dx * _scale,
      top: pos.dy * _scale,
      child: GestureDetector(
        onTap: () => _editTable(t),
        onLongPress: () => _confirmDelete(t),
        onPanStart: (_) {
          setState(() => _draggingTableId = t.id);
        },
        onPanUpdate: (details) {
          final maxX = _selectedPlan!.widthCm.toDouble();
          final maxY = _selectedPlan!.heightCm.toDouble();
          setState(() {
            final cur = _localPositions[t.id] ?? Offset(t.posX, t.posY);
            _localPositions[t.id] = Offset(
              (cur.dx + details.delta.dx / _scale).clamp(0, maxX),
              (cur.dy + details.delta.dy / _scale).clamp(0, maxY),
            );
          });
        },
        onPanEnd: (_) async {
          final newPos = _localPositions[t.id]!;
          try {
            await context.read<PartnerReservasStore>().updateTablePosition(
                  tableId: t.id,
                  posX: newPos.dx,
                  posY: newPos.dy,
                );
          } catch (_) {
            if (mounted) {
              setState(() => _localPositions.remove(t.id));
            }
          }
          if (mounted) setState(() => _draggingTableId = null);
        },
        child: Container(
          width: w,
          height: h,
          decoration: _shapeDecoration(t.shape, isDragging),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.numero,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${t.capacity}p',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _tableWidth(int capacity) =>
      (40 + capacity * 8).clamp(40, 120).toDouble();
  static double _tableHeight(int capacity) =>
      (40 + (capacity ~/ 4) * 8).clamp(40, 80).toDouble();

  static BoxDecoration _shapeDecoration(String shape, bool dragging) {
    const color = AppColors.primary;
    final border = dragging
        ? Border.all(color: AppColors.accent, width: 3)
        : Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1);
    if (shape == 'circle') {
      return BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border,
      );
    }
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(shape == 'square' ? 6 : 4),
      border: border,
    );
  }
}
