import 'package:vayug/features/auth/data/usermodel.dart';

abstract class IUserService {
  Future<Map<String, dynamic>> getUserById(String id);
  Future<bool> followUser(String userIdToFollow);
  Future<bool> unfollowUser(String userIdToUnfollow);
  Future<bool> isFollowingUser(String userIdToCheck);
  Future<Map<String, bool>> batchCheckFollowStatus(List<String> userIds);
  Future<bool> updateProfile({
    required String googleId,
    required String name,
    String? profilePic,
    String? websiteUrl,
  });
  Future<String?> updateProfilePhoto(String googleId, String photoPath);
  Future<Map<String, dynamic>> updateProfession(String? professionId);
  Future<UserModel?> getUserData(String userId);
}
