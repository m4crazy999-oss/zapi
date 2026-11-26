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

  // Caminho para presença em tempo real
  static const String rtdbPresencePath = 'presence';

  // Canal de notificação Android para mensagens
  static const String messagesNotificationChannelId = 'zapi_messages_v2';
  static const String messagesNotificationChannelName = 'Mensagens';
  static const String messagesNotificationChannelDesc =
      'Notificações de novas mensagens recebidas.';

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

  static const String defaultBannerPreset = 'aurora';

  static const int audioBitRate = 24000;
  static const int audioSampleRate = 24000;
  static const Duration maxAudioDuration = Duration(minutes: 3);
  static const int maxChatAudioBytes = 900 * 1024;
  static const int maxFirestoreMediaBase64Chars = 980000;

  static const int stickerSizePx = 512;
  static const int maxStickerBytes = 100 * 1024;

  // Figurinhas originais empacotadas no aplicativo
  static const List<({String id, String label, String assetPath})>
      builtInStickers = [
    (id: 'builtin_oi', label: 'Oi!', assetPath: 'asset://assets/stickers/zapi_oi.png'),
    (id: 'builtin_feliz', label: 'Feliz', assetPath: 'asset://assets/stickers/zapi_feliz.png'),
    (id: 'builtin_coracao', label: 'Coração', assetPath: 'asset://assets/stickers/zapi_coracao.png'),
    (id: 'builtin_riso', label: 'Riso', assetPath: 'asset://assets/stickers/zapi_riso.png'),
    (id: 'builtin_apaixonado', label: 'Apaixonado', assetPath: 'asset://assets/stickers/zapi_apaixonado.png'),
    (id: 'builtin_surpreso', label: 'Surpreso', assetPath: 'asset://assets/stickers/zapi_surpreso.png'),
    (id: 'builtin_piscadinha', label: 'Piscadinha', assetPath: 'asset://assets/stickers/zapi_piscadinha.png'),
    (id: 'builtin_joinha', label: 'Joinha', assetPath: 'asset://assets/stickers/zapi_joinha.png'),
    (id: 'builtin_festa', label: 'Festa', assetPath: 'asset://assets/stickers/zapi_festa.png'),
    (id: 'builtin_cafe', label: 'Café', assetPath: 'asset://assets/stickers/zapi_cafe.png'),
    (id: 'builtin_fogo', label: 'Fogo', assetPath: 'asset://assets/stickers/zapi_fogo.png'),
    (id: 'builtin_ok', label: 'OK!', assetPath: 'asset://assets/stickers/zapi_ok.png'),
  ];
}
