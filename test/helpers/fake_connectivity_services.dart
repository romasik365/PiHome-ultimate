import 'package:smart_display/services/bluetooth_service.dart';
import 'package:smart_display/services/wifi_service.dart';

/// Dobles sin procesos nativos; mantienen activo el refresco de conectividad.
class FakeWifiService extends WifiService {
  int currentSsidCalls = 0;

  @override
  Future<String?> currentSsid() async {
    currentSsidCalls++;
    return '';
  }

  @override
  Future<int?> signalOf(String ssid) async => null;
}

class FakeBluetoothService extends BluetoothService {
  int connectedDevicesCalls = 0;

  @override
  Future<List<BluetoothDevice>> connectedDevices() async {
    connectedDevicesCalls++;
    return const [];
  }
}
