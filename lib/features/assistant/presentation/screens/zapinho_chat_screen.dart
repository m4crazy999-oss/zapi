import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/widgets/zapi_mascot.dart';
import '../../data/zapinho_ai_service.dart';

class _ZapinhoMessage {
  const _ZapinhoMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.sources = const [],
    this.isError = false,
  });

  final String id;
  final bool isUser;
  final String text;
  final List<ZapinhoSource> sources;
  final bool isError;

  _ZapinhoMessage copyWith({
    String? text,
    List<ZapinhoSource>? sources,
    bool? isError,
  }) {
    return _ZapinhoMessage(
      id: id,
      isUser: isUser,
      text: text ?? this.text,
      sources: sources ?? this.sources,
      isError: isError ?? this.isError,
    );
  }
}

/// Tela de chat padrão com o assistente virtual Zapinho.
class ZapinhoChatScreen extends StatefulWidget {
  const ZapinhoChatScreen({super.key});

  @override
  State<ZapinhoChatScreen> createState() => _ZapinhoChatScreenState();
}

class _ZapinhoChatScreenState extends State<ZapinhoChatScreen> {
  final _service = ZapinhoAiService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_ZapinhoMessage> _messages = [];
  Timer? _typingRevealTimer;
  bool _isWaiting = false;
  bool _isSpeaking = false;
  String? _lastFailedPrompt;

  static const String _welcomeMessage =
      'Oi! Eu sou o Zapinho, seu assistente virtual. Pode me perguntar qualquer coisa ou pedir uma pesquisa na web!';

  @override
  void dispose() {
    _typingRevealTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _clearChat() {
    _typingRevealTimer?.cancel();
    setState(() {
      _messages.clear();
      _isWaiting = false;
      _isSpeaking = false;
      _lastFailedPrompt = null;
    });
  }

  Future<void> _sendMessage([String? overrideText]) async {
    final text = (overrideText ?? _textController.text).trim();
    if (text.isEmpty || _isWaiting || _isSpeaking) return;

    final isRetry = overrideText != null;
    if (!isRetry) {
      _textController.clear();
    }

    final history = _messages
        .where((m) => !m.isError && m.text.trim().isNotEmpty)
        .map(
          (m) => ZapinhoHistoryTurn(
            role: m.isUser ? 'user' : 'model',
            text: m.text,
          ),
        )
        .toList();

    final replyId = 'zapinho-${DateTime.now().microsecondsSinceEpoch}';

    setState(() {
      if (isRetry && _messages.isNotEmpty && _messages.last.isError) {
        _messages.removeLast();
      } else {
        _messages.add(
          _ZapinhoMessage(
            id: 'user-${DateTime.now().microsecondsSinceEpoch}',
            isUser: true,
            text: text,
          ),
        );
      }
      _messages.add(
        _ZapinhoMessage(
          id: replyId,
          isUser: false,
          text: '',
        ),
      );
      _isWaiting = true;
      _isSpeaking = false;
      _lastFailedPrompt = text;
    });
    _scrollToBottom();

    try {
      final reply = await _service.ask(message: text, history: history);
      if (!mounted) return;
      _lastFailedPrompt = null;
      _revealReplyWithSpeechAnimation(
        messageId: replyId,
        fullText: reply.text,
        sources: reply.sources,
      );
    } on AppException catch (e) {
      if (!mounted) return;
      _setErrorReply(replyId, e.message);
    } catch (_) {
      if (!mounted) return;
      _setErrorReply(
        replyId,
        'Não foi possível falar com o Zapinho agora. Tente novamente.',
      );
    }
  }

  void _setErrorReply(String messageId, String errorText) {
    setState(() {
      _isWaiting = false;
      _isSpeaking = false;
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          text: errorText,
          isError: true,
        );
      }
    });
    _scrollToBottom();
  }

  void _revealReplyWithSpeechAnimation({
    required String messageId,
    required String fullText,
    required List<ZapinhoSource> sources,
  }) {
    _typingRevealTimer?.cancel();
    var cursor = 0;
    final step = (fullText.length / 26).ceil().clamp(3, 18);

    setState(() {
      _isWaiting = false;
      _isSpeaking = true;
    });

    _typingRevealTimer = Timer.periodic(
      const Duration(milliseconds: 35),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        cursor = (cursor + step).clamp(0, fullText.length);
        final done = cursor >= fullText.length;

        setState(() {
          final index = _messages.indexWhere((m) => m.id == messageId);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              text: fullText.substring(0, cursor),
              sources: done ? sources : const [],
            );
          }
          if (done) {
            _isSpeaking = false;
          }
        });
        _scrollToBottom();

        if (done) {
          timer.cancel();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final ZapiMascotMood headerMood;
    final String statusText;
    if (_isSpeaking) {
      headerMood = ZapiMascotMood.speaking;
      statusText = 'Respondendo...';
    } else if (_isWaiting) {
      headerMood = ZapiMascotMood.waiting;
      statusText = 'Pesquisando e pensando...';
    } else if (_messages.isNotEmpty && _messages.last.isError) {
      headerMood = ZapiMascotMood.resting;
      statusText = 'Sem resposta no momento';
    } else {
      headerMood = ZapiMascotMood.happy;
      statusText = 'Assistente virtual';
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ZapiMascot(
              mood: headerMood,
              size: 40,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Zapinho',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Nova conversa',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _clearChat,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: ZapiMascotWithBubble(
                        mood: ZapiMascotMood.happy,
                        mascotSize: 124,
                        maxBubbleWidth: 300,
                        message: _welcomeMessage,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    itemCount: _messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isLast = index == _messages.length - 1;
                      final ZapiMascotMood avatarMood;
                      if (msg.isError) {
                        avatarMood = ZapiMascotMood.resting;
                      } else if (isLast && _isSpeaking) {
                        avatarMood = ZapiMascotMood.speaking;
                      } else if (isLast && _isWaiting) {
                        avatarMood = ZapiMascotMood.waiting;
                      } else {
                        avatarMood = ZapiMascotMood.happy;
                      }

                      return Row(
                        mainAxisAlignment: msg.isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!msg.isUser) ...[
                            ZapiMascot(
                              mood: avatarMood,
                              size: 36,
                              animate: isLast,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: msg.isUser
                                    ? accentColor
                                    : (msg.isError
                                        ? Theme.of(context)
                                            .colorScheme
                                            .error
                                            .withValues(alpha: 0.12)
                                        : surfaceColor),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft:
                                      Radius.circular(msg.isUser ? 18 : 6),
                                  bottomRight:
                                      Radius.circular(msg.isUser ? 6 : 18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!msg.isUser &&
                                      msg.text.isEmpty &&
                                      _isWaiting)
                                    Text(
                                      'Zapinho pensando...',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: secondaryText,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                  else
                                    SelectableText(
                                      msg.text,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        height: 1.4,
                                        color: msg.isUser
                                            ? Colors.white
                                            : (msg.isError
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                : null),
                                      ),
                                    ),
                                  if (!msg.isUser &&
                                      msg.isError &&
                                      _lastFailedPrompt != null) ...[
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () =>
                                          _sendMessage(_lastFailedPrompt),
                                      icon: const Icon(
                                        Icons.refresh_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Tentar novamente'),
                                    ),
                                  ],
                                  if (!msg.isUser &&
                                      !msg.isError &&
                                      msg.sources.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Fontes encontradas',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final src in msg.sources)
                                          InkWell(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            onTap: () async {
                                              await Clipboard.setData(
                                                ClipboardData(text: src.uri),
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Link copiado.',
                                                  ),
                                                  duration: Duration(
                                                    seconds: 2,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? AppColors.darkSurfaceAlt
                                                    : AppColors.lightSurfaceAlt,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                src.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              color: surfaceColor,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Pergunte qualquer coisa ao Zapinho...',
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkBackground
                            : AppColors.lightBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: FilledButton(
                      onPressed: (_isWaiting || _isSpeaking)
                          ? null
                          : () => _sendMessage(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
