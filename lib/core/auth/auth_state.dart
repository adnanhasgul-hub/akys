enum AuthStatus { checking, signedOut, authorized, denied, unavailable }

class AuthState {
  const AuthState(this.status);
  final AuthStatus status;
}

/// Only a trusted Admin SDK/IAM workflow may grant this custom claim.
class AdminAuthorization {
  const AdminAuthorization();

  bool allows(Map<String, dynamic>? claims) => claims?['admin'] == true;
}
