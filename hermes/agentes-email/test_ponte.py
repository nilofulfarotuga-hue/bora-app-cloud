#!/usr/bin/env python3
"""Testes do ponte.py (ronda 2b, 22/10/2026).

Correm numa pasta temporária, sem rede e sem chave: o `pedido()` ao Supabase é trocado por um falso.
A classe Fila só funciona em Linux (dir_fd, O_NOFOLLOW, FIFO) — fora de Linux falha, não se salta.
Uso:  python3 -I test_ponte.py              (Linux: tudo)
      python -I -B test_ponte.py Responder  (Windows: só o responder)
"""
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ponte  # noqa: E402

ID = '12345678-1234-1234-1234-123456789abc'


def md5(caminho):
    with open(caminho, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()


class ComFalso(unittest.TestCase):
    def setUp(self):
        self.chamadas = []
        self.remetente = 'Cliente <cliente@exemplo.pt>'

        def falso(metodo, caminho, corpo=None, extra=None):
            self.chamadas.append((metodo, caminho))
            if caminho.startswith('/rest/v1/rpc/agentes_email_resumo'):
                return 200, [{'agente': 'emerson', 'nao_lidos': 2, 'total': 5}]
            if caminho.startswith('/rest/v1/agentes_email?id=eq.'):
                return 200, [{'de': self.remetente, 'direcao': 'entrada'}]
            if caminho.startswith('/functions/v1/agentes-email-enviar'):
                return 200, {'ok': True, 'de': 'emerson@boraguarda.com', 'para': ['x@exemplo.pt'], 'id': 'r1', 'resend_id': 'z1'}
            return 404, {'erro': 'falso'}

        self._orig = ponte.pedido
        ponte.pedido = falso

    def tearDown(self):
        ponte.pedido = self._orig

    def enviou(self):
        return any(c[1].startswith('/functions/') for c in self.chamadas)


class Responder(ComFalso):
    def test_recusa_remetentes_automaticos(self):
        for de in ('no-reply@accounts.google.com', 'noreply@github.com', 'MAILER-DAEMON@mx.exemplo.pt',
                   '"Mail Delivery Subsystem" <mailer-daemon@googlemail.com>', 'postmaster@exemplo.pt',
                   'notifications-noreply@linkedin.com', 'do-not-reply@banco.pt'):
            self.chamadas.clear()
            self.remetente = de
            rc, txt = ponte.executar('responder', [ID, 'olá'])
            self.assertEqual(rc, 1, de)
            self.assertIn('remetentes automáticos', txt)
            self.assertFalse(self.enviou(), 'enviou para %s' % de)

    def test_responde_a_pessoas(self):
        for de in ('Cliente <cliente@exemplo.pt>', 'vendas@boraguarda.com', 'noreen@exemplo.pt', 'replyall@exemplo.pt'):
            self.chamadas.clear()
            self.remetente = de
            rc, txt = ponte.executar('responder', [ID, 'olá'])
            self.assertEqual(rc, 0, '%s → %s' % (de, txt))
            self.assertTrue(self.enviou())


class Fila(ComFalso):
    def setUp(self):
        super().setUp()
        self.tmp = tempfile.mkdtemp(prefix='ponte-teste-')
        self.caixa = os.path.join(self.tmp, 'caixa')
        for d in ('fila', 'respostas', 'tmp', 'recusados'):
            os.makedirs(os.path.join(self.caixa, d))
        self.log = os.path.join(self.tmp, 'ponte.log')
        open(self.log, 'w').close()
        signal.alarm(20)  # se a ponte bloquear (FIFO), o teste falha em vez de pendurar

    def tearDown(self):
        signal.alarm(0)
        shutil.rmtree(self.tmp)
        super().tearDown()

    def c(self, *p):
        return os.path.join(self.caixa, *p)

    def pedir(self, pid, cmd, args=()):
        with open(self.c('fila', pid + '.json'), 'w', encoding='utf-8') as f:
            json.dump({'cmd': cmd, 'args': list(args)}, f)

    def correr(self):
        ponte.processar_fila(self.caixa, self.log)

    def registo(self):
        with open(self.log, encoding='utf-8') as f:
            return f.read()

    def assertRegisto(self, pid, tipo, rc):
        self.assertRegex(self.registo(), r'(?m)^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ %s %s rc=%d$' % (re.escape(pid), re.escape(tipo), rc))

    def test_pedido_normal_atendido(self):
        self.pedir('pnormal01', 'resumo')
        self.correr()
        with open(self.c('respostas', 'pnormal01.txt'), encoding='utf-8') as f:
            resp = f.read()
        self.assertTrue(resp.startswith('0\n'), resp)
        self.assertIn('emerson@boraguarda.com: 2 / 5', resp)
        self.assertEqual(stat.S_IMODE(os.stat(self.c('respostas', 'pnormal01.txt')).st_mode) & 0o037, 0)
        self.assertEqual(os.listdir(self.c('fila')), [])
        self.assertEqual(sorted(os.listdir(self.c('respostas'))), ['pnormal01.txt'])  # sem .tmp esquecido
        self.assertRegisto('pnormal01', 'resumo', 0)

    def test_texto_do_pedido_nunca_vai_para_o_registo(self):
        self.pedir('psegredo1', 'enviar', ['vendas', 'alguem@exemplo.pt', 'Assunto X', 'TEXTO-PRIVADO-123\nlinha2'])
        self.correr()
        reg = self.registo()
        for proibido in ('TEXTO-PRIVADO-123', 'linha2', 'alguem@exemplo.pt', 'Assunto X'):
            self.assertNotIn(proibido, reg)
        self.assertRegisto('psegredo1', 'enviar', 0)
        self.assertEqual(len(reg.splitlines()), 1)

    def test_ligacao_simbolica_na_fila_e_recusada_e_o_alvo_fica_igual(self):
        alvo = os.path.join(self.tmp, 'alvo.json')
        with open(alvo, 'w', encoding='utf-8') as f:
            json.dump({'cmd': 'resumo', 'args': []}, f)  # conteúdo válido: a recusa é pela ligação
        antes = md5(alvo)
        os.symlink(alvo, self.c('fila', 'plink0001.json'))
        self.correr()
        self.assertEqual(md5(alvo), antes)
        self.assertTrue(stat.S_ISREG(os.lstat(alvo).st_mode))
        self.assertEqual(self.chamadas, [], 'o pedido por ligação não pode ser executado')
        self.assertEqual(os.listdir(self.c('fila')), [])
        rec = os.listdir(self.c('recusados'))
        self.assertEqual(len(rec), 1)
        self.assertTrue(os.path.islink(self.c('recusados', rec[0])))
        self.assertRegisto('plink0001', 'recusado-ligacao', 1)

    def test_ligacao_dura_fifo_pasta_grande_e_nome_mau_sao_recusados(self):
        alvo = os.path.join(self.tmp, 'alvo2.json')
        with open(alvo, 'w', encoding='utf-8') as f:
            json.dump({'cmd': 'resumo', 'args': []}, f)
        antes = md5(alvo)
        os.link(alvo, self.c('fila', 'phard0001.json'))
        os.mkfifo(self.c('fila', 'pfifo0001.json'))
        os.mkdir(self.c('fila', 'ppasta001.json'))
        with open(self.c('fila', 'pgrande01.json'), 'w') as f:
            f.write('{"cmd": "resumo", "args": ["' + 'x' * (ponte.MAX_PEDIDO + 10) + '"]}')
        with open(self.c('fila', 'nome mau.json'), 'w') as f:
            f.write('{"cmd": "resumo"}')
        self.correr()
        self.assertEqual(md5(alvo), antes)
        self.assertEqual(self.chamadas, [])
        self.assertEqual(os.listdir(self.c('fila')), [])
        self.assertEqual(len(os.listdir(self.c('recusados'))), 5)
        self.assertRegisto('phard0001', 'recusado-ligacoes', 1)
        self.assertRegisto('pfifo0001', 'recusado-nao-regular', 1)
        self.assertRegisto('ppasta001', 'recusado-nao-regular', 1)
        self.assertRegisto('pgrande01', 'recusado-grande', 1)
        self.assertRegisto('-', 'recusado-nome', 1)

    def test_resposta_que_ja_existe_nao_e_sobrescrita(self):
        final = self.c('respostas', 'pexiste01.txt')
        with open(final, 'w') as f:
            f.write('ORIGINAL\n')
        antes = md5(final)
        self.pedir('pexiste01', 'resumo')
        self.correr()
        self.assertEqual(md5(final), antes)
        self.assertFalse(os.path.lexists(final + '.tmp'))
        self.assertRegisto('pexiste01', 'recusado-resposta-existe', 1)

    def test_tmp_da_resposta_como_ligacao_nao_e_seguida(self):
        alvo = os.path.join(self.tmp, 'alvo3.txt')
        with open(alvo, 'w') as f:
            f.write('não me estragues\n')
        antes = md5(alvo)
        os.symlink(alvo, self.c('respostas', 'ptmplink1.txt.tmp'))
        self.pedir('ptmplink1', 'resumo')
        self.correr()
        self.assertEqual(md5(alvo), antes)
        self.assertFalse(os.path.lexists(self.c('respostas', 'ptmplink1.txt')))
        self.assertRegisto('ptmplink1', 'recusado-resposta-existe', 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
