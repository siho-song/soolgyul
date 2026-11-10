import 'package:image_picker/image_picker.dart';

class SupportInquiryDraft {
  SupportInquiryDraft({
    required this.id,
    required this.type,
    required this.email,
    required this.content,
    List<XFile> images = const [],
  }) : images = List.unmodifiable(images);

  final String id;
  final String type;
  final String email;
  final String content;
  final List<XFile> images;

  static const typeKeys = {
    '시스템 오류 및 버그': 'bug',
    '서비스 이용 문의': 'usage',
    '의견 및 기능 제안': 'suggestion',
    '기타 문의': 'other',
  };
}

class SupportInquiryException implements Exception {
  const SupportInquiryException(this.message);
  final String message;
}

abstract interface class SupportInquiryGateway {
  Future<void> submit(SupportInquiryDraft draft);
}

String? validateInquiryEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return '답변받을 이메일을 입력해 주세요.';
  }
  if (email.length > 254 ||
      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return '올바른 이메일 주소를 입력해 주세요.';
  }
  return null;
}

String? validateInquiryContent(String? value) {
  if ((value?.trim() ?? '').isEmpty) {
    return '문의 내용을 입력해 주세요.';
  }
  if ((value?.trim().runes.length ?? 0) > 1000) {
    return '문의 내용은 1000자 이내로 입력해 주세요.';
  }
  return null;
}
