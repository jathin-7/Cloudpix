class GoogleAccount {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int totalStorage;
  final int usedStorage;

  GoogleAccount({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.totalStorage,
    required this.usedStorage,
  });

  factory GoogleAccount.fromJson(Map<String, dynamic> json) => GoogleAccount(
        id: json['id'],
        email: json['email'],
        displayName: json['displayName'],
        photoUrl: json['photoUrl'],
        totalStorage: json['totalStorage'] ?? 0,
        usedStorage: json['usedStorage'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'totalStorage': totalStorage,
        'usedStorage': usedStorage,
      };
}
