# Registo das Atividades de Tratamento — TVDE Bora (RGPD, art. 30.º)

> 30/09/2026 · agente `compliance-pt` · documento interno (não se publica; mostra-se à CNPD se ela pedir, RGPD art. 30.º n.º 4).
> Responsável: **[DENOMINAÇÃO]**, NIPC **[NIPC]**, sede **[SEDE]**, contacto **[EMAIL PRIVACIDADE]**. EPD: **[A CONFIRMAR se é obrigatório]**.
> A dispensa das empresas com menos de 250 pessoas (art. 30.º n.º 5) **não se aplica**: o tratamento é regular e inclui localização, dados de saúde (mobilidade reduzida) e registo criminal.
> Nomes de tabelas entre `crases` = onde os dados vivem hoje no Supabase (projeto `ojykpzwqrtusfeakzrna`).

## A. Tratamentos

| # | Atividade | Titulares | Categorias de dados | Finalidade | Fundamento | Onde vive | Destinatários | Prazo de conservação |
|---|---|---|---|---|---|---|---|---|
| T1 | Contas de passageiros | passageiros | nome, telefone, email, idioma | prestar o serviço | 6.º n.º 1 b) | Supabase Auth, perfis | subcontratantes (S1) | vida da conta |
| T2 | Pedidos e viagens TVDE | passageiros, motoristas | origem, destino, paragens, horas, distância, preço, código da viagem | intermediação, preço, fatura | 6.º n.º 1 b) e c); Lei 45/2018 arts. 13.º n.º 3, 15.º | `tvde_rides`, `tvde_ride_events` | operador e motorista da viagem; IMT/AMT/AT (T13) | 2 anos + até 1 ano **[POR CONFIRMAR]** |
| T3 | Geolocalização do passageiro | passageiros | posição durante o pedido e a viagem | recolha, acompanhamento, SOS | 6.º n.º 1 b) | na viagem (`tvde_rides`) | motorista da viagem | com a viagem (T2) |
| T4 | Geolocalização do motorista | motoristas | posição e sinal enquanto está disponível e em viagem | despacho, mapa do passageiro, SOS | 6.º n.º 1 b) e c); art. 19.º n.º 1 c) | `drivers` (última posição e sinal) | passageiro da viagem | última posição sobrescrita; percurso com a viagem (T2) **[A CONFIRMAR se há histórico de posições]** |
| T5 | Pagamentos | passageiros | forma de pagamento, montantes; o cartão fica no processador | cobrança | 6.º n.º 1 b) e c); art. 15.º n.º 7 | pedidos + processador (S2) | processador de pagamentos | prazo fiscal **[A CONFIRMAR]** |
| T6 | Preferências de acessibilidade e língua | passageiros | fala português; mobilidade reduzida, cadeira, cão-guia, carrinho (**possível dado de saúde**) | art. 6.º e art. 19.º n.º 1 i) | 6.º n.º 1 b) + **9.º n.º 2 a)** (consentimento explícito) | `tvde_client_prefs`, `tvde_rides.necessidades` | motorista da viagem (só o que precisa) | até o titular desligar a opção; na viagem, com T2 |
| T7 | Candidatura e documentos do motorista | motoristas | identificação, NIF, CMTVDE, carta, contrato com o operador, curso, **registo criminal** | verificar requisitos legais | 6.º n.º 1 c) + **art. 10.º RGPD** (lei: art. 11.º da Lei 45/2018) | `drivers`, `motorista_ficha_legal`, `tvde_driver_documents` (bucket privado) | IMT (verificação) | enquanto ativo + 2 anos |
| T8 | Operadores e veículos | representantes dos operadores | denominação, NIPC, contactos, licença; matrícula, seguro, inspeção, foto | art. 12.º n.º 1, art. 20.º n.º 5 | 6.º n.º 1 c) | `tvde_operators`, `tvde_vehicles`, `tvde_driver_vehicle` | IMT | enquanto ativo + 2 anos |
| T9 | Conformidade e bloqueio | motoristas | motivos, avisos, bloqueio manual, histórico | art. 14.º n.º 2 | 6.º n.º 1 c); com **revisão humana** (art. 22.º) | `tvde_driver_compliance`, `tvde_compliance_events` | admin | 2 anos + até 1 ano |
| T10 | Tempos de trabalho | motoristas | início e fim em serviço; horas declaradas noutras plataformas | arts. 13.º e 20.º n.º 3 | 6.º n.º 1 c) | `tvde_driver_work_log`, `drivers.tvde_horas_outras_plataformas` | ACT, IMT | 2 anos + até 1 ano |
| T11 | Avaliações | passageiros, motoristas | nota, comentário | art. 19.º n.º 1 d) e n.º 2 c) | 6.º n.º 1 c) | `tvde_rides` | admin | com a viagem |
| T12 | Queixas e Livro de Reclamações | quem se queixa, visados | descrição, contacto, viagem, diligências | art. 19.º n.º 3; DL 156/2005 | 6.º n.º 1 c) | `tvde_complaints` | entidade RAL, se houver recurso | 2 anos + até 1 ano **[POR CONFIRMAR]** |
| T13 | Fiscalização e partilha com autoridades | motoristas, veículos, operadores, viagens (sem contacto do passageiro) | dados estritamente necessários | arts. 17.º-A n.º 2 d), 20.º-A, 23.º | 6.º n.º 1 c) | `tvde_fiscal_access` (registo de acessos) + ficha de fiscalização | IMT, AMT, AT, ISS, GNR, PSP, ACT, CNPD | registo de acessos: 2 anos |
| T14 | SOS | passageiros, motoristas | localização, hora, chamada ao 112, partilha | art. 19.º n.º 1 j) | 6.º n.º 1 c) e d) | `tvde_sos_events` | 112 e forças de segurança; admin | 2 anos, ou mais se houver processo |
| T15 | Faturação e e-fatura | passageiros | dados da fatura | art. 15.º n.º 8; DL 28/2019; DL 198/2012 | 6.º n.º 1 c) | `tvde_invoices` + fornecedor (S6) | AT | prazo fiscal **[A CONFIRMAR]** |
| T16 | Relatório e contribuição AMT | nenhum dado pessoal (agregados) | viagens, montantes | art. 30.º | 6.º n.º 1 c) | `tvde_amt_reports`, `tvde_intermediacao_verificacao` | AMT | prazo fiscal |
| T17 | DAC7 | operadores (vendedores) | denominação, NIF, morada, montantes | Lei 36/2023 **[NC]** | 6.º n.º 1 c) | exportação no admin | AT | 10 anos **[NC]** |
| T18 | Notificações push | passageiros, motoristas | identificador do dispositivo | avisos da viagem | 6.º n.º 1 b) | perfis / `drivers` | Firebase (S3) | vida da conta |
| T19 | Marketing | passageiros que aceitaram | contacto, preferências | promoções | **6.º n.º 1 a)** (consentimento) | perfis | — | até retirar o consentimento |
| T20 | Suporte (chat) | utilizadores | mensagens | responder a pedidos | 6.º n.º 1 b) | tabelas de suporte | — | **[A CONFIRMAR]** |

## B. Subcontratantes (RGPD art. 28.º) — **[A CONFIRMAR nomes, contratos e regiões]**

| # | Serviço | Para quê | Região / transferência |
|---|---|---|---|
| S1 | Supabase | base de dados, autenticação, armazenamento, funções | **[A CONFIRMAR região do projeto]** |
| S2 | Stripe | cartão e MB WAY | fora da UE: garantias do RGPD **[A CONFIRMAR]** |
| S3 | Google Firebase (FCM) | notificações | fora da UE **[A CONFIRMAR]** |
| S4 | Google Maps Platform | mapas, moradas, rotas | fora da UE **[A CONFIRMAR]** |
| S5 | Cloudflare Pages | alojamento da app web e da página de fiscalização | **[A CONFIRMAR]** |
| S6 | Fornecedor de faturação certificada (Moloni, InvoiceXpress ou Vendus) | faturas | Portugal **[por escolher]** |
| S7 | Fornecedor de email (Resend ou outro) | recibos e avisos | **[A CONFIRMAR]** |

## C. Medidas de segurança (RGPD art. 32.º)

- RLS (segurança por linha) em todas as tabelas TVDE novas: o motorista só vê o que é dele; a administração vê tudo.
- Documentos em bucket privado, com links assinados e temporários.
- Funções do servidor com permissões fechadas ao público (migração `20260930126000`).
- Acesso de fiscalização por código temporário, com prazo, revogável e com contador de consultas; sem nome, telefone nem email do passageiro.
- Histórico de conformidade e de bloqueios guardado (`tvde_compliance_events`).
- Por fazer: auditoria sob supervisão da CNPD (Lei 45/2018, art. 20.º n.º 2); procedimento escrito para violações de dados (72 h, arts. 33.º–34.º).

## D. Revisão

Rever este registo sempre que entrar um tratamento novo e, no mínimo, uma vez por ano. Próxima revisão: no dia da licença.
