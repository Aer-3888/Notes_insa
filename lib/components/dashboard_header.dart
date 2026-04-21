import 'package:flutter/material.dart';
import '../models.dart';
import '../app_colors.dart';

String _formatLastUpdated(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'Mis à jour à l\'instant';
  if (diff.inMinutes < 60) return 'Mis à jour il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Mis à jour il y a ${diff.inHours} h';
  return 'Mis à jour il y a ${diff.inDays} j';
}

class DashboardHeader extends StatelessWidget {
  final double? average;
  final String title;
  final VoidCallback onMenuPressed;
  final DateTime? lastUpdated;
  final int selectedSemester;
  final List<int> availableSemesters;
  final ValueChanged<int> onSemesterChanged;

  const DashboardHeader({
    super.key,
    required this.average,
    required this.title,
    required this.onMenuPressed,
    this.lastUpdated,
    required this.selectedSemester,
    required this.availableSemesters,
    required this.onSemesterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Menu Button
              IconButton(
                icon: const Icon(Icons.menu, size: 28, color: Colors.black87),
                onPressed: onMenuPressed,
              ),
              const SizedBox(width: 8),

              // Department Title + last updated
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (lastUpdated != null)
                      Text(
                        _formatLastUpdated(lastUpdated!),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),

              // Average Circle
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GradeUtils.getColor(average),
                  boxShadow: [
                    BoxShadow(
                      color: GradeUtils.getColor(average).withOpacity(.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  average?.toStringAsFixed(2) ?? '-',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (availableSemesters.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AnimatedSemesterSelector(
              availableSemesters: availableSemesters,
              selectedSemester: selectedSemester,
              onSemesterChanged: onSemesterChanged,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AnimatedSemesterSelector extends StatefulWidget {
  final List<int> availableSemesters;
  final int selectedSemester;
  final ValueChanged<int> onSemesterChanged;

  const _AnimatedSemesterSelector({
    required this.availableSemesters,
    required this.selectedSemester,
    required this.onSemesterChanged,
  });

  @override
  State<_AnimatedSemesterSelector> createState() =>
      _AnimatedSemesterSelectorState();
}

class _AnimatedSemesterSelectorState extends State<_AnimatedSemesterSelector> {
  // Fixed item width used only when there are enough items to scroll.
  static const double _scrollItemWidth = 100.0;

  // Semesters displayed highest-first (most recent on the left).
  List<int> get _display => widget.availableSemesters.reversed.toList();

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(_AnimatedSemesterSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSemester != widget.selectedSemester) {
      _scrollToSelected();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    final idx = _display.indexOf(widget.selectedSemester);
    if (idx < 0) return;
    final target =
        (idx * _scrollItemWidth) -
        (position.viewportDimension - _scrollItemWidth) / 2;
    _scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildTab(int i, int semNum, int selectedIndex) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSemesterChanged(semNum),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: i == selectedIndex ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          child: Text('Semestre $semNum'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = _display;
    final n = display.length;
    final selectedIndex = display
        .indexOf(widget.selectedSemester)
        .clamp(0, n - 1);
    final useScroll = n > 3;

    final container = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(4),
      child: useScroll
          ? SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: n * _scrollItemWidth,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * _scrollItemWidth,
                      top: 0,
                      bottom: 0,
                      width: _scrollItemWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(
                        n,
                        (i) => SizedBox(
                          width: _scrollItemWidth,
                          child: _buildTab(i, display[i], selectedIndex),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / n;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * itemWidth,
                      top: 0,
                      bottom: 0,
                      width: itemWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(
                        n,
                        (i) => Expanded(
                          child: _buildTab(i, display[i], selectedIndex),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );

    return container;
  }
}
