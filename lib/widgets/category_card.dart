import 'package:flutter/material.dart';

/// Port of components/home/CategoryCard.tsx.
///
/// RN bug fixed: the studios list uses "hindu" but the image/overlay maps were
/// keyed "hindi", so the Bollywood card fell back to the China image. Both keys
/// resolve to bollywood.jpg here.
class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.item, this.title, this.onTap, this.width, this.height = 100});
  final String item;
  final String? title;
  final VoidCallback? onTap;
  final double? width;
  final double height;

  static const _images = {
    'anime': 'assets/images/anime.png',
    'hindi': 'assets/images/bollywood.jpg',
    'hindu': 'assets/images/bollywood.jpg',
    'china': 'assets/images/china.jpg',
    'korean': 'assets/images/korea.jpg',
    'netflix': 'assets/images/netflix.png',
    'disney': 'assets/images/disney.jpg',
    'eden': 'assets/images/eden.jpg', // web .eden-nav (assets/home.png)
  };

  static const _overlays = {
    'anime': Color.fromRGBO(209, 0, 0, 0.5),
    'korean': Color.fromRGBO(0, 178, 169, 0.5),
    'hindi': Color.fromRGBO(50, 255, 106, 0.5),
    'hindu': Color.fromRGBO(50, 255, 106, 0.5),
    'china': Color.fromRGBO(255, 195, 0, 0.5),
    'netflix': Color.fromRGBO(229, 9, 20, 0.5),
    'disney': Color.fromRGBO(0, 82, 204, 0.5),
    'eden': Color.fromRGBO(0, 0, 0, 0.35),
  };

  @override
  Widget build(BuildContext context) {
    final key = item.toLowerCase();
    final src = _images[key] ?? _images['china']!;
    final overlay = _overlays[key] ?? const Color.fromRGBO(0, 0, 0, 0.5);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: Colors.black,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(src, fit: BoxFit.cover),
                Opacity(opacity: 0.8, child: ColoredBox(color: overlay)),
                Center(
                  child: Text(title ?? item,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
