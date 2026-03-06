import 'conversation_list_input_dto.dart';
import 'conversation_detail_result.dart';

class ConversationListResult {
  final List<ConversationDetailResult> list;
  final ConversationListInputDto? nextCursor;
  final bool hasMore;

  const ConversationListResult({required this.list, this.nextCursor, required this.hasMore});

  factory ConversationListResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> listJson = json['list'] ?? [];
    final List<ConversationDetailResult> list = listJson
        .map((item) => ConversationDetailResult.fromJson(item))
        .toList();

    final nextCursorJson = json['nextCursor'];
    final ConversationListInputDto? nextCursor = nextCursorJson != null
        ? ConversationListInputDto.fromJson(nextCursorJson)
        : null;

    return ConversationListResult(list: list, nextCursor: nextCursor, hasMore: json['hasMore'] as bool? ?? false);
  }
}
