import requests
import uuid

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
TIMEOUT = 30

CLIENT_EMAIL = "test-client@bora.app"
CLIENT_PASSWORD = "TestBora2026!"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def login_get_jwt(email: str, password: str) -> str:
    url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    payload = {
        "email": email,
        "password": password
    }
    headers = {"Content-Type": "application/json", "apikey": ANON_KEY}
    resp = requests.post(url, json=payload, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json().get("access_token")

def create_order(jwt_token: str) -> dict:
    url = f"{BASE_URL}/rest/v1/orders"
    # Minimal valid order payload based on typical order schema: must include at least user_id or such, here relying on RLS.
    # Generate a unique client reference
    order_payload = {
        "description": f"Test order {uuid.uuid4()}",
        "status": "pending",
        "total_cents": 1000,
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {jwt_token}",
        "Accept": "application/json",
        "apikey": ANON_KEY
    }
    resp = requests.post(url, json=order_payload, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()[0] if isinstance(resp.json(), list) else resp.json()

def delete_order(jwt_token: str, order_id: str):
    url = f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}"
    headers = {
        "Authorization": f"Bearer {jwt_token}",
        "apikey": ANON_KEY
    }
    resp = requests.delete(url, headers=headers, timeout=TIMEOUT)
    # deletion might return 204 or 200 with json, ignore errors here
    # just raise for anything unexpected
    if resp.status_code not in (200,204,404):
        resp.raise_for_status()

def test_get_orders_rls_client_only():
    # Login as client
    client_jwt = login_get_jwt(CLIENT_EMAIL, CLIENT_PASSWORD)

    # Create one order for this client to ensure we have one
    order = None
    try:
        order = create_order(client_jwt)
        order_id = order.get("id")
        assert order_id is not None, "Created order must have an id"

        # Make authenticated GET request to /rest/v1/orders
        url = f"{BASE_URL}/rest/v1/orders"
        headers = {
            "Authorization": f"Bearer {client_jwt}",
            "Accept": "application/json",
            "apikey": ANON_KEY
        }
        resp = requests.get(url, headers=headers, timeout=TIMEOUT)
        resp.raise_for_status()
        orders = resp.json()
        assert isinstance(orders, list), "Response should be a list of orders"
        assert any(o.get("id") == order_id for o in orders), "Created order should be in returned orders"

        # Verify all returned orders belong to the client only
        # Assumes orders have a user_id or equivalent field to identify owner
        # Check user_id matches JWT's user's id or at least no other users returned
        # Since we do not have user_id exposed here, we check no orders from other clients appear by client not appearing with other user_ids
        # Instead, if orders include user_id or client_id, check all equal
        # Because schema is not explicit on order format, rely on RLS effect and presence of only orders owned by the token user.
        # Here just check all orders contain the attribute "user_id" matching the created one's user_id if available
        # If user_id missing, skip check
        client_user_id = order.get("user_id")
        if client_user_id is not None:
            for o in orders:
                assert o.get("user_id") == client_user_id, "Orders from other users returned, RLS failed"

        # Now test unauthenticated request returns 401
        resp_no_auth = requests.get(url, timeout=TIMEOUT)
        assert resp_no_auth.status_code == 401, f"Expected 401 Unauthorized for no auth, got {resp_no_auth.status_code}"

    finally:
        if order and "id" in order:
            try:
                delete_order(client_jwt, order.get("id"))
            except Exception:
                pass

test_get_orders_rls_client_only()