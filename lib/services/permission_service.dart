import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum SmsPermissionState {
  unknown,
  granted,
  denied,
  permanentlyDenied,
  restricted,
  unsupported,
}

abstract class SmsPermissionService {
  Future<SmsPermissionState> check();

  Future<SmsPermissionState> request();

  Future<bool> openSettings();
}

class PermissionHandlerSmsPermissionService implements SmsPermissionService {
  const PermissionHandlerSmsPermissionService();

  @override
  Future<SmsPermissionState> check() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return SmsPermissionState.unsupported;
    }
    return _mapStatus(await Permission.sms.status);
  }

  @override
  Future<SmsPermissionState> request() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return SmsPermissionState.unsupported;
    }
    final smsStatus = await Permission.sms.request();
    await Permission.notification.request();
    return _mapStatus(smsStatus);
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  SmsPermissionState _mapStatus(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return SmsPermissionState.granted;
      case PermissionStatus.denied:
        return SmsPermissionState.denied;
      case PermissionStatus.permanentlyDenied:
        return SmsPermissionState.permanentlyDenied;
      case PermissionStatus.restricted:
        return SmsPermissionState.restricted;
      case PermissionStatus.limited:
      case PermissionStatus.provisional:
        return SmsPermissionState.denied;
    }
  }
}
