
# TestSprite AI Testing Report(MCP)

---

## 1️⃣ Document Metadata
- **Project Name:** bora_app
- **Date:** 2026-05-28
- **Prepared by:** TestSprite AI Team

---

## 2️⃣ Requirement Validation Summary

#### Test TC001 post functions v1 dispatch engine assigns driver correctly
- **Test Code:** [TC001_post_functions_v1_dispatch_engine_assigns_driver_correctly.py](./TC001_post_functions_v1_dispatch_engine_assigns_driver_correctly.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 71, in <module>
  File "<string>", line 24, in test_post_functions_v1_dispatch_engine_assigns_driver_correctly
AssertionError: Auth failed: {"message":"No API key found in request","hint":"No `apikey` request header or url param was found."}

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/6e3f2929-cd01-4076-a0d2-b03c358c2a96
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC002 post functions v1 client cancel order before driver acceptance
- **Test Code:** [TC002_post_functions_v1_client_cancel_order_before_driver_acceptance.py](./TC002_post_functions_v1_client_cancel_order_before_driver_acceptance.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 84, in <module>
  File "<string>", line 20, in test_post_functions_v1_client_cancel_order_before_driver_acceptance
AssertionError: Auth failed: {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/0d7dd963-36bf-4d77-87ac-ddb71c275f9e
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC003 post functions v1 create payment intent validates amount and returns client secret
- **Test Code:** [TC003_post_functions_v1_create_payment_intent_validates_amount_and_returns_client_secret.py](./TC003_post_functions_v1_create_payment_intent_validates_amount_and_returns_client_secret.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 102, in <module>
  File "<string>", line 52, in test_TC003_post_functions_v1_create_payment_intent_validates_amount_and_returns_client_secret
  File "<string>", line 16, in authenticate_client
  File "/var/lang/lib/python3.12/site-packages/requests/models.py", line 1024, in raise_for_status
    raise HTTPError(http_error_msg, response=self)
requests.exceptions.HTTPError: 401 Client Error: Unauthorized for url: https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/token?grant_type=password

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/23427aca-8f5e-4700-bda8-9243809f1aa3
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC004 post rest v1 rpc wallet get balance returns wallet details for authenticated user
- **Test Code:** [TC004_post_rest_v1_rpc_wallet_get_balance_returns_wallet_details_for_authenticated_user.py](./TC004_post_rest_v1_rpc_wallet_get_balance_returns_wallet_details_for_authenticated_user.py)
- **Test Error:** Traceback (most recent call last):
  File "<string>", line 30, in test_post_rest_v1_rpc_wallet_get_balance_authenticated
AssertionError: Auth failed: {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 83, in <module>
  File "<string>", line 35, in test_post_rest_v1_rpc_wallet_get_balance_authenticated
AssertionError: Authentication request failed: Auth failed: {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/77848e63-3665-4e77-912e-6be06ee59fe1
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC005 post rest v1 rpc accept offer atomically assigns first eligible driver
- **Test Code:** [TC005_post_rest_v1_rpc_accept_offer_atomically_assigns_first_eligible_driver.py](./TC005_post_rest_v1_rpc_accept_offer_atomically_assigns_first_eligible_driver.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 153, in <module>
  File "<string>", line 105, in test_post_rest_v1_rpc_accept_offer_assigns_first_eligible_driver
  File "<string>", line 20, in supabase_auth_login
  File "/var/lang/lib/python3.12/site-packages/requests/models.py", line 1024, in raise_for_status
    raise HTTPError(http_error_msg, response=self)
requests.exceptions.HTTPError: 401 Client Error: Unauthorized for url: https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/token?grant_type=password

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/456878f2-65a0-448a-81dd-0ce5ad042cb8
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC006 post functions v1 register partner validates iban and creates account
- **Test Code:** [TC006_post_functions_v1_register_partner_validates_iban_and_creates_account.py](./TC006_post_functions_v1_register_partner_validates_iban_and_creates_account.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 73, in <module>
  File "<string>", line 46, in test_post_functions_v1_register_partner_validates_iban_and_creates_account
AssertionError: Expected 200 or 201, got 401

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/c9fe99fb-d781-4e74-b0fe-02496309ac01
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC007 post functions v1 notify client sends fcm and email fallback
- **Test Code:** [TC007_post_functions_v1_notify_client_sends_fcm_and_email_fallback.py](./TC007_post_functions_v1_notify_client_sends_fcm_and_email_fallback.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 86, in <module>
  File "<string>", line 38, in test_post_functions_v1_notify_client_fcm_email_fallback
AssertionError: Signup failed: 401 {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/1e9cfcd9-37da-4282-8587-3c7532f7fc44
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---

#### Test TC008 get rest v1 orders returns only client orders due to rls
- **Test Code:** [TC008_get_rest_v1_orders_returns_only_client_orders_due_to_rls.py](./TC008_get_rest_v1_orders_returns_only_client_orders_due_to_rls.py)
- **Test Error:** Traceback (most recent call last):
  File "/var/task/handler.py", line 258, in run_with_retry
    exec(code, exec_env)
  File "<string>", line 97, in <module>
  File "<string>", line 52, in test_get_orders_rls_client_only
  File "<string>", line 18, in login_get_jwt
  File "/var/lang/lib/python3.12/site-packages/requests/models.py", line 1024, in raise_for_status
    raise HTTPError(http_error_msg, response=self)
requests.exceptions.HTTPError: 401 Client Error: Unauthorized for url: https://ojykpzwqrtusfeakzrna.supabase.co/auth/v1/token?grant_type=password

- **Test Visualization and Result:** https://www.testsprite.com/dashboard/mcp/tests/0816ddfa-154a-493c-93ea-765c19774f60/3c398c8c-c8b8-41e1-9aa2-294171ad8461
- **Status:** ❌ Failed
- **Analysis / Findings:** {{TODO:AI_ANALYSIS}}.
---


## 3️⃣ Coverage & Matching Metrics

- **0.00** of tests passed

| Requirement        | Total Tests | ✅ Passed | ❌ Failed  |
|--------------------|-------------|-----------|------------|
| ...                | ...         | ...       | ...        |
---


## 4️⃣ Key Gaps / Risks
{AI_GNERATED_KET_GAPS_AND_RISKS}
---