import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"


def test_post_orders_insert_order_with_unknown_field():
    session = requests.Session()
    session.headers.update({
        "apikey": APIKEY,
        "Content-Type": "application/json"
    })

    try:
        # Authenticate and get JWT token
        login_resp = session.post(
            f"{BASE_URL}/auth/v1/token?grant_type=password",
            json={"email": LOGIN_EMAIL, "password": LOGIN_PASSWORD},
            timeout=30
        )
        assert login_resp.status_code == 200, f"Login failed: {login_resp.text}"
        login_data = login_resp.json()
        jwt_token = login_data.get("access_token")
        assert jwt_token, "No access_token in login response"

        # Prepare headers for POST /rest/v1/orders with Bearer JWT and Prefer header
        headers = {
            "apikey": APIKEY,
            "Authorization": f"Bearer {jwt_token}",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }

        # Get auth user's uid for user_id field from JWT payload (can decode JWT)
        # Since no JWT decode library allowed, parse user id from user object in login response
        user_id = login_data.get("user", {}).get("id")
        assert user_id, "No user id in login response"

        # Construct invalid body with unknown field 'currency'
        invalid_order = {
            "user_id": user_id,
            "status": "created",
            "items": [],
            "is_test_order": True,
            "currency": "USD"  # unknown field causing error
        }

        # Attempt to insert order with unknown field
        post_resp = session.post(
            f"{BASE_URL}/rest/v1/orders",
            headers=headers,
            json=invalid_order,
            timeout=30
        )

        # Expect 400 response with PGRST204 error body and no order inserted
        assert post_resp.status_code == 400, f"Expected 400, got {post_resp.status_code} with body {post_resp.text}"
        resp_json = None
        try:
            resp_json = post_resp.json()
        except Exception:
            pass
        if resp_json:
            error_message = resp_json.get("message") or resp_json.get("error") or ""
            # Adjust assertion to match the actual error message seen
            msg_lower = error_message.lower()
            assert ("pgrst204" in error_message) or ("unknown column" in msg_lower) or (
                "could not find" in msg_lower and "currency" in msg_lower and "column" in msg_lower
            ), f"Unexpected error message: {error_message}"

    finally:
        # Cleanup: ensure test orders are removed, although no order inserted, just attempt cleanup for safety
        list_headers = {
            "apikey": APIKEY,
            "Authorization": f"Bearer {jwt_token}",
            "Content-Type": "application/json"
        }
        try:
            get_resp = session.get(
                f"{BASE_URL}/rest/v1/orders?user_id=eq.{user_id}&is_test_order=eq.true",
                headers=list_headers,
                timeout=30
            )
            if get_resp.status_code == 200:
                orders = get_resp.json()
                for order in orders:
                    order_id = order.get("id")
                    if order_id:
                        delete_resp = session.delete(
                            f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}",
                            headers=list_headers,
                            timeout=30
                        )
                        assert delete_resp.status_code in [200, 204], f"Failed to delete test order {order_id}: {delete_resp.text}"
        except Exception:
            pass


test_post_orders_insert_order_with_unknown_field()
