// Ecrãs de CAPTURA para a App Store — missão `ios-lancamento` (2026-09-07).
//
// Nada aqui chama Supabase/Firebase/Stripe nem cria Timer nenhum: são widgets
// 100% estáticos, alimentados só por dados falsos escritos à mão neste
// ficheiro, para o `pumpAndSettle` do integration_test assentar sempre
// (determinismo é o único objetivo — ver `integration_test/capturas_loja_test.dart`).
//
// Regra de ouro (Danilo, 2026-09-07): NUNCA mostrar carro nem boleia/TVDE
// numa captura desta lista — só mercado, comida e serviços. Por isso o ecrã
// de lavagem usa ícones de água/espuma, nunca um ícone de carro.
//
// "1 elemento laranja por ecrã": em cada ecrã abaixo há OU o cabeçalho em
// gradiente laranja OU um botão de ação em laranja — nunca os dois ao mesmo
// tempo (ver comentário em cada widget).

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// Uma entrada do menu de capturas — usada pelo `main_capturas.dart` (menu
/// manual) e espelha, por ordem, os ficheiros que o CI vai gravar.
class CapturaScreenSpec {
  const CapturaScreenSpec({
    required this.fileName,
    required this.titulo,
    required this.builder,
  });

  /// Nome do ficheiro SEM extensão, ex.: `01-mercado`.
  final String fileName;
  final String titulo;
  final WidgetBuilder builder;
}

/// Lista canónica, na ordem exacta pedida para a App Store.
final List<CapturaScreenSpec> capturaScreens = <CapturaScreenSpec>[
  CapturaScreenSpec(
    fileName: '01-mercado',
    titulo: 'Mercado',
    builder: (_) => const CapturaMercadoScreen(),
  ),
  CapturaScreenSpec(
    fileName: '02-comida',
    titulo: 'Comida',
    builder: (_) => const CapturaComidaScreen(),
  ),
  CapturaScreenSpec(
    fileName: '03-barbearia',
    titulo: 'Barbearia',
    builder: (_) => const CapturaBarbeariaScreen(),
  ),
  CapturaScreenSpec(
    fileName: '04-acai',
    titulo: 'Açaí',
    builder: (_) => const CapturaAcaiScreen(),
  ),
  CapturaScreenSpec(
    fileName: '05-limpeza',
    titulo: 'Limpeza',
    builder: (_) => const CapturaLimpezaScreen(),
  ),
  CapturaScreenSpec(
    fileName: '06-favores',
    titulo: 'Favores',
    builder: (_) => const CapturaFavoresScreen(),
  ),
  CapturaScreenSpec(
    fileName: '07-lavagem',
    titulo: 'Lavagem',
    builder: (_) => const CapturaLavagemScreen(),
  ),
];

// ─────────────────────────────────────────────────────────────────────────
// Peças reutilizáveis (só desenho, sem lógica nenhuma)
// ─────────────────────────────────────────────────────────────────────────

/// Cabeçalho hero em gradiente de categoria — imita `BoraTileCard`/app bar
/// custom dos ecrãs reais, sem depender deles.
class _CapturaHeader extends StatelessWidget {
  const _CapturaHeader({
    required this.gradient,
    required this.icone,
    required this.titulo,
    required this.subtitulo,
  });

  final Gradient gradient;
  final IconData icone;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Spacing.xl,
        Spacing.huge,
        Spacing.xl,
        Spacing.xxl,
      ),
      decoration: BoxDecoration(gradient: gradient),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Icon(icone, color: Colors.white, size: 30),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Spacing.xxs),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
}

/// Placeholder de "foto" — bloco de cor com ícone, NUNCA uma foto real (regra
/// global agent-memory #1: nunca gerar/trocar foto real de produto/loja).
class _FotoPlaceholder extends StatelessWidget {
  const _FotoPlaceholder({required this.icone, required this.cor});

  final IconData icone;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Icon(icone, color: cor, size: 30),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.icone,
    required this.corIcone,
    required this.nome,
    required this.descricao,
    required this.preco,
  });

  final IconData icone;
  final Color corIcone;
  final String nome;
  final String descricao;
  final String preco;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowSm,
      ),
      child: Row(
        children: [
          _FotoPlaceholder(icone: icone, cor: corIcone),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Text(
                  descricao,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            preco,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão de ação — único elemento laranja permitido quando o cabeçalho do
/// ecrã NÃO for já laranja (ver comentário em cada screen).
class _CtaLaranja extends StatelessWidget {
  const _CtaLaranja({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          disabledBackgroundColor: AppColors.accent,
          disabledForegroundColor: Colors.white,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Botão de ação em verde — usado quando o cabeçalho já é laranja (ecrã de
/// comida), para manter só 1 elemento laranja por ecrã.
class _CtaVerde extends StatelessWidget {
  const _CtaVerde({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary,
          disabledForegroundColor: Colors.white,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: Spacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, this.selecionado = false});

  final String texto;
  final bool selecionado;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: Spacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: selecionado ? AppColors.primary : AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selecionado ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 1. Mercado — cabeçalho verde (tileSupermarkets); CTA laranja (carrinho).
// ─────────────────────────────────────────────────────────────────────────
class CapturaMercadoScreen extends StatelessWidget {
  const CapturaMercadoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileSupermarkets,
            icone: Icons.storefront_rounded,
            titulo: 'Mercado da Guarda',
            subtitulo: 'Entrega em 35–50 min · a partir de €2,50',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const [
                      _Chip(texto: 'Padaria', selecionado: true),
                      _Chip(texto: 'Laticínios'),
                      _Chip(texto: 'Bebidas'),
                      _Chip(texto: 'Limpeza'),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                const _ItemCard(
                  icone: Icons.bakery_dining_rounded,
                  corIcone: Color(0xFF16A34A),
                  nome: 'Pão de Forma Integral',
                  descricao: 'Embalagem 500g',
                  preco: '€1,49',
                ),
                const _ItemCard(
                  icone: Icons.icecream_rounded,
                  corIcone: Color(0xFF16A34A),
                  nome: 'Leite Meio Gordo',
                  descricao: 'Pacote 1L',
                  preco: '€0,89',
                ),
                const _ItemCard(
                  icone: Icons.local_drink_rounded,
                  corIcone: Color(0xFF16A34A),
                  nome: 'Água das Pedras',
                  descricao: 'Garrafa 1,5L',
                  preco: '€0,55',
                ),
                const _ItemCard(
                  icone: Icons.eco_rounded,
                  corIcone: Color(0xFF16A34A),
                  nome: 'Maçã Fuji',
                  descricao: 'Preço por kg',
                  preco: '€1,29',
                ),
                const SizedBox(height: Spacing.lg),
                const _CtaLaranja(texto: 'Ver carrinho (3) · €2,93'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 2. Comida — cabeçalho laranja (tileRestaurants); CTA verde (regra 1
//    laranja/ecrã: o cabeçalho já é o elemento laranja).
// ─────────────────────────────────────────────────────────────────────────
class CapturaComidaScreen extends StatelessWidget {
  const CapturaComidaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileRestaurants,
            icone: Icons.restaurant_rounded,
            titulo: 'Sabores de Casa',
            subtitulo: '★ 4.8 · Comida Portuguesa · 25–35 min',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: const [
                _ItemCard(
                  icone: Icons.lunch_dining_rounded,
                  corIcone: Color(0xFFF97316),
                  nome: 'Francesinha à Casa',
                  descricao: 'Com batata frita e molho especial',
                  preco: '€8,50',
                ),
                _ItemCard(
                  icone: Icons.set_meal_rounded,
                  corIcone: Color(0xFFF97316),
                  nome: 'Bitoque com Arroz',
                  descricao: 'Bife de vaca, ovo e batata frita',
                  preco: '€7,90',
                ),
                _ItemCard(
                  icone: Icons.rice_bowl_rounded,
                  corIcone: Color(0xFFF97316),
                  nome: 'Arroz de Marisco',
                  descricao: 'Dose para 1 pessoa',
                  preco: '€9,50',
                ),
                _ItemCard(
                  icone: Icons.bakery_dining_rounded,
                  corIcone: Color(0xFFF97316),
                  nome: 'Bifana no Pão',
                  descricao: 'Receita tradicional da casa',
                  preco: '€4,20',
                ),
                SizedBox(height: Spacing.lg),
                _CtaVerde(texto: 'Adicionar ao carrinho'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3. Barbearia — cabeçalho índigo (tileServices); CTA laranja.
// ─────────────────────────────────────────────────────────────────────────
class CapturaBarbeariaScreen extends StatelessWidget {
  const CapturaBarbeariaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileServices,
            icone: Icons.content_cut_rounded,
            titulo: 'Barbearias',
            subtitulo: 'Marca já o teu horário na Guarda',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: const [
                _ItemCard(
                  icone: Icons.content_cut_rounded,
                  corIcone: Color(0xFF4338CA),
                  nome: 'Barbearia Central',
                  descricao: '★ 4.9 · Corte + Barba · 40 min',
                  preco: '€15,00',
                ),
                _ItemCard(
                  icone: Icons.face_retouching_natural_rounded,
                  corIcone: Color(0xFF4338CA),
                  nome: 'Corte Clássico',
                  descricao: 'Máquina + tesoura, acabamento a navalha',
                  preco: '€10,00',
                ),
                _ItemCard(
                  icone: Icons.spa_rounded,
                  corIcone: Color(0xFF4338CA),
                  nome: 'Barba Completa',
                  descricao: 'Toalha quente e óleo hidratante',
                  preco: '€8,00',
                ),
                SizedBox(height: Spacing.lg),
                _CtaLaranja(texto: 'Marcar horário'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 4. Açaí — cabeçalho roxo-açaí (tileSobremesas); CTA laranja.
// ─────────────────────────────────────────────────────────────────────────
class CapturaAcaiScreen extends StatelessWidget {
  const CapturaAcaiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileSobremesas,
            icone: Icons.icecream_rounded,
            titulo: 'Goola Açaí',
            subtitulo: '★ 4.7 · Sobremesas · 20–30 min',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: const [
                _ItemCard(
                  icone: Icons.icecream_rounded,
                  corIcone: Color(0xFF6D28D9),
                  nome: 'Açaí Tradicional 500ml',
                  descricao: 'Com granola, banana e mel',
                  preco: '€4,50',
                ),
                _ItemCard(
                  icone: Icons.icecream_outlined,
                  corIcone: Color(0xFF6D28D9),
                  nome: 'Açaí Especial 700ml',
                  descricao: 'Morango, kiwi, granola e leite condensado',
                  preco: '€5,90',
                ),
                _ItemCard(
                  icone: Icons.cookie_rounded,
                  corIcone: Color(0xFF6D28D9),
                  nome: 'Sorvete de Morango',
                  descricao: 'Copo 300ml',
                  preco: '€3,50',
                ),
                SizedBox(height: Spacing.lg),
                _CtaLaranja(texto: 'Adicionar ao carrinho'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 5. Limpeza — cabeçalho azul-céu (tileCleaning); CTA laranja.
// ─────────────────────────────────────────────────────────────────────────
class CapturaLimpezaScreen extends StatelessWidget {
  const CapturaLimpezaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileCleaning,
            icone: Icons.cleaning_services_rounded,
            titulo: 'Limpeza ao domicílio',
            subtitulo: 'Profissionais verificados na Guarda',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: const [
                _ItemCard(
                  icone: Icons.home_rounded,
                  corIcone: Color(0xFF0284C7),
                  nome: 'Limpeza Padrão',
                  descricao: 'Sala, cozinha, quartos e casa de banho',
                  preco: '€25,00/h',
                ),
                _ItemCard(
                  icone: Icons.cleaning_services_rounded,
                  corIcone: Color(0xFF0284C7),
                  nome: 'Limpeza Profunda',
                  descricao: 'Inclui interior de armários e electrodomésticos',
                  preco: '€35,00/h',
                ),
                _ItemCard(
                  icone: Icons.window_rounded,
                  corIcone: Color(0xFF0284C7),
                  nome: 'Limpeza de Vidros',
                  descricao: 'Janelas e varandas',
                  preco: '€18,00/h',
                ),
                SizedBox(height: Spacing.lg),
                _CtaLaranja(texto: 'Marcar limpeza'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 6. Favores — cabeçalho teal (tileErrand); CTA laranja.
// ─────────────────────────────────────────────────────────────────────────
class CapturaFavoresScreen extends StatelessWidget {
  const CapturaFavoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileErrand,
            icone: Icons.shopping_bag_rounded,
            titulo: 'Favores',
            subtitulo: 'Compramos e entregamos o que precisares',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Container(
                  padding: const EdgeInsets.all(Spacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    boxShadow: AppColors.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'O que precisas que a gente resolva?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                      Container(
                        padding: const EdgeInsets.all(Spacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        child: const Text(
                          'Levantar uma encomenda nos CTT e trazer até casa',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                      const Row(
                        children: [
                          Icon(Icons.euro_rounded,
                              size: 18, color: AppColors.textSecondary),
                          SizedBox(width: Spacing.xs),
                          Text(
                            'Orçamento até €10,00',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                const _ItemCard(
                  icone: Icons.local_shipping_rounded,
                  corIcone: Color(0xFF14B8A6),
                  nome: 'Levar / Enviar',
                  descricao: 'Documentos e encomendas pequenas',
                  preco: 'Desde €4,50',
                ),
                const _ItemCard(
                  icone: Icons.receipt_long_rounded,
                  corIcone: Color(0xFF14B8A6),
                  nome: 'Comprar por mim',
                  descricao: 'A gente vai à loja e traz — talão real',
                  preco: 'Desde €6,00',
                ),
                const SizedBox(height: Spacing.lg),
                const _CtaLaranja(texto: 'Pedir favor'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 7. Lavagem — cabeçalho ciano-petróleo (tileCarwash); CTA laranja.
//    Regra de ouro: SEM ícone de carro/TVDE — só água/espuma/brilho.
// ─────────────────────────────────────────────────────────────────────────
class CapturaLavagemScreen extends StatelessWidget {
  const CapturaLavagemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _CapturaHeader(
            gradient: AppColors.tileCarwash,
            icone: Icons.water_drop_rounded,
            titulo: 'Lavagem ao domicílio',
            subtitulo: 'Nós vamos até ti, com água e produto',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.lg),
              children: const [
                _ItemCard(
                  icone: Icons.water_drop_rounded,
                  corIcone: Color(0xFF155E75),
                  nome: 'Lavagem Simples',
                  descricao: 'Exterior com espuma activa',
                  preco: '€8,00',
                ),
                _ItemCard(
                  icone: Icons.bubble_chart_rounded,
                  corIcone: Color(0xFF155E75),
                  nome: 'Lavagem Completa',
                  descricao: 'Exterior + interior aspirado',
                  preco: '€15,00',
                ),
                _ItemCard(
                  icone: Icons.auto_awesome_rounded,
                  corIcone: Color(0xFF155E75),
                  nome: 'Lavagem + Cera',
                  descricao: 'Brilho e proteção extra',
                  preco: '€20,00',
                ),
                SizedBox(height: Spacing.lg),
                _CtaLaranja(texto: 'Marcar lavagem'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
