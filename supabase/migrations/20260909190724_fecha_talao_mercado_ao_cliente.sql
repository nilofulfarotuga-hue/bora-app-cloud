-- FIX 2026-09-09: o talao do mercado (foto + linhas lidas pelo OCR, com precos
-- reais de compra) NUNCA pode chegar ao cliente. O recibo do cliente e o da app:
-- produtos ao preco que ele viu + entrega + taxa de servico + sacos.
DROP POLICY IF EXISTS client_select_own_receipt ON public.order_receipts_v2;
DROP POLICY IF EXISTS client_select_own_receipt ON storage.objects;