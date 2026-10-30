import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Release unused GPU resources after the last player screen has gone away.
/// Keep a normal cache budget afterwards so returning to the library stays fast.
class PlayerGraphicsCache {
  PlayerGraphicsCache._();

  static int _activeScreens = 0;
  static int _generation = 0;

  static Future<void> Function() acquire() {
    _activeScreens++;
    _generation++;
    bool released = false;
    return () async {
      if (released) return;
      released = true;
      _activeScreens--;
      final int generation = ++_generation;
      if (_activeScreens != 0) return;

      // Let the departed Video/Texture leave the rendered scene first.
      await SchedulerBinding.instance.endOfFrame;
      if (_activeScreens != 0 || generation != _generation) return;
      try {
        await _setBudget(0);
      } finally {
        await _setBudget(64 * 1024 * 1024);
      }
    };
  }

  static Future<void> _setBudget(int bytes) async {
    try {
      await SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        bytes,
      );
    } on MissingPluginException {
      // Some rendering backends do not expose the Skia cache.
    } on PlatformException {
      // Cache trimming is optional; it must not prevent player disposal.
    }
  }
}
