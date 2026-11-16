import 'package:intl/intl.dart';

class AppHelpers {
  static String formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    int i = 0;
    double d = bytes.toDouble();
    while (d > 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return "${d.toStringAsFixed(1)} ${suffixes[i]}";
  }

  static String formatPercentage(int used, int total) {
    if (total <= 0) return "0%";
    return "${((used / total) * 100).toStringAsFixed(1)}%";
  }

  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (now.year == date.year) {
      return DateFormat('MMM d').format(date);
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  static String getYearsAgoText(DateTime date) {
    final now = DateTime.now();
    final years = now.year - date.year;
    if (years == 1) return '1 year ago';
    if (years > 1) return '$years years ago';
    return 'Recently';
  }
}
