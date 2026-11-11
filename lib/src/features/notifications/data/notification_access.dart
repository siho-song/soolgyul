/// Whether this phone shows the app's notifications.
enum NotificationStatus {
  /// Turned on in the app, and the phone allows them.
  on,

  /// Not turned on yet, or turned off in the app.
  off,

  /// The phone's settings refuse them; only those settings change that.
  blocked,
}

/// Turning the app's notifications on and off for this phone.
abstract interface class NotificationAccess {
  Future<NotificationStatus> load();

  /// Turns notifications on. The first time, the phone asks the member, and
  /// a refusal there answers [NotificationStatus.blocked].
  Future<NotificationStatus> turnOn();

  Future<NotificationStatus> turnOff();

  /// Opens the phone's own notification settings of the app.
  Future<void> openPhoneSettings();

  /// A signed-in member has arrived: a phone that has notifications on is
  /// made known to the server again, under this account.
  Future<void> resume();

  /// The member is signing out: the server forgets this phone, so nothing
  /// meant for the account shows on it. Signing in again resumes.
  Future<void> forgetThisPhone();
}

/// [NotificationAccess] kept in memory, for looking at the screens before a
/// phone is connected. It never asks the phone and never sends anything.
class PretendNotificationAccess implements NotificationAccess {
  PretendNotificationAccess({this.status = NotificationStatus.off});

  NotificationStatus status;

  @override
  Future<NotificationStatus> load() async => status;

  @override
  Future<NotificationStatus> turnOn() async {
    if (status != NotificationStatus.blocked) status = NotificationStatus.on;
    return status;
  }

  @override
  Future<NotificationStatus> turnOff() async {
    if (status != NotificationStatus.blocked) status = NotificationStatus.off;
    return status;
  }

  @override
  Future<void> openPhoneSettings() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> forgetThisPhone() async {}
}
