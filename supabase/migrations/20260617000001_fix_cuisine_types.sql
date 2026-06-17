-- Limpar cuisine_type com valores inválidos em restaurants
UPDATE public.restaurants
SET cuisine_type = ''
WHERE cuisine_type IN ('fizxfjxfk', '509300100');

UPDATE public.restaurants
SET cuisine_type = 'Pizza'
WHERE cuisine_type = 'pizza';
