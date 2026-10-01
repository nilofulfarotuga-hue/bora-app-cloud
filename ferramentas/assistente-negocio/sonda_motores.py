"""Sonda: cada motor da cadeia responde com chamada de ferramenta? (status, latencia, erro literal)"""
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from servidor import carregar_env  # noqa: E402

carregar_env(os.environ.get("ASSISTENTE_ENV", os.path.join(AQUI, ".env")))
import motores  # noqa: E402

FER = [{"type": "function", "function": {"name": "ver_servicos", "description": "Lista serviços e preços",
                                         "parameters": {"type": "object", "properties": {}}}}]
MSG = [{"role": "system", "content": "És o atendimento de uma barbearia. Usa as ferramentas para preços."},
       {"role": "user", "content": "Quanto custa um corte?"}]
for m in sys.argv[1:] or ["gemini-pago:gemini-3-flash-preview", "go:glm-5.2", "go:qwen3.8-max", "go:minimax-m3",
                          "gemini:gemini-3-flash-preview", "gemini:gemini-3.1-flash-lite", "groq:openai/gpt-oss-120b"]:
    t = time.time()
    try:
        msg, meta = motores._chamar(m, MSG, FER)
        tc = [c["function"]["name"] for c in (msg.get("tool_calls") or [])]
        print(f"OK   {m:40s} {meta['ms']:6d} ms  ferramentas={tc} texto={str(msg.get('content'))[:60]!r}")
    except motores.MotorFalhou as e:
        print(f"FAIL {m:40s} {int((time.time() - t) * 1000):6d} ms  {str(e)[:170]}")
