import 'package:JsxposedX/core/networks/http_service.dart';

class RepositoryActionDatasource {
  final HttpService _httpService;

  RepositoryActionDatasource({required HttpService httpService})
      : _httpService = httpService;
}
