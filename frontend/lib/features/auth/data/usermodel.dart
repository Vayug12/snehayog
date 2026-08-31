class UserModel {
  final String id;
  final String name;
  final String email;
  final String profilePic;
  final List<String> videos;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final DateTime? createdAt;
  final String? bio;
  final String? location;
  final String? websiteUrl;
  final String? professionId;
  final String? professionLabel;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.profilePic,
    required this.videos,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.createdAt,
    this.bio,
    this.location,
    this.websiteUrl,
    this.professionId,
    this.professionLabel,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    try {
      return UserModel(
        id: json['_id']?.toString() ?? json['id']?.toString() ?? json['googleId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        profilePic: json['profilePic']?.toString() ?? '',
        videos: (json['videos'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        
        // Defensive parsing for numbers
        followersCount: (json['followersCount'] is int) 
            ? json['followersCount'] 
            : int.tryParse(json['followersCount']?.toString() ?? json['followers']?.toString() ?? '0') ?? 0,
            
        followingCount: (json['followingCount'] is int)
            ? json['followingCount']
            : int.tryParse(json['followingCount']?.toString() ?? json['following']?.toString() ?? '0') ?? 0,
            
        isFollowing: json['isFollowing'] == true,
        
        // Defensive parsing for dates
        createdAt: () {
          try {
            if (json['createdAt'] != null) {
              return DateTime.parse(json['createdAt'].toString());
            }
          } catch (e) {
            // Ignore parse errors and return null
          }
          return null;
        }(),
        
        bio: json['bio']?.toString(),
        location: json['location']?.toString(),
        websiteUrl: json['websiteUrl']?.toString(),
        professionId: json['professionId']?.toString(),
        professionLabel:
            (json['profession'] as Map<String, dynamic>?)?['label']?.toString(),
      );
    } catch (e) {
      // Return a safe minimal fallback if parsing utterly fails
      return UserModel(
        id: json['_id']?.toString() ?? 'unknown',
        name: 'Unknown User',
        email: '',
        profilePic: '',
        videos: [],
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profilePic': profilePic,
      'videos': videos,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'isFollowing': isFollowing,
      'createdAt': createdAt?.toIso8601String(),
      'bio': bio,
      'location': location,
      'websiteUrl': websiteUrl,
      'professionId': professionId,
      'profession': professionLabel == null
          ? null
          : {'id': professionId, 'label': professionLabel},
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? profilePic,
    List<String>? videos,
    int? followersCount,
    int? followingCount,
    bool? isFollowing,
    DateTime? createdAt,
    String? bio,
    String? location,
    String? websiteUrl,
    String? professionId,
    String? professionLabel,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profilePic: profilePic ?? this.profilePic,
      videos: videos ?? this.videos,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      createdAt: createdAt ?? this.createdAt,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      professionId: professionId ?? this.professionId,
      professionLabel: professionLabel ?? this.professionLabel,
    );
  }
}
