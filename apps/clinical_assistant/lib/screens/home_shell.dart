import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../theme/app_theme.dart';
import '../widgets/disclaimer_banner.dart';
import 'chat_screen.dart';
import 'consent_screen.dart';
import 'drug_search_screen.dart';
import 'guidelines_screen.dart';
import 'interaction_screen.dart';
import 'note_drafter_screen.dart';
import 'activity_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.repository,
    required this.consentGranted,
    required this.syncStatusText,
    required this.onOpenConsent,
  });

  final ClinicalRepository repository;
  final bool consentGranted;
  final String syncStatusText;
  final VoidCallback onOpenConsent;

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
    'Note Draft',
    'Activity',
    'Consent',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      DrugSearchScreen(repository: widget.repository),
      InteractionScreen(repository: widget.repository),
      GuidelinesScreen(repository: widget.repository),
      ChatScreen(repository: widget.repository),
      NoteDrafterScreen(repository: widget.repository),
      ActivityScreen(repository: widget.repository),
      ConsentScreen(
        embedded: true,
        onChanged: widget.onOpenConsent,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                widget.syncStatusText,
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
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.privacy_tip_outlined),
            selectedIcon: Icon(Icons.privacy_tip),
            label: 'Consent',
          ),
        ],
      ),
    );
  }
}
