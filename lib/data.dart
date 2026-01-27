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

// Json fetch from the API
String jsonString = '''
{
  "3INFO-SEMESTRE5": "Aucun résultat",
  "3INFO-SEMESTRE6": "Aucun résultat",
  "ARCHITECTURE LOGICIELLE ET MATERIELLE": "13.188/20",
  "Analyse de données et Fouille de données": "Aucun résultat",
  "Anglais S5": "Aucun résultat",
  "Anglais S6": "Aucun résultat",
  "Base de données": "Aucun résultat",
  "CLP DS 2h": "13/20",
  "CONCEPTION LOGICIELLE": "Aucun résultat",
  "CPOO1 DS 2H": "12.25/20",
  "Conception et programmation orientée objet": "12.25/20",
  "Concepts de la logique à la programmation": "13/20",
  "Controle continu EPS S5": "13.75/20",
  "Controle continu Gestion du Risque": "19.2/20",
  "Créativ'": "Aucun résultat",
  "ENSEIGNEMENTS D'HUMANITE S5": "Aucun résultat",
  "ENSEIGNEMENTS D'HUMANITE S6": "Aucun résultat",
  "Education physique et sportive S5": "13.75/20",
  "Education physique et sportive S6": "Aucun résultat",
  "Etude Pratique - S5": "Aucun résultat",
  "Gestion du Risque": "19.2/20",
  "HI DS 2h": "14/20",
  "Hygiène numérique": "14/20",
  "INFORMATIQUE THEORIQUE": "Aucun résultat",
  "INGENIERIE ET RESEAUX": "Aucun résultat",
  "INGENIEUR INFO 3A": "Aucun résultat",
  "ITI - DS 2H": "17.25/20",
  "Ingénierie Web 1": "11/20",
  "Introduction au Numérique Durable": "Aucun résultat",
  "Introduction aux techniques de l’ingénieur": "Aucun résultat",
  "LANGAGE C DS 1h": "17/20",
  "LANGAGE C DS TP 1h": "17/20",
  "Langage C": "17/20",
  "MATHEMATIQUES POUR L'INFORMATIQUE": "Aucun résultat",
  "PARADIGMES DE PROGRAMMATION": "Aucun résultat",
  "PROJETS ET OUVERTURE": "Aucun résultat",
  "Probabilités": "Aucun résultat",
  "Programmation fonctionnelle": "Aucun résultat",
  "Programmation logique": "Aucun résultat",
  "Projet Personnel Individualisé S6": "Aucun résultat",
  "Projet Sciences Humaines": "Aucun résultat",
  "REMEDIATION GESTION DU TRAVAIL": "Aucun résultat",
  "Remédiation Gestion du travail ": "Aucun résultat",
  "Réseaux": "16/20",
  "Structure de données": "Aucun résultat"
}
''';
