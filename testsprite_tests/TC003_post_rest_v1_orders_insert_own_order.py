import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
APIKEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
EMAIL = "test-client@bora.app"
PASSWORD = "TestBora2026!"
USER_ID = "95dcdebb-6fff-4abb-8f82-f9b7cef36c2a"

def test_post_rest_v1_orders_insert_own_order():
    headers_auth = {
        "apikey": APIKEY,
        "Content-Type": "application/json"
    }
    # Step 1: Authenticate to get access_token and auth.uid()
    auth_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    auth_payload = {
        "email": EMAIL,
        "password": PASSWORD
    }
    auth_resp = requests.post(auth_url, json=auth_payload, headers=headers_auth, timeout=30)
    assert auth_resp.status_code == 200, f"Authentication failed with status {auth_resp.status_code}"
    auth_json = auth_resp.json()
    access_token = auth_json.get("access_token")
    assert access_token, "No access_token returned from auth"

    headers = {
        "apikey": APIKEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }

    created_order_id = None
    try:
        # Step 2: POST /rest/v1/orders with user_id==auth.uid()
        order_payload = {
            "user_id": USER_ID,
            "status": "created",
            "items": [],
            "vendor_name": "Pizzaria Teste 27",
            "is_test_order": True
        }
        post_url = f"{BASE_URL}/rest/v1/orders"
        resp = requests.post(post_url, json=order_payload, headers=headers, timeout=30)
        assert resp.status_code == 201, f"Order creation failed with status {resp.status_code}: {resp.text}"
        data = resp.json()
        assert isinstance(data, list), "Response should be a list containing the created order"
        assert len(data) == 1, "Response list should contain exactly one order"
        order = data[0]
        # Validate fields in response
        assert order.get("user_id") == USER_ID, "Returned order user_id differs from authenticated user"
        assert order.get("status") == "created"
        assert order.get("vendor_name") == "Pizzaria Teste 27"
        assert order.get("is_test_order") is True

        created_order_id = order.get("id")
        assert created_order_id, "Created order does not have an id"

    finally:
        # Cleanup: DELETE the created test order
        if created_order_id:
            delete_url = f"{BASE_URL}/rest/v1/orders?id=eq.{created_order_id}"
            del_resp = requests.delete(delete_url, headers=headers, timeout=30)
            # DELETE 204 No Content or 200 OK expected
            assert del_resp.status_code in (200, 204), f"Failed to delete test order {created_order_id}, status {del_resp.status_code}"

test_post_rest_v1_orders_insert_own_order()
