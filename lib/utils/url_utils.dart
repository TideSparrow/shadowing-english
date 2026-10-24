import 'package:url_launcher/url_launcher.dart';

/// Open a URL externally and let the caller handle launch failures.
/// Avoid a preflight check: Android package visibility can report false negatives.
Future<bool> openUrl(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
