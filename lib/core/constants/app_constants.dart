class AppConstants {
  AppConstants._();

  static const String appName = 'Zapi';
  static const String appTagline = 'Mensagens rápidas, limpas e seguras.';
  static const String defaultAbout = 'Olá! Estou usando o Zapi.';

  static const String usersCollection = 'users';
  static const String usernamesCollection = 'usernames';
  static const String publicIdsCollection = 'publicIds';
  static const String privateSubcollection = 'private';
  static const String privateAccountDoc = 'account';
  static const String contactsSubcollection = 'contacts';
  static const String chatsCollection = 'chats';
  static const String messagesSubcollection = 'messages';
  static const String mediaSubcollection = 'media';
  static const String stickersSubcollection = 'stickers';
  static const String statusesCollection = 'statuses';
  static const String statusViewsSubcollection = 'views';

  // Caminho para presença em tempo real
  static const String rtdbPresencePath = 'presence';

  // Canais de notificação Android para mensagens (combinações de som e vibração)
  static const String messagesChannelSoundVibrateId = 'zapi_messages_sv';
  static const String messagesChannelSoundOnlyId = 'zapi_messages_s';
  static const String messagesChannelVibrateOnlyId = 'zapi_messages_v';
  static const String messagesChannelSilentId = 'zapi_messages_silent';
  static const String messagesNotificationChannelName = 'Mensagens';
  static const String messagesNotificationChannelDesc =
      'Notificações de novas mensagens recebidas.';

  static String notificationChannelId({
    required bool sound,
    required bool vibration,
  }) {
    if (sound && vibration) return messagesChannelSoundVibrateId;
    if (sound) return messagesChannelSoundOnlyId;
    if (vibration) return messagesChannelVibrateOnlyId;
    return messagesChannelSilentId;
  }

  // Paginação e limites de chat
  static const int messagesPageSize = 30;
  static const int maxMessageLength = 4000;
  static const Duration typingTimeout = Duration(seconds: 5);

  // Limites internos de mídia e perfil
  static const int maxProfilePhotoDimension = 256;
  static const int maxProfilePhotoBytes = 100 * 1024;
  static const int maxProfileBannerWidth = 960;
  static const int maxProfileBannerBytes = 320 * 1024;
  static const int maxProfileBannerBase64Chars = 440000;
  static const int maxDisplayNameLength = 50;
  static const int maxAboutLength = 140;

  static const int maxImageDimension = 1280;
  static const int imageJpegQuality = 82;
  static const int thumbnailMaxDimension = 320;
  static const int thumbnailJpegQuality = 72;
  static const int maxThumbnailBytes = 26 * 1024;
  static const int maxChatImageBytes = 700 * 1024;

  // Limites de Status (expiração em 24h)
  static const int maxStatusTextLength = 500;
  static const int maxStatusImageBytes = 450 * 1024;
  static const int maxStatusImageBase64Chars = 620000;
  static const int maxStatusVideoBytes = 700 * 1024;
  static const int maxStatusVideoBase64Chars = 960000;
  static const Duration maxStatusVideoDuration = Duration(seconds: 30);
  static const int statusDurationHours = 24;

  static const String defaultBannerPreset = 'aurora';

  static const int audioBitRate = 64000;
  static const int audioSampleRate = 44100;
  static const Duration maxAudioDuration = Duration(minutes: 3);
  static const int maxChatAudioBytes = 900 * 1024;
  static const int maxChatFileBytes = 680 * 1024;
  static const int maxChatVideoBytes = 700 * 1024;
  static const int maxFirestoreMediaBase64Chars = 980000;

  static const int stickerSizePx = 512;
  static const int maxStickerBytes = 100 * 1024;
}
