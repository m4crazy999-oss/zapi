import '../constants/app_constants.dart';
import 'public_id_helper.dart';

class Validators {
  Validators._();

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  static final RegExp _usernameRegex = RegExp(r'^[a-z0-9._]{3,20}$');

  static String normalizeUsername(String input) {
    final trimmed = input.trim().toLowerCase();
    return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  }

  static bool isEmailFormat(String input) {
    return _emailRegex.hasMatch(input.trim());
  }

  static String? validateDisplayName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Informe seu nome de exibição.';
    }
    if (text.length < 2) {
      return 'O nome deve ter pelo menos 2 caracteres.';
    }
    if (text.length > AppConstants.maxDisplayNameLength) {
      return 'O nome pode ter no máximo ${AppConstants.maxDisplayNameLength} caracteres.';
    }
    return null;
  }

  static String? validateUsername(String? value) {
    final normalized = normalizeUsername(value ?? '');
    if (normalized.isEmpty) {
      return 'Escolha um @usuário.';
    }
    if (normalized.length < 3 || normalized.length > 20) {
      return 'O @usuário deve ter entre 3 e 20 caracteres.';
    }
    if (!_usernameRegex.hasMatch(normalized)) {
      return 'Use apenas letras minúsculas, números, ponto (.) ou sublinhado (_).';
    }
    if (normalized.startsWith('.') || normalized.endsWith('.')) {
      return 'O @usuário não pode começar nem terminar com ponto.';
    }
    return null;
  }

  static String? validateContactLookup(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Digite um @usuário ou ID Zapi para buscar.';
    }
    if (PublicIdHelper.looksLikePublicId(trimmed)) {
      if (!PublicIdHelper.isValid(trimmed)) {
        return 'ID inválido. Exemplo: ZP-4K8M9P2X.';
      }
      return null;
    }
    return validateUsername(trimmed);
  }

  static String? validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Informe seu e-mail.';
    }
    if (!_emailRegex.hasMatch(text)) {
      return 'Digite um endereço de e-mail válido.';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return 'Informe sua senha.';
    }
    if (text.length < 6) {
      return 'A senha deve ter no mínimo 6 caracteres.';
    }
    return null;
  }

  static String? validateAbout(String? value) {
    final text = value?.trim() ?? '';
    if (text.length > AppConstants.maxAboutLength) {
      return 'O recado pode ter no máximo ${AppConstants.maxAboutLength} caracteres.';
    }
    return null;
  }
}
