import requests
import uuid

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
TIMEOUT = 30

# Demo client credentials for authentication
CLIENT_EMAIL = "cliente@bora.app"
CLIENT_PASSWORD = "123456"

def authenticate_client(email, password):
    url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    headers = {"Content-Type": "application/json"}
    payload = {"email": email, "password": password}
    resp = requests.post(url, json=payload, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()["access_token"]

def create_order(auth_token, amount_cents=1000, currency="eur"):
    url = f"{BASE_URL}/rest/v1/orders"
    headers = {
        "Authorization": f"Bearer {auth_token}",
        "Content-Type": "application/json",
        "apikey": auth_token,  # Supabase usually requires apikey header equal to anon or service role key, but here we rely on auth token for RLS
        "Prefer": "return=representation"
    }
    # Create a minimal valid order payload
    payload = {
        "id": str(uuid.uuid4()),
        "amount": amount_cents,
        "currency": currency,
        "status": "pending"
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    order = resp.json()
    if isinstance(order, list):
        order = order[0]
    return order["id"]

def delete_order(auth_token, order_id):
    url = f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}"
    headers = {
        "Authorization": f"Bearer {auth_token}",
        "apikey": auth_token
    }
    resp = requests.delete(url, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()

def test_TC003_post_functions_v1_create_payment_intent_validates_amount_and_returns_client_secret():
    # Authenticate client
    token = authenticate_client(CLIENT_EMAIL, CLIENT_PASSWORD)

    # Create an order to get a valid order_id
    order_id = create_order(token)

    try:
        url = f"{BASE_URL}/functions/v1/create-payment-intent"
        headers = {
            "Content-Type": "application/json"
        }

        # Test valid amount within allowed buffer (amount in cents, min 50 cents, buffer ±5%)
        valid_amount = 1000  # €10.00 (assumed valid for test)
        currency = "eur"
        payload_valid = {
            "order_id": order_id,
            "amount": valid_amount,
            "currency": currency
        }

        resp_valid = requests.post(url, json=payload_valid, headers=headers, timeout=TIMEOUT)
        assert resp_valid.status_code == 200, f"Expected 200, got {resp_valid.status_code}"
        data_valid = resp_valid.json()
        assert "client_secret" in data_valid and isinstance(data_valid["client_secret"], str) and data_valid["client_secret"], "Missing or invalid client_secret in response"
        assert "payment_intent_id" in data_valid and isinstance(data_valid["payment_intent_id"], str) and data_valid["payment_intent_id"], "Missing or invalid payment_intent_id in response"

        # Test invalid amount below Stripe minimum (e.g., 10 cents)
        invalid_amount_low = 10  # 10 cents, below €0.50 min
        payload_invalid_low = {
            "order_id": order_id,
            "amount": invalid_amount_low,
            "currency": currency
        }
        resp_invalid_low = requests.post(url, json=payload_invalid_low, headers=headers, timeout=TIMEOUT)
        assert resp_invalid_low.status_code == 400, f"Expected 400 for low amount, got {resp_invalid_low.status_code}"

        # Test invalid amount outside allowed buffer (e.g., ±5% buffer on 1000 is 950-1050, use 1100)
        invalid_amount_high = 1100
        payload_invalid_high = {
            "order_id": order_id,
            "amount": invalid_amount_high,
            "currency": currency
        }
        resp_invalid_high = requests.post(url, json=payload_invalid_high, headers=headers, timeout=TIMEOUT)
        assert resp_invalid_high.status_code == 400, f"Expected 400 for amount outside buffer, got {resp_invalid_high.status_code}"

    finally:
        # Clean up the created order
        delete_order(token, order_id)

test_TC003_post_functions_v1_create_payment_intent_validates_amount_and_returns_client_secret()