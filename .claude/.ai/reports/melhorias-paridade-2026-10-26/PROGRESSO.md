# PROGRESSO — melhorias-paridade-2026-10-26

Cópia: `../bora-melhorias`, ramo `melhorias-paridade-2026-10-26`, base origin b42736d3.
e2e_log: fluxo e run_id `melhorias-paridade-2026-10-26`.
Regra por item: código → analyze → teste → revisor SIM → commit → e2e_log.
Estados: [ ] por fazer · [~] a meio · [x] feito (commit) · [!] bloqueado/reportado

## Bloco 1 — o que faz perder clientes
- [x] 1. (70375d0d) Finalizar sem conta → "Entrar ou criar conta" → volta ao mesmo carrinho
- [x] 2. (70375d0d; migração 20261026090000 por aplicar; Edge sessao-convidado por publicar) Sessão de convidado (guest@bora.com, sem anónimo) + interruptor no painel
- [x] 3. (8e44066c) Taxas sem conta: "calculada no fim", nunca valor de recurso
- [x] 4. (7172332c) Loja fechada: vê tudo, faixa "Fechado · abre às", travão no carrinho, nunca "5-20 min"; painel "aberta agora?"
- [x] 5. (1f714ea4; migração 20261026091000 por aplicar) Antes de pagar: "Entregar em: … · Trocar" + nota visível; painel: morada trocada no fim
- [~] 6. Preços no formato PT (9,65 €)
- [x] 7. (9ce18db7) "Pedir de novo" pergunta antes de substituir o carrinho

## Bloco 2 — loja, produto e carrinho
- [ ] 8. Ficha "Informações da loja"
- [ ] 9. Faixas "Os mais pedidos" e "Novidades" + painel
- [ ] 10. Tocar numa linha do carrinho reabre o produto para editar
- [ ] 11. "Para acompanhar" no carrinho + painel
- [~] 12. (migração 20261026093000 escrita) Extras BK "SIN" → "Sem" (migração no pacote do bloco 4)
- [ ] 13. Produto a 1440 px com largura máxima
- [ ] 14. Textos sem tradução (cart 569/647, product_detail 520)

## Bloco 3 — página inicial e lista
- [ ] 15. Cartões da home com tempo, taxa, nota (mínimo no painel), distância
- [ ] 16. Lista: 3 filtros + ordenar; admin_discovery_filters

## Bloco 4 — parceiro e painel
- [~] 17. Alergénios no painel admin
- [~] 18. Interruptor das gorjetas por admin_update_setting
- [ ] 19. Parceiro: extras tudo-ou-nada, esgotado_ate, confirmar recusa, prep_time, botão Avaliações
- [ ] 20. Livro de Reclamações (home, rodapé web, topo do Perfil)
- [~] 21. (migração 20261026092000 escrita) home_banners: migração idempotente no repo (não aplicar)
- [ ] Pacote de migrações (com item 12)

## Bloco 5 — create_order (SÓ PREPARAR)
- [ ] pendente_create_order.sql + ROLLBACK + revisor

## Bloco 6 — fecho
- [ ] Ramo por cima do origin, envio do ramo
- [ ] RELATORIO.md · Córtex · e2e_log 99 · PADRAO_BORA · Obsidian · digest · Telegram · /ctx

## Adendo da Claude.ai (26/10, 10:25)
- [ ] A1. Horários depois da meia-noite (20:00–02:00) contam como abertos (isOpenNow vê a janela de ontem)
- [ ] A2. Aviso do travão: "abre amanhã às" / dia da semana; dia fechado diz quando abre
- [ ] A3. "Lojas abertas parecidas" usa a loja que o cliente está a ver
- [ ] A4. stores_screen usa fechadaParaCliente
- [ ] A5. Painel "aberta agora?" vê todas as lojas (não só aprovadas/ativas)
- [ ] A-testes: janela da noite e "amanhã"
- [ ] B. Carrinho reposto: isPartnerStore vem da loja, nunca ?? true (só o que se VÊ) + teste não-parceira
- [ ] C. Marca "morada trocada" também no timeout do cartão
- [ ] D. Bloco 5: pendente_get_setting.sql (claims → só service_role/admin; sem claims → só session_user postgres/supabase_admin; prova ROLLBACK)
