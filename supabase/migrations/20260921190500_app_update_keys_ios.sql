-- Paridade 3 plataformas (2026-09-21): o aviso de actualização passa a ter
-- chaves próprias para o iPhone.
--
-- Porquê: o iOS tem OUTRO contador de versão (CFBundleVersion = número da
-- corrida do build_ios.yml, ia em 115) enquanto o Android vai em 614. Com uma
-- chave só, no dia em que app_min_supported_version_code subisse acima de 115
-- e o CI do iOS passasse a injectar BORA_VERSION_CODE, todos os iPhones
-- ficavam bloqueados de uma vez. Cada plataforma passa a comparar com a sua
-- chave (lib/services/app_update_service.dart, sufixo `_ios`).
--
-- 0 = desligado (o gate cala-se), exactamente como nas chaves do Android.
-- A `app_latest_version_code_ios` NÃO é escrita pelo CI: um build iOS enviado
-- ao App Store Connect ainda não está na loja (passa pela revisão da Apple).
-- Quem a põe é o Danilo no painel admin quando a versão ficar disponível.
--
-- Só valores operacionais (números de build) — nada de dinheiro.

insert into public.platform_settings (key, value, category, description)
values
  ('app_latest_version_code_ios', '0'::jsonb, 'app_update',
   'iPhone: número do build (CFBundleVersion) mais recente disponível na App Store; 0 = aviso desligado. Preenche-se à mão quando a Apple aprova a versão.'),
  ('app_min_supported_version_code_ios', '0'::jsonb, 'app_update',
   'iPhone: número do build mínimo suportado; abaixo disto a app bloqueia até actualizar. 0 = sem bloqueio.')
on conflict (key) do nothing;

update public.platform_settings
   set description = 'Android: versionCode mais recente publicado na Play Store; 0 = aviso desligado. O CI atualiza a cada release (o iPhone tem a chave _ios).'
 where key = 'app_latest_version_code';

update public.platform_settings
   set description = 'Android: versionCode mínimo suportado; abaixo disto o app bloqueia até atualizar. 0 = sem bloqueio (o iPhone tem a chave _ios).'
 where key = 'app_min_supported_version_code';
