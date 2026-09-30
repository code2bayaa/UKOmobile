// Port of mobile/components/home/clip.jsx (CLIP): a tappable YouTube
// thumbnail with the video name underneath. (Only referenced by the
// commented-out list in clips.jsx; kept for parity.)
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class Clip extends StatelessWidget {
  const Clip({super.key, required this.index, this.name, this.updateClip});

  /// YouTube video key (RN prop `index`).
  final String index;
  final String? name;
  final ValueChanged<String>? updateClip;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => updateClip?.call(index),
      child: LayoutBuilder(builder: (context, c) {
        final h = c.hasBoundedHeight ? c.maxHeight : 150.0;
        return SizedBox(
          width: c.hasBoundedWidth ? c.maxWidth : 200,
          height: h,
          child: Column(
            children: [
              Expanded(
                child: Image.network(
                  'https://img.youtube.com/vi/$index/maxresdefault.jpg',
                  width: 200,
                  fit: BoxFit.cover,
                  semanticLabel: name,
                  errorBuilder: (context, e, st) => const ColoredBox(color: Colors.black),
                ),
              ),
              // w-[100%] h-[20%] bg-popover items-center
              Container(
                height: h * 0.2,
                width: double.infinity,
                color: UkoColors.background,
                alignment: Alignment.center,
                child: Text(
                  name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
