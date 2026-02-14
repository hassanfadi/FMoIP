import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization.dart';
import '../models.dart';
import '../state/radio_state.dart';

class CountryDropdown extends StatelessWidget {
  const CountryDropdown({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Country? selected;
  final ValueChanged<Country?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final textColor = Theme.of(context).colorScheme.onSurface;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: strings.country,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: TextStyle(fontSize: 15, color: textColor),
      ),
      child: InkWell(
        onTap: () async {
          final radioState = context.read<RadioState>();
          final selectedCountry = await showModalBottomSheet<Country>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => _CountryPickerSheet(radioState: radioState),
          );
          if (selectedCountry != null) {
            onChanged(selectedCountry);
          }
        },
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected == null
                    ? strings.country
                    : strings.countryName(selected!),
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.radioState});

  final RadioState radioState;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';
  Map<String, int> _countryCounts = {};
  bool _countsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCountryCounts();
  }

  Future<void> _loadCountryCounts() async {
    try {
      final counts = await widget.radioState.getCountryCountsForDropdown();
      if (mounted) setState(() {
        _countryCounts = counts;
        _countsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _countsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final items = Country.defaults.where((country) {
      final localized = strings.countryName(country).toLowerCase();
      final english = country.name.toLowerCase();
      final code = country.code.toLowerCase();
      return q.isEmpty ||
          localized.contains(q) ||
          english.contains(q) ||
          code.contains(q);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_countsLoading)
              const LinearProgressIndicator(),
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.country,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final count = _countryCounts[item.code.toUpperCase()];
                  return ListTile(
                    title: Text(strings.countryName(item)),
                    trailing: count != null
                        ? Text(
                            count.toString(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
