# Missão m2-estafeta-conta-fila-2026-11-08 — o que falta aplicar no servidor (para a Claude.ai)

O Claude Code não pode mudar a estrutura do banco de produção nem publicar (trava do modo automático de 05/11).
Ficou tudo pronto aqui, por esta ordem. Nenhuma destas mexe em valores de dinheiro.

1. `01_driver_minha_conta_estado.sql` — o semáforo "A minha conta" (fonte única da app e do painel). Só lê.
   Provado a 08/11 com o corpo corrido em bloco só de leitura contra 4 contas reais (resultados no relatório
   `docs/relatorio-m2-estafeta-2026-11-08.md`). Depois de aplicar: `select public.driver_minha_conta_estado('e355fde0-b634-48ba-bce1-e2a4466c4cc2');`
   tem de dar ao Valdemir: document, document_number, nascimento, iban, fiscal, atividade e recibo a "falta".
2. `02_meu_trabalho_em_curso_janela.sql` — a faixa "a decorrer" só para o que é hoje/agora (aceite até 3 h antes);
   o resto vem em `proxima`. Provado por SELECT com a limpeza ae42a171 (aceite para 14/11): antes "a decorrer",
   depois "próxima".
3. `03_fila_de_espera_candidatos.sql` — fase do candidato, `admin_estafetas_fila` (painel /admin/estafetas), texto
   fixo do "falta enviar", aviso único "tudo em ordem, ficas na fila" (push + WhatsApp da Bora) e a corrida diária
   (ligar o pg_cron no fim do ficheiro). Precisa da 01. Regra provada por SELECT: Adryan, Felipe e Marcley na fila;
   Adriano, Francielly, SAM, Valter e Waldyr com documentos pendentes.
4. `04_agendado_chamar_pelo_tempo_de_estrada.sql` — ZONA DE DESPACHO. Chamar o estafeta do pedido agendado de loja
   não-parceira a (hora pronto − estrada do estafeta online mais perto − 5 min), mínimo 10 min, tecto no setting de
   30 min. Aplicar só se a Claude.ai/Danilo concordarem que não é motor de despacho protegido.

Depois de aplicar cada uma: copiar o texto aplicado para `supabase/migrations/2026110820xxxx_<nome>.sql`.
A app já está preparada: sem a 01 monta o semáforo sozinha; sem a 02 lê a hora marcada da própria marcação.
