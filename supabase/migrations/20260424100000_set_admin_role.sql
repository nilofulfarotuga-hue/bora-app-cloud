-- Migration: set bora_role='admin' in user_metadata for the Bora admin account.
-- Uses the same user_metadata pattern already established for driver/partner roles.
-- Reversible: UPDATE auth.users SET raw_user_meta_data = raw_user_meta_data - 'bora_role' WHERE email = '...';

UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || '{"bora_role":"admin"}'::jsonb
WHERE email = 'nilofulfarotuga@gmail.com';
