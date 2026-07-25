import 'dart:convert';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';

class NoticeService implements INoticeService {
  @override
  Future<List<NoticeModel>> fetchNotices() async {
    try {
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/notices'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final notices = data['notices'] as List<dynamic>? ?? const [];
        return notices
            .map((json) => NoticeModel.fromJson(Map<String, dynamic>.from(json)))
            .toList();
      } else {
        AppLogger.log('Failed to fetch notices: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      AppLogger.log('Error fetching notices: $e');
      return [];
    }
  }

  @override
  Future<NoticeModel?> getActiveNotice() async {
    final notices = await fetchNotices();
    if (notices.isNotEmpty) {
      // Return the most recent/active notice
      return notices.first;
    }
    return null;
  }

  @override
  Future<void> markAsSeen(String noticeId) async {
    try {
      await httpClientService.put(
        Uri.parse('${NetworkHelper.usersEndpoint}/notices/$noticeId/seen'),
        body: {},
      );
    } catch (e) {
      AppLogger.log('Error marking notice as seen: $e');
    }
  }
}
