import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../../domain/sms_inbox.dart';

/// Search plus the five class filters. Horizontally scrollable so the labels
/// never truncate at 360 dp / 1.3x text.
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
    final p = T.of(context);
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in InboxFilter.values) ...[
                if (option != InboxFilter.values.first)
                  const SizedBox(width: T.s2),
                ChoiceChip(
                  label: Text(option.label),
                  showCheckmark: false,
                  selected: filter == option,
                  onSelected: (_) => onFilter(option),
                  labelStyle: T.bodySmall.copyWith(
                    color: filter == option ? p.ink : p.inkSecondary,
                    fontWeight: filter == option
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
