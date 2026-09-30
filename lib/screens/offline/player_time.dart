/// Port of `formatTime(ms)` shared by app/video/speed.tsx and
/// app/offline/play.tsx. Output is identical to the RN version, e.g.
/// 3723000 -> "1:02:03", 65000 -> "00:01:05", 0 -> "00:00:00"
/// (the hour is not zero-padded, like RN).
String formatPlayerTime(num ms) {
  int? hour;
  int minutes;
  int seconds;
  if (ms > 3600000) {
    final wholeHour = ms / 3600000;
    hour = wholeHour.floor();
    final wholeMinutes = (wholeHour - hour) * 60;
    minutes = wholeMinutes.floor();
    seconds = ((wholeMinutes - minutes) * 60).floor();
  } else {
    final wholeMinutes = ms / 60000;
    minutes = wholeMinutes.floor();
    seconds = ((wholeMinutes - minutes) * 60).floor();
  }
  String two(int v) => v != 0 && v < 10 ? '0$v' : (v != 0 ? '$v' : '00');
  return '${hour != null && hour != 0 ? hour : '00'}:${two(minutes)}:${two(seconds)}';
}
