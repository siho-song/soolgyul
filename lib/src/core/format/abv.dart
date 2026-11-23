/// '11.5%' or '40%': a strength as the app writes it; whole numbers drop the
/// decimal.
String formatAbv(double percent) =>
    '${percent % 1 == 0 ? percent.toInt() : percent}%';
