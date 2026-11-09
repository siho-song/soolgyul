/// A file dragged in from the desktop and dropped on the admin page.
class AdminDroppedFile {
  const AdminDroppedFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}
