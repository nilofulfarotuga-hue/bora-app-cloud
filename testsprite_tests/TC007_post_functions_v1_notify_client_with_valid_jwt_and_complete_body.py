import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"
TIMEOUT = 30

def test_post_functions_v1_notify_client_with_valid_jwt_and_complete_body():
    # Step 1: Authenticate to obtain JWT
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_headers = {
        "apikey": APIKEY,
        "Content-Type": "application/json"
    }
    login_payload = {
        "email": LOGIN_EMAIL,
        "password": LOGIN_PASSWORD
    }
    try:
        login_resp = requests.post(login_url, headers=login_headers, json=login_payload, timeout=TIMEOUT)
        login_resp.raise_for_status()
    except Exception as e:
        assert False, f"Authentication request failed: {e}"
    login_data = login_resp.json()
    assert "access_token" in login_data and isinstance(login_data["access_token"], str) and login_data["access_token"], \
        "Authentication response missing access_token"
    jwt_token = login_data["access_token"]
    user_id = login_data.get("user", {}).get("id")
    assert user_id, "Authentication response missing user id"

    # Step 2: Send POST request to /functions/v1/notify-client with valid JWT and complete body
    notify_url = f"{BASE_URL}/functions/v1/notify-client"
    notify_headers = {
        "apikey": APIKEY,
        "Authorization": f"Bearer {jwt_token}",
        "Content-Type": "application/json"
    }
    notify_payload = {
        "user_id": user_id,
        "title": "Order Update",
        "body": "Your order is on the way"
    }

    try:
        notify_resp = requests.post(notify_url, headers=notify_headers, json=notify_payload, timeout=TIMEOUT)
    except Exception as e:
        assert False, f"Notify-client request failed: {e}"

    # Validate that the response is NOT 401 Unauthorized (authorization accepted)
    assert notify_resp.status_code != 401, f"Request was unauthorized, status code: {notify_resp.status_code}"

    # The request may return 200 or other domain-specific errors, so no other status code assertions
    # But response content should be JSON or text; attempting minimal validation
    try:
        notify_data = notify_resp.json()
    except ValueError:
        notify_data = notify_resp.text

    # We don't assert further on response content because domain error is acceptable as per instructions

test_post_functions_v1_notify_client_with_valid_jwt_and_complete_body()