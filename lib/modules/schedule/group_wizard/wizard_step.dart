/// The kinds of question the wizard asks.
///
/// They mirror how ADE nests its resources, with two departures forced by the
/// data:
///
///  - [semestre] is multi-select and [groupe] repeats once per semester
///    chosen. An academic year is two semesters with two different ADE nodes
///    (S7-INFO in the autumn, S8-INFO in the spring), so a student who picks
///    only one has an empty timetable for half the year.
///  - [semestre] is skipped entirely for a formation that has no semester
///    level, such as MASTER-EO, whose children are already the groups.
///
/// [options] exists because the branches a student needs on top of their
/// group sit *beside* it rather than under it, so no single pick can reach
/// them: options, ouvertures, langues, and the TP branch in the promos that
/// keep it separate from TD.
enum WizardStep { formation, semestre, groupe, options }

/// One screen of the wizard: a question, and for [WizardStep.groupe] the
/// semester it is being asked about.
typedef WizardPage = ({WizardStep kind, int? semestre});
