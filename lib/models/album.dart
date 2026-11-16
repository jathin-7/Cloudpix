class Album {
  final String id;
  final String name;
  final int photoCount;
  final String? coverPhotoUrl;
  final DateTime createdAt;
  final bool isLocal; // Local device album vs Drive folder

  Album({
    required this.id,
    required this.name,
    this.photoCount = 0,
    this.coverPhotoUrl,
    required this.createdAt,
    this.isLocal = false,
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: json['id'],
        name: json['name'],
        photoCount: json['photoCount'] ?? 0,
        coverPhotoUrl: json['coverPhotoUrl'],
        createdAt: DateTime.parse(json['createdAt']),
        isLocal: json['isLocal'] == 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'photoCount': photoCount,
        'coverPhotoUrl': coverPhotoUrl,
        'createdAt': createdAt.toIso8601String(),
        'isLocal': isLocal ? 1 : 0,
      };
}
