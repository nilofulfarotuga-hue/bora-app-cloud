---
tema: licao-supabase-em-teste-liga-app-links · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-supabase-em-teste-liga-app-links
tipo: licao
origem: [commit ac626b95, test/loja_fechada_ficha_e_repetir_test.dart, test/home_faixas_toque_test.dart, test/home_esqueleto_ecra_estreito_test.dart, e2e_log 2941]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — `Supabase.initialize` num teste liga o ouvinte de links; passa no Windows, cai no macOS

- **Contexto:** testes Flutter que arrancam o Supabase contra um servidor de brincar (para
  provar a ficha da loja fechada e as faixas da home).
- **A descoberta:** por omissão o `Supabase.initialize` liga o ouvinte de links
  (`app_links`, canal `com.llfbandit.app_links/events`). Em teste não há plugin, e o
  `MissingPluginException` chega **assíncrono**:
  - no **Windows do PC** cai fora dos testes → tudo passa;
  - no **macOS do CI do iPhone** cai **dentro** do 1.º teste → o
    `expect(tester.takeException(), isNull)` falha.
- **O que aconteceu (05/10/2026):** iOS #166 (commit `744fe903`): **"998 tests passed,
  1 failed"**, em `test/loja_fechada_ficha_e_repetir_test.dart:236`. A app não tinha defeito.
- **Medição da causa:** rascunho com contador de ligações ao canal: `LIGACOES_APP_LINKS=1` com
  a configuração normal, `0` com `detectSessionInUri: false` (registado no `e2e_log` id 2941,
  fluxo `fecho-home-dinheiro-2026-10-05`, passo `B3-ios-correccao`).
- **Regra a aplicar:**
  1. Teste que arranca o Supabase com servidor de brincar passa **sempre**
     `authOptions: const FlutterAuthClientOptions(detectSessionInUri: false)`. Os testes não
     usam links.
  2. **"Passa no PC" não prova que passa no macOS.** Excepções assíncronas de plugins em
     falta podem cair noutro teste (ou em nenhum) consoante a plataforma.
- **Evidência:** commit `ac626b95` — 3 ficheiros de teste, 4 linhas em cada (12 inserções,
  0 remoções, nenhum `expect` mudado); `+22: All tests passed!` no PC; relatório
  `.claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md` ("iPhone #166"). O Juiz deu
  `PHANTOM_FIX` a este conserto — ver `licao-juiz-phantom-fix-em-arnes-de-teste.md`.

`estado: atual`
