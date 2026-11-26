import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/media_cache_service.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/chats_repository.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_thread.dart';

final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  return ChatsRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    mediaCache: ref.watch(mediaCacheServiceProvider),
  );
});

final userChatsProvider = StreamProvider<List<ChatThread>>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null || uid.isEmpty) {
    return Stream.value(const []);
  }
  return ref.watch(chatsRepositoryProvider).watchUserChats(uid);
});

final chatThreadProvider =
    StreamProvider.autoDispose.family<ChatThread?, String>((ref, chatId) {
  return ref.watch(chatsRepositoryProvider).watchChat(chatId);
});

final peerUserProfileProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, peerUid) {
  if (peerUid.isEmpty) return Stream.value(null);
  return ref.watch(chatsRepositoryProvider).watchUserProfile(peerUid);
});

typedef ChatMessagesQuery = ({String chatId, int limit});

final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, ChatMessagesQuery>((ref, query) {
  return ref.watch(chatsRepositoryProvider).watchMessages(
        chatId: query.chatId,
        limit: query.limit,
      );
});
