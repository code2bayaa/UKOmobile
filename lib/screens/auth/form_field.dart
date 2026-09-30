import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Port of components/home/FormField.tsx:
/// `w-[80%] border-b-2 border-white mb-5`, a semibold white label, then a
/// borderless white TextInput (h-[40px], placeholder #666; multiline -> minHeight 100).
class UkoFormField extends StatelessWidget {
  const UkoFormField({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder,
    this.multiline = false,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.widthFactor = 0.8,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final bool multiline;
  final TextInputType keyboardType;
  final ValueChanged<String>? onChanged;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Container(
      width: w * widthFactor,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: multiline ? 100 : 40),
            child: TextField(
              controller: controller,
              keyboardType: multiline ? TextInputType.multiline : keyboardType,
              maxLines: multiline ? null : 1,
              minLines: multiline ? 4 : 1,
              textAlignVertical: multiline ? TextAlignVertical.top : TextAlignVertical.center,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                isDense: true,
                hintText: placeholder,
                hintStyle: const TextStyle(color: UkoColors.divider),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
