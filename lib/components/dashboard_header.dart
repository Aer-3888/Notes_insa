import 'package:flutter/material.dart';
import '../models.dart';

class DashboardHeader extends StatelessWidget {
  final double? average;
  final String title;
  final VoidCallback onMenuPressed;

  const DashboardHeader({
    super.key,
    required this.average,
    required this.title,
    required this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 0),
      child: Row(
        children: [
          // Menu Button
          IconButton(
            icon: const Icon(Icons.menu, size: 28, color: Colors.black87),
            onPressed: onMenuPressed,
          ),
          const SizedBox(width: 8),

          // Department Title
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
                  color: GradeUtils.getColor(average).withValues(alpha: .4),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              average?.toStringAsFixed(2) ?? "-",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
