
# TestSprite AI Testing Report(MCP)

---

## 1️⃣ Document Metadata
- **Project Name:** bora_app
- **Date:** 2026-05-29
- **Prepared by:** TestSprite AI Team

---

## 2️⃣ Requirement Validation Summary

#### Test TC001 post_auth_v1_token_password_valid_credentials
- **Test Code:** [TC001_post_auth_v1_token_password_valid_credentials.py](./TC001_post_auth_v1_token_password_valid_credentials.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/5b9564a1-4681-4522-a625-eb26968c26a6
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC002 get_rest_v1_orders_authorized_access
- **Test Code:** [TC002_get_rest_v1_orders_authorized_access.py](./TC002_get_rest_v1_orders_authorized_access.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 96, in <module>
  File "<string>", line 63, in test_get_rest_v1_orders_authorized_access
AssertionError: Order creation failed with status 400

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/fccc18a0-c607-4bd6-b1c6-65a12473e58c
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC003 post_rest_v1_orders_insert_own_order
- **Test Code:** [TC003_post_rest_v1_orders_insert_own_order.py](./TC003_post_rest_v1_orders_insert_own_order.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/2f78f36c-b9e4-499a-bd3e-b3d7d44296dd
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC004 post_rest_v1_orders_insert_foreign_userid_forbidden
- **Test Code:** [TC004_post_rest_v1_orders_insert_foreign_userid_forbidden.py](./TC004_post_rest_v1_orders_insert_foreign_userid_forbidden.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/24ac0ad4-23a0-4cca-bc4e-d4e78fc634a6
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC005 post_rest_v1_rpc_wallet_get_balance_own_user
- **Test Code:** [TC005_post_rest_v1_rpc_wallet_get_balance_own_user.py](./TC005_post_rest_v1_rpc_wallet_get_balance_own_user.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/81d1dea2-fe7b-4953-af9d-c817717829c4
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC006 get_rest_v1_bora_tokens_own_user_only
- **Test Code:** [TC006_get_rest_v1_bora_tokens_own_user_only.py](./TC006_get_rest_v1_bora_tokens_own_user_only.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/312ed4a3-aaa2-4a32-9970-6116c3bf4df4
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC007 post_functions_v1_notify_client_authenticated
- **Test Code:** [TC007_post_functions_v1_notify_client_authenticated.py](./TC007_post_functions_v1_notify_client_authenticated.py)
- **Test Error:** Traceback (most recent call last):
  File "<string>", line 19, in test_post_functions_v1_notify_client_authenticated
  File "/var/lang/lib/python3.12/site-packages/requests/models.py", line 1024, in raise_for_status
    raise HTTPError(http_error_msg, response=self)
requests.exceptions.HTTPError: 401 Client Error: Unauthorized for url: https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/token?grant_type=password

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 50, in <module>
  File "<string>", line 21, in test_post_functions_v1_notify_client_authenticated
AssertionError: Login request failed: 401 Client Error: Unauthorized for url: https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/token?grant_type=password

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/918e9251-d7e3-462f-a95e-df1ef5c38182
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC008 post_functions_v1_client_cancel_order_controlled_error
- **Test Code:** [TC008_post_functions_v1_client_cancel_order_controlled_error.py](./TC008_post_functions_v1_client_cancel_order_controlled_error.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/6ad2e2a0-a627-4050-a204-0bddf593d805
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC009 get_rest_v1_ledger_entries_unauthorized_rejected
- **Test Code:** [TC009_get_rest_v1_ledger_entries_unauthorized_rejected.py](./TC009_get_rest_v1_ledger_entries_unauthorized_rejected.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/914bcae1-3104-4f5a-8713-62e3dee7a177
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC010 get_rest_v1_client_wallets_rls_enforced
- **Test Code:** [TC010_get_rest_v1_client_wallets_rls_enforced.py](./TC010_get_rest_v1_client_wallets_rls_enforced.py)
- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0e3385f9-8bc0-4e99-b8d0-1ed506c0a58d/78b74336-1e81-4a28-a548-696565f24e24
- **Status:** ✅ Passed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---


## 3️⃣ Coverage & Matching Metrics

- **80.00** of tests passed

| Requirement        | Total Tests | ✅ Passed | ❌ Failed  |
|--------------------|-------------|-----------|------------|
| ...                | ...         | ...       | ...        |
---


## 4️⃣ Key Gaps / Risks
{AI_GNERATED_KET_GAPS_AND_RISKS}
---