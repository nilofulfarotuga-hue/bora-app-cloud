import requests
import json

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
CLIENT_EMAIL = "cliente@bora.app"
CLIENT_PASSWORD = "123456"
API_KEY = "YOUR_SUPABASE_ANON_OR_SERVICE_ROLE_KEY"
TIMEOUT = 30

def test_post_functions_v1_client_cancel_order_before_driver_acceptance():
    session = requests.Session()
    try:
        # 1. Authenticate client to get JWT
        token_resp = session.post(
            f"{BASE_URL}/auth/v1/token?grant_type=password",
            headers={"Content-Type": "application/json", "apikey": API_KEY},
            data=json.dumps({"email": CLIENT_EMAIL, "password": CLIENT_PASSWORD}),
            timeout=TIMEOUT
        )
        assert token_resp.status_code == 200, f"Auth failed: {token_resp.text}"
        access_token = token_resp.json().get("access_token")
        assert access_token, "No access_token returned"

        auth_headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "apikey": API_KEY
        }

        # 2. Create a new order via POST /rest/v1/orders
        order_payload = {
            "status": "pending",
            "items": [],  # empty items, as no schema detail given
            "total_cents": 1000,  # e.g. 10.00 EUR
            "currency": "EUR"
        }

        create_order_resp = session.post(
            f"{BASE_URL}/rest/v1/orders",
            headers=auth_headers,
            json=order_payload,
            timeout=TIMEOUT
        )
        assert create_order_resp.status_code in (201, 200), f"Order creation failed: {create_order_resp.text}"
        order_data = create_order_resp.json()
        order_id = None

        if isinstance(order_data, list):
            order_id = order_data[0].get("id")
        else:
            order_id = order_data.get("id")

        assert order_id, "No order_id returned after creation"

        # 3. POST /functions/v1/client-cancel-order with order_id before driver acceptance
        cancel_payload = {"order_id": order_id}
        cancel_resp = session.post(
            f"{BASE_URL}/functions/v1/client-cancel-order",
            headers=auth_headers,
            json=cancel_payload,
            timeout=TIMEOUT
        )
        assert cancel_resp.status_code == 200, f"Cancel order failed: {cancel_resp.text}"
        cancel_result = cancel_resp.json()

        # Validate response contains cancelled:true and refund details
        assert cancel_result.get("cancelled") is True, "Order not cancelled as expected"
        assert "refund" in cancel_result, "Refund details missing from cancel response"
        refund_info = cancel_result["refund"]
        assert isinstance(refund_info, dict) and refund_info, "Refund info is empty or invalid"

    finally:
        if 'order_id' in locals() and order_id:
            try:
                delete_resp = session.delete(
                    f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}",
                    headers=auth_headers,
                    timeout=TIMEOUT
                )
                assert delete_resp.status_code in (200, 204), f"Order deletion failed: {delete_resp.text}"
            except Exception:
                pass

test_post_functions_v1_client_cancel_order_before_driver_acceptance()
