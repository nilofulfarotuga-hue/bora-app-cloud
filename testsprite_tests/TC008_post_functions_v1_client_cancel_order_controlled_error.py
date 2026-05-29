import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"
TIMEOUT = 30


def test_post_functions_v1_client_cancel_order_controlled_error():
    # Step 1: Authenticate and get access_token
    auth_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    auth_headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    auth_payload = {
        "email": LOGIN_EMAIL,
        "password": LOGIN_PASSWORD
    }
    try:
        auth_resp = requests.post(auth_url, json=auth_payload, headers=auth_headers, timeout=TIMEOUT)
        assert auth_resp.status_code == 200, f"Auth failed with status {auth_resp.status_code}: {auth_resp.text}"
        access_token = auth_resp.json().get("access_token")
        assert access_token, "No access_token in auth response"
    except Exception as e:
        raise AssertionError(f"Authentication request failed: {e}")

    # Step 2: Call client-cancel-order function with non-existent order_id
    func_url = f"{BASE_URL}/functions/v1/client-cancel-order"
    func_headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json"
    }
    func_payload = {
        "order_id": "nonexistent-order-id-xyz-123"
    }
    try:
        func_resp = requests.post(func_url, json=func_payload, headers=func_headers, timeout=TIMEOUT)
    except Exception as e:
        raise AssertionError(f"Function call failed: {e}")

    # Step 3: Validate response is controlled 4xx and not 500
    assert 400 <= func_resp.status_code < 500, (
        f"Expected controlled 4xx error but got {func_resp.status_code}. Response text: {func_resp.text}"
    )
    assert func_resp.status_code != 500, "Server error 500 returned, expected controlled 4xx error"

    # Optional: Validate response body for error structure if any
    # Just validate that response content-type is JSON and contains error keys if present
    content_type = func_resp.headers.get("Content-Type", "")
    if "application/json" in content_type:
        try:
            json_body = func_resp.json()
            # There might be an 'error' or 'message' key for controlled errors, validate presence
            # This is optional, depends on API error schema - won't fail test if not present
            assert isinstance(json_body, dict)
        except Exception:
            # JSON parse fail - acceptable, but note it
            pass


test_post_functions_v1_client_cancel_order_controlled_error()