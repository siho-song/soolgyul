import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_typography.dart';
import '../../../widgets/app_surface.dart';
import '../../../widgets/app_text_field.dart';
import '../data/support_inquiry_gateway.dart';
import 'widgets/support_inquiry_widgets.dart';
import '../../../core/ids.dart';

typedef SupportInquiryImagePicker = Future<List<XFile>> Function();

class SupportInquiryScreen extends StatefulWidget {
  const SupportInquiryScreen({
    this.pickImages,
    this.onSubmitted,
    this.gateway,
    super.key,
  });

  final SupportInquiryImagePicker? pickImages;
  final ValueChanged<SupportInquiryDraft>? onSubmitted;
  final SupportInquiryGateway? gateway;

  @override
  State<SupportInquiryScreen> createState() => _SupportInquiryScreenState();
}

class _SupportInquiryScreenState extends State<SupportInquiryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _contentController = TextEditingController();
  final _imagePicker = ImagePicker();

  String _inquiryType = '오류 신고';
  List<XFile> _images = [];
  String? _submissionId;
  bool _sending = false;
  bool _isPickingImages = false;

  @override
  void dispose() {
    _emailController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.screenX,
      AppSpacing.sm,
      AppSpacing.screenX,
      AppSpacing.massive,
    ),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppPanel(
            key: const ValueKey<String>('support-inquiry-form'),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const InquiryFieldLabel('문의 유형'),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  key: const ValueKey<String>('support-inquiry-type'),
                  initialValue: _inquiryType,
                  dropdownColor: AppColors.surfacePrimary,
                  decoration: inquiryFieldDecoration(),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 24,
                    color: AppColors.supportSecondary,
                  ),
                  style: AppTextStyles.supportFieldText,
                  items: SupportInquiryDraft.typeKeys.keys.map((value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: _sending
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _inquiryType = value;
                              _submissionId = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.xxl),
                const InquiryFieldLabel('이메일'),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  key: const ValueKey<String>('support-inquiry-email'),
                  controller: _emailController,
                  enabled: !_sending,
                  maxLength: 254,
                  onChanged: (_) => _submissionId = null,
                  hintText: '답변받을 이메일을 입력해 주세요.',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  size: AppTextFieldSize.compact,
                  textStyle: AppTextStyles.supportFieldText,
                  hintStyle: AppTextStyles.supportFieldHint,
                  validator: validateInquiryEmail,
                ),
                const SizedBox(height: AppSpacing.xxl),
                const InquiryFieldLabel('문의 내용'),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 136,
                  child: AppTextField(
                    key: const ValueKey<String>('support-inquiry-content'),
                    controller: _contentController,
                    enabled: !_sending,
                    hintText: '발생한 상황이나 의견을 자세히 남겨주세요.',
                    maxLength: 1000,
                    maxLines: null,
                    expands: true,
                    size: AppTextFieldSize.compact,
                    textStyle: AppTextStyles.supportFieldText,
                    hintStyle: AppTextStyles.supportFieldHint,
                    textAlignVertical: TextAlignVertical.top,
                    validator: validateInquiryContent,
                    onChanged: (_) => setState(() => _submissionId = null),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_contentController.text.runes.length}/1000',
                  textAlign: TextAlign.end,
                  style: AppTextStyles.supportCounter,
                ),
                const SizedBox(height: AppSpacing.xxl),
                InquiryAttachments(
                  count: _images.length,
                  picking: _isPickingImages,
                  onPick: _isPickingImages || _sending ? null : _pickImages,
                  onClear: _sending || _isPickingImages
                      ? null
                      : () => setState(() {
                          _images = [];
                          _submissionId = null;
                        }),
                ),
                const SizedBox(height: AppSpacing.xxl),
                InquirySubmitButton(
                  key: const ValueKey<String>('support-inquiry-submit'),
                  onPressed: _sending || _isPickingImages ? null : _submit,
                  sending: _sending,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickImages() async {
    setState(() => _isPickingImages = true);
    try {
      final images =
          await (widget.pickImages?.call() ??
              _imagePicker.pickMultiImage(maxWidth: 1920, imageQuality: 88));
      if (mounted) {
        if (images.isNotEmpty) {
          setState(() {
            _images = images.take(5).toList();
            _submissionId = null;
          });
        }
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지를 불러오지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImages = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_sending || _isPickingImages) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final draft = SupportInquiryDraft(
      id: _submissionId ??= createUuidV4(),
      type: _inquiryType,
      email: _emailController.text.trim(),
      content: _contentController.text.trim(),
      images: _images,
    );
    setState(() => _sending = true);
    try {
      final gateway = widget.gateway;
      if (gateway == null) {
        throw const SupportInquiryException('문의 전송 연결을 확인해 주세요.');
      }
      await gateway.submit(draft);
      if (!mounted) return;
      setState(() {
        _contentController.clear();
        _images = [];
        _submissionId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문의가 접수됐어요. 남겨주신 이메일로 답변드릴게요.')),
      );
      widget.onSubmitted?.call(draft);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is SupportInquiryException
                ? error.message
                : '문의를 보내지 못했어요. 다시 시도해 주세요.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
