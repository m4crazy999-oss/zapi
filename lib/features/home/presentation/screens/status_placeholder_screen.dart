import 'package:flutter/material.dart';
import '../../../../core/widgets/empty_feature_placeholder.dart';

class StatusPlaceholderScreen extends StatelessWidget {
  const StatusPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status')),
      body: const EmptyFeaturePlaceholder(
        icon: Icons.donut_large_rounded,
        title: 'Nenhuma atualização de Status',
        subtitle:
            'Em breve você poderá compartilhar fotos e atualizações rápidas com seus contatos.',
      ),
    );
  }
}
