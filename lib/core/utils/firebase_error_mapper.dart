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
        case 'weak-password':
          return const AppException(
            'A senha é muito fraca. Use pelo menos 6 caracteres.',
          );
        case 'user-not-found':
          return const AppException(
            'Nenhuma conta encontrada com essas credenciais.',
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
        default:
          return const AppException(
            'Não foi possível entrar agora. Tente novamente.',
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
            'Você não tem permissão para realizar esta operação.',
          );
        case 'object-not-found':
        case 'not-found':
          return const AppException(
            'O item solicitado não foi encontrado.',
          );
        case 'canceled':
          return const AppException('Operação cancelada.');
        default:
          return const AppException(
            'Não foi possível concluir esta ação. Tente novamente.',
          );
      }
    }

    return const AppException(
      'Ocorreu um erro inesperado. Tente novamente em instantes.',
    );
  }
}
