import 'dart:math';

class PublicIdHelper {
  PublicIdHelper._();

  static const String prefix = 'ZP-';
  static const int codeLength = 8;

  // Alfabeto sem caracteres ambíguos (sem 0, O, I, 1, L) para facilitar leitura por voz.
  static const String _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  static final RegExp _publicIdRegex = RegExp(
    r'^ZP-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$',
  );

  static final Random _secureRandom = Random.secure();

  /// Gera um ID público único no formato ZP-XXXXXXXX.
  static String generate() {
    final buffer = StringBuffer(prefix);
    for (var i = 0; i < codeLength; i++) {
      buffer.write(_alphabet[_secureRandom.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Normaliza o texto digitado pelo usuário para maiúsculas (ex: "zp-4k8m9p2x" -> "ZP-4K8M9P2X").
  static String normalize(String input) {
    final cleaned = input.trim().toUpperCase().replaceAll(' ', '');
    if (cleaned.startsWith('ZP') &&
        !cleaned.startsWith(prefix) &&
        cleaned.length == 2 + codeLength) {
      return '$prefix${cleaned.substring(2)}';
    }
    return cleaned;
  }

  /// Indica se a entrada parece ser um ID Zapi (começa com ZP- ou ZP).
  static bool looksLikePublicId(String input) {
    final upper = input.trim().toUpperCase();
    return upper.startsWith(prefix) ||
        (upper.startsWith('ZP') && upper.length >= 3);
  }

  /// Verifica se a string já normalizada segue exatamente o padrão ZP-XXXXXXXX.
  static bool isValid(String input) {
    return _publicIdRegex.hasMatch(normalize(input));
  }
}
