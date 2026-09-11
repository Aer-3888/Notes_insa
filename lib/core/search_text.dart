/// Lower-cases and strips the accents students will not bother typing.
///
/// Shared by every module that searches French text, so "theatre" finds
/// "Théâtre" and "batiment" finds "Bâtiment" wherever it is typed.
String foldForSearch(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  final out = StringBuffer();
  for (final rune in s.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().trim();
}
