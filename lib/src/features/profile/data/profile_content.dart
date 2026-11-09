/// `yyyy.MM.dd`, the date format of the saved collections.
String formatProfileDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
