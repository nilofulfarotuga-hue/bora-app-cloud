# Prompt da missão `sistema-sem-travas-2026-10-15`

> Registado a 15/10/2026 a partir do que chegou ao Claude Code (colado pelo Danilo, escrito na
> Claude.ai). Mesmas palavras; algumas sub-listas foram juntadas numa linha.
> O relatório da missão está em `docs/missoes/2026-10-15-sistema-sem-travas-RELATORIO.md`.

⚠️ MODO PROTECÇÃO TOTAL ⚠️
MOTOR: OPUS 5.5 · PORTA: Claude Code no PC do Danilo · SESSÃO NOVA
PASTA: bora-app-cloud · RAMO: autonomous-night-2026-04-29
WORKTREE: próprio · RUN_ID: sistema-sem-travas-2026-10-15

1. CONTEXTO E REGRAS DE DECISÃO
- Invoca o orquestrador CEO-AI em .claude/skills/ceo-ai/.
- Lê PADRAO_BORA.md, .claude/skills/protocolo-missao-bora e .claude/skills/danilo-como-trabalhar.
- Consulta o Córtex (cortex_buscar) antes de cada bloco.
- AUTORIZAÇÃO DO DANILO (15/10/2026): "Fazer tudo que for necessário dentro do escopo Bora (chave Supabase, trancas, RAM, missões paradas, mapa, pesquisa, ecrã limpeza, receita do dia)."
- NÃO COBRE (proibido nesta missão): mudar preços, comissões, taxas ou ganhos; Stripe; tokens; carteira/ledger; ligar reembolsos novos; segredos fora do vault; apagar dados de produção (pedidos, utilizadores, pagamentos, reservas). Isto exige "autorizo" concreto do Danilo na Claude.ai, com data.
- REGRAS DE DECISÃO (Aplicar antes de agir):
  1. Reversível → Fazer sem perguntar.
  2. Irreversível permitido (troca de chave, envio para o servidor, publicar nas 3) → Fazer e registar decisão e porquê no e2e_log.
  3. Algo na lista NÃO COBRE ou contradição com a autorização → Parar esse passo, registar bloqueio, 1 Telegram, seguir para o próximo bloco, voltar ao fim.
  4. Ambiguidade técnica → Assumir a solução mais conservadora (segura) e documentar.
  5. Nunca terminar o turno com "esperando aprovação". Se não podes fazer, documenta e segue.
- REGRAS DE COMUNICAÇÃO:
  - Nunca ficas 15 min sem output visível.
  - Bloqueio crítico → 1 mensagem Telegram com link exato do que falta + seguir para o bloco seguinte.
  - Erro encontrado no caminho → REPORTAS no e2e_log e relatório final. Nunca corriges calado.
  - O Danilo não faz nada à mão: tudo o que for clicar em painéis fazes tu pelo Chrome (perfil Bora deviceId d9e862e0-a5ea-486f-b054-f333ef51b46a; perfil pessoal deviceId 5b260cdd-9d4f-49d6-842b-ebfbfea69c75).
  - Estilo: Texto corrido, sem jargão. Relatório final: "Fiz isto, falta isto".

2. BLOCO 0 — SEGURANÇA DA CHAVE SUPABASE (Prioridade Máxima)
- FACTO: Repo github.com/nilofulfarotuga-hue/bora-app-cloud está PÚBLICO. Chave service_role exposta em 3 scripts antigos e possivelmente em temp_schema_dump.sql. No banco, 58 funções lêem a vault 'service_role_key' e 9 usam _dispatch_jwt() (vault 'dispatch_anon_jwt').
- AÇÃO 0.1 (Repo Privado): gh repo edit nilofulfarotuga-hue/bora-app-cloud --visibility private --accept-visibility-change-consequences; fallback pelo Chrome perfil pessoal (github.com → repo → Settings → Danger Zone → Change visibility). Validar: Confirmar que o CI do GitHub Actions continua a correr.
- AÇÃO 0.2 (Limpar Código): Grep por "service_role" e "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" em scripts/, supabase/, backend/, .github/ e raiz. Substituir literais por variáveis de ambiente/vault. Apagar temp_schema_dump.sql se contiver segredos. Commit: "chore: segredos fora do código".
- AÇÃO 0.3 (Nova Chave Secreta): Criar nova chave no Supabase pelo Chrome perfil Bora: Dashboard → Project Settings → API Keys → Secret keys → Create, nome "bora-server-2026-10-15". Guardar SÓ em: vault (vault.update_secret no secret 'service_role_key'), GitHub Secrets, .env local (fora do repo), VPS env (Hermes/carteiro). NUNCA em ficheiro versionado ou chat. Validação: Edge Function responde 200 com a nova chave; cron dispatch/fecho corre sem erro depois da troca.
- AÇÃO 0.4 (Migração App/Admin): Trocar anon key legada pela publishable key (sb_publishable_ylfhSuS2D_JoKmtFY-x6-A_DlOgHhVP) em lib/, web/ e .dart_defines. Confirmar suporte no supabase_flutter na documentação oficial antes. Publicar nas 3 plataformas via CI. Se não existir mecanismo de "versão mínima", registar como pendência. Não inventar.
- AÇÃO 0.5 (Gestão de Legado): NÃO desligar chaves legadas agora (apps instaladas dependem). Criar docs/SEGURANCA-CHAVES.md: o que foi feito e quando desligar as legadas (quando a maioria das instalações estiver na versão nova). Esse clique fica para a Claude.ai/Danilo.
- AÇÃO 0.6 (Histórico Git): NÃO reescrever histórico git. Registar no e2e_log que o histórico ainda contém a chave antiga até as legadas serem desligadas.

3. BLOCO 1 — TRANCAS NOSSAS (Inventário e Defeitos)
- OBJECTIVO: Entender as 8 paragens desta semana (10/10, 13/10, 15/10) e corrigir falsos positivos.
- AÇÃO 1.1 (Inventário): Criar docs/TRANCAS.md. Listar: bora-tranca, bora-vigia, hooks .claude, zonas do CEO-AI, classificador do carteiro na VPS. Para cada uma: onde vive, o que bloqueia, contagem de disparos (e2e_log fluxo bora-mods + grep), falso positivo?
- AÇÃO 1.2 (Pesquisa Técnica): Subagente claude-code-guide + web: como o Claude Code 2.1.x decide permissões (allow/deny/ask, hooks, settings.json, modo Automático em Controlo Remoto). Resumir em 10 linhas em docs/TRANCAS.md.
- AÇÃO 1.3 (Correções Específicas): (a) bora-tranca: deixar de bloquear por palavras da lista "NÃO tocar" se for apenas menção. Bloquear só com verbo de escrita + ficheiro de dinheiro. Permitir rm dentro de scratchpad/worktree. (b) Fluxo de bloqueio: tranca bloqueia → e2e_log + 1 Telegram (link) + seguir para o próximo bloco. (c) bora-vigia: ao 10.º minuto parado, injectar "continua com o próximo bloco" e registar. (d) CEO-AI/Carteiro: corrigir o mesmo falso positivo de palavras "NÃO tocar". (e) Permissões do Claude Code: PROPOR mudanças allow/deny/defaultMode em docs/TRANCAS.md, linha a linha. NÃO aplicar nesta missão.
- AÇÃO 1.4 (Prova): Testar no worktree: 1 leitura, 1 edição em lib/screens, 1 rm em scratchpad. Contar caixas de permissão antes/depois. Registar no e2e_log.
- AÇÃO 1.5 (Memória e Skills): Confirmar que o "Protocolo Danilo" (colado antes desta missão) está no CLAUDE.md, em ~/.claude/CLAUDE.md e em .claude/skills/danilo-como-trabalhar/SKILL.md. Criar skill navegadores-e-contas com os deviceIds e o que cada perfil abre.

4. BLOCO 2 — RAM DO PC (Diagnóstico e Limpeza)
- FACTO: 15/10 06:56 o PC ficou com 470 MB livres. "System UI isn't responding". Emulador desligado.
- AÇÃO 2.1 (Medição): PowerShell: RAM total/livre, Get-Process (top 25 WorkingSet). Tarefas agendadas activas (BoraStudioRelogio, BoraStudioCondutor, EmDia-Retomar, radar, carteiro, ponte Hermes). Contar: claude.exe, node, java/qemu, chrome (por perfil), vmmem, Obsidian, OpenCode. Gravar em docs/RAM-2026-10-15.md. Responder "o que estamos a fazer de errado" em 5 linhas.
- AÇÃO 2.2 (Limpeza): Matar emuladores e sessões órfãs (nunca o Chrome do Danilo nem sessões Claude activas). AVD único: 2048 MB, -no-snapshot-save. Se WSL/Docker: .wslconfig memory=4GB. Desligar tarefas agendadas de 15 em 15 min não críticas (BoraStudio parado desde 30/09). Registar quais. Chrome: ligar descarte de separadores. Regra nova em protocolo-missao-bora: antes de abrir emulador, ≥ 3 GB livres.
- AÇÃO 2.3 (Prova): Build debug + emulador a correr. ≥ 2 GB livres no fim.

5. BLOCO 3 — ACABAR O QUE FICOU A MEIO
- REGRA: verificar git log/grep + e2e_log + build. Se FEITO e publicado, só registar. Se não, acabar.
- 3.1 tvde-pedir-nunca-trava (Estela): Aplicar migração supabase/migrations/20261014190000 (CHECK + RPC admin_web_health_eventos + alarme). Enviar para o servidor. Publicar nas 3. Provar na web e no Android (morada escrita não trava pedido).
- 3.2 missao-reservas-num-so-sitio (10/10): Corrida, limpeza, barbearia, mesa no separador Reservas do cliente. Parou na bora-tranca 05:58 de 10/10. Retomar do ponto exato.
- 3.3 Toque/Chamada/Reembolso (10/10): Toque alto persistente (Android push só-dados + canal de alarme; iOS alertas repetidos). Rotação: estafetas online → chamada forçada aos aprovados offline (opt-in, Valdemir 1.º, limites no painel). Reembolso ao meio original (MB Way imediato; cartão 5-10 dias com aviso; carteira só por escolha): deixar PRONTO atrás de um interruptor DESLIGADO no painel admin. Ligar só com "autorizo" do Danilo.
- 3.4 Ecrã do Motorista (estilo Uber/Bolt): tvde_ride_active_screen.dart. Botão principal fixo fora da folha; cabeçalho por fase (recolha/destino); folha até 0,88. Verificar e acabar.
- 3.5 Login Google/Apple (corrida na nuvem trig_01NB64EAXGW6PqPh3t1uWCwQ de 10/10): Ver se os botões sociais (topo, "ou", email) estão no ramo e publicados; uma conta por pessoa nos 3 papéis. Painel admin mostra o método de login. Se não estiver, implementar e publicar.
- 3.6 Goola: Leite Ninho ×2 + WhatsApp: Grupos goola-big-extra / goola-bowl-extra. WhatsApp da loja assumir conversa (PROMPT_whatsapp-assumir_e_acompanhamentos-duplos_2026-10-14.md em Desktop\recebidos ou scratchpad). Retomar do 14/10 21:03.
- 3.7 Ecrã da Profissional de Limpeza: Ao abrir limpeza Standard: o que fazer e o que levar (produtos sim/não, aspirador, balde). Texto em PT simples vindo de platform_settings, editável no admin. Começado 15/10 05:34. Acabar.

6. BLOCO 4 — NOVO (só depois dos 0-3)
- 4.1 Carro ao Vivo + Fila: Ler e executar PROMPT_tvde_carro_ao_vivo_e_fila_2026-10-14.md. Carro a deslizar no mapa via broadcast. Fila inteligente já ligada no servidor. Prova de pico no emulador: 3 clientes × 4 motoristas, pagamento em dinheiro, sem acordar motoristas reais.
- 4.2 Pesquisa Única (Home): Lupa única: lojas, produtos, serviços, motorista, limpeza. NÃO fazer: repetir pedido, assinatura, pedido de grupo, ganho garantido.
- 4.3 Receita do Dia (Bora Todo Dia): 1 receita/dia (PT-PT, 5-8 ingredientes comuns). Notificação 10:00 Lisboa (opt-in, editável no painel). Botão "pôr no carrinho": monta carrinho no mercado não-parceiro mais barato (reusar Bora Assistente / propose_cart). Painel admin: criar, editar, agendar, ligar/desligar, hora. Sem tokens. Publicar nas 3.

7. FECHO E ENTREGA
- git push origin autonomous-night-2026-04-29.
- CI incrementa versionCode (NUNCA à mão).
- Publicar e PROVAR nas 3: Play Store, Apple (TestFlight), Web.
- Relatório final (texto corrido): "Fiz isto, falta isto" + lista de erros encontrados.
- Digest no Córtex (cortex_escrever) e Telegram.
- Registar este prompt em docs/ e no Obsidian (C:\Users\danil\Desktop\Bora).
- /ctx doctor
- /ctx stats
