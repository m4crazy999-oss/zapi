import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/zapi_sticker.dart';
import '../providers/stickers_providers.dart';
import 'zapi_sticker_image.dart';

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

  static const List<({String title, List<String> items})> _emojiGroups = [
    (
      title: 'Expressões',
      items: [
        '😀', '😄', '😁', '😆', '🥹', '😂', '🤣', '😊',
        '😇', '🙂', '😉', '😌', '😍', '🥰', '😘', '😋',
        '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🤩', '🥳',
        '😏', '😒', '😔', '😢', '😭', '😤', '🤯', '😳',
        '🥺', '😬', '😴', '🤗', '🤔', '🤭', '🤫', '🫠',
      ],
    ),
    (
      title: 'Gestos e reações',
      items: [
        '👍', '👎', '👏', '🙌', '🫶', '🤝', '🙏', '✌️',
        '🤞', '🤟', '👌', '🤌', '👋', '💪', '👀', '🔥',
        '✨', '💥', '💯', '🎉', '🎊', '🏆', '⚡', '☕',
      ],
    ),
    (
      title: 'Corações e carinho',
      items: [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🩷', '🤍',
        '🖤', '💔', '❤️‍🔥', '💖', '💘', '💝', '🌹', '☀️',
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
                    Icons.delete_outline_rounded,
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
      height: 312,
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
                  groups: _emojiGroups,
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

class _EmojiPickerView extends StatelessWidget {
  const _EmojiPickerView({
    required this.groups,
    required this.onSelected,
  });

  final List<({String title, List<String> items})> groups;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Text(
                group.title,
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
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: group.items.length,
              itemBuilder: (context, index) {
                return _AnimatedEmojiCell(
                  emoji: group.items[index],
                  onTap: () => onSelected(group.items[index]),
                );
              },
            ),
          ],
        );
      },
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
