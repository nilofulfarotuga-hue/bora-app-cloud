import requests
import time

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
TIMEOUT = 30

# Test client credentials (provisioned in auth.users)
CLIENT_EMAIL = "test-client@bora.app"
CLIENT_PASSWORD = "TestBora2026!"
DRIVER_ID = "910000000"  # demo driver id
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def supabase_auth_login(email: str, password: str):
    url = f"{BASE_URL}/auth/v1/token?grant_type=password"
    payload = {
        "email": email,
        "password": password
    }
    headers = {"Content-Type": "application/json", "apikey": ANON_KEY}
    resp = requests.post(url, json=payload, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()["access_token"]

def create_order(client_jwt: str):
    url = f"{BASE_URL}/rest/v1/orders"
    headers = {
        "Authorization": f"Bearer {client_jwt}",
        "apikey": ANON_KEY,
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    # Minimal order payload assuming required fields
    payload = {
        "status": "created"
        # Add any other required fields for order creation here
    }
    resp = requests.post(url, headers=headers, json=payload, timeout=TIMEOUT)
    resp.raise_for_status()
    result = resp.json()
    if not result or not isinstance(result, list):
        raise Exception("Unexpected order creation response")
    order = result[0]
    return order["id"]

def authenticate_driver():
    # For this test the driver_id is provided as demo driver id "910000000"
    # Assuming no JWT needed for driver for accept_offer, but API requires auth:
    # No driver login endpoint provided in PRD, so reuse client login with email-pw is not possible.
    # Assuming we can use client token for this test or skip auth for driver as no driver-auth endpoint given.
    # Since auth_required: true indicated in PRD for accept_offer, we must authenticate driver.
    # However no driver login endpoint specified, we will assume that driver token can be obtained via client credentials for test.
    # So using client login token as driver token here (limitation due to given data).
    return supabase_auth_login(CLIENT_EMAIL, CLIENT_PASSWORD)

def dispatch_order(client_jwt: str, order_id: str):
    url = f"{BASE_URL}/functions/v1/dispatch-engine"
    headers = {
        "Authorization": f"Bearer {client_jwt}",
        "Content-Type": "application/json",
        "apikey": ANON_KEY
    }
    payload = {"order_id": order_id}
    resp = requests.post(url, headers=headers, json=payload, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()

def get_order_status(client_jwt: str, order_id: str):
    url = f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}"
    headers = {
        "Authorization": f"Bearer {client_jwt}",
        "apikey": ANON_KEY,
        "Content-Type": "application/json"
    }
    resp = requests.get(url, headers=headers, timeout=TIMEOUT)
    resp.raise_for_status()
    orders = resp.json()
    if not orders:
        return None
    return orders[0].get("status")

def accept_offer(client_jwt: str, order_id: str, driver_id: str):
    url = f"{BASE_URL}/rest/v1/rpc/accept_offer"
    headers = {
        "Authorization": f"Bearer {client_jwt}",
        "Content-Type": "application/json",
        "apikey": ANON_KEY
    }
    payload = {
        "p_order_id": order_id,
        "p_driver_id": driver_id
    }
    resp = requests.post(url, headers=headers, json=payload, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()

def delete_order(client_jwt: str, order_id: str):
    url = f"{BASE_URL}/rest/v1/orders?id=eq.{order_id}"
    headers = {
        "Authorization": f"Bearer {client_jwt}",
        "apikey": ANON_KEY
    }
    resp = requests.delete(url, headers=headers, timeout=TIMEOUT)
    if resp.status_code not in (200, 204):
        raise Exception(f"Failed to delete order {order_id}")

def test_post_rest_v1_rpc_accept_offer_assigns_first_eligible_driver():
    client_jwt = supabase_auth_login(CLIENT_EMAIL, CLIENT_PASSWORD)
    driver_jwt = client_jwt  # Using client token as driver token due to no driver auth endpoint in PRD
    
    order_id = None
    try:
        # Create a new order as client
        order_id = create_order(client_jwt)

        # Dispatch to assign first eligible driver
        dispatch_resp = dispatch_order(client_jwt, order_id)
        dispatched = dispatch_resp.get("dispatched")
        assert dispatched is True, "Order was not dispatched successfully"

        # Accept offer with first eligible driver
        accept_resp = accept_offer(driver_jwt, order_id, DRIVER_ID)
        assert isinstance(accept_resp, dict), "Accept offer response is not a dictionary"
        accepted = accept_resp.get("accepted")
        assert accepted is True, "Accept offer did not return accepted:true"

        # Check order status is updated to driverAccepted
        # Wait briefly to ensure status updated
        time.sleep(1)
        status = get_order_status(client_jwt, order_id)
        assert status == "driverAccepted", f"Order status after accept_offer is not 'driverAccepted' but '{status}'"

        # Attempt to accept offer again with same or different driver triggers error (simulate other driver)
        another_driver_id = "910000001"
        try:
            resp2 = accept_offer(driver_jwt, order_id, another_driver_id)
            # If request succeeds, check if accepted is False or error sent.
            # Likely this should raise or return error, so fail if accepted true.
            accepted2 = resp2.get("accepted", False)
            assert not accepted2, "Second driver was able to accept offer, but should not"
        except requests.HTTPError as err:
            # Expecting an error due to offer unavailable or conflict
            assert err.response.status_code in (409, 400), f"Expected conflict/validation error but got {err.response.status_code}"
            # Optionally check error message content
            err_json = err.response.json()
            msg = err_json.get("message", "").lower()
            assert "offer_unavailable" in msg or "conflict" in msg or "already claimed" in msg

    finally:
        if order_id:
            try:
                delete_order(client_jwt, order_id)
            except Exception:
                pass

test_post_rest_v1_rpc_accept_offer_assigns_first_eligible_driver()