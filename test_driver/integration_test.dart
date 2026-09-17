import 'package:integration_test/integration_test_driver.dart';

/// Controlador para `flutter drive` en escritorio/dispositivo real:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_test.dart -d linux
Future<void> main() => integrationDriver();
