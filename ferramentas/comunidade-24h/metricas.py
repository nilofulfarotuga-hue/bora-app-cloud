"""Números do dia (09:00 Lisboa) -> redes_metricas. Só leitura nas plataformas.

YouTube: canal (seguidores, visualizações, vídeos) + últimos 10 vídeos (visualizações, gostos,
comentários). Facebook: seguidores da Página. Instagram: seguidores e publicações. Anúncio da
Meta: gasto do dia anterior (só ler, nunca mudar). Hotmart/Etsy/Shopify ficam de fora até haver
credenciais no cofre.
"""
from datetime import date, timedelta

import yt_oauth
from comum import contas, e2e, http, ler_cofre, registo, sb_upsert

YT = "https://www.googleapis.com/youtube/v3"
GRAPH = "https://graph.facebook.com/v21.0"


def linha(conta, rede, numeros, fonte, id_video=""):
    return {"conta": conta, "rede": rede, "dia": date.today().isoformat(), "id_video": id_video,
            "numeros": numeros, "fonte": fonte}


def youtube(c):
    tok, canal = yt_oauth.token(c["conta"])
    cab = {"Authorization": "Bearer " + tok}
    st, ch = http("GET", f"{YT}/channels?part=statistics,contentDetails&id={canal}", cabecalhos=cab)
    if st != 200 or not ch.get("items"):
        raise RuntimeError(f"channels HTTP {st}")
    s = ch["items"][0]["statistics"]
    out = [linha(c["conta"], "youtube", {"seguidores": int(s.get("subscriberCount", 0)),
                                         "visualizacoes": int(s.get("viewCount", 0)),
                                         "videos": int(s.get("videoCount", 0))}, "channels.list")]
    up = ch["items"][0]["contentDetails"]["relatedPlaylists"]["uploads"]
    st, pl = http("GET", f"{YT}/playlistItems?part=contentDetails&playlistId={up}&maxResults=10", cabecalhos=cab)
    ids = ",".join(i["contentDetails"]["videoId"] for i in pl.get("items", [])) if st == 200 else ""
    if ids:
        st, vs = http("GET", f"{YT}/videos?part=statistics&id={ids}", cabecalhos=cab)
        for v in vs.get("items", []) if st == 200 else []:
            vs_ = v["statistics"]
            out.append(linha(c["conta"], "youtube", {"visualizacoes": int(vs_.get("viewCount", 0)),
                                                     "gostos": int(vs_.get("likeCount", 0)),
                                                     "comentarios": int(vs_.get("commentCount", 0))},
                             "videos.list", v["id"]))
    return out


def meta(c):
    m = ler_cofre(f"meta/{c['conta']}.json")
    tok = m["page_token"]
    out = []
    st, p = http("GET", f"{GRAPH}/{m['page_id']}?fields=followers_count,fan_count&access_token={tok}")
    if st == 200:
        out.append(linha(c["conta"], "facebook", {"seguidores": p.get("followers_count"),
                                                  "gostos_pagina": p.get("fan_count")}, "page fields"))
    if m.get("ig_user_id"):
        st, i = http("GET", f"{GRAPH}/{m['ig_user_id']}?fields=followers_count,media_count&access_token={tok}")
        if st == 200:
            out.append(linha(c["conta"], "instagram", {"seguidores": i.get("followers_count"),
                                                       "publicacoes": i.get("media_count")}, "ig user fields"))
    return out


def anuncio(c):
    a = ler_cofre("meta-ads.json")  # {ad_account_id, token} — token só com ads_read
    ontem = (date.today() - timedelta(days=1)).isoformat()
    st, r = http("GET", f"{GRAPH}/act_{a['ad_account_id']}/insights?fields=spend,impressions,clicks"
                        f"&time_range={{\"since\":\"{ontem}\",\"until\":\"{ontem}\"}}&access_token={a['token']}")
    if st != 200:
        raise RuntimeError(f"insights HTTP {st}: {str(r)[:200]}")
    d = (r.get("data") or [{}])[0]
    return [linha(c["conta"], "meta-ads", {"dia_medido": ontem, "gasto_eur": float(d.get("spend", 0) or 0),
                                           "impressoes": int(d.get("impressions", 0) or 0),
                                           "cliques": int(d.get("clicks", 0) or 0)}, "ads insights")]


def main():
    linhas, resumo = [], []
    for c in contas():
        for nome, fn, tem in (("youtube", youtube, c.get("youtube")), ("meta", meta, c.get("facebook_page_id")),
                              ("anuncio", anuncio, c.get("anuncio_meta"))):
            if not tem:
                continue
            try:
                novas = fn(c)
                linhas += novas
                resumo.append(f"{c['conta']}/{nome}: {len(novas)}")
            except FileNotFoundError:
                resumo.append(f"{c['conta']}/{nome}: sem token")
            except Exception as e:
                resumo.append(f"{c['conta']}/{nome}: ERRO {str(e)[:120]}")
    if linhas:
        st, r = sb_upsert("redes_metricas", linhas, "conta,rede,dia,id_video")
        resumo.append(f"gravadas={len(linhas)} HTTP {st}")
        ok = st in (200, 201)
    else:
        ok = False
    texto = "; ".join(resumo)
    registo("metricas", resumo=texto)
    e2e("metricas", "feito" if ok else "erro", texto)
    print(texto)


if __name__ == "__main__":
    main()
