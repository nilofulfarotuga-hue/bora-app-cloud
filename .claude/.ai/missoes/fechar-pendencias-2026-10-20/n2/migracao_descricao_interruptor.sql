-- 21/10/2026 · fechar-pendencias, agente-encomendas-n2 (Tarefa 3, painel PT-BR).
-- A descrição do interruptor das encomendas (que o painel mostra em Definições) passa a dizer
-- a regra de acesso nova (migração 20261021195814). Só a coluna description; o VALOR do
-- interruptor não muda (continua false). Aborta se a descrição no ar não for a esperada.
DO $mig$
DECLARE
  v_n int;
BEGIN
  UPDATE public.platform_settings
     SET description = 'Bora Encomendas: encomendas no MESMO motor do Bora Motorista (mesmo preço, despacho, pagamentos, reservas e cancelamento; só mudam as palavras). Acesso: a MESMA regra do Bora Motorista (users.tvde_access) — quem não tem acesso não pede encomendas; aprova-se em Pedidos de acesso TVDE. Desligado: o ladrilho Enviar Encomenda abre o fluxo antigo e o servidor recusa encomendas (encomendas_desligadas), salvo admin.'
   WHERE key = 'tvde_encomendas_enabled'
     AND description = 'Bora Encomendas: encomendas no MESMO motor do Bora Motorista (mesmo preço, despacho, pagamentos, reservas e cancelamento; só mudam as palavras). Desligado: o ladrilho Enviar Encomenda abre o fluxo antigo e o servidor recusa encomendas (encomendas_desligadas), salvo admin.';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'descrição de tvde_encomendas_enabled mudou no ar (% linhas) — nada aplicado', v_n;
  END IF;
END
$mig$;
