import requests

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4"

def test_get_rest_v1_ledger_entries_unauthorized_rejected():
    headers = {
        "apikey": API_KEY
        # intentionally no Authorization header
    }
    url = f"{BASE_URL}/rest/v1/ledger_entries"
    try:
        response = requests.get(url, headers=headers, timeout=30)
    except requests.RequestException as e:
        assert False, f"Request failed: {e}"

    # Assert that the status code is 401 Unauthorized
    assert response.status_code == 401, f"Expected 401 Unauthorized but got {response.status_code}"

    # Assert that response does not contain ledger data (should be empty or error message)
    # Typically, the body might be JSON with error detail or empty
    try:
        payload = response.json()
    except ValueError:
        payload = response.text

    # The payload should not contain any ledger data keys (such as list of entries)
    if isinstance(payload, dict):
        # Common keys that ledger entries might expose would vary. Just confirm it's an error response
        assert "error" in payload or "message" in payload, "Expected error message in response body"
    else:
        # If not JSON, verify the body is not a ledger data dump - heuristic: length is small or contains 'unauthorized'
        assert "unauthorized" in str(payload).lower() or len(str(payload)) < 100, "Unexpected response content for unauthorized access"

test_get_rest_v1_ledger_entries_unauthorized_rejected()