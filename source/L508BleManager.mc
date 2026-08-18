import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

//! Minimal BLE lifecycle for a single read of the Magene L508 Battery Level.
class L508BleManager {

    private const BATTERY_SERVICE_UUID = BluetoothLowEnergy.stringToUuid("0000180f-0000-1000-8000-00805f9b34fb");
    private const BATTERY_LEVEL_UUID = BluetoothLowEnergy.stringToUuid("00002a19-0000-1000-8000-00805f9b34fb");
    private const BATTERY_PROFILE = {
        :uuid => BATTERY_SERVICE_UUID,
        :characteristics => [{ :uuid => BATTERY_LEVEL_UUID }]
    };

    private var mBatteryPercent as Number?;
    private var mConnectionState as BluetoothLowEnergy.ConnectionState;
    private var mDevice as BluetoothLowEnergy.Device?;
    private var mBatteryService as BluetoothLowEnergy.Service?;
    private var mBatteryLevelCharacteristic as BluetoothLowEnergy.Characteristic?;
    private var mDelegate as L508BleDelegate?;
    private var mProfileRegistering as Boolean;
    private var mProfileRegistered as Boolean;
    private var mScanning as Boolean;
    private var mPairing as Boolean;
    private var mReadRequested as Boolean;
    private var mLastBatteryRequestTime as Number?;

    function initialize() {
        mBatteryPercent = null;
        mConnectionState = BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED;
        mDevice = null;
        mBatteryService = null;
        mBatteryLevelCharacteristic = null;
        mDelegate = null;
        mProfileRegistering = false;
        mProfileRegistered = false;
        mScanning = false;
        mPairing = false;
        mReadRequested = false;
        mLastBatteryRequestTime = null;
    }

    function start() as Void {
        if (mProfileRegistering || mProfileRegistered) {
            return;
        }

        System.println("[L508 BLE] BUILD=TEST4-COMPUTE-POLL60");
        System.println("[L508 BLE] init");
        mDelegate = new L508BleDelegate(self);
        BluetoothLowEnergy.setDelegate(mDelegate as L508BleDelegate);
        mProfileRegistering = true;
        System.println("[L508 BLE] registering Battery Service profile");
        BluetoothLowEnergy.registerProfile(BATTERY_PROFILE);
    }

    function stop() as Void {
        if (mScanning) {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
            mScanning = false;
        }
    }

    function getBatteryPercent() as Number? {
        return mBatteryPercent;
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        if (!uuid.equals(BATTERY_SERVICE_UUID)) {
            return;
        }

        mProfileRegistering = false;
        System.println("[L508 BLE] profile registered: " + status);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) {
            System.println("[L508 BLE] ERROR: Battery Service profile registration failed");
            return;
        }

        mProfileRegistered = true;
        connectBondedL508OrScan();
    }

    function onScanResults(scanResults as Iterator) as Void {
        if (!mProfileRegistered || mPairing) {
            return;
        }

        for (var result = scanResults.next(); result != null; result = scanResults.next()) {
            if (result instanceof BluetoothLowEnergy.ScanResult) {
                var scanResult = result as BluetoothLowEnergy.ScanResult;
                logScanResult(scanResult);
                if (isL508(scanResult)) {
                    System.println("[L508 BLE] L508 candidate found: " + scanResult.getDeviceName());
                    stopScan();
                    connect(scanResult);
                    return;
                }
            }
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (mDevice != null && mDevice != device) {
            return;
        }

        System.println("[L508 BLE] connection state=" + state);
        if (mConnectionState == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED && state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED && mReadRequested) {
            return;
        }
        mConnectionState = state;
        if (state != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            mBatteryPercent = null;
            mDevice = null;
            mBatteryService = null;
            mBatteryLevelCharacteristic = null;
            mReadRequested = false;
            mPairing = false;
            System.println("[L508 BLE] disconnected");
            return;
        }

        mDevice = device;
        mPairing = false;
        System.println("[L508 BLE] connected");
        findBatteryCharacteristic();
    }

    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as ByteArray?) as Void {
        mReadRequested = false;
        if (mBatteryLevelCharacteristic == null || characteristic != mBatteryLevelCharacteristic) {
            return;
        }

        System.println("[L508 BLE] battery read status=" + status);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS || value == null || value.size() < 1) {
            mBatteryPercent = null;
            System.println("[L508 BLE] ERROR: invalid battery read");
            return;
        }

        var percent = value[0];
        if (percent < 0 || percent > 100) {
            mBatteryPercent = null;
            System.println("[L508 BLE] ERROR: battery value out of range=" + percent);
            return;
        }

        var previousPercent = mBatteryPercent;
        mBatteryPercent = percent;
        System.println("[L508 BLE] battery=" + percent + "%");
        if (previousPercent != null && previousPercent != percent) {
            System.println("[L508 BLE] battery changed: " + previousPercent + " -> " + percent);
        }
    }

    private function connectBondedL508OrScan() as Void {
        var bondedDevices = BluetoothLowEnergy.getBondedDevices();
        for (var result = bondedDevices.next(); result != null; result = bondedDevices.next()) {
            if (result instanceof BluetoothLowEnergy.ScanResult) {
                var scanResult = result as BluetoothLowEnergy.ScanResult;
                logScanResult(scanResult);
                if (isL508(scanResult)) {
                    System.println("[L508 BLE] bonded L508 candidate found: " + scanResult.getDeviceName());
                    connect(scanResult);
                    return;
                }
            }
        }
        startScan();
    }

    private function startScan() as Void {
        if (mScanning || mPairing || !mProfileRegistered) {
            return;
        }
        mScanning = true;
        System.println("[L508 BLE] scan started");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    private function stopScan() as Void {
        if (!mScanning) {
            return;
        }
        System.println("[L508 BLE] stopping scan");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        mScanning = false;
    }

    private function connect(scanResult as BluetoothLowEnergy.ScanResult) as Void {
        if (mPairing) {
            return;
        }
        mPairing = true;
        System.println("[L508 BLE] connecting");
        mDevice = BluetoothLowEnergy.pairDevice(scanResult);
        if (mDevice == null) {
            mPairing = false;
            System.println("[L508 BLE] ERROR: pairDevice returned null");
        }
    }

    private function findBatteryCharacteristic() as Void {
        if (mDevice == null) {
            System.println("[L508 BLE] ERROR: connected callback without device");
            return;
        }

        mBatteryService = mDevice.getService(BATTERY_SERVICE_UUID);
        if (mBatteryService == null) {
            System.println("[L508 BLE] ERROR: Battery Service not found");
            return;
        }
        System.println("[L508 BLE] Battery Service found");

        mBatteryLevelCharacteristic = mBatteryService.getCharacteristic(BATTERY_LEVEL_UUID);
        if (mBatteryLevelCharacteristic == null) {
            System.println("[L508 BLE] ERROR: Battery Level characteristic not found");
            return;
        }
        System.println("[L508 BLE] Battery Level characteristic found");

        System.println("[L508 BLE] requesting battery");
        requestBatteryRead();
    }

    //! Called by the Data Field once per compute cycle; it only reads when 60 s elapsed.
    function pollBatteryIfDue() as Void {
        if (mConnectionState != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED || mBatteryLevelCharacteristic == null || mReadRequested || mLastBatteryRequestTime == null) {
            return;
        }

        var now = System.getTimer();
        var last = mLastBatteryRequestTime as Number;
        // getTimer() rolls over. A lower value means rollover, so read once now
        // rather than allowing a negative elapsed value to stall polling.
        if (now >= last && now - last < 60000) {
            return;
        }

        System.println("[L508 BLE] periodic battery read");
        requestBatteryRead();
    }

    private function requestBatteryRead() as Void {
        if (mConnectionState != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED || mBatteryLevelCharacteristic == null || mReadRequested) {
            return;
        }

        var characteristic = mBatteryLevelCharacteristic as BluetoothLowEnergy.Characteristic;
        mReadRequested = true;
        mLastBatteryRequestTime = System.getTimer();
        try {
            characteristic.requestRead();
        } catch (e) {
            mReadRequested = false;
            System.println("[L508 BLE] ERROR: requestRead failed: " + e.getErrorMessage());
        }
    }

    private function isL508(scanResult as BluetoothLowEnergy.ScanResult) as Boolean {
        var name = scanResult.getDeviceName();
        if (name == null) {
            System.println("[L508 BLE] CHECK name=[<no name>] len=0 exact=false");
            return false;
        }
        var exact = name.equals("19813-5");
        System.println("[L508 BLE] CHECK name=[" + name + "] len=" + name.length() + " exact=" + exact);
        return exact || name.toUpper().find("L508") != null;
    }

    private function logScanResult(scanResult as BluetoothLowEnergy.ScanResult) as Void {
        var name = scanResult.getDeviceName();
        if (name == null) {
            name = "<no name>";
        }
        System.println("[L508 BLE] found: " + name + " RSSI=" + scanResult.getRssi() + " services=" + serviceUuidsToString(scanResult.getServiceUuids()));
    }

    private function serviceUuidsToString(uuids as Iterator) as String {
        var result = "";
        for (var uuid = uuids.next(); uuid != null; uuid = uuids.next()) {
            if (result.length() > 0) {
                result += ",";
            }
            result += uuid.toString();
        }
        return result;
    }
}
