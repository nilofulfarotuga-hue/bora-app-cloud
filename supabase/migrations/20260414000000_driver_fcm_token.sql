-- Migration: add fcm_token to drivers table
-- Used by NotificationService (Flutter) to persist Firebase Cloud Messaging tokens.
-- The notify-driver Edge Function reads this column to send push notifications.

ALTER TABLE drivers
  ADD COLUMN IF NOT EXISTS fcm_token TEXT DEFAULT NULL;

COMMENT ON COLUMN drivers.fcm_token IS
  'Firebase Cloud Messaging token. Updated by Flutter NotificationService.saveTokenForDriver() on each driver login. Cleared automatically by notify-driver Edge Function when FCM returns UNREGISTERED.';
