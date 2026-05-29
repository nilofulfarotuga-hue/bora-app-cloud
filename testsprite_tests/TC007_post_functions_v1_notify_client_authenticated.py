import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def test_post_functions_v1_notify_client_authenticated():
    # Step 1: Login valid test client to get access_token
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_headers = {
        "apikey": APIKEY,
        "Content-Type": "application/json"
    }
    login_body = {
        "email": "test-client@bora.app",
        "password": "TestBora2026!"
    }
    try:
        login_resp = requests.post(login_url, headers=login_headers, json=login_body, timeout=30)
        login_resp.raise_for_status()
    except requests.RequestException as e:
        assert False, f"Login request failed: {e}"

    token_data = login_resp.json()
    assert "access_token" in token_data, "No access_token in login response"
    access_token = token_data["access_token"]

    # Step 2: POST /functions/v1/notify-client with valid JWT and JSON body
    notify_url = f"{BASE_URL}/functions/v1/notify-client"
    notify_headers = {
        "apikey": APIKEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    notify_body = {
        # notify-client Edge Function expects "clientId" (not "user_id")
        "clientId": "95dcdebb-6fff-4abb-8f82-f9b7cef36c2a",  # cliente1 uid
        "title": "Test Notification",
        "body": "Hello from test_post_functions_v1_notify_client_authenticated"
    }

    try:
        notify_resp = requests.post(notify_url, headers=notify_headers, json=notify_body, timeout=30)
    except requests.RequestException as e:
        assert False, f"Notify client request failed: {e}"

    # Validate response is not 401 Unauthorized
    assert notify_resp.status_code != 401, f"Received 401 Unauthorized when it should not: {notify_resp.text}"
    # Also confirm success-oriented status codes (200-299)
    assert 200 <= notify_resp.status_code < 300, f"Unexpected status code: {notify_resp.status_code} Response: {notify_resp.text}"

test_post_functions_v1_notify_client_authenticated()
