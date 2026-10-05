-- 05/10 09:20 — o motor v62 (no ar desde 09:10) exige GPS com menos de 900 s. Os 2 estafetas online
-- (heartbeat fresco) têm o GPS parado há 8 h e 37 h: as apps antigas não mandam a posição quando estão
-- parados, por isso NENHUM recebia ofertas. Alívio temporário a 48 h até os estafetas terem a versão nova
-- (posição a cada 60 s, publicada a 04/10). Voltar a 900 depois.
update public.platform_settings
   set value = '172800'::jsonb,
       description = 'Entregas: estafeta com GPS ou sinal (heartbeat) mais velho que isto (segundos) não recebe ofertas. Não o desliga. 05/10: 172800 (48 h) TEMPORÁRIO — apps antigas não mandam a posição parados; voltar a 900 quando os estafetas tiverem a versão nova.'
 where key = 'dispatch_gps_fresh_seconds_entregas';
