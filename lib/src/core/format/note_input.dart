/// What a member types into the tasting note's form, read the way the form
/// keeps it: a day as 2020.01.05 and a price in whole won.
library;

/// The most won a price may hold.
const maxWon = 10000000;

/// [input] as a day, 2020.01.05, or null when it is not one.
///
/// Its digits are read: eight as YYYYMMDD and six as YYMMDD in this
/// century (200115 is 2020.01.15). A form with separators (2020.1.5,
/// 2020-01-05, 2020/1/5) is read by its parts. Anything else, a day that is
/// not on the calendar, and a day after [today] are not days.
String? normalizeDay(String input, {DateTime? today}) {
  final text = input.trim();
  if (text.isEmpty || RegExp(r'[^0-9.\-/\s]').hasMatch(text)) return null;
  final parts = text
      .split(RegExp(r'[.\-/\s]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  final int year;
  final int month;
  final int day;
  if (parts.length == 3) {
    if (parts[0].length != 4 && parts[0].length != 2) return null;
    if (parts[1].length > 2 || parts[2].length > 2) return null;
    final y = int.parse(parts[0]);
    year = parts[0].length == 2 ? 2000 + y : y;
    month = int.parse(parts[1]);
    day = int.parse(parts[2]);
  } else if (parts.length == 1) {
    final digits = parts.single;
    if (digits.length == 8) {
      year = int.parse(digits.substring(0, 4));
      month = int.parse(digits.substring(4, 6));
      day = int.parse(digits.substring(6, 8));
    } else if (digits.length == 6) {
      year = 2000 + int.parse(digits.substring(0, 2));
      month = int.parse(digits.substring(2, 4));
      day = int.parse(digits.substring(4, 6));
    } else {
      return null;
    }
  } else {
    return null;
  }
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  final now = today ?? DateTime.now();
  if (date.isAfter(DateTime(now.year, now.month, now.day))) return null;
  return dotDay(date);
}

/// A day as the form shows it: 2020.01.05.
String dotDay(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}.'
      '${two(date.month)}.${two(date.day)}';
}

/// The day of 2020.01.05, as [normalizeDay] writes it.
DateTime? dayOfDot(String dotted) {
  final parts = dotted.split('.');
  if (parts.length != 3) return null;
  final values = parts.map(int.tryParse).toList();
  if (values.contains(null)) return null;
  return DateTime(values[0]!, values[1]!, values[2]!);
}

/// The whole won typed into [input], its digits only; null with none or
/// more than [maxWon].
int? parseWon(String input) {
  final digits = input.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty || digits.length > 8) return null;
  final won = int.parse(digits);
  return won < 1 || won > maxWon ? null : won;
}

/// 80000 as 80,000.
String groupWon(int won) {
  final digits = won.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// [input] as stars, 0.5 to 5 in halves (3, 3.0, 3.50 and .5 are read),
/// or null when it is not such a number.
double? parseRating(String input) {
  final text = input.trim();
  if (!RegExp(r'^(\d+(\.\d*)?|\.\d+)$').hasMatch(text)) return null;
  final value = double.parse(text);
  if (value < .5 || value > 5 || (value * 2) % 1 != 0) return null;
  return value;
}
