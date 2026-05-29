import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"
TIMEOUT = 30


def test_post_rest_v1_rpc_wallet_get_balance_with_valid_jwt_and_user_id():
    session = requests.Session()
    try:
        # Step 1: Login to get JWT
        login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
        login_headers = {
            "apikey": APIKEY,
            "Content-Type": "application/json"
        }
        login_payload = {
            "email": LOGIN_EMAIL,
            "password": LOGIN_PASSWORD
        }

        login_resp = session.post(login_url, headers=login_headers, json=login_payload, timeout=TIMEOUT)
        assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code} and body {login_resp.text}"
        login_data = login_resp.json()
        assert "access_token" in login_data, "No access_token in login response"
        assert "user" in login_data and "id" in login_data["user"], "No user.id in login response"
        access_token = login_data["access_token"]
        user_id = login_data["user"]["id"]

        # Step 2: Call wallet_get_balance RPC
        rpc_url = f"{BASE_URL}/rest/v1/rpc/wallet_get_balance"
        rpc_headers = {
            "apikey": APIKEY,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }
        rpc_payload = {
            "p_user_id": user_id
        }

        rpc_resp = session.post(rpc_url, headers=rpc_headers, json=rpc_payload, timeout=TIMEOUT)
        assert rpc_resp.status_code == 200, f"wallet_get_balance RPC failed with status {rpc_resp.status_code} and body {rpc_resp.text}"
        rpc_data = rpc_resp.json()

        # Validate response content
        assert isinstance(rpc_data, dict), "RPC response is not a JSON object"
        # The response must include free_cents (number), tokens_balance (number), last_transactions (array)
        assert "free_cents" in rpc_data, "free_cents missing in RPC response"
        assert isinstance(rpc_data["free_cents"], (int, float)), "free_cents is not a number"
        assert "tokens_balance" in rpc_data, "tokens_balance missing in RPC response"
        assert isinstance(rpc_data["tokens_balance"], (int, float)), "tokens_balance is not a number"
        assert "last_transactions" in rpc_data, "last_transactions missing in RPC response"
        assert isinstance(rpc_data["last_transactions"], list), "last_transactions is not a list"
    finally:
        session.close()

test_post_rest_v1_rpc_wallet_get_balance_with_valid_jwt_and_user_id()