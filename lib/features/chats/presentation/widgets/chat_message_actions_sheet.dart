import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/chat_message.dart';

const List<String> kChatQuickReactions = [
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

void showChatMessageActionsSheet({
  required BuildContext context,
  required ChatMessage message,
  required String myUid,
  required String senderLabel,
  required bool isLastMessage,
  required VoidCallback onRetryUpload,
  required VoidCallback onCancelUpload,
  required ValueChanged<String> onToggleReaction,
  required VoidCallback onReply,
  required VoidCallback onForward,
  required VoidCallback onSaveSticker,
  required VoidCallback onOpenFile,
  required VoidCallback onSaveFile,
  required VoidCallback onDeleteForMe,
  required VoidCallback onDeleteForEveryone,
}) {
  unawaited(HapticFeedback.mediumImpact());
  final isMine = message.senderId == myUid;

  if (message.isUploading || message.uploadFailed) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.uploadFailed)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Tentar enviar novamente'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    onRetryUpload();
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.close_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  message.uploadFailed ? 'Descartar envio' : 'Cancelar envio',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onCancelUpload();
                },
              ),
            ],
          ),
        );
      },
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final myReaction = message.reactionFor(myUid);

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.deletedForEveryone) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: kChatQuickReactions.map((emoji) {
                    final selected = myReaction == emoji;
                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onToggleReaction(emoji);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? AppColors.emerald.withValues(alpha: 0.2)
                              : (isDark
                                  ? AppColors.darkSurfaceAlt
                                  : AppColors.lightSurfaceAlt),
                          border: selected
                              ? Border.all(
                                  color: AppColors.emerald,
                                  width: 1.4,
                                )
                              : null,
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Responder'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onReply();
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text('Encaminhar'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onForward();
                },
              ),
              if (message.isSticker && (message.mediaId?.isNotEmpty ?? false))
                ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: const Text('Adicionar às minhas figurinhas'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSaveSticker();
                  },
                ),
              if (message.isFile) ...[
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Abrir arquivo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onOpenFile();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded),
                  title: const Text('Salvar ou compartilhar arquivo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSaveFile();
                  },
                ),
              ],
              if (message.text.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copiar texto'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Clipboard.setData(ClipboardData(text: message.text));
                    unawaited(HapticFeedback.selectionClick());
                  },
                ),
            ],
            ListTile(
              leading: const Icon(Icons.delete_rounded),
              title: const Text('Apagar para mim'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDeleteForMe();
              },
            ),
            if (isMine && !message.deletedForEveryone)
              ListTile(
                leading: Icon(
                  Icons.delete_forever_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Apagar para todos',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDeleteForEveryone();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
