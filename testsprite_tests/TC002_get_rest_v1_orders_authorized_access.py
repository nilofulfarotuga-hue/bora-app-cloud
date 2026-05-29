import requests
import base64
import json

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"
LOGIN_EMAIL = "test-client@bora.app"
LOGIN_PASSWORD = "TestBora2026!"
TIMEOUT = 30

def decode_jwt_get_user_id(token: str) -> str:
    # JWT format: header.payload.signature
    # We want the payload
    parts = token.split('.')
    if len(parts) != 3:
        raise ValueError("Invalid JWT token format")
    payload_b64 = parts[1]
    # Fix base64 padding
    padding = '=' * (-len(payload_b64) % 4)
    payload_b64 += padding
    payload_bytes = base64.urlsafe_b64decode(payload_b64.encode('utf-8'))
    payload_json = json.loads(payload_bytes)
    # user_id usually in 'sub'
    user_id = payload_json.get('sub')
    if not user_id:
        raise ValueError("user_id not found in JWT payload")
    return user_id

def test_get_rest_v1_orders_authorized_access():
    session = requests.Session()
    headers = {
        "apikey": API_KEY,
        "Content-Type": "application/json"
    }
    # Step 1: Login and get access_token
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    login_payload = {"email": LOGIN_EMAIL, "password": LOGIN_PASSWORD}
    login_resp = session.post(login_url, json=login_payload, headers=headers, timeout=TIMEOUT)
    assert login_resp.status_code == 200, f"Login failed with status {login_resp.status_code}"
    login_data = login_resp.json()
    assert "access_token" in login_data and login_data["access_token"], "No access_token in login response"
    access_token = login_data["access_token"]

    # Decode user_id from token
    user_id = decode_jwt_get_user_id(access_token)

    auth_headers = {
        "apikey": API_KEY,
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }

    # Step 2: Create a test order for this authenticated user to ensure at least one order exists
    create_order_url = f"{BASE_URL}/rest/v1/orders"
    order_payload = {
        "user_id": user_id,
        "status": "created",
        "items": [],
        "vendor_name": "Pizzaria Teste 27",
        "is_test_order": True
    }
    create_resp = session.post(create_order_url, json=order_payload, headers=auth_headers, timeout=TIMEOUT)
    assert create_resp.status_code == 201, f"Order creation failed with status {create_resp.status_code}"
    created_orders = create_resp.json()
    assert isinstance(created_orders, list) and len(created_orders) > 0, "No order representation received"
    created_order = created_orders[0]
    created_order_id = created_order.get("id")
    created_user_id = created_order.get("user_id")
    assert created_order_id, "Created order has no id"
    assert created_user_id, "Created order has no user_id"

    try:
        # Step 3: Retrieve all orders for authenticated user
        get_orders_url = f"{BASE_URL}/rest/v1/orders?select=id,user_id,status,vendor_name"
        get_resp = session.get(get_orders_url, headers=auth_headers, timeout=TIMEOUT)
        assert get_resp.status_code == 200, f"Get orders failed with status {get_resp.status_code}"
        orders = get_resp.json()
        assert isinstance(orders, list), "Orders response is not a list"

        # Step 4: Verify all returned orders belong to the authenticated user only
        for order in orders:
            assert "user_id" in order, "Order missing user_id"
            assert order["user_id"] == created_user_id, "Order user_id does not match authenticated user_id"

        # Additionally verify the created order is in the list
        order_ids = [order.get("id") for order in orders]
        assert created_order_id in order_ids, "Created order not found in user's orders"

    finally:
        # Cleanup: delete the created test order
        if created_order_id:
            delete_order_url = f"{BASE_URL}/rest/v1/orders?id=eq.{created_order_id}"
            del_resp = session.delete(delete_order_url, headers=auth_headers, timeout=TIMEOUT)
            assert del_resp.status_code in (204, 200), f"Failed to delete test order, status {del_resp.status_code}"

test_get_rest_v1_orders_authorized_access()
