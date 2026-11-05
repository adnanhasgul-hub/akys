import 'package:flutter/material.dart';

import 'clinical_teal_theme.dart';

class AkysDestination {
  const AkysDestination({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Module-neutral shell. First four destinations are direct on mobile;
/// additional destinations are reachable through a scrollable More sheet.
class AkysAdaptiveNavigation extends StatelessWidget {
  const AkysAdaptiveNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.enabled = true,
    super.key,
  }) : assert(destinations.length > 0),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);
  final List<AkysDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final bool enabled;
  Future<void> more(BuildContext context) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('Diğer')),
              for (var i = 4; i < destinations.length; i++)
                ListTile(
                  selected: i == selectedIndex,
                  leading: Icon(destinations[i].icon),
                  title: Text(destinations[i].label),
                  onTap: () => Navigator.pop(context, i),
                ),
            ],
          ),
        ),
      ),
    );
    if (index != null) onSelected(index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= AkysTokens.tablet) {
        return Row(
          children: [
            SizedBox(
              width: constraints.maxWidth >= AkysTokens.desktop ? 260 : 220,
              child: FocusTraversalGroup(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        ListTile(
                          selected: i == selectedIndex,
                          selectedTileColor: AkysTokens.selected,
                          leading: Icon(destinations[i].icon),
                          title: Text(destinations[i].label),
                          onTap: enabled ? () => onSelected(i) : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        );
      }
      final direct = destinations.length > 5 ? 4 : destinations.length;
      return Column(
        children: [
          Expanded(child: body),
          SafeArea(
            top: false,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < direct; i++)
                    Expanded(
                      child: _item(
                        context,
                        destinations[i],
                        i == selectedIndex,
                        () => onSelected(i),
                      ),
                    ),
                  if (destinations.length > 5)
                    Expanded(
                      child: _item(
                        context,
                        const AkysDestination(
                          label: 'Diğer',
                          icon: Icons.more_horiz,
                        ),
                        selectedIndex >= 4,
                        () => more(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _item(
    BuildContext context,
    AkysDestination destination,
    bool selected,
    VoidCallback tap,
  ) => Semantics(
    selected: selected,
    child: TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        backgroundColor: selected ? AkysTokens.selected : null,
        foregroundColor: AkysTokens.navy,
        shape: const RoundedRectangleBorder(),
      ),
      onPressed: enabled ? tap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(destination.icon),
          const SizedBox(height: 4),
          Text(
            destination.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
