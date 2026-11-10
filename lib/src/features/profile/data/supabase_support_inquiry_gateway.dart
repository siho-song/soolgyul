import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support_inquiry_gateway.dart';

class SupabaseSupportInquiryGateway implements SupportInquiryGateway {
  const SupabaseSupportInquiryGateway(this._client);
  final SupabaseClient _client;
  static const _bucket = 'soolgyul-private';
  static const maxImageBytes = 10 * 1024 * 1024;

  @override
  Future<void> submit(SupportInquiryDraft draft) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const SupportInquiryException('로그인 후 문의를 보내주세요.');
    final type = SupportInquiryDraft.typeKeys[draft.type];
    if (type == null ||
        draft.images.length > 5 ||
        draft.content.trim().isEmpty ||
        draft.content.trim().runes.length > 1000 ||
        draft.email.trim().length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(draft.email.trim()) ||
        !RegExp(
          r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
        ).hasMatch(draft.id)) {
      throw const SupportInquiryException('입력한 문의 내용을 다시 확인해 주세요.');
    }
    try {
      final paths = <String>[];
      // Upload sequentially so five large attachments do not fill memory at once.
      for (var index = 0; index < draft.images.length; index++) {
        final image = draft.images[index];
        if (await image.length() > maxImageBytes) {
          throw const SupportInquiryException('첨부 이미지는 장당 10MB 이하만 가능해요.');
        }
        final bytes = await image.readAsBytes();
        if (bytes.isEmpty || bytes.length > maxImageBytes) {
          throw const SupportInquiryException('첨부 이미지의 용량이나 형식을 확인해 주세요.');
        }
        final format = _imageFormat(bytes);
        final path =
            '$userId/inquiries/${draft.id}/$index-${sha256.convert(bytes)}.${format.extension}';
        if (_client.auth.currentUser?.id != userId) {
          throw const SupportInquiryException('로그인 상태가 변경됐어요. 다시 시도해 주세요.');
        }
        await _client.storage
            .from(_bucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: format.mime, upsert: true),
            );
        paths.add(path);
      }
      if (_client.auth.currentUser?.id != userId) {
        throw const SupportInquiryException('로그인 상태가 변경됐어요. 다시 시도해 주세요.');
      }
      final response = await _client.rpc(
        'soolgyul_submit_support_inquiry',
        params: {
          'p_id': draft.id,
          'p_inquiry_type': type,
          'p_reply_email': draft.email.trim(),
          'p_content': draft.content.trim(),
          'p_attachment_paths': paths,
        },
      );
      if (response != draft.id || _client.auth.currentUser?.id != userId) {
        throw const SupportInquiryException('접수 결과를 확인하지 못했어요. 다시 시도해 주세요.');
      }
    } on SupportInquiryException {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.message.contains('inquiry_rate_limited')) {
        throw const SupportInquiryException(
          '짧은 시간에 문의가 여러 번 접수되었어요. 잠시 후 다시 시도해 주세요.',
        );
      }
      throw const SupportInquiryException(
        '문의를 보내지 못했어요. 작성한 내용은 보관되니 다시 시도해 주세요.',
      );
    } catch (_) {
      // Do not remove files on an ambiguous network failure: the RPC may have
      // committed. The same request ID and content-addressed paths make retry safe.
      throw const SupportInquiryException(
        '문의를 보내지 못했어요. 작성한 내용은 보관되니 다시 시도해 주세요.',
      );
    }
  }
}

({String extension, String mime}) _imageFormat(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return (extension: 'jpg', mime: 'image/jpeg');
  }
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= 8 &&
      List.generate(8, (i) => bytes[i] == png[i]).every((v) => v)) {
    return (extension: 'png', mime: 'image/png');
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return (extension: 'webp', mime: 'image/webp');
  }
  throw const SupportInquiryException('JPG, PNG, WebP 이미지만 첨부할 수 있어요.');
}
