import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../app/widgets/kit.dart';
import '../../domain/sms_inbox.dart';

/// Search plus the five class filters. The chip row is the shared [ChipStrip],
/// which scrolls and fades at the edges instead of cutting a chip off at the
/// screen edge.
class InboxFilterBar extends StatelessWidget {
  const InboxFilterBar({
    super.key,
    required this.controller,
    required this.filter,
    required this.onFilter,
    required this.onQueryChanged,
  });

  final TextEditingController controller;
  final InboxFilter filter;
  final ValueChanged<InboxFilter> onFilter;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onQueryChanged,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search message or sender',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onQueryChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: T.s3),
        ChipStrip(
          children: [
            for (final option in InboxFilter.values)
              FilterChipView(
                label: option.label,
                selected: filter == option,
                onTap: () => onFilter(option),
              ),
          ],
        ),
      ],
    );
  }
}
