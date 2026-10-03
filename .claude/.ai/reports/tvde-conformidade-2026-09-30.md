# TVDE pronto para a lei — relatório da missão `tvde-conformidade-lei-59-2026`

> 30/09/2026 · Claude Code (PC do Danilo) · ramo `autonomous-night-2026-04-29` · commit `75143a93`
> Autorização do Danilo: "eu autorizo" (30/09/2026 10:00). RAM medida: 1251 MB no arranque, 871 MB antes do `flutter analyze`, 1042 MB antes dos testes (acima dos portões).

## Primeiro, o que NÃO ficou feito (e porquê)

1. **Capturas no emulador:** não feitas. O emulador precisa de ~3 GB e o PC tinha ~1 GB livre. As provas de ecrã foram pela web (PADRAO_BORA §3.10) — ver secção "Provas".
2. **Testes de imagem (golden) do painel admin:** o comando foi recusado nesta sessão; ficaram por correr. A entrada nova no menu admin pode mudar `painel_admin_menu_*`. Os testes normais do painel (30) passam.
3. **Preço fixo fechado** (obrigatório, art. 15.º n.º 6): NÃO construído — mexe no valor cobrado. Só o interruptor existe (desligado).
4. **Ligação ao IMT:** o IMT não publicou especificação nem API. Ficou o esqueleto "aguarda IMT" com testes.
5. **Faturação certificada:** sem empresa não há software certificado. Ficou o adaptador (InvoiceXpress pronto a ligar) em modo stub, que nunca inventa número nem ATCUD.
6. **Mensagem do servidor ao motorista quando o online é recusado:** o `DriverStore` engole o erro; ficou só a pré-verificação antes de ligar (não mexi no `DriverStore`).
7. **Upload de PDF** no ecrã Conformidade do motorista: só imagem (não há `file_picker` no projeto).

## A descoberta que muda tudo — PARA O DANILO

1. **O Bora já fez 116 corridas TVDE sem licença de plataforma** (63 em dinheiro). A lei está em vigor desde 01/09/2026. Coima até 44 000 € para empresa, ou até 4 500 € em nome próprio, mais proibição até 2 anos (arts. 25.º e 26.º). **Decisão tua:** suspender o TVDE ou passá-lo a teste fechado sem cobrança até haver licença.
2. **Uma só empresa para o Bora e para o teu TVDE colide com a lei:** a plataforma não pode ter interesse em operadores nem em carros TVDE (art. 12.º n.º 5 e art. 20.º n.º 11). Ir a um advogado **antes** de constituir a empresa.
3. **Avaliar o passageiro passou a ser OBRIGATÓRIO** (a Lei 59/2026 revogou a proibição; art. 19.º n.º 2 c)). O interruptor `tvde_driver_rates_client_disabled` foi construído como pedido, mas **nunca se liga**. Está marcado assim no painel.
4. **⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto a propor — confirma que eu aplico:**
   - **preço fixo fechado** antes de pedir (art. 15.º n.º 6, obrigatório);
   - **teto de 25 %**: 5 de 116 corridas passaram: uma de balcão (10 € ao cliente, 4 € ao motorista = 60 %), dois pacotes ida-e-volta em que só a ida foi feita (50 %) e duas com paragem, porque a paragem é 2 € ao cliente e 1 € ao motorista (26,67 %);
   - **taxa de cancelamento:** hoje cobra-se o valor total depois de 3 min; o agente legal aponta risco de penalização desproporcionada (DL 446/85 art. 19.º c)).
5. **Código do Trabalho 12.º-A:** hoje o Bora fixa e paga diretamente o ganho do motorista, o que é um indício de contrato de trabalho. Com operadores, o pagamento deve ir para o operador. Advogado.
6. **Perguntas por escrito:** ao contabilista (quem emite a fatura, taxa de IVA 6 %?, software) e ao IMT (como uma plataforma nova se liga à partilha de dados; se o SOS pelo telefone do utilizador basta).

## O que ficou pronto (com prova)

**Placar: a checklist "Pronto para licenciamento" tem 80 requisitos — 10 verdes, 45 amarelos, 25 vermelhos** (a matriz completa tem 90: 17 / 48 / 25). Os vermelhos são quase todos coisas que não se fazem em código: empresa, licença, operadores, carros, faturação certificada e IMT.

### Fase 0 — pesquisa
Texto oficial da Lei 59/2026 (DR 1.ª série n.º 164, 25/08/2026) lido na íntegra: 164 requisitos (138 confirmados, 16 não confirmados, 10 mistos). Ficheiros:
`_pesquisa-tvde-lei-59-2026-bruto.md`, `tvde-matriz-legal-2026-09-30.md`.

### Fase 1 — dados (migrations aplicadas e no repo)
Tabelas novas com RLS ligada: `tvde_operators`, `tvde_vehicles`, `tvde_driver_vehicle`, `tvde_driver_work_log`, `tvde_complaints`, `tvde_compliance_events`, `tvde_driver_compliance`, `tvde_client_prefs`, `tvde_sos_events`, `tvde_fiscal_access`, `tvde_intermediacao_verificacao`, `tvde_amt_reports`, `tvde_invoices`, `tvde_legal_requirements`. Colunas novas em `drivers` (operador, carta B, contrato, fala português, curso, horas noutras plataformas) e em `tvde_rides` (preferências). Reaproveitado, sem gémeos: `motorista_ficha_legal` (CMTVDE, carta, seguro, inspeção, dístico) e `tvde_driver_documents` + bucket privado `driver-documents`.
Avisos de segurança do Supabase sobre os objetos novos: só os esperados (funções `admin_*` protegidas por `is_admin()`). Os gatilhos novos foram fechados a `anon` e `authenticated`.

### Fase 2 — regras no servidor (todas atrás do mestre `tvde_compliance_enforce`)
- **Despacho (zona protegida):** uma linha a mais em `tvde_offer_to_next` (2 ramos) e `tvde_reservation_offer_to_next`. **Prova:** a definição nova, sem essa linha, é igual byte a byte ao backup `bkp_fn_tvde_despacho_20260930`.
- **Prova de regressão, tudo desligado** (transação desfeita no fim): pedido em dinheiro → oferta ao motorista online → aceite → chegou → iniciou → terminou: **5,00 € / motorista 4,00 € / Bora 1,00 €**, igual à tabela de hoje; teto 20 % registado; resumo com os campos novos.
- **Prova com interruptores ligados** (transação desfeita):
  - dinheiro recusado (`PAGAMENTO_ELETRONICO_OBRIGATORIO`), também no balcão; volta de pacote pago e MB Way aceites;
  - motorista sem operador nem carro: sem ofertas e online recusado (`TVDE_BLOQUEADO`);
  - 9 h + 1,5 h declaradas noutra plataforma = 10,48 h: sem ofertas e `LIMITE_HORAS`;
  - avaliação do passageiro ignorada (0 linhas gravadas);
  - queixa n.º 1 criada e SOS registado com evento;
  - pedido "fala português" não vai para quem não o declarou;
  - acesso de fiscalização criado e consultado: 74 viagens, **sem dados do passageiro**, consulta registada.
- **Depois das provas:** 0 queixas, 0 SOS, 0 acessos, 0 corridas de prova; interruptores todos a `false`.
- **Crons:** `tvde-conformidade-diaria` (07:15), `tvde-work-log-sweep` (a cada 5 min), `tvde-amt-mensal` (dia 1, 06:00).

### Fase 3 — cliente (PT-PT)
Preço discriminado antes de pedir; seletor sem dinheiro quando o interruptor liga; opções "fala português" e mobilidade reduzida (mesmo preço, aviso de alternativas); ecrã de Queixas com Livro de Reclamações, formulário interno e informação RAL; página "Sobre o operador da plataforma"; cartão do motorista com CMTVDE, foto, lugares, ano e operador; botão SOS (112 + partilha de localização); "Resumo da viagem" com código, duração, % de intermediação e cálculo — nunca "fatura". O email automático também passou a "Resumo da viagem" (função `tvde-recibo-viagem` v3 no ar; a versão local era igual à que estava no ar antes do deploy). O mapa em tempo real já existia (confirmado).

### Fase 4 — motorista
Área "Conformidade TVDE" em secções (operador + contrato, carta B, fala português, curso, foto do CMTVDE, carro, horas noutras plataformas); contador de horas nas últimas 24 h; cartão de avisos; pré-verificação antes de ficar online; SOS na corrida. Sem controlos novos sobre o motorista (Código do Trabalho 12.º-A).

### Fase 5 — autoridades
Esqueleto do IMT ("aguarda IMT", nunca diz "válido"); modo Fiscalização (código temporário de 1 a 168 h, só leitura, cada acesso e exportação registados) com a página pública `app.boraguarda.com/fiscalizacao.html`; relatório AMT mensal. **AMT calculado:** julho 2 viagens / 8,00 € / intermediação 0,50 €; agosto 18 / 111,80 € / 21,20 €; setembro 96 / 491,50 € / 65,30 € (contribuição de 5 % sobre a intermediação positiva). Minuta do contrato de adesão, política de privacidade, registo de atividades e DPIA escritos.

### Fase 6 — painel admin (PT-BR)
"Conformidade TVDE (IMT/AMT)", 12 separadores: interruptores, operadores, veículos, motoristas, a caducar, horas, queixas, fiscalização, AMT, teto 25 %, checklist, registo. Rota `/admin/tvde-conformidade` ligada.

### Fase 7 — provas técnicas
- `flutter analyze` (projeto inteiro): **0 erros, 0 avisos** (255 infos de estilo, antigas na maioria).
- Testes: **243/243 verdes** (TVDE antigos + novos); os 3 ficheiros novos à parte: **32/32**; painel admin e ficha legal: **30/30**; Deno (faturação + IMT): **7/7**.
- Anti-trapaça do Juiz: **CLEAN**.
- Push `ea5ab48d..75143a93`; CI arrancou: web, Android, iOS e imagens de referência (resultado na secção "Provas").

## Interruptores a ligar no dia da licença (por esta ordem)
Guia completo em `tvde-interruptores-dia-da-licenca-2026-09-30.md`:
0. **Antes de tudo (fora da app):** advogado, empresa, licença IMT, minutas à AMT, Livro de Reclamações e RAL, faturação certificada, o "vai" do dinheiro, e o RGPD publicado.
1. `plataforma_denominacao`, `plataforma_nif`, `plataforma_sede`, `plataforma_licenca_imt`.
2. Registar operadores. 3. Registar carros e associá-los aos motoristas. 4. Completar cada motorista.
5. `tvde_compliance_enforce` (mestre).
6. `tvde_compliance_block`. 7. `tvde_work_limit_enforce`. 8. `tvde_electronic_payment_only`.
9. `tvde_client_options_enabled`, depois `tvde_pref_matching_enforce`.
10. `tvde_iva_discriminar`. 11. `tvde_invoicing_provider`, depois `tvde_invoicing_enabled`.
12. `tvde_fixed_price_option_enabled` (depois de construído, com "vai"). 13. `tvde_imt_integration_enabled` (só com especificação do IMT).
**Nunca:** `tvde_driver_rates_client_disabled`.

## Outros erros encontrados pelo caminho (não corrigidos)
- A função antiga `fn_tvde_recibo_email_ao_finalizar` continua executável por `anon` (aviso do Supabase; é de 23/09).
- No projeto inteiro o Supabase aponta 203 funções `SECURITY DEFINER` executáveis por `anon` e 712 por `authenticated` (a maioria é intencional, protegida por `is_admin()` ou pela sessão). Não revisto nesta missão; só fechei as minhas.
- Imagens de referência (goldens) e `.gitignore`, `analysis_options.yaml` e `android/gradle.properties` já estavam alterados no PC antes desta sessão; não entraram no commit.
- O acerto de horas conta o tempo **online**; a lei fala em tempo de condução/trabalho — separar condução, espera e pausa (TT-02).
- As corridas de balcão podem violar a regra "só por reserva prévia na plataforma" (art. 5.º; PL-10).

## Provas

**CI do commit `75143a93`** (verificado na API do GitHub):
- Build & Deploy Web (Cloudflare Pages): **success**, 11:27 UTC.
- olho-golden: **success**, 11:25 UTC.
- Build Android & Deploy to Google Play e build-ios: **a correr** quando este relatório foi escrito (ver o resultado no GitHub Actions).

**Página de fiscalização no ar** (`app.boraguarda.com/fiscalizacao.html` e `bora-app-web.pages.dev/fiscalizacao.html`): HTTP 200 com o conteúdo novo nos dois endereços. Prova real com um código verdadeiro (válido 1 h, revogado logo a seguir):
- 25 viagens, 1 período de trabalho, 1 ficha de documentos e 1 bloqueio no período, sem dados do passageiro;
- código errado → "Código inválido."; depois de revogado → `codigo_revogado`;
- consultas registadas: 4 eventos `fiscalizacao_*`.
- Capturas: `.claude/.ai/provas/tvde-conformidade-2026-09-30/01_fiscalizacao_telemovel.png`, `01_fiscalizacao_computador.png`, `02_fiscalizacao_codigo_invalido.png`.
- **Defeito apanhado pela prova e corrigido:** o período saía em hora UTC ("01:00"); passou a meia-noite de Lisboa (migration `20260930128000`, conferida: 25/09 00:00 a 01/10 00:00).

**Ecrãs do cliente, motorista e admin na app:** sem captura. Chegar ao preço discriminado na web exige escrever um destino na pesquisa de moradas, dentro do canvas do Flutter. O cartão do motorista e o SOS só aparecem com uma corrida real, que seria oferecida a motoristas reais. O emulador não cabe na RAM de hoje. Provados por 32 testes de ecrã (cliente 12, motorista 10, admin 10) e pelas provas SQL acima. **Por fazer:** capturas no telemóvel de teste quando houver RAM ou cabo.
