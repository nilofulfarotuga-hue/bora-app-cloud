import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"

def test_post_rest_v1_orders_insert_order_with_mismatched_user_id():
    session = requests.Session()
    session.headers.update({
        "apikey": APIKEY,
        "Content-Type": "application/json"
    })

    # Step 1: Authenticate to get JWT and auth.uid()
    login_payload = {
        "email": LOGIN_EMAIL,
        "password": LOGIN_PASSWORD
    }
    try:
        login_resp = session.post(f"{BASE_URL}/auth/v1/token?grant_type=password", json=login_payload, timeout=30)
        assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code}: {login_resp.text}"
        login_data = login_resp.json()
        access_token = login_data.get("access_token")
        assert access_token, "Access token not found in login response"
        user_object = login_data.get("user")
        assert user_object and "id" in user_object, "User info or user id missing in login response"
        auth_uid = user_object["id"]

        # Prepare headers for authenticated requests
        auth_headers = {
            "apikey": APIKEY,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }

        # Step 2: Attempt to insert an order with mismatched user_id
        mismatched_user_id = "00000000-0000-0000-0000-000000000000"
        assert mismatched_user_id != auth_uid, "Mismatched user_id must be different from authenticated user id"

        order_payload = {
            "user_id": mismatched_user_id,
            "status": "created",
            "items": [],
            "is_test_order": True
        }

        post_resp = session.post(f"{BASE_URL}/rest/v1/orders", headers=auth_headers, json=order_payload, timeout=30)
        # Expecting 403 Forbidden due to RLS violation
        assert post_resp.status_code == 403, f"Expected 403 RLS violation, got {post_resp.status_code}: {post_resp.text}"

    finally:
        session.close()

test_post_rest_v1_orders_insert_order_with_mismatched_user_id()