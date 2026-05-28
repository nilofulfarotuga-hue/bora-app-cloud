import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
AUTH_URL = f"{BASE_URL}/auth/v1/token?grant_type=password"
WALLET_BALANCE_RPC = f"{BASE_URL}/rest/v1/rpc/wallet_get_balance"

CLIENT_EMAIL = "cliente@bora.app"
CLIENT_PASSWORD = "123456"
TIMEOUT = 30

# Replace with your Supabase anon/public API key
API_KEY = "your-anon-key"

def test_post_rest_v1_rpc_wallet_get_balance_authenticated():
    # Authenticate to get JWT token
    auth_payload = {
        "email": CLIENT_EMAIL,
        "password": CLIENT_PASSWORD
    }
    auth_headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    try:
        auth_response = requests.post(AUTH_URL, 
                                      json=auth_payload, 
                                      headers=auth_headers,
                                      timeout=TIMEOUT)
        assert auth_response.status_code == 200, f"Auth failed: {auth_response.text}"
        auth_data = auth_response.json()
        access_token = auth_data.get("access_token")
        assert access_token, "No access_token in auth response"
    except Exception as e:
        assert False, f"Authentication request failed: {e}"

    headers_auth = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    # Successful wallet_get_balance call with valid auth
    try:
        user = auth_data.get("user")
        assert user is not None, "No user info in auth response"
        p_user_id = user.get("id")
        assert p_user_id, "No user id in user info"

        payload = {
            "p_user_id": p_user_id
        }

        balance_response = requests.post(WALLET_BALANCE_RPC,
                                         headers=headers_auth,
                                         json=payload,
                                         timeout=TIMEOUT)
        assert balance_response.status_code == 200, f"Balance request failed: {balance_response.text}"

        balance_data = balance_response.json()
        assert "free_cents" in balance_data, "free_cents missing in response"
        assert "tokens_balance" in balance_data, "tokens_balance missing in response"
        assert "last_transactions" in balance_data, "last_transactions missing in response"
    except Exception as e:
        assert False, f"Authenticated wallet_get_balance request failed: {e}"

    # Unauthenticated request returns 401
    try:
        no_auth_headers = {
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
        unauth_response = requests.post(WALLET_BALANCE_RPC,
                                       headers=no_auth_headers,
                                       json={"p_user_id": p_user_id},
                                       timeout=TIMEOUT)
        assert unauth_response.status_code == 401, f"Expected 401 for unauthenticated request, got {unauth_response.status_code}"
    except Exception as e:
        assert False, f"Unauthenticated wallet_get_balance request failed: {e}"



test_post_rest_v1_rpc_wallet_get_balance_authenticated()