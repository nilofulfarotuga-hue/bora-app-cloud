// Diário E2E (Maestro) — POST best-effort de 1 milestone para a tabela `e2e_log`.
// Dá OLHOS EM TEMPO REAL ao Claude.ai sobre o que o teste faz DENTRO de um flow
// (abriu loja, fez scroll, tocou produto, adicionou ao carrinho, finalizou...),
// coisa que o runner (que só regista início/fim de cada YAML) não vê.
//
// Env injetados pelo runner (--env, NUNCA no repo): SUPABASE_URL, SUPABASE_KEY, E2E_RUN_ID.
// Env por chamada (runFlow env:): DIARIO_FLUXO, DIARIO_PASSO, DIARIO_ESTADO, DIARIO_DETALHE.
//
// Observabilidade PURA: NUNCA lança — se a rede/credenciais falharem, o teste continua.
try {
  if (typeof SUPABASE_URL !== 'undefined' && SUPABASE_URL &&
      typeof SUPABASE_KEY !== 'undefined' && SUPABASE_KEY) {
    var payload = {
      fluxo:   (typeof DIARIO_FLUXO   !== 'undefined' ? DIARIO_FLUXO   : 'maestro'),
      passo:   (typeof DIARIO_PASSO   !== 'undefined' ? DIARIO_PASSO   : '?'),
      estado:  (typeof DIARIO_ESTADO  !== 'undefined' ? DIARIO_ESTADO  : 'passou'),
      detalhe: (typeof DIARIO_DETALHE !== 'undefined' ? DIARIO_DETALHE : ''),
      device:  'maestro',
      run_id:  (typeof E2E_RUN_ID     !== 'undefined' ? E2E_RUN_ID     : 'maestro')
    };
    http.post(SUPABASE_URL + '/rest/v1/e2e_log', {
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: 'Bearer ' + SUPABASE_KEY,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal'
      },
      body: JSON.stringify(payload)
    });
  }
} catch (e) {
  // best-effort: ignora qualquer falha (o diário nunca pode afundar o teste).
}
