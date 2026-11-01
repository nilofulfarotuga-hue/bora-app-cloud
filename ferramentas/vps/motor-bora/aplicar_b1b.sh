#!/bin/bash
# B1b: so o porteiro.py (sonda de 6 h + interruptor racao do painel). Prova falsa antes; repoe se o motor cair.
set -u
ST=/root/infra-2026-11-01
M=/opt/motor-bora
cd $ST || exit 1
sed -i 's/\r$//' porteiro.py prova_porteiro_sem_racao.py
python3 -m py_compile porteiro.py || { echo COMPILA_FALHOU; exit 2; }
rm -rf stage && mkdir -p stage && cp -r $M/motor_bora stage/ && rm -rf stage/motor_bora/__pycache__ && cp porteiro.py stage/motor_bora/
MOTOR_DIR=$ST/stage python3 prova_porteiro_sem_racao.py | tail -1 | tee /tmp/prova_b1b.txt
grep -q 'RESULTADO \([0-9]*\)/\1$' /tmp/prova_b1b.txt || { echo "PROVA_FALHOU: nao aplico"; MOTOR_DIR=$ST/stage python3 prova_porteiro_sem_racao.py | grep FALHOU; exit 4; }
cp -p $M/motor_bora/porteiro.py $M/motor_bora/porteiro.py.bak-b1b-20261101
cp porteiro.py $M/motor_bora/porteiro.py
systemctl restart motor-bora
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 2
  curl -s -m 3 http://127.0.0.1:8792/saude | grep -q '"ok": true' && { echo MOTOR_OK; exit 0; }
done
echo "MOTOR_NAO_RESPONDE: a repor"
cp -p $M/motor_bora/porteiro.py.bak-b1b-20261101 $M/motor_bora/porteiro.py
systemctl restart motor-bora
exit 3
