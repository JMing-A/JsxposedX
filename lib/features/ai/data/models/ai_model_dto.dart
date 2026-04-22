import 'package:JsxposedX/features/ai/domain/models/ai_model.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'ai_model_dto.freezed.dart';
part 'ai_model_dto.g.dart';

@freezed
abstract class AiModelDto with _$AiModelDto {
  const AiModelDto._(); // 私有构造函数，用于添加自定义方法

  const factory AiModelDto({
    @Default('') String id,
    @Default('') String object,
    @Default(0) int created,
    @JsonKey(name: "owned_by") @Default('') String ownedBy,
    @JsonKey(name: "supported_endpoint_types")
    @Default([])
    List<String> supportedEndpointTypes,
  }) = _AiModelDto;

  factory AiModelDto.fromJson(Map<String, dynamic> json) =>
      _$AiModelDtoFromJson(json);

  AiModel toEntity() {
    return AiModel(
      id: id,
      object: object,
      created: created,
      ownedBy: ownedBy,
      supportedEndpointTypes: supportedEndpointTypes,
    );
  }
}
