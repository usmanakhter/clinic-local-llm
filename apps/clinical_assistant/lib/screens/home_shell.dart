import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../data/sync_worker.dart';
import '../theme/app_theme.dart';
import '../widgets/disclaimer_banner.dart';
import 'chat_screen.dart';
import 'drug_search_screen.dart';
import 'guidelines_screen.dart';
import 'interaction_screen.dart';
import 'note_drafter_screen.dart';
import 'patients_screen.dart';
import 'sync_transparency_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = [
    'Drug Search',
    'Interactions',
    'Guidelines',
    'Chat',
    'Notes',
    'Patients',
  ];

  @override
  void initState() {
    super.initState();
    // Sync is on after Terms — best-effort upload of pending scrubbed queue.
    SyncWorker.flushPending();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DrugSearchScreen(repository: widget.repository),
      InteractionScreen(repository: widget.repository),
      GuidelinesScreen(repository: widget.repository),
      ChatScreen(repository: widget.repository),
      NoteDrafterScreen(repository: widget.repository),
      PatientsScreen(repository: widget.repository),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Sync transparency',
            icon: const Icon(Icons.cloud_queue_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SyncTransparencyScreen(),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Terms accepted · sync on',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DisclaimerBanner(),
          if (_index == 0)
            Material(
              color: AppColors.tealSoft,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Nepal Clinical Assistant — essential medicines reference',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.tealDark,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          Expanded(child: pages[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_outlined),
            selectedIcon: Icon(Icons.compare_arrows),
            label: 'Interact',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Guides',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.note_alt_outlined),
            selectedIcon: Icon(Icons.note_alt),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Patients',
          ),
        ],
      ),
    );
  }
}
