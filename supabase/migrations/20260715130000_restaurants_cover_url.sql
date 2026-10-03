-- Adiciona cover_url (imagem de capa, retangular) à tabela restaurants.
-- Distinto de photo_url (logo, quadrada). Nullable — opcional, preenchido
-- no wizard de cadastro de parceiro (passo "Logo & Confirmação").
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS cover_url TEXT;
