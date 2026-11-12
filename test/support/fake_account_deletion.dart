import 'dart:async';

import 'package:soolgyul/src/features/profile/data/account_deletion_gateway.dart';

/// An [AccountDeletionGateway] that answers [fetchStatus] with [status], or,
/// when none is given, holds the answer until [server] is completed.
class FakeAccountDeletionGateway implements AccountDeletionGateway {
  FakeAccountDeletionGateway([this.status]);

  AccountDeletionStatus? status;
  final Completer<AccountDeletionStatus> server =
      Completer<AccountDeletionStatus>();
  int deletions = 0;
  int restores = 0;
  int fetches = 0;

  /// What the real gateway does once the server has scheduled it.
  Future<void> Function()? afterScheduled;

  @override
  Future<AccountDeletionStatus> fetchStatus() async {
    fetches += 1;
    return status ?? server.future;
  }

  @override
  Future<void> requestDeletion() async {
    deletions += 1;
    await afterScheduled?.call();
  }

  @override
  Future<void> restore() async {
    restores += 1;
    status = const AccountDeletionStatus(state: 'active');
  }
}
