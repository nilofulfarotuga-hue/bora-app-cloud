#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Titulo do cartaz e legenda da loja do dia, em PT-PT, pelas regras de marca.

  --campo titulo  -> uma linha (gancho curto para o cartaz, 7 palavras no maximo)
  --campo legenda -> legenda completa: gancho humano na 1.a linha, BEMVINDO e link, aviso legal se for loja
                     grande, hashtags locais no fim, @mencao do parceiro se houver.

VOZ HUMANA (ordem do Danilo de 08/11/2026, missao m6-crescimento-hermes; regras em /opt/data/social/VOZ-HUMANA.md):
  quem escreve e' uma pessoa da Guarda que trabalha no Bora, na primeira pessoa do plural ("vamos nos buscar",
  "levamos-te a casa"), nunca "a nossa plataforma"; legenda curta com um detalhe humano e UMA chamada; no maximo
  1 emoji (o do link); nada de factos inventados (numeros de entregas, nomes de clientes, horas que nao se viram).

Parceiro: pode ter logo, fotos e nome. Loja grande: nome SO em texto, nunca "parceiro", "oficial" nem promessas sobre
o produto deles. Nunca TVDE/boleia. Ouro e Prata fora (lojas_permitidas.py ja a tira).
"""
import argparse
import datetime
import sys

LINK = "https://boraguarda.com/baixar?de=qr-feed"
LOCAIS = "#Guarda #GuardaPortugal #Beiras #entregasGuarda #BoraApp"

TIT_PARCEIRO = {
    "restaurant": ["{nome}: vamos nós buscar", "{nome} até à tua porta", "Pedes {nome}, levamos nós"],
    "festas": ["Salgados da Keli, levamos nós", "A festa começa nos salgados da Keli", "Encomendas de festa até à porta"],
    "barbershop": ["Corte marcado pela app", "{nome}: marca o corte na app", "Marca o corte sem telefonar"],
}
TIT_GRANDE = {
    "restaurant": ["{nome}? Vamos nós buscar", "{nome} sem sair do sofá", "Hoje é {nome}, levamos nós"],
    "supermarket": ["Compras do {nome} à tua porta", "Vamos nós ao {nome} por ti", "As compras do {nome}, sem carrinho"],
    "pharmacy": ["{nome} até tua casa", "Da {nome} à tua porta", "Farmácia sem sair de casa"],
    "store": ["Da {nome} para tua casa", "Vamos nós à {nome} por ti", "{nome} sem ires lá"],
}
TAGS_TEMA = {
    "restaurant": "#comida #delivery #restaurantesGuarda #jantar #almoço",
    "festas": "#festas #salgados #encomendas #aniversário #coxinha",
    "barbershop": "#barbearia #corte #barba #beleza",
    "supermarket": "#supermercado #compras #mercearia #entregaEmCasa",
    "pharmacy": "#farmácia #saúde #entregaEmCasa #bemEstar",
    "store": "#loja #compras #entregaEmCasa #Guarda",
}
# Tres ganchos por tema, a rodar pelo dia (nunca o mesmo dois dias seguidos).
GANCHO_GRANDE = {
    "restaurant": [
        "Apetece {nome} e não te apetece sair? Pedes na app e um de nós vai lá buscar e leva-te a casa.",
        "Hoje é dia de {nome}? Fica no sofá: pedes na app e nós tratamos do resto, da fila à tua porta.",
        "Somos da Guarda e somos nós que entregamos. Pedes {nome} na app e levamos-to a casa.",
    ],
    "supermarket": [
        "Esqueceste-te de alguma coisa? Fazes a lista no telemóvel, um de nós vai ao {nome} e deixa-te as compras à porta.",
        "As compras do {nome} sem fila nem sacos pesados: escolhes na app e nós levamos até à tua porta.",
        "Chuva lá fora e a despensa vazia? Pedes as compras do {nome} na app e vamos nós buscar.",
    ],
    "pharmacy": [
        "O que precisas da {nome} levamos nós, para não teres de sair de casa.",
        "Não estás para sair? Pedes à {nome} pela app e nós vamos lá buscar.",
        "Da {nome} até à tua porta, entregue por gente da Guarda.",
    ],
    "store": [
        "Aquilo que querias da {nome}? Vamos nós buscar e levamos-te a casa.",
        "Da {nome} para tua casa, sem ires lá: pedes na app e nós tratamos.",
        "Pedes na app, nós passamos na {nome} e levamos-te a casa.",
    ],
}
GANCHO_PARCEIRO = {
    "restaurant": [
        "Na {nome} fazem, nós levamos. Pedes na app, vês o preço logo e chega-te quentinho a casa.",
        "Hoje somos nós que vamos à {nome} buscar o teu jantar. É pedir na app e esperar à porta.",
        "Está frio para sair? Pedes {nome} na app e vamos nós lá buscar, com o saco fechado até tua casa.",
    ],
    "festas": [
        "Festa marcada? A Keli faz os salgados por encomenda e nós vamos buscá-los para ti. É só pedir na app com tempo.",
        "Coxinhas, kibe, risóis: a Keli frita, nós entregamos. Encomendas para a festa pela app, na Guarda.",
        "Aniversário lá em casa? Encomendas os salgados da Keli na app e nós levamos-tos no dia.",
    ],
    "barbershop": [
        "Marcas o corte na {nome} pela app, sem telefonemas nem esperas.",
        "O teu corte na {nome}, com hora marcada na app.",
        "Escolhes a hora na app e a {nome} fica à tua espera.",
    ],
}
AVISO = "Serviço de entrega independente, sem ligação oficial à marca."


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nome", required=True)
    p.add_argument("--tipo", default="grande")
    p.add_argument("--categoria", default="restaurant")
    p.add_argument("--ig", default="")
    p.add_argument("--campo", choices=["titulo", "legenda"], default="titulo")
    p.add_argument("--dia", type=int, default=None, help="ordinal do dia (para provar a rotacao sem mexer no relogio)")
    a = p.parse_args()
    nome = a.nome.split(" - ")[0].strip()  # "Sabores do Brasil - Keli Barbosa" -> "Sabores do Brasil"
    cat = a.categoria if a.categoria in TAGS_TEMA else "restaurant"
    n = a.dia if a.dia is not None else datetime.date.today().toordinal()
    if a.tipo == "parceiro":
        tit = TIT_PARCEIRO.get(cat, TIT_PARCEIRO["restaurant"])[n % 3].format(nome=nome)
        gancho = GANCHO_PARCEIRO.get(cat, GANCHO_PARCEIRO["restaurant"])[n % 3].format(nome=nome)
    else:
        tit = TIT_GRANDE.get(cat, TIT_GRANDE["restaurant"])[n % 3].format(nome=nome)
        gancho = GANCHO_GRANDE.get(cat, GANCHO_GRANDE["restaurant"])[n % 3].format(nome=nome)
    # 2026-09-21: a grelha do fiscal exige 7 palavras ou menos no titulo. Com nome comprido o gancho fica curto.
    if len(tit.split()) > 7:
        curtos = ["{nome}, à tua porta", "{nome}: levamos nós", "{nome} chega a casa"]
        tit = curtos[n % 3].format(nome=nome)
        if len(tit.split()) > 7:
            tit = nome
    if a.campo == "titulo":
        print(tit)
        return 0
    linhas = [gancho, "Primeiro pedido com o código BEMVINDO.", "👉 " + LINK]
    if a.tipo != "parceiro":
        linhas.append(AVISO)
    rodape = ("@" + a.ig + " " if a.ig else "") + LOCAIS + " " + TAGS_TEMA[cat]
    linhas.append(rodape)
    print("\n".join(linhas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
