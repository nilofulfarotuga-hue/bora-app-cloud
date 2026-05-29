import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"

def test_get_orders_select_id_user_id_status_with_valid_jwt():
    # Step 1: Authenticate and get JWT
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_headers = {
        "apikey": APIKEY,
        "Content-Type": "application/json"
    }
    login_body = {
        "email": LOGIN_EMAIL,
        "password": LOGIN_PASSWORD
    }
    try:
        login_resp = requests.post(login_url, json=login_body, headers=login_headers, timeout=30)
        assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code}"
        login_json = login_resp.json()
        assert "access_token" in login_json, "access_token not in login response"
        access_token = login_json["access_token"]
        auth_user_id = login_json["user"]["id"] if "user" in login_json and "id" in login_json["user"] else None
        assert auth_user_id is not None, "Authenticated user id missing in login response"
    except Exception as e:
        raise AssertionError(f"Authentication failed: {e}")

    # Step 2: Create a test order with this user_id and is_test_order=true (so we have known owned order)
    orders_url = f"{BASE_URL}/rest/v1/orders"
    headers_order_post = {
        "apikey": APIKEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    order_payload = {
        "user_id": auth_user_id,
        "status": "created",
        "items": [],
        "is_test_order": True
    }

    created_order = None
    try:
        post_resp = requests.post(orders_url, json=order_payload, headers=headers_order_post, timeout=30)
        assert post_resp.status_code == 201, f"Order creation failed with status {post_resp.status_code}"
        json_post = post_resp.json()
        assert isinstance(json_post, list) and len(json_post) == 1, "Expected one order representation returned"
        created_order = json_post[0]
        assert created_order.get("user_id") == auth_user_id, "Created order user_id does not match auth user"
        # We can now test GET request for orders belonging to user
        orders_get_url = f"{orders_url}?select=id,user_id,status"
        headers_get = {
            "apikey": APIKEY,
            "Authorization": f"Bearer {access_token}"
        }
        get_resp = requests.get(orders_get_url, headers=headers_get, timeout=30)
        assert get_resp.status_code == 200, f"GET orders failed with status {get_resp.status_code}"
        orders = get_resp.json()
        assert isinstance(orders, list), "GET orders response is not a list"
        # Validate all orders have user_id equals to auth_user_id and only selected fields (id, user_id, status)
        for order in orders:
            assert "id" in order and "user_id" in order and "status" in order, f"Order missing required fields: {order}"
            assert order["user_id"] == auth_user_id, f"Order user_id {order['user_id']} does not match authenticated user {auth_user_id}"
            # No extra fields allowed
            allowed_keys = {"id", "user_id", "status"}
            assert set(order.keys()) <= allowed_keys, f"Order has unexpected fields: {set(order.keys()) - allowed_keys}"

    finally:
        # Cleanup: Delete the created test order to keep DB clean
        if created_order and "id" in created_order:
            delete_url = f"{orders_url}?id=eq.{created_order['id']}&is_test_order=eq.true"
            try:
                del_resp = requests.delete(delete_url, headers=headers_get, timeout=30)
                assert del_resp.status_code in [200, 204], f"Failed to delete test order with status {del_resp.status_code}"
            except Exception as e:
                # Log but don't fail test on cleanup
                print(f"Warning: cleanup failed to delete order {created_order['id']}: {e}")

test_get_orders_select_id_user_id_status_with_valid_jwt()