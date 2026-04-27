-- Migration: add fcm_token to restaurants table
-- Used by NotificationService (Flutter) to persist Firebase Cloud Messaging tokens.
-- The notify-partner Edge Function reads this column to send push notifications
-- when a new order arrives for a partner restaurant.

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS fcm_token TEXT DEFAULT NULL;

COMMENT ON COLUMN restaurants.fcm_token IS
  'Firebase Cloud Messaging token. Updated by Flutter NotificationService.saveTokenForPartner() on each partner login. Cleared automatically by notify-partner Edge Function when FCM returns UNREGISTERED.';
