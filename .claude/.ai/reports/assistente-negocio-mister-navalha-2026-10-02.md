# Assistente de Negócio no WhatsApp — Barbearia Mister Navalha (modo teste)

Missão 01–02/10/2026 · Claude Code no PC · commits `499df7f1`, `f4e73e95` (merge `61a07ab6`, push feito).
Como funciona: `ferramentas/assistente-negocio/COMO-FUNCIONA.md`.

## O que funciona — com prova

| bloco | prova |
|---|---|
| Multi-cliente | `assistant_tenants` com o 1.º cliente: Mister Navalha, `mode=teste`, allowlist 931 992 662 + 937 472 634, perguntas ao dono → 931 (Danilo) |
| Encaminhamento | a porta pergunta `/quem`: `931992662 → {"meu": true}` · `351912345678 → {"meu": false}`; o resto segue o cérebro da Bora, **pausado** (`envio_ligado=false`, 0 saídas da Bora desde 01/10 22:00 UTC) + 2.ª tranca `ENVIO_DESLIGADO` reposta |
| Fora da allowlist não recebe nada | `prova_real.py 351912345678` → `BLOQUEADO`, `exit=2`; linha `entrega_estado=bloqueado` |
| Troca REAL (931 → Bora → resposta) | Danilo escreveu 11 mensagens (02/10 04:22–09:06); 11 respostas `entregue` (aviso da própria WhatsApp, status 3); marcou Corte sábado 03/10 14:30 (hora vinda de `horarios_livres`); 2.ª mensagem da app `entregue`, uma vez |
| Saída real com aviso de entrega | `3EB08E8D53E307A160C6BC ENTREGUE status=3 (assistente)` |
| 18 conversas simuladas pela MESMA `atender()` | `provas/assistente-negocio-2026-10-01/` — preço, horário, morada, fim da tarde, marcação completa, hora ocupada (ofereceu 09:30/10:30), domingo fechado, desmarcar, remarcar (para as 16:00), criança, degradê (incluído no Corte), freestyle → dono, pergunta desconhecida (MB Way) → dono → resposta entregue e aprendida, pessoal → silêncio, grupo → silêncio, fora da allowlist → silêncio, dono escreveu → 12 h calado, blocklist → silêncio |
| Adendo 1 — `apos_marcacao` | 2.ª mensagem curta só depois de `marcar` dar ok, 1 por marcação (`motivo=apos_marcacao:<id>`); "Obrigado!" já não repete |
| Adendo 2 — áudios | `provas/assistente-negocio-2026-10-02-audios/`: A1 preço por áudio → texto + nota de voz; A2 marcação completa por áudio (Barba sábado 11:00) → texto + voz + mensagem da app; A3 áudio pessoal → silêncio. Notas de voz: opus, mono, 48 kHz, 10–13 s. Reserva faster-whisper local: "Quanto custa uma barba?" em 3,0 s |
| Painel admin | "Robôs e Autonomia → Assistentes (funcionário digital)" — modo, allowlist/blocklist, ficha, perguntas aprendidas, conversas, custo do mês, "Limpar marcações de teste"; `flutter analyze` → **No issues found** |
| App de parceiro | a marcação aparece na agenda; o cartão diz "Paga no local · marcado pelo WhatsApp" (antes diria "Pago pela app: €0,00") |
| Dinheiro | nenhuma cobrança: marcações `is_walk_in`, `deposit_status=waived`; RPCs só service_role; tabelas RLS só admin |
| Verificador adversarial | chão anti-trapaça CLEAN; verificador de contexto limpo: A/C/E resistem; 6 pontos tratados abaixo |

## Adendo 3 — correcção dos áudios (02/10, depois de o Danilo testar)

| pedido | feito | prova |
|---|---|---|
| Voz masculina de Portugal | `pt-PT-DuarteNeural` (defeito em `voz.py`; o serviço não o sobrepõe) | `grep DuarteNeural voz.py` → 1; serviço sem `ASSISTENTE_VOZ` |
| Cliente manda áudio → resposta SÓ em áudio | sem texto antes nem depois; horas lidas por extenso ("dez e meia", "meio-dia") | simulação A2 (`provas/.../adendo3-voz-masculina-so-audio/simulacao-20261002-1613.json`): 3 saídas, as 3 `motivo=voz`/`apos_marcacao` com nota de voz, **0 de texto** |
| Mensagem da app depois da marcação, em conversa de áudio | vai em voz: "…misternavalha ponto boraguarda ponto com" | linha `apos_marcacao:3342eea7…` = `[nota de voz] … misternavalha ponto boraguarda ponto com` |
| Cliente escreve → só texto | inalterado | cenário 01-preco: 1 saída, `motivo=resposta`, texto |
| Se a voz falhar | vai em texto (o cliente nunca fica sem resposta) | `responder_em_voz()` devolve None → `enfileirar` texto |

Notas de voz geradas: opus, mono, 7–11 s. Serviço reiniciado (`active`); `voz.py`, `assistente.py`, `simular.py` iguais na VPS e no repo (md5 `30ab9bfa`, `831dd2df`, `c976789e`).

## O que falhou pelo caminho (e foi corrigido)

1. Remarcar rebentava quando um motor caía a meio (o Gemini recusa chamadas feitas por outro motor) → histórico de ferramentas passa a texto na troca de motor + castigo para motores fechados.
2. "Não aceitamos MB Way" inventado → regra: o que não está escrito pergunta-se ao dono. Reprovado e passou.
3. "Obrigado!" voltava a marcar e dizia "erro no sistema" → `marcar` idempotente + "[sistema: marcação FEITA]" no histórico.
4. As simulações mandaram **9 avisos reais ao Ernando** (01/10 23:16–23:28, sem a palavra TESTE) → funções `_v2`: simulação não avisa; testes reais dizem "TESTE ·". Desde as 11h de 02/10: 0 avisos a mais.
5. **Erro meu:** a limpeza de testes das 11:56 cancelou a marcação real de teste do Danilo (sábado 14:30) e apagou a memória da conversa dele → reposta às 12:00 (sem novo aviso ao parceiro) e memória reconstruída das 10 mensagens reais; a limpeza das simulações passa a cancelar só as suas.
6. faster-whisper local não existia em lado nenhum (a cadeia antiga dizia que sim) → instalado; rebentava no `av.open` → descodificação pelo ffmpeg.
7. Na 1.ª tentativa de instalar a porta, um `;` no meu comando fez o reinício correr sem a cópia de segurança no servidor → cópia reposta a partir do PC, verificada por hash.

## O que fica por fazer / limites

- ~~Áudio real do 931~~ **FEITO 02/10 12:01**: nota de voz do Danilo "Olá, beleza?" → transcrita (Groq whisper) → resposta em texto `3EB096B5C2DC83218DBD88` **entregue** + nota de voz `3EB03D82041F4DF56B2F94` **entregue** (status 3 da WhatsApp).
- **Motor**: principal = OpenCode Go (decisão do Danilo). O plano Go está no **limite mensal** (429 `GoUsageLimitError`, `limitName: monthly`, medido 01 e 02/10) → até renovar respondem os grátis (Gemini 3 Flash em 2 projetos, Flash-Lite, Groq). Custo real até agora: 0 €.
- **Chamadas de voz**: não (o Baileys não as atende) — passo futuro com a API oficial do WhatsApp.
- Lembrete real: a marcação de sábado 14:30 do Danilo vai gerar o lembrete às 18:00 de hoje (véspera) e o pedido de avaliação no sábado ~16:00 — primeira prova viva das rotinas.

## Erros fora do âmbito (reportados, não corrigidos)

- **Bora "falha aberta"**: se o Supabase falhar, `envio_ligado` lê `None` e o cérebro da Bora volta a poder responder. Mitigado agora pela 2.ª tranca (`ENVIO_DESLIGADO`), mas o código do cérebro continua assim.
- **Corrida app × WhatsApp**: `client_book_appointment` não tranca o profissional e `partner_add_walk_in` nem verifica; `appointments` não tem restrição de exclusão. Duas marcações ao mesmo milissegundo (app + WhatsApp) podem coincidir.

## PARA O DANILO

1. ⚠️ **ISTO MEXE EM DINHEIRO (latente, hoje 0 €):** o repasse semanal (`compute_provider_weekly_payout`) não distingue marcações de teste e cobra `appointment_walkin_fee_cents` por cada marcação "ao balcão" concluída — as do WhatsApp contam como "ao balcão". Hoje a taxa é 0, logo não sai dinheiro. Se um dia a subires, as marcações do WhatsApp passam a pagar essa taxa. Não toquei. Diz se queres que as do assistente fiquem de fora.
2. O plano OpenCode Go está esgotado no mês. Quando renovar, o assistente usa-o sozinho.
3. Os "67" e "58" que mandaste não percebi — se eram uma instrução, diz por palavras.
