import 'package:JsxposedX/core/networks/http_service.dart';
import 'package:JsxposedX/features/home/data/models/post_detail_dto.dart';
import 'package:JsxposedX/features/home/data/models/post_dto.dart';
import 'package:JsxposedX/features/home/data/models/user_detail_dto.dart';
import 'package:JsxposedX/features/home/domain/models/page_result_dto.dart';
import 'package:dio/dio.dart';

class RepositoryQueryDatasource {
  final HttpService _httpService;

  RepositoryQueryDatasource({required HttpService httpService})
    : _httpService = httpService;
  final String _postApi =
      "https://apiv2.muxue.pro/api/public/post/category/tag/470/posts";

  final String _favoritePostApi =
      "https://apiv2.muxue.pro/api/public/post/favorites";

  final String _myUserDetailApi = "https://apiv2.muxue.pro/api/public/user/me";

  String _postDetailApi({required int postId}) =>
      "https://apiv2.muxue.pro/api/public/post/$postId/detail";

  Future<PageResultDto<PostDto>> getScriptPosts({
    required int limit,
    required int offset,
  }) async {
    try {
      final result = await _httpService.get(
        _postApi,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return PageResultDto.fromJson(
        result.data,
        (data) => PostDto.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      throw Exception(e);
    }
  }

  Future<PageResultDto<PostDto>> getScriptFavoritePosts({
    required int limit,
    required int offset,
  }) async {
    try {
      final result = await _httpService.get(
        _favoritePostApi,
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return PageResultDto.fromJson(
        result.data,
        (data) => PostDto.fromJson(data as Map<String, dynamic>),
      );
    } catch (e) {
      throw Exception(e);
    }
  }

  Future<PostDetailDto> getScriptDetail({required int id}) async {
    try {
      final result = await _httpService.get(_postDetailApi(postId: id));
      return PostDetailDto.fromJson(result.data["data"]);
    } catch (e) {
      throw Exception(e);
    }
  }

  Future<UserDetailDto> getMyUserDetail({required String token}) async {
    final result = await _httpService.get(
      _myUserDetailApi,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    if (result.statusCode != 200) {
      throw RepositoryLoginStatusException(result.statusCode);
    }

    final payload = result.data;
    if (payload is! Map<String, dynamic> || payload['data'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid user detail response');
    }

    return UserDetailDto.fromJson(payload['data'] as Map<String, dynamic>);
  }
}

class RepositoryLoginStatusException implements Exception {
  final int? statusCode;

  const RepositoryLoginStatusException(this.statusCode);

  @override
  String toString() => 'RepositoryLoginStatusException(statusCode: $statusCode)';
}
