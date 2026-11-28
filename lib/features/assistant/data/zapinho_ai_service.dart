import 'package:dio/dio.dart';

import '../../../core/utils/app_exceptions.dart';

class ZapinhoSource {
  const ZapinhoSource({
    required this.title,
    required this.uri,
  });

  final String title;
  final String uri;
}

class ZapinhoReply {
  const ZapinhoReply({
    required this.text,
    this.sources = const [],
  });

  final String text;
  final List<ZapinhoSource> sources;
}

class ZapinhoHistoryTurn {
  const ZapinhoHistoryTurn({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
      };
}

class ZapinhoAiService {
  ZapinhoAiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 35),
                sendTimeout: const Duration(seconds: 15),
                headers: const {'Content-Type': 'application/json'},
              ),
            );

  static const String _endpointUrl = String.fromEnvironment(
    'ZAPI_AI_URL',
    defaultValue:
        'https://ais-pre-6kos3tsztqs6szp44hh35b-931700898249.us-east1.run.app/api/mascot-chat',
  );

  final Dio _dio;

  Future<ZapinhoReply> ask({
    required String message,
    required List<ZapinhoHistoryTurn> history,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpointUrl,
        data: {
          'message': message,
          'history': history.map((h) => h.toJson()).toList(),
          'stream': false,
        },
      );

      final data = response.data;
      if (data == null) {
        throw const AppException(
          'Não recebi resposta do Zapinho agora. Tente novamente.',
        );
      }

      final text = (data['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        throw const AppException(
          'Não consegui formular uma resposta desta vez. Tente perguntar de outro jeito.',
        );
      }

      final rawSources = data['sources'];
      final sources = <ZapinhoSource>[];
      if (rawSources is List) {
        for (final item in rawSources) {
          if (item is Map) {
            final uri = (item['uri'] as String?)?.trim() ?? '';
            final title = (item['title'] as String?)?.trim() ?? '';
            if (uri.isNotEmpty) {
              sources.add(
                ZapinhoSource(
                  title: title.isNotEmpty ? title : uri,
                  uri: uri,
                ),
              );
            }
          }
        }
      }

      return ZapinhoReply(text: text, sources: sources);
    } on DioException catch (e) {
      final serverData = e.response?.data;
      if (serverData is Map && serverData['error'] is String) {
        throw AppException(serverData['error'] as String);
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const AppException(
          'Sem conexão com o assistente no momento. Verifique sua internet e tente novamente.',
        );
      }
      throw const AppException(
        'Não foi possível falar com o Zapinho agora. Tente novamente em instantes.',
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Algo deu errado ao falar com o Zapinho. Tente novamente.',
      );
    }
  }
}
