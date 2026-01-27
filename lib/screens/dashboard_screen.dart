import 'dart:convert';
import 'package:flutter/material.dart';
import '../models.dart';
import '../data.dart';
import '../components/app_drawer.dart';
import '../components/dashboard_header.dart';
import '../components/semester_selector.dart';
import '../components/unit_card_grid.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int selectedSemester = 5;
  List<TeachingUnit> curriculum = [];
  double? semesterAverage;
  String departmentName = "Etudiant";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    List<TeachingUnit> loadedCurriculum = getCurriculum(selectedSemester);
    Map<String, dynamic> rawData = jsonDecode(jsonString);

    for (String key in rawData.keys) {
      if (key.toUpperCase().contains("SEMESTRE")) {
        departmentName = key.split('-')[0];
        break;
      }
    }

    // Remplissage des notes
    for (var unit in loadedCurriculum) {
      for (var sub in unit.subjects) {
        sub.grades = [];
        sub.jsonKeys.forEach((jsonKey, readableLabel) {
          if (rawData.containsKey(jsonKey)) {
            double? val = GradeUtils.parseDouble(rawData[jsonKey]);
            if (val != null) {
              sub.grades.add(GradeInstance(readableLabel, val));
            }
          }
        });
      }
    }

    // Calcul de la moyenne
    double totalSemScore = 0;
    double totalSemCoeff = 0;
    for (var unit in loadedCurriculum) {
      if (unit.average != null) {
        for (var sub in unit.subjects) {
          if (sub.average != null) {
            totalSemScore += sub.average! * sub.coeff;
            totalSemCoeff += sub.coeff;
          }
        }
      }
    }

    setState(() {
      curriculum = loadedCurriculum;
      semesterAverage = (totalSemCoeff > 0)
          ? totalSemScore / totalSemCoeff
          : null;
    });
  }

  void _switchSemester(int newSem) {
    if (selectedSemester == newSem) return;
    setState(() {
      selectedSemester = newSem;
    });
    _loadData();
  }

  void _showUEDetails(BuildContext context, TeachingUnit unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    unit.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: GradeUtils.getColor(
                      unit.average,
                    ).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    unit.average?.toStringAsFixed(2) ?? "-",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: GradeUtils.getColor(unit.average),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 40),
            Expanded(
              child: ListView.separated(
                itemCount: unit.subjects.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final sub = unit.subjects[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              sub.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Coeff ${sub.coeff}",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: sub.grades.isEmpty
                              ? [
                                  Chip(
                                    label: const Text("Aucun résultat"),
                                    backgroundColor: Colors.grey.shade200,
                                  ),
                                ]
                              : sub.grades
                                    .map(
                                      (g) => Chip(
                                        label: Text("${g.label}: ${g.value}"),
                                        backgroundColor: GradeUtils.getColor(
                                          g.value,
                                        ).withValues(alpha: 0.1),
                                        labelStyle: TextStyle(
                                          color: GradeUtils.getColor(g.value),
                                          fontWeight: FontWeight.bold,
                                        ),
                                        side: BorderSide.none,
                                      ),
                                    )
                                    .toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // ON PASSE LA VARIABLE departmentName ICI
            DashboardHeader(
              title: departmentName,
              average: semesterAverage,
              onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            SemesterSelector(
              selectedSemester: selectedSemester,
              onSemesterChanged: _switchSemester,
            ),
            Expanded(
              child: UnitCardGrid(
                curriculum: curriculum,
                onUnitTap: (unit) => _showUEDetails(context, unit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
