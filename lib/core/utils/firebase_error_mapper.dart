import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'app_exceptions.dart';

class FirebaseErrorMapper {
  FirebaseErrorMapper._();

  static AppException map(Object error) {
    if (error is AppException) {
      return error;
    }

    if (error is SocketException) {
      return const AppException(
        'Sem conexão com a internet. Verifique sua rede e tente novamente.',
      );
    }

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return const AppException(
            'Este e-mail já está cadastrado em outra conta.',
          );
        case 'invalid-email':
          return const AppException(
            'O endereço de e-mail informado não é válido.',
          );
        case 'missing-email':
          return const AppException(
            'Informe o e-mail da sua conta para continuar.',
          );
        case 'weak-password':
          return const AppException(
            'A senha é muito fraca. Use pelo menos 6 caracteres.',
          );
        case 'user-not-found':
          return const AppException(
            'Nenhuma conta encontrada com esse e-mail.',
          );
        case 'wrong-password':
        case 'invalid-credential':
          return const AppException(
            'E-mail ou senha incorretos.',
          );
        case 'user-disabled':
          return const AppException(
            'Esta conta foi desativada.',
          );
        case 'operation-not-allowed':
          return const AppException(
            'O método de login por e-mail/senha não está ativado no Firebase Authentication.',
          );
        case 'too-many-requests':
          return const AppException(
            'Muitas tentativas seguidas. Aguarde alguns instantes e tente de novo.',
          );
        case 'network-request-failed':
          return const AppException(
            'Sem conexão com a internet. Verifique seu Wi-Fi ou dados móveis.',
          );
        case 'requires-recent-login':
          return const AppException(
            'Por segurança, confirme sua senha atual para concluir esta ação.',
          );
        case 'expired-action-code':
        case 'invalid-action-code':
          return const AppException(
            'O link de verificação expirou ou já foi utilizado. Solicite um novo.',
          );
        case 'invalid-recipient-email':
          return const AppException(
            'Não foi possível enviar para este endereço de e-mail.',
          );
        default:
          return AppException(
            'Não foi possível concluir a autenticação (${error.code}). Tente novamente.',
          );
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'network-request-failed':
          return const AppException(
            'Serviço temporariamente indisponível ou sem conexão com a internet.',
          );
        case 'permission-denied':
        case 'unauthorized':
          return const AppException(
            'Permissão negada no Firestore. Verifique se o arquivo firestore.rules atualizado foi publicado no Firebase Console.',
          );
        case 'object-not-found':
        case 'not-found':
          return const AppException(
            'O item solicitado não foi encontrado.',
          );
        case 'canceled':
          return const AppException('Operação cancelada.');
        default:
          return AppException(
            'Não foi possível concluir esta ação (${error.code}). Tente novamente.',
          );
      }
    }

    return const AppException(
      'Ocorreu um erro inesperado. Tente novamente em instantes.',
    );
  }
}
