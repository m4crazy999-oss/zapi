import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen({
    super.key,
    required this.initialPaths,
    required this.recipientName,
  });

  final List<String> initialPaths;
  final String recipientName;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  late final PageController _pageController;
  late final List<String> _paths;
  late final List<TextEditingController> _captionControllers;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _paths = List<String>.from(widget.initialPaths);
    _captionControllers = List.generate(
      _paths.length,
      (_) => TextEditingController(),
    );
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _captionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _removeCurrent() {
    if (_paths.length <= 1) {
      Navigator.pop(context);
      return;
    }

    final removeIndex = _currentIndex;
    setState(() {
      _paths.removeAt(removeIndex);
      final removedCtrl = _captionControllers.removeAt(removeIndex);
      removedCtrl.dispose();
      if (_currentIndex >= _paths.length) {
        _currentIndex = _paths.length - 1;
      }
    });
    _pageController.jumpToPage(_currentIndex);
  }

  void _sendAll() {
    final result = <({String sourcePath, String caption})>[];
    for (var i = 0; i < _paths.length; i++) {
      result.add((
        sourcePath: _paths[i],
        caption: _captionControllers[i].text.trim(),
      ));
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _paths.length > 1
              ? 'Foto ${_currentIndex + 1} de ${_paths.length}'
              : 'Enviar para ${widget.recipientName}',
          style: const TextStyle(fontSize: 16.5),
        ),
        actions: [
          if (_paths.length > 1)
            IconButton(
              onPressed: _removeCurrent,
              tooltip: 'Remover esta foto',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _paths.length,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 3.5,
                  child: Center(
                    child: Image.file(
                      File(_paths[index]),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_paths.length > 1)
            SizedBox(
              height: 62,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _paths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final selected = index == _currentIndex;
                  return GestureDetector(
                    onTap: () => _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? AppColors.emerald : Colors.white24,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(
                        File(_paths[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.black.withValues(alpha: 0.78),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionControllers[_currentIndex],
                      maxLength: AppConstants.maxMessageLength,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Adicione uma legenda...',
                        hintStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: const Color(0xFF1F2C34),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: FilledButton(
                      onPressed: _sendAll,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send_rounded, size: 22),
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
