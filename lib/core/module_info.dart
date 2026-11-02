/// Platformdan ve backend'den bağımsız modül tanımı.
class ModuleInfo {
  const ModuleInfo({required this.title, this.comingSoon = false});

  final String title;
  final bool comingSoon;
}
