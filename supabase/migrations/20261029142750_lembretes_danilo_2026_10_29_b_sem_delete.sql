-- Os privilégios por defeito do Supabase dão tudo a "authenticated"; aqui ficam só select/insert/update.
revoke delete, truncate, references, trigger on public.lembretes_danilo from authenticated;
revoke all on sequence public.lembretes_danilo_id_seq from authenticated;
grant usage, select on sequence public.lembretes_danilo_id_seq to authenticated;
