import 'package:flutter/material.dart';

/// Port of components/home/pages.jsx (SWEETPAGE): a "page N ˅" toggle that
/// expands into a 3-column grid of the other pages. Selecting one calls
/// [onPageChange] with the new 1-based page — callers then run the equivalent
/// of `intitializeMovies({runContent:[index], adjustable:true, page, genreId:'',
/// regionId:'', languageId:'', yearId:0})`.
class SweetPage extends StatefulWidget {
  const SweetPage({super.key, required this.page, required this.totalPages, required this.onPageChange});
  final int page;
  final int totalPages;
  final ValueChanged<int> onPageChange;

  @override
  State<SweetPage> createState() => _SweetPageState();
}

class _SweetPageState extends State<SweetPage> {
  bool _view = false;
  late int _newPage = widget.page;

  @override
  void didUpdateWidget(covariant SweetPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) _newPage = widget.page;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final pages = [for (var i = 1; i <= widget.totalPages; i++) if (i != _newPage) i];
    return Padding(
      padding: EdgeInsets.only(left: w * 0.2, right: w * 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _view = !_view),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('page $_newPage', style: const TextStyle(color: Colors.white)),
                  const SizedBox(width: 8),
                  Icon(_view ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 500),
            child: !_view
                ? const SizedBox(width: double.infinity)
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisExtent: 40,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: pages.length,
                      itemBuilder: (context, i) => OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: Colors.white24, width: 2),
                          shape: const RoundedRectangleBorder(),
                        ),
                        onPressed: () {
                          setState(() => _newPage = pages[i]);
                          widget.onPageChange(pages[i]);
                        },
                        child: Text('page ${pages[i]}', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
