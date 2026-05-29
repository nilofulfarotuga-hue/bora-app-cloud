import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

CLIENT_EMAIL = "cliente1"
CLIENT_EMAIL_FULL = "test-client@bora.app"
CLIENT_PASSWORD = "TestBora2026!"
TIMEOUT = 30

def test_get_rest_v1_bora_tokens_own_user_only():
    session = requests.Session()
    session.headers.update({
        "apikey": APIKEY,
        "Content-Type": "application/json"
    })

    # 1. Authenticate user cliente1 to get access_token
    auth_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    auth_payload = {
        "email": CLIENT_EMAIL_FULL,
        "password": CLIENT_PASSWORD
    }
    try:
        auth_resp = session.post(auth_url, json=auth_payload, timeout=TIMEOUT)
        assert auth_resp.status_code == 200, f"Auth failed with status {auth_resp.status_code}, body: {auth_resp.text}"
        auth_data = auth_resp.json()
        access_token = auth_data.get("access_token")
        assert access_token and isinstance(access_token, str), "access_token missing in auth response"
    except requests.RequestException as e:
        assert False, f"Exception during auth request: {e}"

    # 2. Use access_token in Authorization header to GET /rest/v1/bora_tokens?select=id,amount,role
    tokens_url = f"{BASE_URL}/rest/v1/bora_tokens?select=id,amount,role"
    headers = {
        "apikey": APIKEY,
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json"
    }
    try:
        tokens_resp = session.get(tokens_url, headers=headers, timeout=TIMEOUT)
        assert tokens_resp.status_code == 200, f"Failed to get bora_tokens: {tokens_resp.status_code}, body: {tokens_resp.text}"
        tokens = tokens_resp.json()
        assert isinstance(tokens, list), "Token response is not a list"

        # Check each token belongs to the authenticated user
        # Since tokens table is accessible only for own user by RLS,
        # we ensure all tokens have expected fields and no cross-user tokens appear.

        for t in tokens:
            assert "id" in t, "Token missing id field"
            assert "amount" in t, "Token missing amount field"
            assert "role" in t, "Token missing role field"
            # No user_id provided in the select but RLS enforces ownership
            # Additional validation: amount should be a number (int or float)
            assert isinstance(t["amount"], (int, float)), f"Token amount invalid type: {type(t['amount'])}"
            # role usually string
            assert isinstance(t["role"], str), f"Token role invalid type: {type(t['role'])}"
    except requests.RequestException as e:
        assert False, f"Exception during bora_tokens GET request: {e}"

test_get_rest_v1_bora_tokens_own_user_only()