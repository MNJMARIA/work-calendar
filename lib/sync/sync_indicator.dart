// Маленький значок хмари біля налаштувань: показує стан синхронізації.

import 'package:flutter/material.dart';

import '../services.dart';
import 'sync_service.dart';

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = AppServicesScope.of(context).sync;
    if (sync == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final IconData icon;
        final String tip;
        switch (sync.status) {
          case SyncStatus.off:
            return const SizedBox.shrink();
          case SyncStatus.idle:
            icon = Icons.cloud_done_outlined;
            tip = 'Дані збережено в хмарі';
          case SyncStatus.syncing:
            icon = Icons.cloud_sync_outlined;
            tip = 'Синхронізація…';
          case SyncStatus.offline:
            icon = Icons.cloud_off_outlined;
            tip = 'Немає зв\'язку: дані збережено на телефоні й підуть у хмару пізніше';
          case SyncStatus.error:
            icon = Icons.error_outline;
            tip = 'Помилка синхронізації. Деталі в налаштуваннях';
        }
        return Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(icon, key: const Key('sync-indicator'), size: 22),
          ),
        );
      },
    );
  }
}
