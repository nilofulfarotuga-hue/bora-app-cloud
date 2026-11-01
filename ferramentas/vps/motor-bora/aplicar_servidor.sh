#!/bin/bash
# so o servidor_motor.py (rotulo do OmniRoute no livro de gastos); repoe se o motor nao responder
set -u
ST=/root/infra-2026-11-01; M=/opt/motor-bora
sed -i 's/\r$//' $ST/servidor_motor.py
python3 -m py_compile $ST/servidor_motor.py || { echo COMPILA_FALHOU; exit 2; }
cp -p $M/servidor_motor.py $M/servidor_motor.py.bak-rotulo-20261101
cp $ST/servidor_motor.py $M/servidor_motor.py
systemctl restart motor-bora
for i in $(seq 1 10); do sleep 2; curl -s -m 3 http://127.0.0.1:8792/saude | grep -q '"ok": true' && { echo MOTOR_OK; ss -tln | grep -cE ':879[23] '; exit 0; }; done
cp -p $M/servidor_motor.py.bak-rotulo-20261101 $M/servidor_motor.py; systemctl restart motor-bora; echo REPOSTO; exit 3
