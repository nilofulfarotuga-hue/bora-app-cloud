import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"

# Client test credentials (provisioned in auth.users 2026-05-28)
CLIENT_EMAIL = "test-client@bora.app"
CLIENT_PASSWORD = "TestBora2026!"

# Supabase anon public key (real, for ojykpzwqrtusfeakzrna)
SUPABASE_API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def test_post_functions_v1_dispatch_engine_assigns_driver_correctly():
    session = requests.Session()
    timeout = 30

    try:
        # 1. Authenticate client to get JWT (apikey required on Supabase Auth)
        auth_resp = session.post(
            f"{BASE_URL}/auth/v1/token?grant_type=password",
            json={"email": CLIENT_EMAIL, "password": CLIENT_PASSWORD},
            headers={"apikey": SUPABASE_API_KEY, "Content-Type": "application/json"},
            timeout=timeout
        )
        assert auth_resp.status_code == 200, f"Auth failed: {auth_resp.text}"
        access_token = auth_resp.json().get("access_token")
        assert access_token, "No access_token in auth response"

        # Update headers with Authorization and apikey for subsequent requests
        session.headers.update({"Authorization": f"Bearer {access_token}", "apikey": SUPABASE_API_KEY, "Content-Type": "application/json"})

        # 2. Create a new order for the authenticated client
        order_payload = {
            "status": "created",
            "total_cents": 1000,
            "currency": "EUR",
            "items": '[{"product_id":1,"quantity":1}]'  # minimal items json string
        }
        create_order_resp = session.post(
            f"{BASE_URL}/rest/v1/orders",
            json=order_payload,
            timeout=timeout
        )
        assert create_order_resp.status_code == 201, f"Order creation failed: {create_order_resp.text}"
        order = create_order_resp.json()
        order_id = order.get("id")
        assert order_id, "Order ID missing in creation response"

        # 3. Call dispatch-engine with created order_id
        dispatch_payload = {"order_id": order_id}
        dispatch_resp = session.post(
            f"{BASE_URL}/functions/v1/dispatch-engine",
            json=dispatch_payload,
            timeout=timeout
        )
        assert dispatch_resp.status_code == 200, f"Dispatch engine call failed: {dispatch_resp.text}"
        dispatch_data = dispatch_resp.json()
        assert "dispatched" in dispatch_data, "Response missing 'dispatched'"
        assert dispatch_data["dispatched"] is True, "Dispatched flag is not True"
        if "driver_offered_id" in dispatch_data:
            assert isinstance(dispatch_data["driver_offered_id"], str) and dispatch_data["driver_offered_id"], \
                "Invalid driver_offered_id in response"

    finally:
        if 'order_id' in locals():
            delete_resp = session.delete(
                f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}",
                timeout=timeout
            )
            assert delete_resp.status_code in (200, 204), f"Cleanup order delete failed: {delete_resp.text}"

test_post_functions_v1_dispatch_engine_assigns_driver_correctly()
