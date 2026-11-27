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
import '../../../../core/utils/zapi_toast.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/unicode_emoji_data.dart';
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

  Future<void> _openCreateSticker() async {
    final created = await context.push<ZapiSticker>('/stickers/create');
    if (created != null && mounted) {
      ref.read(recentStickerIdsProvider.notifier).markUsed(created);
      widget.onStickerSelected(created);
    }
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
                    ZapiToast.showError(context, e.message, bottomOffset: 80);
                  }
                },
              ),
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
                    ZapiToast.showError(context, e.message, bottomOffset: 80);
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
                    onPressed: _openCreateSticker,
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
                  onSelected: (emoji) {
                    HapticFeedback.selectionClick();
                    widget.onEmojiSelected?.call(emoji);
                  },
                ),
                _StickerGrid(
                  stickers: recents,
                  emptyText:
                      'Suas figurinhas criadas e usadas aparecerão aqui.',
                  onTap: (s) {
                    ref.read(recentStickerIdsProvider.notifier).markUsed(s);
                    widget.onStickerSelected(s);
                  },
                  onLongPress: _showStickerOptions,
                ),
                _StickerGrid(
                  stickers: favorites,
                  emptyText:
                      'Segure qualquer figurinha sua para adicioná-la às favoritas.',
                  onTap: (s) {
                    ref.read(recentStickerIdsProvider.notifier).markUsed(s);
                    widget.onStickerSelected(s);
                  },
                  onLongPress: _showStickerOptions,
                ),
                _StickerGrid(
                  stickers: allStickers,
                  emptyText:
                      'Crie suas próprias figurinhas com fotos da galeria ou da câmera.',
                  emptyActionLabel: 'Criar figurinha',
                  onCreatePressed: _openCreateSticker,
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
    required this.onSelected,
  });

  final ValueChanged<String> onSelected;

  @override
  State<_EmojiPickerView> createState() => _EmojiPickerViewState();
}

class _EmojiPickerViewState extends State<_EmojiPickerView> {
  static List<String>? _memoryRecents;
  static int? _memoryToneIndex;

  final TextEditingController _searchController = TextEditingController();
  String _selectedCategoryId = 'all';
  String _query = '';
  List<String> _recentEmojis = const [];
  int _selectedToneIndex = 0;
  bool _showToneBar = false;

  @override
  void initState() {
    super.initState();
    if (_memoryRecents != null) {
      _recentEmojis = List<String>.from(_memoryRecents!);
    } else {
      unawaited(_loadRecents());
    }

    if (_memoryToneIndex != null) {
      _selectedToneIndex = _memoryToneIndex!;
    } else {
      unawaited(_loadSkinTone());
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

  Future<File> _toneFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'zapi_emoji_tone_v1.json'));
  }

  Future<void> _loadRecents() async {
    try {
      final file = await _recentsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        final list = decoded.whereType<String>().take(32).toList();
        _memoryRecents = list;
        if (mounted) {
          setState(() => _recentEmojis = list);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSkinTone() async {
    try {
      final file = await _toneFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is int &&
          decoded >= 0 &&
          decoded < UnicodeEmojiCatalog.skinTones.length) {
        _memoryToneIndex = decoded;
        if (mounted) {
          setState(() => _selectedToneIndex = decoded);
        }
      }
    } catch (_) {}
  }

  Future<void> _setSkinTone(int index) async {
    _memoryToneIndex = index;
    setState(() {
      _selectedToneIndex = index;
      _showToneBar = false;
    });
    try {
      final file = await _toneFile();
      await file.writeAsString(jsonEncode(index), flush: true);
    } catch (_) {}
  }

  Future<void> _recordEmojiUse(String emoji) async {
    final updated = [
      emoji,
      ..._recentEmojis.where((e) => e != emoji),
    ].take(32).toList();
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

  String _renderedEmoji(EmojiEntry entry) {
    final modifier = UnicodeEmojiCatalog.skinTones[_selectedToneIndex].modifier;
    return UnicodeEmojiCatalog.applySkinTone(
      entry.emoji,
      modifier,
      supportsSkinTone: entry.supportsSkinTone,
    );
  }

  void _handleEmojiTap(String emoji) {
    widget.onSelected(emoji);
    unawaited(_recordEmojiUse(emoji));
  }

  Future<void> _showToneOptions(EmojiEntry entry) async {
    if (!entry.supportsSkinTone) return;
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogCtx) {
        return Center(
          child: Material(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: UnicodeEmojiCatalog.skinTones.map((tone) {
                  final variant = UnicodeEmojiCatalog.applySkinTone(
                    entry.emoji,
                    tone.modifier,
                    supportsSkinTone: true,
                  );
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(dialogCtx);
                      _handleEmojiTap(variant);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        variant,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
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
    final fieldBg =
        isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final accent = isDark ? AppColors.emeraldBright : AppColors.emeraldDark;
    final currentTone = UnicodeEmojiCatalog.skinTones[_selectedToneIndex];

    final normalizedQuery = _normalize(_query);

    final List<({String title, List<EmojiEntry> entries})> visibleSections = [];
    if (normalizedQuery.isNotEmpty) {
      final seen = <String>{};
      final matches = <EmojiEntry>[];
      for (final category in UnicodeEmojiCatalog.categories) {
        for (final entry in category.items) {
          if (seen.contains(entry.emoji)) continue;
          if (_normalize(entry.keywords).contains(normalizedQuery) ||
              _normalize(category.title).contains(normalizedQuery) ||
              entry.emoji.contains(normalizedQuery)) {
            seen.add(entry.emoji);
            matches.add(entry);
          }
        }
      }
      if (matches.isNotEmpty) {
        visibleSections.add((title: 'Resultados', entries: matches));
      }
    } else if (_selectedCategoryId == 'recentes') {
      if (_recentEmojis.isNotEmpty) {
        visibleSections.add((
          title: 'Recentes',
          entries: _recentEmojis.map((e) => EmojiEntry(e, '')).toList(),
        ));
      }
    } else if (_selectedCategoryId == 'all') {
      if (_recentEmojis.isNotEmpty) {
        visibleSections.add((
          title: 'Recentes',
          entries: _recentEmojis.map((e) => EmojiEntry(e, '')).toList(),
        ));
      }
      for (final category in UnicodeEmojiCatalog.categories) {
        visibleSections.add((
          title: category.title,
          entries: category.items,
        ));
      }
    } else {
      for (final category in UnicodeEmojiCatalog.categories) {
        if (category.id == _selectedCategoryId) {
          visibleSections.add((
            title: category.title,
            entries: category.items,
          ));
        }
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Buscar emoji...',
                      hintStyle:
                          TextStyle(fontSize: 13.5, color: secondaryText),
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
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
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
              const SizedBox(width: 8),
              Tooltip(
                message: 'Tom de pele (${currentTone.label})',
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _showToneBar = !_showToneBar),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: fieldBg,
                      shape: BoxShape.circle,
                      border: _showToneBar
                          ? Border.all(color: AppColors.emerald, width: 1.6)
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: currentTone.swatch,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.18),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: _showToneBar
              ? Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tom de pele',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondaryText,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          UnicodeEmojiCatalog.skinTones.length,
                          (i) {
                            final tone = UnicodeEmojiCatalog.skinTones[i];
                            final selected = i == _selectedToneIndex;
                            return Tooltip(
                              message: tone.label,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _setSkinTone(i),
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tone.swatch,
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.emerald
                                          : Colors.black.withValues(alpha: 0.18),
                                      width: selected ? 2.4 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
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
                ...UnicodeEmojiCatalog.categories.map(
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
                          itemCount: section.entries.length,
                          itemBuilder: (context, index) {
                            final entry = section.entries[index];
                            final rendered = _renderedEmoji(entry);
                            return _AnimatedEmojiCell(
                              emoji: rendered,
                              onTap: () => _handleEmojiTap(rendered),
                              onLongPress: entry.supportsSkinTone
                                  ? () => _showToneOptions(entry)
                                  : null,
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
    this.onLongPress,
  });

  final String emoji;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

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
      onLongPress: widget.onLongPress,
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
    this.emptyActionLabel,
    this.onCreatePressed,
  });

  final List<ZapiSticker> stickers;
  final String emptyText;
  final ValueChanged<ZapiSticker> onTap;
  final ValueChanged<ZapiSticker> onLongPress;
  final String? emptyActionLabel;
  final VoidCallback? onCreatePressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    if (stickers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emptyText,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondaryText, fontSize: 13.5),
              ),
              if (emptyActionLabel != null && onCreatePressed != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onCreatePressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  icon: const Icon(Icons.add_reaction_rounded, size: 18),
                  label: Text(emptyActionLabel!),
                ),
              ],
            ],
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
