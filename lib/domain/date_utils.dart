/// Pure Dart date formatting and calculation utilities for worship services.
///
/// Pure Dart: zero Flutter imports.
class ServiceDateUtils {
  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Calculates the next upcoming Sunday relative to [from] (or DateTime.now()).
  ///
  /// If [from] is already a Sunday, returns the Sunday 7 days later.
  /// Normalized to midnight (00:00:00).
  static DateTime getNextSunday([DateTime? from]) {
    final base = from ?? DateTime.now();
    final daysUntilSunday = (DateTime.sunday - base.weekday) % 7;
    final daysToAdd = daysUntilSunday == 0 ? 7 : daysUntilSunday;
    final next = base.add(Duration(days: daysToAdd));
    return DateTime(next.year, next.month, next.day);
  }

  /// Formats a service date as "Sun, Nov 29, 2026".
  static String formatServiceDate(DateTime date) {
    final weekday = _weekdays[date.weekday - 1];
    final month = _months[date.month - 1];
    return '$weekday, $month ${date.day}, ${date.year}';
  }
}
