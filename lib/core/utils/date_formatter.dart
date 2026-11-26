class DateFormatter {
  DateFormatter._();

  static String formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static bool isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  static String formatDaySeparator(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(local.year, local.month, local.day);

    if (target == today) return 'Hoje';
    if (target == yesterday) return 'Ontem';

    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd/$mm/${local.year}';
  }

  static String formatChatListTimestamp(DateTime? dateTime) {
    if (dateTime == null) return '';
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(local.year, local.month, local.day);

    if (target == today) return formatTime(local);
    if (target == yesterday) return 'Ontem';

    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    if (local.year == now.year) {
      return '$dd/$mm';
    }
    return '$dd/$mm/${local.year.toString().substring(2)}';
  }

  static String formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'offline';
    final local = lastSeen.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(local.year, local.month, local.day);
    final time = formatTime(local);

    if (target == today) {
      return 'visto por último hoje às $time';
    }
    if (target == yesterday) {
      return 'visto por último ontem às $time';
    }

    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return 'visto por último em $dd/$mm/${local.year} às $time';
  }

  static String formatDuration(Duration duration) {
    final safeSeconds = duration.inSeconds.clamp(0, 359999);
    final minutes = safeSeconds ~/ 60;
    final seconds = (safeSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
