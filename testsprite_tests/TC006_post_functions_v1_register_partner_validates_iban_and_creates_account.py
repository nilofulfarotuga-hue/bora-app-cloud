import requests
import uuid

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
REGISTER_PARTNER_ENDPOINT = "/functions/v1/register-partner"
TIMEOUT = 30
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def test_post_functions_v1_register_partner_validates_iban_and_creates_account():
    headers = {
        "Content-Type": "application/json",
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {ANON_KEY}"
    }

    # Valid partner registration payload with PT IBAN
    valid_payload = {
        "email": f"testpartner_{uuid.uuid4().hex[:8]}@example.com",
        "password": "StrongPassw0rd!",
        "restaurant_name": "Test Restaurant",
        "restaurant_address": "123 Test Street, Guarda, Portugal",
        "iban": "PT50000201231234567890154"  # Valid PT IBAN format (PT + 21 digits)
    }

    # Invalid IBAN payload (invalid format)
    invalid_iban_payload = {
        "email": f"invalidiban_{uuid.uuid4().hex[:8]}@example.com",
        "password": "StrongPassw0rd!",
        "restaurant_name": "Invalid IBAN Restaurant",
        "restaurant_address": "456 Error Road, Guarda, Portugal",
        "iban": "PT123"  # Invalid IBAN, too short
    }

    # Missing required fields payload (missing email and iban)
    missing_fields_payload = {
        "password": "StrongPassw0rd!",
        "restaurant_name": "Missing Fields Restaurant",
        "restaurant_address": "789 Missing St, Guarda, Portugal"
    }

    # --- Test valid registration ---
    try:
        response = requests.post(
            BASE_URL + REGISTER_PARTNER_ENDPOINT,
            headers=headers,
            json=valid_payload,
            timeout=TIMEOUT
        )
        assert response.status_code in (200, 201), f"Expected 200 or 201, got {response.status_code}"
        json_resp = response.json()
        # Check that partner approval is pending by presence of expected keys or status
        # Since schema not specific on response keys, just check json_resp is dict and non-empty
        assert isinstance(json_resp, dict) and len(json_resp) > 0, "Empty or invalid response JSON"
    finally:
        # As no delete endpoint indicated, no cleanup possible for partner account
        pass

    # --- Test invalid IBAN returns 400 ---
    response_invalid_iban = requests.post(
        BASE_URL + REGISTER_PARTNER_ENDPOINT,
        headers=headers,
        json=invalid_iban_payload,
        timeout=TIMEOUT
    )
    assert response_invalid_iban.status_code == 400, f"Expected 400 for invalid IBAN, got {response_invalid_iban.status_code}"

    # --- Test missing fields returns 400 ---
    response_missing_fields = requests.post(
        BASE_URL + REGISTER_PARTNER_ENDPOINT,
        headers=headers,
        json=missing_fields_payload,
        timeout=TIMEOUT
    )
    assert response_missing_fields.status_code == 400, f"Expected 400 for missing fields, got {response_missing_fields.status_code}"

test_post_functions_v1_register_partner_validates_iban_and_creates_account()