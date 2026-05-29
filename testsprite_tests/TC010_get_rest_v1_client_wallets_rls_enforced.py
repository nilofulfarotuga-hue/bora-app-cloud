import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def test_get_rest_v1_client_wallets_rls_enforced():
    # Login as estafeta (driver) user who should not have access to client wallets due to RLS
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json"
    }
    login_payload = {
        "email": "test-driver@bora.app",
        "password": "TestBora2026!"
    }
    try:
        login_resp = requests.post(login_url, json=login_payload, headers=login_headers, timeout=30)
        assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code}, response: {login_resp.text}"
        access_token = login_resp.json().get("access_token")
        assert access_token is not None, "access_token not found in login response"

        # Use estafeta token to GET /rest/v1/client_wallets
        wallets_url = f"{BASE_URL}/rest/v1/client_wallets"
        wallets_headers = {
            "apikey": API_KEY,
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json"
        }
        wallets_resp = requests.get(wallets_url, headers=wallets_headers, timeout=30)

        # The response should be either empty (200 with empty array) or forbidden (403)
        if wallets_resp.status_code == 200:
            data = wallets_resp.json()
            # Validate it is empty list or empty object or no wallet data
            assert (isinstance(data, list) and len(data) == 0) or data == {}, "Expected empty response for unauthorized wallet access"
        else:
            # Status should be 403 Forbidden if not empty
            assert wallets_resp.status_code == 403, f"Expected 200 with empty list or 403 forbidden, got {wallets_resp.status_code}"
    except requests.RequestException as e:
        assert False, f"Request error occurred: {str(e)}"

test_get_rest_v1_client_wallets_rls_enforced()