import requests
import time

BASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
SERVICE_ROLE_JWT = "<your_service_role_jwt_here>"  # Replace with valid service_role JWT
ANON_API_KEY = "<your_anon_public_api_key_here>"  # Replace with valid anon public API key
TIMEOUT = 30

def test_post_functions_v1_notify_client_fcm_email_fallback():
    notify_url = f"{BASE_URL}/functions/v1/notify-client"
    headers_auth = {
        "Authorization": f"Bearer {SERVICE_ROLE_JWT}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    headers_no_auth = {
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    signup_url = f"{BASE_URL}/auth/v1/signup"
    login_url = f"{BASE_URL}/auth/v1/token?grant_type=password"

    test_email = f"test_notify_client_{int(time.time())}@bora.app"
    test_password = "Test1234!"

    signup_payload = {
        "email": test_email,
        "password": test_password
    }
    signup_headers = {
        "apikey": ANON_API_KEY,
        "Authorization": f"Bearer {ANON_API_KEY}",
        "Content-Type": "application/json"
    }

    resp_signup = requests.post(signup_url, json=signup_payload, headers=signup_headers, timeout=TIMEOUT)
    assert resp_signup.status_code == 200, f"Signup failed: {resp_signup.status_code} {resp_signup.text}"
    user_info = resp_signup.json()
    user_id = user_info.get("user", {}).get("id")
    assert user_id, "User ID not returned after signup"

    login_payload = {
        "email": test_email,
        "password": test_password
    }
    login_headers = {
        "apikey": ANON_API_KEY,
        "Authorization": f"Bearer {ANON_API_KEY}",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    resp_login = requests.post(login_url, data=login_payload, headers=login_headers, timeout=TIMEOUT)
    assert resp_login.status_code == 200, f"Login failed: {resp_login.status_code} {resp_login.text}"

    try:
        payload = {
            "user_id": user_id,
            "title": "Test Notification Title",
            "body": "This is a test notification body to FCM with email fallback"
        }
        resp_notify = requests.post(notify_url, headers=headers_auth, json=payload, timeout=TIMEOUT)
        assert resp_notify.status_code == 200, f"Notify-client success case failed: {resp_notify.status_code} {resp_notify.text}"

        resp_unauth = requests.post(notify_url, headers=headers_no_auth, json=payload, timeout=TIMEOUT)
        assert resp_unauth.status_code in (401, 403), f"Notify-client unauthorized request did not fail as expected, got {resp_unauth.status_code}"

        incomplete_payload = {
            "user_id": user_id
        }
        resp_incomplete = requests.post(notify_url, headers=headers_auth, json=incomplete_payload, timeout=TIMEOUT)
        assert resp_incomplete.status_code >= 400, f"Notify-client missing fields did not fail as expected, got {resp_incomplete.status_code}"

    finally:
        token_resp = requests.post(login_url, data=login_payload, headers=login_headers, timeout=TIMEOUT)
        if token_resp.status_code == 200:
            user_jwt = token_resp.json().get("access_token")
            if user_jwt:
                delete_account_url = f"{BASE_URL}/functions/v1/delete-account"
                delete_headers = {
                    "Authorization": f"Bearer {user_jwt}",
                    "Content-Type": "application/json"
                }
                requests.post(delete_account_url, headers=delete_headers, timeout=TIMEOUT)

test_post_functions_v1_notify_client_fcm_email_fallback()
