// Vigia do servidor em português de gente (17/11/2026, missão
// servidor-busca-leve-2026-11-17, B4). O servidor grava `quem` e `o_que` em
// cada medição a partir da migração 20261117100400 (funções vigia_quem e
// vigia_o_que); estas duas funções dão o mesmo texto às medições antigas, que
// só têm o papel (role) e o SQL.
library;

/// Quem gerou a carga, a partir do papel (role) da base.
String quemGerouCarga(String? papel) {
  switch (papel) {
    case 'anon':
      return 'pessoas sem login (pode ser o robô de teste do Google depois de uma versão nova)';
    case 'authenticated':
      return 'clientes com conta';
    case 'service_role':
      return 'os robôs e funções internas da Bora';
    case 'supabase_admin':
      return 'o próprio Supabase (tempo real e manutenção)';
    case 'postgres':
      return 'tarefas agendadas e administração';
    case 'authenticator':
      return 'a ligação da API';
  }
  final p = (papel ?? '').trim();
  return p.isEmpty ? 'desconhecido' : p;
}

const Map<String, String> _funcoes = {
  'search_products': 'a lupa dentro das lojas (search_products)',
  'cliente_pesquisar': 'a lupa da página inicial (cliente_pesquisar)',
  'pesquisa_produtos': 'a pesquisa de produtos (pesquisa_produtos)',
  'assistant_search_products':
      'o assistente de compras (assistant_search_products)',
  'agent_search_products': 'o robô de suporte (agent_search_products)',
};

const Map<String, String> _tabelas = {
  'orders': 'a leitura dos pedidos (tabela orders)',
  'products': 'a leitura dos produtos (tabela products)',
  'restaurants': 'a leitura das lojas (tabela restaurants)',
};

final RegExp _rpcComAspas = RegExp(r'"public"\."([A-Za-z0-9_]+)"\(');
final RegExp _rpcSemAspas = RegExp(r'public\.([A-Za-z0-9_]+)\(');
final RegExp _tabela = RegExp(r'FROM "public"\."([A-Za-z0-9_]+)"');

/// O quê gerou a carga: o nome da função (RPC) ou da tabela, em vez do SQL.
String oQueGerouCarga(String? consulta) {
  final c = (consulta ?? '').trim();
  if (c.isEmpty) return 'desconhecido';
  final rpc =
      _rpcComAspas.firstMatch(c)?.group(1) ??
      _rpcSemAspas.firstMatch(c)?.group(1);
  if (rpc != null) return _funcoes[rpc] ?? 'a função $rpc';
  if (c.contains('wal->>')) {
    return 'o tempo real do Supabase a ler as alterações';
  }
  final t = _tabela.firstMatch(c)?.group(1);
  if (t != null) return _tabelas[t] ?? 'a leitura da tabela $t';
  final curta = c.replaceAll(RegExp(r'\s+'), ' ');
  return 'uma consulta: ${curta.length > 80 ? curta.substring(0, 80) : curta}';
}
