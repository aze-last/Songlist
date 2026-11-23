import 'package:flutter_test/flutter_test.dart';
import 'package:worship_setlist/domain/date_utils.dart';

void main() {
  group('ServiceDateUtils.getNextSunday', () {
    test('returns next Sunday when current day is Monday', () {
      final monday = DateTime(2026, 11, 23); // Monday
      final sunday = ServiceDateUtils.getNextSunday(monday);
      expect(sunday, DateTime(2026, 11, 29));
      expect(sunday.weekday, DateTime.sunday);
    });

    test('returns following Sunday when current day is Sunday', () {
      final sunday = DateTime(2026, 11, 29); // Sunday
      final nextSunday = ServiceDateUtils.getNextSunday(sunday);
      expect(nextSunday, DateTime(2026, 12, 6));
      expect(nextSunday.weekday, DateTime.sunday);
    });

    test('returns next Sunday when current day is Saturday', () {
      final saturday = DateTime(2026, 11, 28);
      final sunday = ServiceDateUtils.getNextSunday(saturday);
      expect(sunday, DateTime(2026, 11, 29));
    });

    test('formats service date into readable string', () {
      final date = DateTime(2026, 11, 29);
      expect(ServiceDateUtils.formatServiceDate(date), 'Sun, Nov 29, 2026');
    });
  });
}
