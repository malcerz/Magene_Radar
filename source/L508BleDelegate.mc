import Toybox.BluetoothLowEnergy;
import Toybox.Lang;

//! Routes Bluetooth Low Energy callbacks to the L508 manager.
class L508BleDelegate extends BluetoothLowEnergy.BleDelegate {

    private var mManager as L508BleManager;

    function initialize(manager as L508BleManager) {
        BleDelegate.initialize();
        mManager = manager;
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        mManager.onProfileRegister(uuid, status);
    }

    function onScanResults(scanResults as Iterator) as Void {
        mManager.onScanResults(scanResults);
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        mManager.onConnectedStateChanged(device, state);
    }

    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as ByteArray) as Void {
        mManager.onCharacteristicRead(characteristic, status, value);
    }
}
