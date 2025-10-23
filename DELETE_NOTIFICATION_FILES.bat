@echo off
echo Deleting notification service files...

del "lib\services\backup_notifications\direct_notification_service.dart"
del "lib\services\backup_notifications\local_notification_test.dart"
del "lib\services\backup_notifications\local_realtime_notification_service.dart"
del "lib\services\backup_notifications\push_notification_service.dart"
del "lib\services\backup_notifications\websocket_notification_service_clean.dart"
rmdir "lib\services\backup_notifications"

del "lib\widgets\notification_test_widget.dart"
del "lib\screens\notification_debug_screen.dart"
del "lib\config\fcm_config.dart"

echo Notification files deleted successfully!
pause
