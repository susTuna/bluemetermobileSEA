import 'package:flutter/foundation.dart';

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  bool _enabled = false;
  
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  void log(String message, {String tag = 'BM'}) {
    if (_enabled) {
      debugPrint("[$tag] $message");
    }
  }

  void error(String message, {String tag = 'BM', Object? error, StackTrace? stackTrace}) {
    if (_enabled) {
      debugPrint("[$tag] ERROR: $message");
      if (error != null) {
        debugPrint("[$tag] Details: $error");
      }
      if (stackTrace != null) {
        debugPrint("[$tag] StackTrace: $stackTrace");
      }
    }
  }
}
