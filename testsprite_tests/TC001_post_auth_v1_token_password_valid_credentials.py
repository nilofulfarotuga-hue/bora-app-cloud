import requests

def test_post_auth_v1_token_password_valid_credentials():
    BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
    endpoint = "/auth/v1/token?grant_type=password"
    url = BASE_URL + endpoint
    headers = {
        "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4",
        "Content-Type": "application/json"
    }
    payload = {
        "email": "test-client@bora.app",
        "password": "TestBora2026!"
    }
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
    except requests.RequestException as e:
        assert False, f"Request failed: {e}"

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    json_resp = response.json()
    assert "access_token" in json_resp, "Response JSON does not contain access_token"
    assert isinstance(json_resp["access_token"], str) and len(json_resp["access_token"]) > 0, "access_token is empty or not a string"

test_post_auth_v1_token_password_valid_credentials()