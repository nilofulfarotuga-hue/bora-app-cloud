-- Advisor 0029: _robot_setting_enabled não precisa de EXECUTE para authenticated —
-- admin_robot_metrics é SECURITY DEFINER e corre como owner. Least privilege.
REVOKE EXECUTE ON FUNCTION public._robot_setting_enabled(text) FROM authenticated;
