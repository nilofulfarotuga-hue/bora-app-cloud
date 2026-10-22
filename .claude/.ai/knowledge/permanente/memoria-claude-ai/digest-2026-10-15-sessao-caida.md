---
id: memoria-claude-ai-digest-2026-10-15-sessao-caida
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-15
zona: verde
confianca: alta
estado: atual
---

# Claude Code 15/10 — sessão caída volta à entrada

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-15-sessao-caida`, origem `claude-code`, atualizada em 2026-10-15T19:25:42.251401+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 15 sessao caida · memoria claude.ai · claude_ai_memoria

Missão sessao-caida-volta-ao-login-2026-10-15 (Claude Code no PC, Opus). Origem: a 15/10 o dono do Sabores de Casa ficou no Editar produto da web com a sessão caída; o AuthStore ignorava o fim da sessão e tudo ia sem login (erro das percentagens). O que funciona agora: quando o Supabase emite signedOut que não foi a app a pedir (refresh recusado, sessão sem dados, saída noutro separador) e há conta em memória, a app espera 2 s e, se continuar sem sessão, limpa a conta como o Sair (sem apagar biometria nem o papel), fecha os ecrãs por cima, abre a entrada do papel certo e mostra "A tua sessão terminou. Entra outra vez.". Queda de rede não faz nada (gotrue 2.27.3 manda-a como erro do stream). Nos ecrãs do parceiro que gravam (produto, esgotado, apagar), sem sessão ou 401 manda entrar; num 401 com sessão no aparelho tenta renovar primeiro (AuthStore.sessaoCaiu). Teste test/sessao_caida_volta_ao_login_test.dart (5 casos, SDK real com servidor falso). Prova web antes/depois em app.boraguarda.com com a conta de teste demo-parceiro, logout global SÓ nessa conta e relógio do Playwright +65 min (guião em .claude/.ai/provas/sessao-caida-2026-10-15/). Publicado nas três: commits dcc9a7fe + 7f36106e, Android 673, iPhone build 193 no App Store Connect, web #219. Parceiro chama estafeta: interruptor true desde 15/10 12:42 UTC; business_rules §2.4.1 e bugs-resolvidos #25 (repo) atualizados; no repo só ficou a migração 20261015123951_reconhecer — a bora-tranca recusou gravar a 124007 e a 124038 (SQL só em supabase_migrations.schema_migrations). Córtex #25: proposta prop-67e6ccd3 por aprovar. O que falta: decidir a tranca para cópias de migrações já aplicadas; aprovar a proposta; tratar numa missão própria o arranque com sessão guardada morta e a sessão de convidado partida (guest@bora.com não entra).
