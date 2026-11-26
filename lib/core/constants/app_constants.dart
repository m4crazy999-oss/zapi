class AppConstants {
  AppConstants._();

  static const String appName = 'Zapi';
  static const String appTagline = 'Mensagens rápidas, limpas e seguras.';
  static const String defaultAbout = 'Olá! Estou usando o Zapi.';

  static const String usersCollection = 'users';
  static const String usernamesCollection = 'usernames';
  static const String contactsSubcollection = 'contacts';
  static const String chatsCollection = 'chats';
  static const String messagesSubcollection = 'messages';
  static const String mediaSubcollection = 'media';
  static const String stickersSubcollection = 'stickers';

  // Caminho no Realtime Database para presença em tempo real
  static const String rtdbPresencePath = 'presence';

  // Canal de notificação Android para mensagens locais (plano gratuito Spark)
  static const String messagesNotificationChannelId = 'zapi_messages';
  static const String messagesNotificationChannelName = 'Mensagens';
  static const String messagesNotificationChannelDesc =
      'Notificações locais de novas mensagens enquanto o Zapi estiver ativo.';

  // Paginação e limites de chat
  static const int messagesPageSize = 30;
  static const int maxMessageLength = 4000;
  static const Duration typingTimeout = Duration(seconds: 5);

  // Limites para persistência 100% em Firestore (Plano Spark sem Storage)
  static const int maxProfilePhotoDimension = 256;
  static const int maxProfilePhotoBytes = 100 * 1024;
  static const int maxDisplayNameLength = 50;
  static const int maxAboutLength = 140;

  // Limites de mídia em documentos dedicados (chats/{chatId}/media/{mediaId})
  static const int maxImageDimension = 1280;
  static const int imageJpegQuality = 82;
  static const int thumbnailMaxDimension = 180;
  static const int thumbnailJpegQuality = 55;
  static const int maxThumbnailBytes = 20 * 1024;
  static const int maxChatImageBytes = 700 * 1024;

  // Limites de áudio (AAC ~24 kbps, máx. 3 minutos, < 900 KB e abaixo do teto de 1 MiB em base64)
  static const int audioBitRate = 24000;
  static const int audioSampleRate = 24000;
  static const Duration maxAudioDuration = Duration(minutes: 3);
  static const int maxChatAudioBytes = 900 * 1024;
  static const int maxFirestoreMediaBase64Chars = 980000;

  // Limites de figurinhas (WebP 512x512 < 100 KB)
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
