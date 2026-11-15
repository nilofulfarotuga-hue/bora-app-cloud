# Contrato R1a — Recibos verdes (servidor)

Missão 12 `recibos-verdes-15-11`, ramo `ai/2026-11-15-recibos-verdes`. Ordem: caixa_guardados 69
(escrita pela Claude.ai), com a autorização do Danilo de 15/11/2026 16:25: "1, 2, 4 e 5. Pode fazer."

Estado: **proposta, não aplicada**. O SQL está em `R1a_servidor.PROPOSTA.sql` e a prova em
`R1a_prova_rollback.sql` (mesma pasta). Este ficheiro diz à app (R2), ao painel e às Edge
Functions (R1b) exatamente o que o servidor passa a ter: nomes, parâmetros, o que devolve e os erros.

---

## 1. Em poucas palavras

- **Um recibo por pessoa por mês**, com tudo o que a pessoa fez: entregas, limpezas, lavagens e
  Casa e Manutenção, somado pelo `user_id` (a Mayra, que é estafeta e limpadora, passa um só).
- O recibo só conta como **entregue** quando tem **PDF ou foto** anexado.
- **Trava do pagamento**: a partir dos recibos de **novembro/2026**, quem não tiver o recibo do mês
  anterior com PDF até ao **dia 10** fica com os pagamentos semanais **retidos** a partir do dia 11.
  A trava **não muda nenhum valor**: só impede marcar "pago". O dinheiro fica nas mesmas linhas
  e sai todo junto no primeiro acerto depois de o recibo ser anexado.
- **Quem deve à Bora continua a ser cobrado como hoje** ("recebido" nunca é travado). Se na mesma
  semana a pessoa deve mais do que recebe, a parte a receber é só compensação e também passa.
- Fora da trava: contas demo e a conta do dono (`boraappbora`), salvo se
  `fecho_dono_passa_recibo` for ligado.
- O admin pode **soltar** uma semana de uma pessoa com motivo escrito (fica na auditoria).
- Não é só o mês anterior: se faltar o recibo de **qualquer** mês desde novembro/2026 cujo dia 10
  já passou, a pessoa continua retida (para ninguém saltar um mês).

---

## 2. Armazenamento — bucket `recibos-verdes`

| | |
|---|---|
| Tipo | privado (como `provider-atividade`) |
| Tamanho máximo | 10 MB |
| Formatos | `application/pdf`, `image/jpeg`, `image/jpg`, `image/png` |
| Caminho | `{user_id}/{ano}-{mês com 2 dígitos}.{pdf\|jpg\|jpeg\|png}` — ex.: `9a8a5657-…/2026-11.pdf` |

Quem pode o quê:

- O **próprio** lê a sua pasta; envia e substitui o seu ficheiro **enquanto o recibo desse mês ainda
  não estiver marcado com PDF**. Depois de marcado, trocar o ficheiro passa pelo admin
  (desmarcar → o prestador volta a poder enviar).
- O **admin** lê tudo e pode enviar/substituir na pasta de qualquer pessoa (recibo que chegou por
  email ou WhatsApp).
- **Ninguém apaga** pela API.

App (R2): primeiro envia o ficheiro (`upload` com `upsert: true`), **só depois** chama
`driver_mark_invoice_issued` com `p_pdf_path`. Se a rede cair a meio, repetir as duas coisas é seguro.

Painel e Edges: para abrir o ficheiro, link assinado (`createSignedUrl`). O painel usa a sessão do
admin; a Edge do contabilista usa a service_role, com validade de 7 dias (604800 s).

---

## 3. Tabela `driver_monthly_invoices` (chave: `user_id`, `ano`, `mes`)

Serve para **todos** os prestadores, não só estafetas. Colunas novas:

| Coluna | Tipo | O que é |
|---|---|---|
| `recibo_pdf_path` | text | caminho do ficheiro no bucket. Sem isto o recibo não conta para a trava. |
| `recibo_verificacao` | jsonb | resultado da conferência automática (OCR), escrito pela Edge (R1b). Limpa-se sozinho quando entra um PDF novo. Formato sugerido: `{ "ok": bool, "nif_lido": "…", "valor_lido": 0.0, "problemas": ["…"], "conferido_em": "…" }` |

Muda o significado de `total_faturar`: passa a ser o **total do mês de todos os serviços** da pessoa
(para quem só faz entregas é o mesmo valor de hoje). `entregas` continua a ser o n.º de entregas.
Leitura direta pela app: o próprio vê a sua linha (regra que já existe).

---

## 4. Definições (`platform_settings`, categoria `fecho`)

| Chave | Valor inicial | O que faz |
|---|---|---|
| `fecho_dono_passa_recibo` | `false` | Se `true`, a partir de novembro/2026 a conta de estafeta do dono entra como qualquer prestador (email, botão, aviso, trava). A Claude.ai liga quando o contabilista responder. Outubro não se mexe. |
| `recibos_trava_ativa` | `true` | Interruptor de emergência da trava inteira. Desligado = ninguém fica retido. |

Paridade admin: as duas devem aparecer no ecrã de definições do painel (ver, ligar/desligar).

---

## 5. Funções para a app do prestador (textos em PT-PT)

### 5.1 `prestador_recibo_mensal_resumo(p_year int, p_month int, p_user_id uuid default null) → jsonb`

A **fonte única** do recibo do mês (app, email do dia 1, painel, aviso do dia 10, trava).

- Prestador: chama sem `p_user_id` (ou com o seu) → recebe só o seu. Outro `user_id` → `sem_permissao`.
- Admin, service_role (Edges) e ligação direta: `p_user_id` nulo → **todas** as pessoas do mês.

Devolve:

```json
{
  "ano": 2026, "mes": 11, "nome_mes": "novembro",
  "periodo": { "inicio": "…", "fim": "…" },
  "adquirente": { "tipo": "sociedade", "nome": "Danilo Fulfaro da Silva - Unipessoal Lda",
                  "nif": "519686233", "morada": "Rua do Torreão 14, 6300-610 Guarda" },
  "regras": {
    "descricao_modelo": "Serviços prestados em novembro de 2026 através da plataforma Bora",
    "prazo_texto": "Fatura-recibo até ao 5.º dia útil seguinte ao recebimento (art. 36.º CIVA / art. 115.º CIRS)",
    "prazo_legal_data": "2026-12-09", "prazo_legal_nota": "…",
    "anexar_ate": "2026-12-10", "anexar_texto": "Anexe o recibo na app, em Ganhos, até 10/12/2026.",
    "trava_desde": "2026-11-01", "conta_para_trava": true,
    "retencao": { "regra": "…", "mencao_dispensa": "Sem retenção, nos termos do n.º 1 do artigo 101.º-B do Código do IRS",
                  "taxa_se_aplicavel": "11,5%", "limite_anual": "15.000 EUR" },
    "iva_texto": "IVA: isento ao abrigo do artigo 53.º do CIVA, se for o seu caso; o contabilista confirma."
  },
  "prestadores": [ {
    "user_id": "…", "nome": "…", "nif": "…", "email": "…",
    "linhas": [ { "servico": "entregas", "nome": "Entregas", "quantidade": 5, "valor": 23.90 },
                { "servico": "limpeza",  "nome": "Limpezas", "quantidade": 2, "valor": 40.00 } ],
    "total": 63.90,
    "descricao": "Serviços prestados em novembro de 2026 através da plataforma Bora (5 entregas, 2 limpezas)",
    "demo": false, "conta_dono": false, "proprio_adquirente": false,
    "precisa_recibo": true, "conta_para_trava": true,
    "recibo_passado": false, "tem_pdf": false,
    "estado": "em_falta",
    "recibo": { "numero": null, "data": null, "marcado_em": null, "pdf_path": null, "verificacao": null }
  } ],
  "prestador": { "…o mesmo objeto, só quando se pede uma pessoa (ou null se não trabalhou)…" },
  "totais": { "pessoas": 3, "precisam": 2, "entregues": 0, "em_falta": 2, "total": 150.52 },
  "gerado_em": "…"
}
```

`estado`: `entregue` (tem PDF) · `sem_pdf` (marcou o número mas falta o ficheiro) · `em_falta`
(não marcou) · `nao_precisa` (sem trabalho, demo ou conta do dono saltada).
Serviços: `entregas`, `limpeza`, `lavagem`, `casa`. TVDE **não** entra (como no fecho de hoje).
Até outubro/2026 o adquirente é o Danilo em nome individual (como hoje).

Erros: `sem_sessao`, `sem_permissao` (42501), `mes_invalido`.

### 5.2 `driver_mark_invoice_issued(p_year int, p_month int, p_numero text, p_data date default null, p_pdf_path text default null) → jsonb`

O botão **"Já passei o recibo"** — agora em todas as apps de prestador (estafeta, limpeza,
lavagem, Casa). Mesmo nome de hoje; a versão antiga mudou de nome, por isso as chamadas da app
publicada (3 ou 4 nomes) continuam a funcionar sem ambiguidade.

- `p_pdf_path` é opcional no servidor (a app publicada não o manda); **a app nova obriga**.
- Sem `p_pdf_path`, um PDF que já lá esteja **não é apagado**.
- Grava o total do mês de todos os serviços.

Devolve: `{ ok, total_faturar, entregas, linhas[], tem_pdf, recibo_pdf_path }`.

Erros: `sem_sessao`, `numero_em_falta`, `mes_invalido`, `pdf_caminho_invalido` (caminho não é
`{o seu user_id}/{ano}-{mês}.pdf|jpg|png`), `pdf_nao_encontrado` (o ficheiro ainda não foi enviado).

App, depois de gravar: "Recibo de novembro entregue" quando `tem_pdf = true`.

### 5.3 `prestador_recibo_trava(p_user_id uuid default null) → jsonb`

Diz se a pessoa está retida. O prestador vê o seu; admin e Edges veem qualquer um.

```json
{
  "retido": true,
  "motivo": "Retido — falta o recibo verde de novembro de 2026",
  "texto_semanal": "O teu pagamento desta semana fica guardado até anexares o recibo verde de novembro de 2026 na app, em Ganhos.",
  "texto_app": "O teu pagamento fica guardado até anexares o recibo verde em falta na app, em Ganhos. Não se perde: sai todo junto no primeiro pagamento depois de o anexares.",
  "meses_em_falta": [ { "ano": 2026, "mes": 11, "nome": "novembro de 2026", "total": 23.90,
                        "estado": "em_falta", "anexar_ate": "2026-12-10" } ],
  "excluido": null,
  "por_pagar": { "total_cents": 3527,
                 "semanas": [ { "tipo": "driver", "id": "…", "semana": "2026-12-07", "cents": 1830, "estado": "pending" } ] },
  "calculado_para": "2026-12-11",
  "user_id": "…"
}
```

Quando não está retido: `retido: false` e, se for o caso, `excluido` = `conta_demo` |
`conta_dono` | `trava_desligada`. `por_pagar` vem sempre (é o dinheiro que a Bora ainda tem de
pagar à pessoa; nada é calculado de novo, só somado das linhas).

App (Ganhos): se `retido`, mostrar `texto_app` e o valor de `por_pagar.total_cents`, com o botão
"Já passei o recibo" à frente. Ganho em número grande (regra do motorista).

Erros: `sem_sessao`, `sem_permissao` (42501).

---

## 6. Painel admin (textos em PT-BR, termos explicados entre parênteses)

### 6.1 Fecho mensal — `/admin/fecho-mensal`

- Lista: `prestador_recibo_mensal_resumo(ano, mes)` (admin → todas as pessoas). Mostrar por
  pessoa: nome, NIF, linhas por serviço, total, número, data, estado e o botão **Abrir PDF**
  (link assinado de `recibo.pdf_path`).
- **Marcar à mão** (recibo que chegou por email/WhatsApp):
  `admin_recibo_prestador_marcar(p_user_id uuid, p_year int, p_month int, p_numero text, p_data date default null, p_pdf_path text default null, p_motivo text default null) → { ok, total_faturar, tem_pdf, recibo_pdf_path }`.
  Motivo obrigatório (5 letras ou mais). Para contar para a trava, o admin envia primeiro o
  ficheiro para a pasta da pessoa e passa `p_pdf_path`.
- **Desmarcar** (recibo errado):
  `admin_recibo_prestador_desmarcar(p_user_id uuid, p_year int, p_month int, p_motivo text) → { ok, nota }`.
  O ficheiro fica guardado; só deixa de contar.
- Reenviar o email do mês: fica para a Edge (R1b).

### 6.2 Acertos da semana e afins — "Retido"

As listas passam a trazer, em cada linha:

| Chave | O que é |
|---|---|
| `retido` | `true` = "Marcar pago" bloqueado nesta linha |
| `retido_motivo` | ex.: "Retido — falta o recibo verde de novembro de 2026" |
| `retido_solto`, `retido_solto_motivo` | a semana foi solta à mão (e porquê) |
| `retido_compensa_divida` | a pessoa deve mais do que recebe nesta semana: passa como acerto de dívida |
| `recibo_meses_em_falta` | lista dos meses em falta |
| `retido_erro` | só aparece se o cálculo falhar (a lista nunca parte por causa disto) |

Listas com estas chaves (mesmos nomes e parâmetros de hoje):
`admin_weekly_closeout_list(p_week_start)` (Acertos da semana, chave `items`),
`admin_acerto_unificado(p_semana)` (acerto unificado, chave `itens`),
`admin_casa_acertos(p_week_start)` (Casa), `admin_list_carwash_settlements(p_status)` (lavagem).

**Soltar** (botão ao lado de "Retido", pede o motivo):
`admin_soltar_retido_recibo(p_subject_type text, p_subject_id text, p_week_start date, p_motivo text) → { ok, user_id, semana, motivo, estava_retido, nota }`

| Ecrã | `p_subject_type` | `p_subject_id` | `p_week_start` |
|---|---|---|---|
| Acertos da semana | `type` da linha (`driver`/`cleaner`/`washer`) | `subject_id` | data de `week_start_at` (ou a semana da lista) |
| Acerto unificado | `user` | `user_id` | `semana` |
| Casa | `casa` | `id` da linha | data de `week_start_at` |
| Lavagem | `washer` | `washer_id` | data de `week_start_at` |

Soltar não paga nada: só deixa o "Marcar pago" dessa semana passar. Erros: `admin_required`
(42501), `faltam_argumentos`, `motivo_obrigatorio`, `tipo_invalido`, `pessoa_nao_encontrada`,
`acerto_nao_encontrado`.

**Marcar pago bloqueado** — em QUALQUER caminho (Acertos da semana, acerto unificado, Casa,
lavagem, limpeza, ecrãs antigos) o erro é:
`code P0001`, `message` a começar por `recibo_verde_em_falta:` seguido do motivo,
`details` = JSON `{ user_id, semana, cents, meses_em_falta }`, `hint` = o que fazer.
O painel deve mostrar o motivo e oferecer "Soltar".

Solturas: tabela `recibo_retencao_solturas` (`user_id`, `semana`, `motivo`, `origem`,
`criado_por`, `criado_em`) — só leitura para o admin; escreve-se só pela função.

Auditoria (`admin_audit_log.action`): `recibo_verde_marcar_admin`, `recibo_verde_desmarcar_admin`,
`recibo_retido_soltar`, `recibo_retido_pago_com_soltura`, `recibo_aviso_prestador`,
`recibo_aviso_admin_falhou`, `auto_payout_retido_recibo`.

---

## 7. Para as Edge Functions (R1b)

Todas chamam com a service_role.

- **`monthly-partner-statement` (dia 1, tarefa 88)**: UM email por pessoa a partir de
  `prestador_recibo_mensal_resumo(ano, mes).prestadores` onde `precisa_recibo = true`: total,
  linhas por serviço, `adquirente` (copiar), `descricao`, `regras.prazo_texto`,
  `regras.retencao` e `regras.iva_texto`, "anexe o recibo na app em Ganhos" (`regras.anexar_texto`).
  Não mandar duas vezes à mesma pessoa (hoje há `driver_monthly_statement_log` e
  `cleaner_monthly_statement_log` em separado: a Mayra receberia dois).
- **`fecho-mensal-contabilista` (dia 1, tarefa 125)**: lista do mês anterior com nome, NIF, valor,
  número e link assinado de 7 dias de `recibo.pdf_path`; quem falta, a dizer que falta (`estado`).
- **Recibo semanal** (`weekly-closeout-digest` / `settlement-receipt`): para cada pessoa, chamar
  `prestador_recibo_trava(user_id)`; se `retido`, acrescentar `texto_semanal` ao email/push.
- **OCR** (`ocr-receipt`): ler o PDF de `recibo_pdf_path`, conferir NIF do adquirente = 519686233 e
  valor = `total` do mês; gravar em `driver_monthly_invoices.recibo_verificacao`; se não bater,
  avisar o prestador (texto simples: o que está errado e como corrigir) e o admin.
- **Stripe Connect**: hoje não há transferências automáticas (Fase 1). Se um dia houver, a Edge tem
  de chamar `prestador_recibo_trava` **antes** de transferir e marcar o acerto pelas funções de
  sempre (o gatilho também segura).

---

## 8. Tarefas agendadas

| Tarefa | Antes | Depois |
|---|---|---|
| 89 (dia 10, 09h Lisboa) | `aviso_recibos_estafetas_em_falta()` — só admin, só estafetas | `aviso_recibos_prestadores_em_falta()` — admin + cada prestador (in-app, push pela `notify-admin-message`, email pela `agentes-email-enviar`), todos os serviços; não repete a mesma pessoa no mesmo mês |
| 88 (dia 1) | Edge `monthly-partner-statement` | igual (a Edge muda no R1b) |
| 2 (`auto_payout_pending`) | desligada | continua desligada; se um dia ligar, salta quem está retido |

`aviso_recibos_prestadores_em_falta(p_year int default null, p_month int default null) → jsonb`
(`{ ok, mes, em_falta, prestadores_avisados, anexar_ate, request_id_admin }`): sem argumentos usa o
mês anterior; o admin pode correr à mão. Avisos ao prestador só para recibos à sociedade
(novembro/2026 em diante). A função antiga fica, sem uso, para o rollback.

---

## 9. Lista de erros

| Erro | Onde | O que quer dizer |
|---|---|---|
| `sem_sessao` | funções do prestador | sem login |
| `sem_permissao` (42501) | resumo, trava | pediu dados de outra pessoa |
| `admin_required` (42501) | funções admin, aviso | não é admin |
| `mes_invalido` | resumo, marcar | mês fora de 1..12 ou ano estranho |
| `numero_em_falta` | marcar | falta o n.º do recibo |
| `pdf_caminho_invalido` | marcar | caminho não é `{user_id}/{ano}-{mês}.pdf\|jpg\|png` |
| `pdf_nao_encontrado` | marcar | o ficheiro não está no bucket |
| `motivo_obrigatorio` | marcar/desmarcar/soltar (admin) | motivo vazio ou com menos de 5 letras |
| `recibo_nao_encontrado` | desmarcar | não há recibo desse mês |
| `faltam_argumentos`, `tipo_invalido`, `pessoa_nao_encontrada`, `acerto_nao_encontrado` | soltar | dados da linha errados |
| `recibo_verde_em_falta: …` (P0001) | marcar pago (qualquer caminho) | pessoa retida; anexar o recibo ou soltar |

---

## 10. O que fica igual (compatibilidade)

- `driver_monthly_invoice_summary` não muda (a app publicada usa-a; só entregas). A app nova passa
  para `prestador_recibo_mensal_resumo`.
- As 4 listas do painel mantêm nomes, parâmetros e todas as chaves de hoje; só ganham chaves novas.
- Nenhum preço, comissão, ganho ou valor muda. Nenhuma linha de acerto é recalculada.
- Outubro/2026 fica fora da trava (era em nome individual).
- Antes de **11/12/2026** ninguém pode ficar retido (o primeiro prazo é 10/12).

---

## 11. Perguntas em aberto (para o contabilista / Danilo, pela Claude.ai)

1. **TVDE dentro do acerto do estafeta**: a linha semanal do estafeta inclui as corridas TVDE; se
   ficar retida, o dinheiro do TVDE também fica. O TVDE não entra no recibo verde. Separar?
2. **Reservas Pro / serviços com marcação** (`appointment_payouts`): não estão na trava nem no
   recibo. Também passam recibo à sociedade?
3. **Trabalhos pagos em dinheiro na mão** (limpeza, Casa): o valor do recibo é o ganho da pessoa,
   como no fecho de hoje — confirmar.
4. **Casa com reembolso por decidir**: fica fora do total do mês (como no acerto) — confirmar.
5. **Retenção 11,5% / dispensa**: só texto; quem passa os 15.000 EUR por ano o contabilista diz.
6. **Todos os meses em falta, não só o anterior**: a trava segura enquanto faltar qualquer mês
   desde novembro/2026 — confirmar que é isto que se quer.
7. **Compensação na mesma semana**: quem deve mais do que recebe nessa semana não fica retido
   (a parte a receber só abate a dívida) — confirmar.
8. **Calendário**: a app nova com o botão do PDF tem de estar publicada nas 3 lojas antes de
   **11/12/2026**; senão quem trabalhou em novembro fica retido até o admin marcar à mão ou soltar.

---

## 12. Coisas erradas encontradas pelo caminho (reportadas, não corrigidas)

- `admin_casa_acerto_marcar` aceita "pago" ou "recebido" seja qual for o sentido do acerto (o
  `admin_set_settlement_state` obriga ao sentido certo). A trava só segura "pago" quando a Bora
  paga (`bora_to_handyman`), por isso não piora, mas o ecrã da Casa deixa marcar o estado errado.
- A Casa não entra no acerto unificado (`v_acerto_semanal_unificado` / `admin_marcar_acerto_pago`)
  nem no resumo semanal (`weekly_digest_log`): quem faz Casa e entregas tem dois acertos separados.
- `driver_monthly_invoices` dá todas as permissões de tabela a `anon` e `authenticated`; só a RLS
  (uma regra de leitura) segura. Funciona, mas é mais largo do que precisa.
- Hoje não há nenhuma linha de acerto por pagar (estafetas: 15 pagas, 10 recebidas; limpeza:
  2+2): a trava não tem efeito imediato nenhum.
