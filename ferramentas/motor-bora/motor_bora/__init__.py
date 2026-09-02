# -*- coding: utf-8 -*-
"""Motor Bora — o roteador de motores gratis, partilhado por WhatsApp, Hermes, Buzz e juiz.
Quatro pecas: rotacao de chaves, failover entre fornecedores, disjuntor por 429/5xx com castigo por
fornecedor, e descoberta viva dos modelos gratis. Perfis: chat-rapido, raciocinio, volume, audio, visao.
So biblioteca padrao (corre na VPS de 1 core/4 GB e no PC)."""
from .roteador import Roteador  # noqa: F401
