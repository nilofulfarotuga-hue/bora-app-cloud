import requests

def test_post_auth_v1_token_grant_type_password_with_valid_credentials():
    BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
    endpoint = f"{BASE_URL}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4",
        "Content-Type": "application/json"
    }
    payload = {
        "email": "test-client@bora.app",
        "password": "TestBora2026!"
    }

    try:
        response = requests.post(endpoint, json=payload, headers=headers, timeout=30)
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        data = response.json()
        assert "access_token" in data and isinstance(data["access_token"], str) and data["access_token"], "access_token missing or invalid"
        assert "user" in data and isinstance(data["user"], dict) and data["user"], "user object missing or invalid"
    except (requests.RequestException, AssertionError) as e:
        raise e

test_post_auth_v1_token_grant_type_password_with_valid_credentials()