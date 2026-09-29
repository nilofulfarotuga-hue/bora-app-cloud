# Provas — missão mister-navalha-2026-09-29 (29/09/2026, Opus, PC do Danilo)

Saídas literais das verificações. RAM no arranque: 1860 MB disponíveis (acima dos portões 400/800).

## Bloco 1 — site

Cópia fixa: `C:\BoraLocal\projetosflutter\sites\misternavalha\` (git local, commits `3e5c0aa` e `e5e5d9e`).

```
index.html d3d78ee55532 d3d78ee55532 IGUAL          (origem vs cópia)
assets/fundo.mp4 387632a80fb4 387632a80fb4 IGUAL
assets/fundo-telemovel.mp4 6d0389759bc0 6d0389759bc0 IGUAL
```

Cloudflare (tokens do `bora-site/.env`, nunca impressos):

```
token PAGES: http 200 status=active success=True
token DNS: http 200 status=active success=True
projecto misternavalha: http 404 (não existia)
criar projecto: http 200 success=True   subdomain: misternavalha.pages.dev
wrangler: ✨ Success! Uploaded 19 files — Deployment complete! https://b860fe12.misternavalha.pages.dev
custom domain: http 200 success=True  status: initializing
criar CNAME: http 200 success=True   CNAME misternavalha.boraguarda.com -> misternavalha.pages.dev proxied= True
(minutos depois) custom domain: status=active verificacao=active validacao=active cert_authority=google
```

Endereço público:

```
DNS: 104.21.74.105
200 text/html; charset=utf-8 35228 md5 d3d78ee55532 local d3d78ee55532 IGUAL https://misternavalha.boraguarda.com/
200 text/html; charset=utf-8 35228 md5 d3d78ee55532 local d3d78ee55532 IGUAL https://misternavalha.pages.dev/
200 video/mp4 1511492 md5 IGUAL assets/fundo.mp4 | accept-ranges bytes
200 video/mp4 855581 md5 IGUAL assets/fundo-telemovel.mp4 | accept-ranges bytes
200 video/mp4 316211 md5 IGUAL assets/workshop.mp4 | accept-ranges bytes
pagina inexistente: 404 e a 404 propria: True
200 text/plain robots.txt / 200 application/xml sitemap.xml
```

Links da página:

```
200 https://app.boraguarda.com
301 https://apps.apple.com/pt/app/bora-entregas-e-servicos/id6809954739
    iphone -> itms-appss://apps.apple.com/pt/app/bora-entregas-e-servicos/id6809954739
    desktop -> 200 "App Bora — entregas e serviços – App Store"
    lookup pt resultCount 1 | Bora — entregas e serviços 1.0.4   (a loja portuguesa já está aberta)
200 https://boraguarda.com
200 https://play.google.com/store/apps/details?id=pt.boraapp.bora | Bora App – Apps no Google Play
200 https://www.google.com/maps/search/?api=1&query=Rua+Ant%C3%B3nio+S%C3%A9rgio+20%2C+Guarda
200 https://www.instagram.com/barbearia_mister_navalha__/ | title=Barbearia Mister Navalha (@barbearia_mister_navalha__) | username=barbearia_mister_navalha__
200 https://www.instagram.com/ernando__silva/ | title=Ernando Silva | Barbeiro (@ernando__silva) | username=ernando__silva
14 recursos da página (fotos, posters, vídeos): todos 200
```

Telemóvel, "reduzir movimento" ligado e desligado (`prova_video_telemovel.py`, capturas em `telemovel/`):

```
webkit-iPhone15-reduzir-LIGADO      fundo-telemovel.mp4 t 2.41 -> 4.92 paused=false readyState=4 erro=null scrollWidth=393  VIDEO_CORRE=true
webkit-iPhone15-reduzir-DESLIGADO   fundo-telemovel.mp4 t 2.41 -> 4.92 ...                                                 VIDEO_CORRE=true
chromium-iPhone15-reduzir-LIGADO    fundo-telemovel.mp4 t 2.58 -> 5.10 ...                                                 VIDEO_CORRE=true
chromium-iPhone15-reduzir-DESLIGADO fundo-telemovel.mp4 t 2.60 -> 5.12 ...                                                 VIDEO_CORRE=true
chromium-Pixel7-reduzir-LIGADO      fundo-telemovel.mp4 t 2.52 -> 5.03 ... scrollWidth=412                                 VIDEO_CORRE=true
chromium-Pixel7-reduzir-DESLIGADO   fundo-telemovel.mp4 t 2.69 -> 5.20 ...                                                 VIDEO_CORRE=true
resumo: 6 de 6 casos com o video a correr
```

## Bloco 2 — loja na app

Upload (`sites/misternavalha/loja-app/upload_storage.py`), leitura de volta sem token:

```
200 image/png   124320 B  md5 IGUAL  .../553a0d77-30ff-4f51-b148-59cb1264cfa1/logo.png
200 image/jpeg   42490 B  md5 IGUAL  .../capa.jpg
200 image/jpeg   90412 B  md5 IGUAL  .../ernando.jpg
200 image/jpeg   13855 B  md5 IGUAL  .../logo-instagram-150px.jpg
200 image/jpeg  192506 B  md5 IGUAL  .../gallery/corte-1.jpg
200 image/jpeg  147276 B  md5 IGUAL  .../gallery/corte-2.jpg
200 image/jpeg  141413 B  md5 IGUAL  .../gallery/corte-3.jpg
200 image/jpeg   58709 B  md5 IGUAL  .../gallery/corte-4.jpg
200 image/jpeg  181005 B  md5 IGUAL  .../gallery/corte-5.jpg
200 image/jpeg   54281 B  md5 IGUAL  .../gallery/corte-6.jpg
200 image/jpeg  201488 B  md5 IGUAL  .../gallery/certificado.jpg
falhas: 0
```

Logo: `fontes carregadas (Norican, Zilla Slab 600): [True, True]` · `tamanho (1024, 1024) modo RGB` ·
`anel (x=512,y=45) (200, 145, 78)` = #c8914e sobre (10,10,10).

Base (UPDATE com guarda "só se ainda vazio"): `lojas_actualizadas 1, barbeiros_actualizados 1`.
SELECT de volta: photo_url=logo.png, hero_image_url=capa.jpg, gallery_urls[0..6]=corte-1..6, certificado,
staff Ernando photo_url=ernando.jpg, coming_soon=true. GET aos 10 URLs da base: 10× 200.

O que a app recebe sem sessão (chave pública, REST):

```
service_providers (anon): 200 linhas 1  coming_soon=True  photo_url=logo.png  hero_image_url=capa.jpg
  gallery_urls: 7 fotos -> corte-1..6.jpg, certificado.jpg
staff_members (anon): 200 [('Ernando Silva', 'ernando.jpg')]
provider_services activos (anon): 200 [('Degradê',1300,45), ('Corte de Cabelo',1200,30), ('Barba',800,20),
  ('Combo Cabelo + Barba',1800,50), ('Corte Criança',1000,30), ('Sobrancelha',300,10), ('Freestyle',300,10)]
barbearias visiveis ao cliente sem sessao: [('Barbearia Ouro e Prata', True, True), ('Barbearia Mister Navalha', True, True)]
```

A origem de cada foto ficou em `storage.objects.user_metadata.origem`.

## Bloco 3 — preços (BLOQUEADO)

```
extensão perfil Bora: screenshot -> "Script injection timed out after 5000ms"
                      javascript -> "CDP sendCommand Runtime.evaluate timed out after 45000ms"
                      (igual em separador novo, em example.com e no nosso site; igual com a janela à frente,
                       maximizada e "sempre por cima"; aba activada por UI Automation)
extensão perfil pessoal: igual
computer use (Chrome, só leitura): {"granted":[],"denied":[... "reason":"user_denied"]}
navegador embutido sem sessão: "Regista-te para ver mais destaques das histórias de barbearia_mister_navalha__."
visualizador público storiesig: página de anúncios e planos pagos — abandonado sem clicar
Chrome, janela Em Dia: 2 barras "\"Claude\" iniciou a depuração deste navegador."
```
