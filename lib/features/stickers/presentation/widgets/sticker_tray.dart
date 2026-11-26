import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/zapi_sticker.dart';
import '../providers/stickers_providers.dart';
import 'zapi_sticker_image.dart';

class _EmojiEntry {
  const _EmojiEntry(this.emoji, this.keywords);

  final String emoji;
  final String keywords;
}

class _EmojiCategory {
  const _EmojiCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.items,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<_EmojiEntry> items;
}

class StickerTray extends ConsumerStatefulWidget {
  const StickerTray({
    super.key,
    required this.onStickerSelected,
    this.onEmojiSelected,
  });

  final ValueChanged<ZapiSticker> onStickerSelected;
  final ValueChanged<String>? onEmojiSelected;

  @override
  ConsumerState<StickerTray> createState() => _StickerTrayState();
}

class _StickerTrayState extends ConsumerState<StickerTray>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _activeTab = 0;

  static const List<_EmojiCategory> _emojiCategories = [
    _EmojiCategory(
      id: 'expressoes',
      title: 'Expressões',
      icon: Icons.sentiment_satisfied_alt_rounded,
      items: [
        _EmojiEntry('😀', 'sorriso feliz alegre'),
        _EmojiEntry('😄', 'sorrindo feliz alegria'),
        _EmojiEntry('😁', 'sorriso dentes feliz'),
        _EmojiEntry('😆', 'risada rindo gargalhada'),
        _EmojiEntry('🥹', 'emocionado lagrima feliz'),
        _EmojiEntry('😂', 'chorando de rir riso comedia'),
        _EmojiEntry('🤣', 'rolando de rir gargalhada'),
        _EmojiEntry('😊', 'sorriso simpatico timido'),
        _EmojiEntry('😇', 'anjo inocente santo'),
        _EmojiEntry('🙂', 'leve sorriso ok'),
        _EmojiEntry('🙃', 'de cabeca para baixo ironia'),
        _EmojiEntry('😉', 'piscadinha piscando'),
        _EmojiEntry('😌', 'alivio calmo paz'),
        _EmojiEntry('😍', 'apaixonado coracao olhos'),
        _EmojiEntry('🥰', 'carinho amor coracoes'),
        _EmojiEntry('😘', 'beijo beijinho amor'),
        _EmojiEntry('😗', 'beijo'),
        _EmojiEntry('😋', 'delicia comida gostoso'),
        _EmojiEntry('😛', 'lingua brincadeira'),
        _EmojiEntry('😜', 'piscando lingua doido'),
        _EmojiEntry('🤪', 'maluco divertido zoeira'),
        _EmojiEntry('🤨', 'desconfiado sobrancelha'),
        _EmojiEntry('🧐', 'curioso monoculo investigando'),
        _EmojiEntry('🤓', 'nerd oculos inteligente'),
        _EmojiEntry('😎', 'oculos escuro estilo legal'),
        _EmojiEntry('🤩', 'estrelas deslumbrado incrivel'),
        _EmojiEntry('🥳', 'festa aniversario comemoracao'),
        _EmojiEntry('😏', 'sorriso maroto malicioso'),
        _EmojiEntry('😒', 'entediado chateado'),
        _EmojiEntry('😔', 'triste pensativo'),
        _EmojiEntry('😟', 'preocupado triste'),
        _EmojiEntry('😕', 'confuso duvida'),
        _EmojiEntry('🙁', 'triste chateado'),
        _EmojiEntry('😣', 'esforco tenso'),
        _EmojiEntry('😫', 'cansado exausto'),
        _EmojiEntry('😢', 'chorando lagrima triste'),
        _EmojiEntry('😭', 'chorando muito pranto'),
        _EmojiEntry('😤', 'bravo bufando raiva'),
        _EmojiEntry('😠', 'raiva bravo irritado'),
        _EmojiEntry('😡', 'muito bravo furioso'),
        _EmojiEntry('🤯', 'mente explodindo chocado'),
        _EmojiEntry('😳', 'vergonha corado surpreso'),
        _EmojiEntry('🥵', 'calor quente suando'),
        _EmojiEntry('🥶', 'frio congelando gelado'),
        _EmojiEntry('😱', 'medo susto grito'),
        _EmojiEntry('😨', 'assustado medo'),
        _EmojiEntry('🥺', 'pidonho olhinhos fofo'),
        _EmojiEntry('😬', 'sem graca nervoso'),
        _EmojiEntry('😴', 'sono dormindo zzz'),
        _EmojiEntry('😪', 'sonolento cansado'),
        _EmojiEntry('🤗', 'abraco carinho'),
        _EmojiEntry('🤔', 'pensando duvida reflexao'),
        _EmojiEntry('🤭', 'risadinha segredo mao boca'),
        _EmojiEntry('🤫', 'silencio segredo shhh'),
        _EmojiEntry('🫠', 'derretendo vergonha calor'),
        _EmojiEntry('🫡', 'continencia respeito'),
      ],
    ),
    _EmojiCategory(
      id: 'gestos',
      title: 'Gestos e mãos',
      icon: Icons.thumb_up_rounded,
      items: [
        _EmojiEntry('👍', 'joinha legal positivo ok sim'),
        _EmojiEntry('👎', 'negativo nao deslike'),
        _EmojiEntry('👏', 'palmas aplausos parabens'),
        _EmojiEntry('🙌', 'comemoracao maos alto'),
        _EmojiEntry('🫶', 'coracao maos amor'),
        _EmojiEntry('🤝', 'aperto de mao acordo fechado'),
        _EmojiEntry('🙏', 'por favor obrigado oracao'),
        _EmojiEntry('✌️', 'paz vitoria dois'),
        _EmojiEntry('🤞', 'dedos cruzados sorte'),
        _EmojiEntry('🤟', 'amor rock mao'),
        _EmojiEntry('🤘', 'rock'),
        _EmojiEntry('👌', 'ok perfeito beleza'),
        _EmojiEntry('🤌', 'italiano gesto'),
        _EmojiEntry('👋', 'tchau oi aceno'),
        _EmojiEntry('🤚', 'pare mao levantada'),
        _EmojiEntry('💪', 'forca musculo academia'),
        _EmojiEntry('☝️', 'atencao um dedo'),
        _EmojiEntry('👉', 'apontando direita'),
        _EmojiEntry('👈', 'apontando esquerda'),
        _EmojiEntry('👀', 'olhos olhando curioso'),
        _EmojiEntry('🧠', 'cerebro ideia mente'),
        _EmojiEntry('👑', 'coroa rei rainha'),
        _EmojiEntry('🔥', 'fogo quente top incrivel'),
        _EmojiEntry('✨', 'brilho estrelas magia'),
        _EmojiEntry('💥', 'explosao impacto'),
        _EmojiEntry('💯', 'cem por cento perfeito'),
        _EmojiEntry('🎉', 'festa confete parabens'),
        _EmojiEntry('🎊', 'comemoracao festa'),
        _EmojiEntry('🏆', 'trofeu campeao vitoria'),
        _EmojiEntry('⚡', 'raio energia rapido'),
      ],
    ),
    _EmojiCategory(
      id: 'coracoes',
      title: 'Corações e carinho',
      icon: Icons.favorite_rounded,
      items: [
        _EmojiEntry('❤️', 'coracao vermelho amor'),
        _EmojiEntry('🧡', 'coracao laranja'),
        _EmojiEntry('💛', 'coracao amarelo amizade'),
        _EmojiEntry('💚', 'coracao verde'),
        _EmojiEntry('💙', 'coracao azul'),
        _EmojiEntry('💜', 'coracao roxo'),
        _EmojiEntry('🩷', 'coracao rosa'),
        _EmojiEntry('🩵', 'coracao azul claro'),
        _EmojiEntry('🤍', 'coracao branco paz'),
        _EmojiEntry('🖤', 'coracao preto'),
        _EmojiEntry('💔', 'coracao partido tristeza'),
        _EmojiEntry('❤️‍🔥', 'coracao em chamas paixao'),
        _EmojiEntry('💖', 'coracao brilhando amor'),
        _EmojiEntry('💘', 'coracao flecha cupido'),
        _EmojiEntry('💝', 'coracao presente'),
        _EmojiEntry('💞', 'coracoes girando'),
        _EmojiEntry('💋', 'beijo batom'),
        _EmojiEntry('🌹', 'rosa flor romance'),
        _EmojiEntry('💐', 'buque flores'),
        _EmojiEntry('☀️', 'sol dia bom dia'),
        _EmojiEntry('🌙', 'lua boa noite'),
        _EmojiEntry('⭐', 'estrela favorito'),
        _EmojiEntry('🌈', 'arco iris'),
      ],
    ),
    _EmojiCategory(
      id: 'natureza',
      title: 'Animais e natureza',
      icon: Icons.pets_rounded,
      items: [
        _EmojiEntry('🐶', 'cachorro cao pet'),
        _EmojiEntry('🐱', 'gato gatinho pet'),
        _EmojiEntry('🐭', 'rato'),
        _EmojiEntry('🐰', 'coelho'),
        _EmojiEntry('🦊', 'raposa'),
        _EmojiEntry('🐻', 'urso'),
        _EmojiEntry('🐼', 'panda'),
        _EmojiEntry('🦁', 'leao'),
        _EmojiEntry('🐸', 'sapo'),
        _EmojiEntry('🐵', 'macaco'),
        _EmojiEntry('🐧', 'pinguim'),
        _EmojiEntry('🦋', 'borboleta'),
        _EmojiEntry('🐝', 'abelha'),
        _EmojiEntry('🐢', 'tartaruga'),
        _EmojiEntry('🐬', 'golfinho'),
        _EmojiEntry('🌸', 'flor cerejeira'),
        _EmojiEntry('🌻', 'girassol'),
        _EmojiEntry('🍀', 'trevo sorte'),
        _EmojiEntry('🌴', 'praia palmeira'),
        _EmojiEntry('🌊', 'onda mar praia'),
        _EmojiEntry('☔', 'chuva guarda chuva'),
        _EmojiEntry('❄️', 'neve frio'),
      ],
    ),
    _EmojiCategory(
      id: 'comidas',
      title: 'Comidas e bebidas',
      icon: Icons.restaurant_rounded,
      items: [
        _EmojiEntry('☕', 'cafe manha xicara'),
        _EmojiEntry('🍵', 'cha verde'),
        _EmojiEntry('🧃', 'suco caixinha'),
        _EmojiEntry('🍺', 'cerveja bar'),
        _EmojiEntry('🥂', 'brinde festa taca'),
        _EmojiEntry('🍕', 'pizza lanche'),
        _EmojiEntry('🍔', 'hamburguer lanche'),
        _EmojiEntry('🍟', 'batata frita'),
        _EmojiEntry('🌭', 'cachorro quente'),
        _EmojiEntry('🌮', 'taco'),
        _EmojiEntry('🍣', 'sushi japones'),
        _EmojiEntry('🍝', 'macarrao massa'),
        _EmojiEntry('🍰', 'bolo fatia doce'),
        _EmojiEntry('🎂', 'bolo aniversario festa'),
        _EmojiEntry('🍫', 'chocolate doce'),
        _EmojiEntry('🍦', 'sorvete'),
        _EmojiEntry('🍿', 'pipoca filme'),
        _EmojiEntry('🍓', 'morango fruta'),
        _EmojiEntry('🍉', 'melancia fruta'),
        _EmojiEntry('🥑', 'abacate'),
      ],
    ),
    _EmojiCategory(
      id: 'lazer',
      title: 'Lazer e esportes',
      icon: Icons.sports_soccer_rounded,
      items: [
        _EmojiEntry('⚽', 'futebol bola gol'),
        _EmojiEntry('🏀', 'basquete bola'),
        _EmojiEntry('🎮', 'videogame jogo controle'),
        _EmojiEntry('🎧', 'fone musica som'),
        _EmojiEntry('🎵', 'musica nota som'),
        _EmojiEntry('🎸', 'guitarra violao rock'),
        _EmojiEntry('🎬', 'cinema filme'),
        _EmojiEntry('📸', 'camera foto'),
        _EmojiEntry('✈️', 'aviao viagem ferias'),
        _EmojiEntry('🚗', 'carro viagem'),
        _EmojiEntry('🚲', 'bicicleta bike'),
        _EmojiEntry('🏖️', 'praia sol ferias'),
        _EmojiEntry('🎁', 'presente surpresa'),
        _EmojiEntry('🎈', 'balao festa'),
        _EmojiEntry('🎯', 'alvo foco meta'),
        _EmojiEntry('🎲', 'dado jogo sorte'),
      ],
    ),
    _EmojiCategory(
      id: 'objetos',
      title: 'Objetos e símbolos',
      icon: Icons.lightbulb_rounded,
      items: [
        _EmojiEntry('💡', 'ideia lampada dica'),
        _EmojiEntry('📱', 'celular telefone'),
        _EmojiEntry('💻', 'notebook computador trabalho'),
        _EmojiEntry('⌚', 'relogio hora'),
        _EmojiEntry('📚', 'livros estudo ler'),
        _EmojiEntry('📝', 'nota escrever texto'),
        _EmojiEntry('🔒', 'cadeado seguranca privado'),
        _EmojiEntry('🔑', 'chave'),
        _EmojiEntry('💰', 'dinheiro'),
        _EmojiEntry('📅', 'calendario data agenda'),
        _EmojiEntry('📍', 'localizacao mapa ponto'),
        _EmojiEntry('🔔', 'sino notificacao alerta'),
        _EmojiEntry('✅', 'certo concluido check'),
        _EmojiEntry('❌', 'erro cancelar x'),
        _EmojiEntry('⚠️', 'aviso atencao alerta'),
        _EmojiEntry('❓', 'duvida pergunta'),
        _EmojiEntry('❗', 'exclamacao importante'),
        _EmojiEntry('💬', 'conversa mensagem balao'),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 0);
    _tabController.addListener(() {
      if (_tabController.index != _activeTab && mounted) {
        setState(() => _activeTab = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showStickerOptions(ZapiSticker sticker) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  sticker.isFavorite
                      ? Icons.star_border_rounded
                      : Icons.star_rounded,
                  color: Colors.amber,
                ),
                title: Text(
                  sticker.isFavorite
                      ? 'Remover das favoritas'
                      : 'Adicionar às favoritas',
                ),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await ref.read(stickersRepositoryProvider).toggleFavorite(
                          uid: uid,
                          sticker: sticker,
                        );
                  } on AppException catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  }
                },
              ),
              if (!sticker.isBuiltIn)
                ListTile(
                  leading: Icon(
                    Icons.delete_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Excluir figurinha',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      await ref
                          .read(stickersRepositoryProvider)
                          .deleteCustomSticker(uid: uid, sticker: sticker);
                    } on AppException catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final allStickers = ref.watch(allAvailableStickersProvider);
    final recentIds = ref.watch(recentStickerIdsProvider);
    final byId = {for (final s in allStickers) s.id: s};

    final recents = recentIds
        .map((id) => byId[id])
        .whereType<ZapiSticker>()
        .toList();
    final favorites = allStickers.where((s) => s.isFavorite).toList();

    return Container(
      height: 332,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor:
                      isDark ? AppColors.emeraldBright : AppColors.emeraldDark,
                  unselectedLabelColor: secondaryText,
                  indicatorColor: AppColors.emerald,
                  dividerHeight: 0.5,
                  tabs: const [
                    Tab(text: 'Emojis'),
                    Tab(text: 'Recentes'),
                    Tab(text: 'Favoritas'),
                    Tab(text: 'Figurinhas'),
                  ],
                ),
              ),
              if (_activeTab != 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton.icon(
                    onPressed: () async {
                      final created =
                          await context.push<ZapiSticker>('/stickers/create');
                      if (created != null && mounted) {
                        ref
                            .read(recentStickerIdsProvider.notifier)
                            .markUsed(created);
                        widget.onStickerSelected(created);
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Criar'),
                  ),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _EmojiPickerView(
                  categories: _emojiCategories,
                  onSelected: (emoji) {
                    HapticFeedback.selectionClick();
                    widget.onEmojiSelected?.call(emoji);
                  },
                ),
                _StickerGrid(
                  stickers: recents,
                  emptyText:
                      'Suas figurinhas enviadas recentemente aparecerão aqui.',
                  onTap: (s) {
                    ref.read(recentStickerIdsProvider.notifier).markUsed(s);
                    widget.onStickerSelected(s);
                  },
                  onLongPress: _showStickerOptions,
                ),
                _StickerGrid(
                  stickers: favorites,
                  emptyText:
                      'Segure qualquer figurinha na bandeja para adicioná-la às favoritas.',
                  onTap: (s) {
                    ref.read(recentStickerIdsProvider.notifier).markUsed(s);
                    widget.onStickerSelected(s);
                  },
                  onLongPress: _showStickerOptions,
                ),
                _StickerGrid(
                  stickers: allStickers,
                  emptyText:
                      'Toque em "Criar" para fazer sua primeira figurinha.',
                  onTap: (s) {
                    ref.read(recentStickerIdsProvider.notifier).markUsed(s);
                    widget.onStickerSelected(s);
                  },
                  onLongPress: _showStickerOptions,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiPickerView extends StatefulWidget {
  const _EmojiPickerView({
    required this.categories,
    required this.onSelected,
  });

  final List<_EmojiCategory> categories;
  final ValueChanged<String> onSelected;

  @override
  State<_EmojiPickerView> createState() => _EmojiPickerViewState();
}

class _EmojiPickerViewState extends State<_EmojiPickerView> {
  static List<String>? _memoryRecents;

  final TextEditingController _searchController = TextEditingController();
  String _selectedCategoryId = 'all';
  String _query = '';
  List<String> _recentEmojis = const [];

  @override
  void initState() {
    super.initState();
    if (_memoryRecents != null) {
      _recentEmojis = List<String>.from(_memoryRecents!);
    } else {
      unawaited(_loadRecents());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<File> _recentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'zapi_recent_emojis_v1.json'));
  }

  Future<void> _loadRecents() async {
    try {
      final file = await _recentsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        final list = decoded.whereType<String>().take(24).toList();
        _memoryRecents = list;
        if (mounted) {
          setState(() => _recentEmojis = list);
        }
      }
    } catch (_) {}
  }

  Future<void> _recordEmojiUse(String emoji) async {
    final updated = [
      emoji,
      ..._recentEmojis.where((e) => e != emoji),
    ].take(24).toList();
    _memoryRecents = updated;
    if (mounted) {
      setState(() => _recentEmojis = updated);
    }
    try {
      final file = await _recentsFile();
      await file.writeAsString(jsonEncode(updated), flush: true);
    } catch (_) {}
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .trim();
  }

  void _handleEmojiTap(String emoji) {
    widget.onSelected(emoji);
    unawaited(_recordEmojiUse(emoji));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final fieldBg =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final accent = isDark ? AppColors.emeraldBright : AppColors.emeraldDark;

    final normalizedQuery = _normalize(_query);

    final List<({String title, List<String> emojis})> visibleSections = [];
    if (normalizedQuery.isNotEmpty) {
      final seen = <String>{};
      final matches = <String>[];
      for (final category in widget.categories) {
        for (final entry in category.items) {
          if (seen.contains(entry.emoji)) continue;
          if (_normalize(entry.keywords).contains(normalizedQuery) ||
              _normalize(category.title).contains(normalizedQuery) ||
              entry.emoji.contains(normalizedQuery)) {
            seen.add(entry.emoji);
            matches.add(entry.emoji);
          }
        }
      }
      if (matches.isNotEmpty) {
        visibleSections.add((title: 'Resultados', emojis: matches));
      }
    } else if (_selectedCategoryId == 'recentes') {
      if (_recentEmojis.isNotEmpty) {
        visibleSections.add((title: 'Recentes', emojis: _recentEmojis));
      }
    } else if (_selectedCategoryId == 'all') {
      if (_recentEmojis.isNotEmpty) {
        visibleSections.add((title: 'Recentes', emojis: _recentEmojis));
      }
      for (final category in widget.categories) {
        visibleSections.add((
          title: category.title,
          emojis: category.items.map((e) => e.emoji).toList(),
        ));
      }
    } else {
      for (final category in widget.categories) {
        if (category.id == _selectedCategoryId) {
          visibleSections.add((
            title: category.title,
            emojis: category.items.map((e) => e.emoji).toList(),
          ));
        }
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Buscar emoji...',
                hintStyle: TextStyle(fontSize: 13.5, color: secondaryText),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: secondaryText,
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: secondaryText,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: fieldBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (normalizedQuery.isEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _CategoryIconButton(
                  icon: Icons.apps_rounded,
                  tooltip: 'Todos',
                  selected: _selectedCategoryId == 'all',
                  accent: accent,
                  secondaryText: secondaryText,
                  onTap: () => setState(() => _selectedCategoryId = 'all'),
                ),
                _CategoryIconButton(
                  icon: Icons.schedule_rounded,
                  tooltip: 'Recentes',
                  selected: _selectedCategoryId == 'recentes',
                  accent: accent,
                  secondaryText: secondaryText,
                  onTap: () => setState(() => _selectedCategoryId = 'recentes'),
                ),
                ...widget.categories.map(
                  (category) => _CategoryIconButton(
                    icon: category.icon,
                    tooltip: category.title,
                    selected: _selectedCategoryId == category.id,
                    accent: accent,
                    secondaryText: secondaryText,
                    onTap: () =>
                        setState(() => _selectedCategoryId = category.id),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: visibleSections.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      normalizedQuery.isNotEmpty
                          ? 'Nenhum emoji encontrado para "$_query".'
                          : 'Os emojis que você usar aparecerão aqui.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryText, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                  itemCount: visibleSections.length,
                  itemBuilder: (context, sectionIndex) {
                    final section = visibleSections[sectionIndex];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                          child: Text(
                            section.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: secondaryText,
                            ),
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 8,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: section.emojis.length,
                          itemBuilder: (context, index) {
                            final emoji = section.emojis[index];
                            return _AnimatedEmojiCell(
                              emoji: emoji,
                              onTap: () => _handleEmojiTap(emoji),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CategoryIconButton extends StatelessWidget {
  const _CategoryIconButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.accent,
    required this.secondaryText,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color accent;
  final Color secondaryText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.emerald.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 19,
            color: selected ? accent : secondaryText,
          ),
        ),
      ),
    );
  }
}

class _AnimatedEmojiCell extends StatefulWidget {
  const _AnimatedEmojiCell({
    required this.emoji,
    required this.onTap,
  });

  final String emoji;
  final VoidCallback onTap;

  @override
  State<_AnimatedEmojiCell> createState() => _AnimatedEmojiCellState();
}

class _AnimatedEmojiCellState extends State<_AnimatedEmojiCell> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 1.28),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: Center(
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutBack,
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 25),
          ),
        ),
      ),
    );
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({
    required this.stickers,
    required this.emptyText,
    required this.onTap,
    required this.onLongPress,
  });

  final List<ZapiSticker> stickers;
  final String emptyText;
  final ValueChanged<ZapiSticker> onTap;
  final ValueChanged<ZapiSticker> onLongPress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    if (stickers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(color: secondaryText, fontSize: 13.5),
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap(sticker),
          onLongPress: () => onLongPress(sticker),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: ZapiStickerImage(
                  assetPath: sticker.assetPath,
                  dataBase64: sticker.dataBase64,
                  mimeType: sticker.mimeType,
                  size: 72,
                ),
              ),
              if (sticker.isFavorite)
                const Positioned(
                  right: 2,
                  bottom: 2,
                  child: Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: Colors.amber,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
