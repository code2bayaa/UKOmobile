import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/profile.dart';

/// State of the phone + country / county / ward fields (movies PRD #6, #21), shared by the
/// signup and profile screens.
class PhoneLocationController extends ChangeNotifier {
  PhoneLocationController({String country = 'Kenya'}) : _country = country {
    phone.addListener(notifyListeners);
  }

  final phone = TextEditingController();
  final county = TextEditingController();
  final ward = TextEditingController();
  String _country;
  String get country => _country;

  /// Fills the fields from a saved profile (country falls back to [fallbackCountry]).
  void load(UkoProfile? p, UkoLocations l, {String? fallbackCountry}) {
    _country = l.byName(p?.country)?.name ?? l.byName(fallbackCountry)?.name ?? l.defaultCountry;
    county.text = p?.county ?? '';
    ward.text = p?.ward ?? '';
    final tel = p?.telephone ?? '';
    phone.text = tel.isNotEmpty ? tel : _dialPrefix(l.byName(_country));
    notifyListeners();
  }

  static String _dialPrefix(UkoCountry? c) => c == null || c.dial.isEmpty ? '' : '+${c.dial} ';

  /// Picking a country swaps an untouched dialling code in the phone field for the new one and
  /// clears county / ward, which belong to the old country.
  void pickCountry(String name, UkoLocations l) {
    if (name == _country) return;
    final typed = phone.text.trim();
    final old = l.byName(_country);
    if (typed.isEmpty || (old != null && typed == '+${old.dial}')) phone.text = _dialPrefix(l.byName(name));
    _country = name;
    county.clear();
    ward.clear();
    notifyListeners();
  }

  void pickCounty(String name) {
    if (county.text == name) return;
    county.text = name;
    notifyListeners();
  }

  /// The phone field holds more than a bare dialling code.
  bool get hasPhone => phone.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 6;

  bool get hasLocation => county.text.trim().isNotEmpty || ward.text.trim().isNotEmpty;

  /// Client-side check before sending; the server re-validates and has the final word.
  String? validate(UkoLocations l, {bool requirePhone = true, bool requireLocation = true}) {
    if (requirePhone && !hasPhone) return 'Enter your phone number, with its country code';
    if (requireLocation || hasLocation) {
      if (l.byName(_country) == null) return 'Pick your country';
      final list = l.countiesFor(_country);
      final c = county.text.trim();
      if (c.isEmpty) return list != null ? 'Pick your county' : 'Enter your county / province';
      if (list != null && !list.any((k) => k.toLowerCase() == c.toLowerCase())) return 'Pick a county from the list';
      if (ward.text.trim().isEmpty) return 'Enter your ward';
    }
    return null;
  }

  Map<String, String> phoneBody() => {'telephone': phone.text.trim()};

  Map<String, String> locationBody() =>
      {'country': _country, 'county': county.text.trim(), 'ward': ward.text.trim()};

  /// The country the typed number belongs to (by its dialling code, else the picked country).
  UkoCountry? phoneCountry(UkoLocations l) => l.phoneCountry(phone.text, _country);

  @override
  void dispose() {
    phone.removeListener(notifyListeners);
    phone.dispose();
    county.dispose();
    ward.dispose();
    super.dispose();
  }
}

/// Country dropdown (default Kenya), phone with the dialling code prefilled, county (Kenya's 47
/// as a dropdown, typed elsewhere) and ward (typed, with suggestions). Warns - without blocking -
/// when the phone number's country can't play videos.
class PhoneLocationFields extends StatefulWidget {
  const PhoneLocationFields({super.key, required this.controller, required this.locations});
  final PhoneLocationController controller;
  final UkoLocations locations;

  @override
  State<PhoneLocationFields> createState() => _PhoneLocationFieldsState();
}

class _PhoneLocationFieldsState extends State<PhoneLocationFields> {
  final _wardFocus = FocusNode();

  PhoneLocationController get _c => widget.controller;
  UkoLocations get _l => widget.locations;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(PhoneLocationFields old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _wardFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static InputDecoration _decoration(String label, {String? hint, String? helper}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        isDense: true,
        labelStyle: const TextStyle(color: Colors.white),
        helperStyle: const TextStyle(color: UkoColors.gray400),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white, width: 1.5)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: UkoColors.yellow, width: 2)),
      );

  @override
  Widget build(BuildContext context) {
    final picked = _l.byName(_c.country);
    final counties = _l.countiesFor(_c.country);
    final phoneCountry = _c.hasPhone ? _c.phoneCountry(_l) : null;
    final warn = _c.hasPhone && (phoneCountry == null || !phoneCountry.plays);
    const white = TextStyle(color: Colors.white);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('country-${_c.country}'),
          initialValue: picked?.name,
          isExpanded: true,
          dropdownColor: UkoColors.gray900,
          style: white,
          decoration: _decoration('Country'),
          items: [
            for (final c in _l.countries) DropdownMenuItem(value: c.name, child: Text(c.name)),
          ],
          onChanged: (v) {
            if (v != null) _c.pickCountry(v, _l);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _c.phone,
          keyboardType: TextInputType.phone,
          style: white,
          cursorColor: Colors.white,
          decoration: _decoration(
            'Phone number',
            hint: picked == null ? '+254 712 345 678' : '+${picked.dial} ...',
            helper: picked == null ? 'Include the country code' : 'Dialling code for ${picked.name}: +${picked.dial}',
          ),
        ),
        if (warn)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Playing videos is only available with a phone number from Africa, Australia or Brazil.'
              '${phoneCountry == null ? '' : ' This number is from ${phoneCountry.name}.'}',
              style: const TextStyle(color: UkoColors.yellow, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        if (counties != null)
          DropdownButtonFormField<String>(
            key: ValueKey('county-${_c.country}-${_c.county.text}'),
            initialValue: counties.contains(_c.county.text) ? _c.county.text : null,
            isExpanded: true,
            dropdownColor: UkoColors.gray900,
            style: white,
            decoration: _decoration('County'),
            hint: const Text('Pick your county', style: TextStyle(color: UkoColors.gray400)),
            items: [for (final k in counties) DropdownMenuItem(value: k, child: Text(k))],
            onChanged: (v) {
              if (v != null) _c.pickCounty(v);
            },
          )
        else
          TextField(
            controller: _c.county,
            style: white,
            cursorColor: Colors.white,
            textCapitalization: TextCapitalization.words,
            decoration: _decoration('County / province / state'),
          ),
        const SizedBox(height: 12),
        RawAutocomplete<String>(
          textEditingController: _c.ward,
          focusNode: _wardFocus,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            final all = _l.wardsFor(_c.county.text);
            return q.isEmpty ? all : all.where((w) => w.toLowerCase().contains(q));
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
            controller: controller,
            focusNode: focusNode,
            style: white,
            cursorColor: Colors.white,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => onSubmitted(),
            decoration: _decoration('Ward', hint: 'Type your ward'),
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: UkoColors.gray900,
              elevation: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(dense: true, title: Text(o, style: white), onTap: () => onSelected(o)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
