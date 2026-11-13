import 'package:core_bloc/network/network_exception.dart';

/// Base contract for all Use Cases in Clean Architecture.
///
/// Every Use Case represents a single, focused piece of business logic.
/// Returns a [Result<Type>] containing either [Success] or [Failure].
abstract interface class BaseUseCase<Type, Params> {
  Future<Result<Type>> call(Params params);
}

/// Helper class for Use Cases that do not require parameters.
class NoParams {
  const NoParams();
}
