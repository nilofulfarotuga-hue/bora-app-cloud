import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"

def test_post_rest_v1_rpc_wallet_get_balance_own_user():
    headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json"
    }
    # Step 1: Login to get access_token and uid
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_payload = {
        "email": LOGIN_EMAIL,
        "password": LOGIN_PASSWORD
    }
    try:
        login_resp = requests.post(login_url, json=login_payload, headers=headers, timeout=30)
        assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code}: {login_resp.text}"
        login_data = login_resp.json()
        access_token = login_data.get("access_token")
        assert access_token, "No access_token in login response"
        user = login_data.get("user")
        assert user, "No user data in login response"
        user_id = user.get("id")
        assert user_id, "No user id found in login response"

        # Step 2: Call wallet_get_balance RPC with authenticated user id
        rpc_url = f"{BASE_URL}/rest/v1/rpc/wallet_get_balance"
        rpc_headers = {
            "apikey": API_KEY,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }
        rpc_payload = {"p_user_id": user_id}

        rpc_resp = requests.post(rpc_url, json=rpc_payload, headers=rpc_headers, timeout=30)
        assert rpc_resp.status_code == 200, f"RPC call failed with status {rpc_resp.status_code}: {rpc_resp.text}"

        rpc_data = rpc_resp.json()
        # Adjusted for actual response structure (dict, not list)
        assert isinstance(rpc_data, dict), f"Unexpected RPC response format: {rpc_data}"
        assert "free_cents" in rpc_data and "tokens_balance" in rpc_data and "last_transactions" in rpc_data, \
            f"Missing expected wallet balance info in response: {rpc_data}"

    except requests.RequestException as e:
        assert False, f"Request exception occurred: {e}"


test_post_rest_v1_rpc_wallet_get_balance_own_user()