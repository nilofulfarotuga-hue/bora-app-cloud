import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
EMAIL = "test-client@bora.app"
PASSWORD = "TestBora2026!"
TIMEOUT = 30

def test_post_rest_v1_orders_insert_valid_order_with_correct_user_id():
    session = requests.Session()
    # Login to get JWT
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json",
    }
    login_payload = {
        "email": EMAIL,
        "password": PASSWORD
    }
    try:
        login_resp = session.post(login_url, headers=login_headers, json=login_payload, timeout=TIMEOUT)
        assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code} and body {login_resp.text}"
        login_data = login_resp.json()
        access_token = login_data.get("access_token")
        user = login_data.get("user")
        assert access_token, "No access_token in login response"
        assert user and "id" in user, "No user id in login response"
        user_id = user["id"]

        # Insert order with proper headers and body
        orders_url = f"{BASE_URL}/rest/v1/orders"
        order_headers = {
            "apikey": API_KEY,
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Prefer": "return=representation"
        }
        order_body = {
            "user_id": user_id,
            "status": "created",
            "items": [],
            "is_test_order": True
        }

        insert_resp = session.post(orders_url, headers=order_headers, json=order_body, timeout=TIMEOUT)
        assert insert_resp.status_code == 201, f"Order insert failed with status {insert_resp.status_code} and body {insert_resp.text}"
        inserted_orders = insert_resp.json()
        assert isinstance(inserted_orders, list) and len(inserted_orders) == 1, "Inserted order representation missing or incorrect"
        inserted_order = inserted_orders[0]
        assert inserted_order["user_id"] == user_id, "Inserted order user_id does not match auth.uid()"
        assert inserted_order["status"] == "created", "Inserted order status is not 'created'"
        assert inserted_order["is_test_order"] is True, "Inserted order is_test_order is not True"
        assert "items" in inserted_order and isinstance(inserted_order["items"], list), "Inserted order items missing or not list"

    finally:
        # Cleanup: delete inserted test orders with is_test_order=true for this user
        if 'access_token' in locals() and 'user_id' in locals():
            delete_url = f"{BASE_URL}/rest/v1/orders"
            delete_headers = {
                "apikey": API_KEY,
                "Authorization": f"Bearer {access_token}",
            }
            # Use filter to delete only orders with is_test_order=true and user_id = current user_id
            delete_params = {
                "user_id": f"eq.{user_id}",
                "is_test_order": "eq.true"
            }
            # Supabase PostgREST expects filters in query string with format ?user_id=eq.<user_id>&is_test_order=eq.true
            # We build query string accordingly
            from urllib.parse import urlencode
            query_string = urlencode(delete_params)
            try:
                del_resp = session.delete(f"{delete_url}?{query_string}", headers=delete_headers, timeout=TIMEOUT)
                # Accept 204 No Content or 200 OK with number of deleted records
                assert del_resp.status_code in (200, 204), f"Cleanup failed with status {del_resp.status_code} and body {del_resp.text}"
            except Exception:
                # Silently ignore cleanup errors
                pass

test_post_rest_v1_orders_insert_valid_order_with_correct_user_id()