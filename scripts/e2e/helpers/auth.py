"""Sessão 7E-A — helpers de autenticação para o framework E2E.

Decisão arquitectural #1: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são lidos
de `scripts/rag/.env` (single source). Nunca duplicar para `.env.test`.
Se a chave RAG rodar, o E2E parte — mitigado pelo fail-fast abaixo.
"""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from supabase import Client, create_client

# Password constante para todas as contas E2E. Não é trivial (≥12 chars) e
# nunca é uma password produção (domínio @boraapp.test garante isolamento).
TEST_PASSWORD = "E2E_TestPassword_2026!"

# Markers obrigatórios — não tocar.
TEST_EMAIL_DOMAIN = "@boraapp.test"
TEST_DRIVER_EMAIL_DOMAIN = "@driver.bora.app"  # synthetic, segue padrão prod
TEST_RESTAURANT_PREFIX = "E2E_TEST_"


def _resolve_rag_env_path() -> Path:
    """Localiza scripts/rag/.env relativo a este ficheiro, com override opt-in."""
    override = os.environ.get("E2E_RAG_ENV_PATH")
    if override:
        return Path(override).resolve()
    here = Path(__file__).resolve().parent  # scripts/e2e/helpers/
    return (here / ".." / ".." / "rag" / ".env").resolve()


def load_env() -> None:
    """Carrega scripts/rag/.env para os.environ (single source).

    Falha rápido se o ficheiro não existir ou faltarem chaves obrigatórias —
    melhor abortar imediatamente do que silenciosamente correr testes contra
    nada.
    """
    rag_env = _resolve_rag_env_path()
    if not rag_env.is_file():
        raise RuntimeError(
            f"E2E não consegue encontrar scripts/rag/.env em {rag_env}. "
            "Confirma que o ficheiro existe (single source — decisão #1)."
        )
    load_dotenv(rag_env, override=False)

    # Também carrega .env.test (opt-in flags) se existir, mas sem sobrescrever.
    here = Path(__file__).resolve().parent
    env_test = (here / ".." / ".env.test").resolve()
    if env_test.is_file():
        load_dotenv(env_test, override=False)

    missing = [k for k in ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY") if not os.environ.get(k)]
    if missing:
        raise RuntimeError(
            f"E2E credenciais ausentes em scripts/rag/.env: {missing}. "
            "Verifica o ficheiro."
        )


def admin_client() -> Client:
    """Cria um cliente Supabase com service_role (bypass RLS).

    Uso: seed/cleanup/setup. Nunca usar em testes que validam RLS — esses
    devem usar `user_client(jwt)`.
    """
    load_env()
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return create_client(url, key)


def user_client(access_token: str) -> Client:
    """Cria um cliente Supabase autenticado com JWT de utilizador (RLS aplicada).

    Uso: testes RLS / fluxos role-scoped. O `access_token` vem de
    `sign_in_email(...)`.
    """
    load_env()
    url = os.environ["SUPABASE_URL"]
    # Anon key não é necessária para client com session JWT, mas o supabase-py
    # exige uma chave no construtor. Usamos service_role por simplicidade —
    # o JWT na auth é o que importa para RLS.
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    client = create_client(url, key)
    client.postgrest.auth(access_token)
    return client


def is_stripe_live() -> bool:
    """Opt-in flag — activar Stripe real (nunca em CI)."""
    return os.environ.get("E2E_STRIPE_LIVE") == "1"


def is_gemini_live() -> bool:
    """Opt-in flag — activar Gemini real (raro)."""
    return os.environ.get("E2E_GEMINI_LIVE") == "1"
