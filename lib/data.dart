import 'models.dart';

// Helper to switch between semesters
List<TeachingUnit> getCurriculum(int semester) {
  if (semester == 5) return _getSemester5();
  if (semester == 6) return _getSemester6();
  return [];
}

// S5 Teaching Units Blueprint
List<TeachingUnit> _getSemester5() {
  return [
    TeachingUnit("UE Développement & Concepts", [
      Subject("Langage C", 1.5, {
        "Langage C": "Moyenne",
        "LANGAGE C DS 1h": "DS Théorie",
        "LANGAGE C DS TP 1h": "DS Pratique",
      }),
      Subject("CLP", 3.0, {
        "Concepts de la logique à la programmation": "Moyenne",
        "CLP DS 2h": "DS Final",
      }),
      Subject("Hygiène", 1.5, {
        "Hygiène numérique": "Moyenne",
        "HI DS 2h": "DS Final",
      }),
    ]),
    TeachingUnit("UE Algo & Logique", [
      Subject("Prog Fonctionnelle", 2.0, {
        "Programmation fonctionnelle": "Moyenne",
      }),
      Subject("Prog Logique", 2.0, {"Programmation logique": "Moyenne"}),
      Subject("ITI", 2.5, {
        "Introduction aux techniques de l’ingénieur": "Moyenne",
        "ITI - DS 2H": "DS Final",
      }),
    ]),
    TeachingUnit("UE Conception", [
      Subject("Struct. Données", 3.0, {"Structure de données": "Moyenne"}),
      Subject("CPOO", 1.5, {
        "Conception et programmation orientée objet": "Moyenne",
        "CPOO1 DS 2H": "DS Final",
      }),
      Subject("Etude Pratique", 2.0, {"Etude Pratique - S5": "Moyenne"}),
    ]),
    TeachingUnit("UE Mathématiques", [
      Subject("Probabilités", 1.5, {"Probabilités": "Moyenne"}),
      Subject("Fouille de données", 2.5, {
        "Analyse de données et Fouille de données": "Moyenne",
        "ADFD  DS 2h": "DS Final",
      }),
    ]),
    TeachingUnit("UE Humanités", [
      Subject("Anglais (LV1)", 2.0, {"Anglais S5": "Moyenne"}),
      Subject("Projet Sc. Humaines", 2.5, {
        "Projet Sciences Humaines": "Moyenne",
      }),
      Subject("Gestion du Risque", 1.5, {
        "Gestion du Risque": "Moyenne",
        "Controle continu Gestion du Risque": "CC",
      }),
      Subject("Sport (EPS)", 1.0, {
        "Education physique et sportive S5": "Moyenne",
      }),
    ]),
  ];
}

// S6 Teaching Units Blueprint (Not filled)
List<TeachingUnit> _getSemester6() {
  return [
    TeachingUnit("UE Humanités S6", [
      Subject("Anglais S6", 2.0, {"Anglais S6": "Moyenne"}),
      Subject("Sport S6", 1.0, {
        "Education physique et sportive S6": "Moyenne",
      }),
      Subject("PPI", 1.0, {"Projet Personnel Individualisé S6": "Moyenne"}),
    ]),
    TeachingUnit("UE Stage & Projet", [
      Subject("Projet S6", 4.0, {
        "PROJETS ET OUVERTURE": "Moyenne",
      }), // Example Key
    ]),
  ];
}

// Json fetch from the API - initially empty, populated after successful login
String jsonString = '{}';
