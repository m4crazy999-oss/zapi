class ChatIdHelper {
  ChatIdHelper._();

  /// Gera ID determinístico para chat 1 a 1: menorUid_maiorUid.
  static String buildDirectChatId(String uidA, String uidB) {
    final sorted = sortedParticipants(uidA, uidB);
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Retorna os dois UIDs ordenados lexicograficamente.
  static List<String> sortedParticipants(String uidA, String uidB) {
    return uidA.compareTo(uidB) <= 0 ? [uidA, uidB] : [uidB, uidA];
  }
}
