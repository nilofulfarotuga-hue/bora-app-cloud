import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

# User info: cliente2 email and uid to use foreign user_id
CLIENTE2_EMAIL = "test-client2@bora.app"
CLIENTE2_UID = "57de96e7-29a4-4e80-b49a-2cbcbc3205cc"

CLIENTE1_EMAIL = "test-client@bora.app"
CLIENTE1_PASSWORD = "TestBora2026!"


def test_post_rest_v1_orders_insert_foreign_userid_forbidden():
    headers = {
        "apikey": APIKEY,
        "Content-Type": "application/json"
    }
    # Step 1: Login cliente1 to get access token
    login_payload = {
        "email": CLIENTE1_EMAIL,
        "password": CLIENTE1_PASSWORD
    }
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    try:
        login_resp = requests.post(login_url, headers=headers, json=login_payload, timeout=30)
        assert login_resp.status_code == 200, f"Expected 200 from login, got {login_resp.status_code}"
        access_token = login_resp.json().get("access_token")
        assert access_token, "No access_token in login response"
    except Exception as e:
        raise AssertionError(f"Login request failed: {e}")

    auth_headers = {
        "apikey": APIKEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    # Step 2: Attempt to create order with foreign user_id (cliente2 UID)
    order_url = f"{BASE_URL}/rest/v1/orders"
    order_payload = {
        "user_id": CLIENTE2_UID,
        "status": "created",
        "items": [],
        "vendor_name": "Pizzaria Teste 27",
        "is_test_order": True
    }
    try:
        resp = requests.post(order_url, headers=auth_headers, json=order_payload, timeout=30)
    except Exception as e:
        raise AssertionError(f"POST /rest/v1/orders request failed: {e}")

    # Validate response status 403 Forbidden due to RLS
    assert resp.status_code == 403, f"Expected 403 Forbidden, got {resp.status_code}. Response: {resp.text}"


test_post_rest_v1_orders_insert_foreign_userid_forbidden()