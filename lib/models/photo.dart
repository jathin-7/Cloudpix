class Photo {
  final String id;
  final String title;
  final String url;
  final String mimeType;
  final DateTime creationTime;
  final int size;
  final String accountId;
  final bool isLocal;
  final String? localPath;

  Photo({
    required this.id,
    required this.title,
    required this.url,
    required this.mimeType,
    required this.creationTime,
    required this.size,
    required this.accountId,
    this.isLocal = false,
    this.localPath,
  });

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
        id: json['id'],
        title: json['title'],
        url: json['url'],
        mimeType: json['mimeType'],
        creationTime: DateTime.parse(json['creationTime']),
        size: json['size'] ?? 0,
        accountId: json['accountId'],
        isLocal: json['isLocal'] == 1,
        localPath: json['localPath'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'mimeType': mimeType,
        'creationTime': creationTime.toIso8601String(),
        'size': size,
        'accountId': accountId,
        'isLocal': isLocal ? 1 : 0,
        'localPath': localPath,
      };
}
