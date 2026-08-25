typedef GreetingClock = DateTime Function();

class GreetingResolver {
  const GreetingResolver();

  String resolve(GreetingClock now) => resolveLocal(now().toLocal());

  String resolveLocal(DateTime localTime) {
    final hour = localTime.hour;
    final period = switch (hour) {
      >= 5 && < 9 => '早上好',
      >= 9 && < 11 => '上午好',
      >= 11 && < 14 => '中午好',
      >= 14 && < 17 => '下午好',
      _ => '晚上好',
    };
    return '$period，我是 Jax';
  }

  DateTime nextChangeAfter(DateTime instant) {
    final local = instant.toLocal();
    DateTime atHour(int hour) =>
        DateTime(local.year, local.month, local.day, hour);

    if (local.hour < 5) return atHour(5);
    if (local.hour < 9) return atHour(9);
    if (local.hour < 11) return atHour(11);
    if (local.hour < 14) return atHour(14);
    if (local.hour < 17) return atHour(17);
    return DateTime(local.year, local.month, local.day + 1, 5);
  }
}
