// Teste do gerador do mapa da app. Uso: node teste_mapa_app.mjs
// Cria um mini-projeto Flutter numa pasta temporária do sistema e confere o resultado.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { gerarMapa, gerarSql, limparTexto } from './gerar_mapa_app.mjs';

const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'mapa-app-teste-'));
const escrever = (rel, texto) => {
  const p = path.join(raiz, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, texto, 'utf8');
};

escrever('pubspec.yaml', 'name: app_teste\nversion: 9.8.7+123\n');

// 1. cliente: botão com literal, botão com tradução, interpolação, ListTile, comentário a ignorar
escrever('lib/screens/client/loja_screen.dart', `
import 'package:flutter/material.dart';
/// Exemplo no comentário: ElevatedButton(child: Text('Fantasma'))
class LojaScreen extends StatelessWidget {
  const LojaScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('A minha loja'.tr)),
      body: Column(children: [
        ElevatedButton(onPressed: () {}, child: const Text('Finalizar pedido')),
        OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.edit), label: Text('Editar perfil'.tr)),
        TextButton(onPressed: () {}, child: Text('Faltam {0} minutos'.trArgs([5]))),
        TextButton(onPressed: () {}, child: Text('Olá $nome, bem-vindo')),
        TextButton(onPressed: () {}, child: Text('Total: \${eur(total)}')),
        ListTile(title: Text('Os meus endereços'.tr), onTap: () {}),
        ElevatedButton(onPressed: () {}, child: const Text('Finalizar pedido')), // duplicado
        TextButton(onPressed: () {}, child: Text(variavelDinamica)),
        IconButton(tooltip: 'Fechar', icon: Icon(Icons.close), onPressed: () {}),
      ]),
    );
  }
}
`);

// 2. cliente: Tab e ternário e botão do design system
escrever('lib/screens/client/pedidos_screen.dart', `
class PedidosScreen extends StatefulWidget { const PedidosScreen({super.key}); @override State<PedidosScreen> createState() => _PedidosScreenState(); }
class _PedidosScreenState extends State<PedidosScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 2, child: Scaffold(
      appBar: AppBar(title: const Text('Pedidos'), bottom: TabBar(tabs: [Tab(text: 'Em curso'), Tab(child: Text('Anteriores'.tr))])),
      body: BotaoLaranja(texto: ativo ? 'Pausar'.tr : 'Retomar'.tr, onPressed: () {}),
    ));
  }
}
`);

// 3. design system: o gerador tem de descobrir sozinho que BotaoLaranja usa 'texto'
escrever('lib/widgets/bora/botao_laranja.dart', `
class BotaoLaranja extends StatelessWidget {
  const BotaoLaranja({super.key, required this.texto, required this.onPressed});
  final String texto;
  final VoidCallback? onPressed;
  @override Widget build(BuildContext context) => ElevatedButton(onPressed: onPressed, child: Text(texto));
}
`);

// 4. estafeta: pasta driver/
escrever('lib/screens/driver/ganhos_screen.dart', `
class GanhosScreen extends StatelessWidget {
  @override Widget build(BuildContext c) => Scaffold(body: FilledButton(onPressed: () {}, child: Text('Levantar ganhos'.tr)));
}
`);

// 5. parceiro: prefixo partner_ em lib/screens
escrever('lib/screens/partner_dashboard_screen.dart', `
class PartnerDashboardScreen extends StatelessWidget {
  @override Widget build(BuildContext c) => Scaffold(body: Row(children: [
    TextButton(onPressed: () {}, child: Text('Abrir loja'.tr)),
    BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Início'),
  ]));
}
`);

// 6. admin: pasta admin/ e registo do menu com rota
escrever('lib/screens/admin/admin_pedidos_screen.dart', `
class AdminPedidosScreen extends StatelessWidget {
  @override Widget build(BuildContext c) => Scaffold(body: ElevatedButton(onPressed: () {}, child: Text("Cancelar pedido")));
}
`);
escrever('lib/screens/admin/admin_menu_registry.dart', `
import 'admin_pedidos_screen.dart';
List<AdminMenuSection> adminMenuSections() => [
  AdminMenuSection(id: 'operacao', title: 'Operação do dia', items: [
    AdminMenuItem(id: 'operacao_pedidos', title: 'Pedidos', subtitle: 'x', builder: () => const AdminPedidosScreen()),
  ]),
];
`);

// 7. widget partilhado por cliente e parceiro (sem pasta própria): entra nas duas apps
escrever('lib/widgets/refund_choice_dialog.dart', `
class RefundChoiceDialog extends StatelessWidget {
  @override Widget build(BuildContext c) => AlertDialog(title: Text('Como queres o reembolso?'.tr), actions: [TextButton(onPressed: () {}, child: Text('Carteira Bora'.tr))]);
}
`);
escrever('lib/screens/client/pagar_screen.dart', "import '../../widgets/refund_choice_dialog.dart';\nclass PagarScreen extends StatelessWidget { Widget build(BuildContext c) => const RefundChoiceDialog(); }\n");
escrever('lib/screens/partner/reembolsos_screen.dart', "import '../../widgets/refund_choice_dialog.dart';\nclass ReembolsosScreen extends StatelessWidget { Widget build(BuildContext c) => const RefundChoiceDialog(); }\n");

// 8. ficheiro de uma app que ninguém importa e sem pasta: ignorado e contado
escrever('lib/widgets/orfao_sheet.dart', `class OrfaoSheet extends StatelessWidget { Widget build(BuildContext c) => TextButton(onPressed: () {}, child: Text('Sem dono')); }\n`);

// 9. rotas no main.dart
escrever('lib/main.dart', `
void main() { runApp(MaterialApp(routes: {
  '/loja': (_) => const LojaScreen(),
  '/admin/pedidos': (_) => const AdminPedidosScreen(),
})); }
`);

const r = gerarMapa(raiz);
const procurar = (app, ecra, elemento) => r.elementos.find((e) => e.app === app && e.ecra === ecra && e.elemento === elemento);

// versão
assert.equal(r.versao, '9.8.7+123');

// botão com literal
assert.equal(procurar('cliente', 'LojaScreen', 'Finalizar pedido')?.tipo, 'botao');
// botão com tradução (.tr) e botão .icon com label
assert.equal(procurar('cliente', 'LojaScreen', 'Editar perfil')?.tipo, 'botao');
assert.equal(procurar('estafeta', 'GanhosScreen', 'Levantar ganhos')?.tipo, 'botao');
// trArgs: {0} vira {…}
assert.equal(procurar('cliente', 'LojaScreen', 'Faltam {…} minutos')?.tipo, 'botao');
// interpolações $nome e ${...}
assert.ok(procurar('cliente', 'LojaScreen', 'Olá {…}, bem-vindo'));
assert.ok(procurar('cliente', 'LojaScreen', 'Total: {…}'));
// ListTile
assert.equal(procurar('cliente', 'LojaScreen', 'Os meus endereços')?.tipo, 'menu');
// título de AppBar
assert.equal(procurar('cliente', 'LojaScreen', 'A minha loja')?.tipo, 'titulo');
// IconButton com tooltip
assert.equal(procurar('cliente', 'LojaScreen', 'Fechar')?.tipo, 'botao');
// comentário não conta
assert.equal(procurar('cliente', 'LojaScreen', 'Fantasma'), undefined);
// duplicados: "Finalizar pedido" aparece 2 vezes no Dart e 1 só no mapa
assert.equal(r.elementos.filter((e) => e.app === 'cliente' && e.ecra === 'LojaScreen' && e.elemento === 'Finalizar pedido').length, 1);
// texto dinâmico não entra
assert.equal(r.elementos.some((e) => e.elemento.includes('variavelDinamica')), false);

// Tab (text: e child: Text) e State -> ecrã certo
assert.equal(procurar('cliente', 'PedidosScreen', 'Em curso')?.tipo, 'separador');
assert.equal(procurar('cliente', 'PedidosScreen', 'Anteriores')?.tipo, 'separador');
assert.equal(procurar('cliente', 'PedidosScreen', 'Pedidos')?.tipo, 'titulo');
// ternário dá os dois textos; botão do design system descoberto sozinho
assert.ok(procurar('cliente', 'PedidosScreen', 'Pausar'));
assert.ok(procurar('cliente', 'PedidosScreen', 'Retomar'));
assert.ok(r.custom.some((c) => c.startsWith('BotaoLaranja(texto)')));

// classificação por app: pasta, prefixo e menu do admin com rota
assert.equal(procurar('parceiro', 'PartnerDashboardScreen', 'Abrir loja')?.tipo, 'botao');
assert.equal(procurar('parceiro', 'PartnerDashboardScreen', 'Início')?.tipo, 'separador');
assert.equal(procurar('admin', 'AdminPedidosScreen', 'Cancelar pedido')?.rota, '/admin/pedidos');
assert.equal(procurar('admin', 'AdminMenu', 'Pedidos')?.rota, 'menu:operacao_pedidos');
assert.equal(procurar('cliente', 'LojaScreen', 'Finalizar pedido')?.rota, '/loja');
assert.equal(procurar('cliente', 'GanhosScreen', 'Levantar ganhos'), undefined, 'estafeta não pode vazar para cliente');

// widget partilhado entra nas duas apps que o usam, e só nessas
assert.ok(procurar('cliente', 'RefundChoiceDialog', 'Carteira Bora'));
assert.ok(procurar('parceiro', 'RefundChoiceDialog', 'Carteira Bora'));
assert.equal(procurar('estafeta', 'RefundChoiceDialog', 'Carteira Bora'), undefined);
assert.equal(procurar('cliente', 'RefundChoiceDialog', 'Como queres o reembolso?')?.tipo, 'titulo');

// ficheiro sem app é ignorado e contado
assert.ok(r.ignorados.some((i) => i.rel === 'lib/widgets/orfao_sheet.dart' && /app desconhecida/.test(i.motivo)));
assert.equal(r.elementos.some((e) => e.elemento === 'Sem dono'), false);

// limpeza de textos técnicos
assert.equal(limparTexto('  Olá   mundo '), 'Olá mundo');
assert.equal(limparTexto('admin_menu_item'), null);
assert.equal(limparTexto('/admin/users'), null);
assert.equal(limparTexto('{…}'), null);
assert.equal(limparTexto(''), null);

// SQL: aspas escapadas, lotes de 200 e DELETE comentado
const extra = [{ app: 'cliente', ecra: 'X', rota: null, elemento: "Não é o 'meu' botão", tipo: 'botao', ficheiro: 'lib/x.dart' }];
for (let i = 0; i < 250; i++) extra.push({ app: 'admin', ecra: 'Y', rota: '/a', elemento: `Botão ${i}`, tipo: 'menu', ficheiro: 'lib/y.dart' });
const sql = gerarSql(extra, '9.8.7+123');
assert.ok(sql.includes("'Não é o ''meu'' botão'"));
assert.equal((sql.match(/^insert into public\.mapa_app/gm) ?? []).length, 2);
assert.equal((sql.match(/on conflict \(app, ecra, elemento\) do update set/g) ?? []).length, 2);
assert.ok(/^-- delete from public\.mapa_app where versao is distinct from '9\.8\.7\+123';$/m.test(sql));
assert.equal(/^delete from/m.test(sql), false);

fs.rmSync(raiz, { recursive: true, force: true });
console.log(`OK: todos os testes passaram (${r.elementos.length} elementos no mini-projeto).`);
