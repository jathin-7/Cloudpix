import 'package:cloudpix/models/photo.dart';

class Memory {
  final String id;
  final String title;
  final DateTime date;
  final List<Photo> photos;
  final String type; // "on_this_day", "recent_trip", etc.

  Memory({
    required this.id,
    required this.title,
    required this.date,
    required this.photos,
    required this.type,
  });
}
