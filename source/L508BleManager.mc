import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

//! BLE battery reader for two Magene lights:
//! AT1200/AT1600 headlight (AT) and L508 radar/tail light (LR).
//! Device ids come from ANT+ when available and may also be entered manually.
class L508BleManager {

    private const ROLE_NONE = 0;
    private const ROLE_AT = 1;
    private const ROLE_LR = 2;

    private const BATTERY_SERVICE_UUID = BluetoothLowEnergy.stringToUuid("0000180f-0000-1000-8000-00805f9b34fb");
    private const BATTERY_LEVEL_UUID = BluetoothLowEnergy.stringToUuid("00002a19-0000-1000-8000-00805f9b34fb");
    private const BATTERY_PROFILE = {
        :uuid => BATTERY_SERVICE_UUID,
        :characteristics => [{ :uuid => BATTERY_LEVEL_UUID }]
    };

    private var mAtBattery as Lang.Number?;
    private var mLrBattery as Lang.Number?;
    private var mAtId as Lang.Number?;
    private var mLrId as Lang.Number?;

    private var mAtDevice as BluetoothLowEnergy.Device?;
    private var mLrDevice as BluetoothLowEnergy.Device?;
    private var mAtCharacteristic as BluetoothLowEnergy.Characteristic?;
    private var mLrCharacteristic as BluetoothLowEnergy.Characteristic?;
    private var mAtReadRequested as Boolean;
    private var mLrReadRequested as Boolean;
    private var mAtLastRead as Lang.Number?;
    private var mLrLastRead as Lang.Number?;

    private var mDelegate as L508BleDelegate?;
    private var mProfileRegistering as Boolean;
    private var mProfileRegistered as Boolean;
    private var mScanning as Boolean;
    private var mPairingRole as Lang.Number;
    private var mEnabled as Boolean;

    function initialize() {
        mAtBattery = null;
        mLrBattery = null;
        mAtId = null;
        mLrId = null;
        mAtDevice = null;
        mLrDevice = null;
        mAtCharacteristic = null;
        mLrCharacteristic = null;
        mAtReadRequested = false;
        mLrReadRequested = false;
        mAtLastRead = null;
        mLrLastRead = null;
        mDelegate = null;
        mProfileRegistering = false;
        mProfileRegistered = false;
        mScanning = false;
        mPairingRole = ROLE_NONE;
        mEnabled = true;
    }

    function setEnabled(enabled as Boolean) as Void {
        mEnabled = enabled;
        if (!enabled) {
            stopScan();
        } else if (mProfileRegistered) {
            ensureDiscovery();
        }
    }

    function setDeviceIds(atId as Lang.Number?, lrId as Lang.Number?) as Void {
        // null means "auto". A real manual-ID change invalidates an existing
        // BLE association; learning an ID from ANT (null -> value) does not.
        if (mAtId != null && atId != null && mAtId != atId) {
            disconnectRole(ROLE_AT);
            mAtBattery = null;
        } else if (mAtId != null && atId == null) {
            disconnectRole(ROLE_AT);
            mAtBattery = null;
        }
        if (mLrId != null && lrId != null && mLrId != lrId) {
            disconnectRole(ROLE_LR);
            mLrBattery = null;
        } else if (mLrId != null && lrId == null) {
            disconnectRole(ROLE_LR);
            mLrBattery = null;
        }
        mAtId = atId;
        mLrId = lrId;
        if (mProfileRegistered && mEnabled) { ensureDiscovery(); }
    }

    function start() as Void {
        if (!mEnabled || mProfileRegistering || mProfileRegistered) { return; }
        System.println("[MAGENE BLE] BUILD=DUAL-BAT-ANT-ID-V1");
        mDelegate = new L508BleDelegate(self);
        BluetoothLowEnergy.setDelegate(mDelegate as L508BleDelegate);
        mProfileRegistering = true;
        BluetoothLowEnergy.registerProfile(BATTERY_PROFILE);
    }

    function stop() as Void {
        stopScan();
    }

    function getAtBatteryPercent() as Lang.Number? { return mAtBattery; }
    function getLrBatteryPercent() as Lang.Number? { return mLrBattery; }
    // Backwards-compatible accessor used by older view code.
    function getBatteryPercent() as Lang.Number? { return mLrBattery; }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        if (!uuid.equals(BATTERY_SERVICE_UUID)) { return; }
        mProfileRegistering = false;
        System.println("[MAGENE BLE] profile registered status=" + status);
        if (status != BluetoothLowEnergy.STATUS_SUCCESS) { return; }
        mProfileRegistered = true;
        ensureDiscovery();
    }

    function onScanResults(scanResults as Iterator) as Void {
        if (!mProfileRegistered || !mEnabled || mPairingRole != ROLE_NONE) { return; }

        for (var result = scanResults.next(); result != null; result = scanResults.next()) {
            if (!(result instanceof BluetoothLowEnergy.ScanResult)) { continue; }
            var scanResult = result as BluetoothLowEnergy.ScanResult;
            var role = identifyRole(scanResult);
            if (role == ROLE_NONE) { continue; }

            var name = scanResult.getDeviceName();
            System.println("[MAGENE BLE] candidate role=" + role + " name=" + (name == null ? "<no name>" : name) + " RSSI=" + scanResult.getRssi());
            stopScan();
            connect(scanResult, role);
            return;
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        var role = roleForDevice(device);
        if (role == ROLE_NONE) {
            System.println("[MAGENE BLE] callback for unknown device state=" + state);
            return;
        }

        System.println("[MAGENE BLE] role=" + role + " state=" + state);
        if (state != BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            clearConnection(role);
            if (mPairingRole == role) { mPairingRole = ROLE_NONE; }
            ensureDiscovery();
            return;
        }

        mPairingRole = ROLE_NONE;
        findBatteryCharacteristic(device, role);
        ensureDiscovery();
    }

    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as ByteArray?) as Void {
        var role = ROLE_NONE;
        if (mAtCharacteristic != null && characteristic == mAtCharacteristic) { role = ROLE_AT; }
        else if (mLrCharacteristic != null && characteristic == mLrCharacteristic) { role = ROLE_LR; }
        if (role == ROLE_NONE) { return; }

        if (role == ROLE_AT) { mAtReadRequested = false; }
        else { mLrReadRequested = false; }

        if (status != BluetoothLowEnergy.STATUS_SUCCESS || value == null || value.size() < 1) {
            System.println("[MAGENE BLE] battery read failed role=" + role + " status=" + status);
            return;
        }

        var percent = value[0];
        if (percent < 0 || percent > 100) {
            System.println("[MAGENE BLE] invalid battery role=" + role + " value=" + percent);
            return;
        }

        if (role == ROLE_AT) { mAtBattery = percent; }
        else { mLrBattery = percent; }
        System.println("[MAGENE BLE] battery role=" + role + " value=" + percent + "%");
        ensureDiscovery();
    }

    function pollBatteryIfDue() as Void {
        if (!mEnabled) { return; }
        pollRoleIfDue(ROLE_AT);
        pollRoleIfDue(ROLE_LR);
        ensureDiscovery();
    }

    private function pollRoleIfDue(role as Lang.Number) as Void {
        var characteristic = role == ROLE_AT ? mAtCharacteristic : mLrCharacteristic;
        var requested = role == ROLE_AT ? mAtReadRequested : mLrReadRequested;
        var lastRead = role == ROLE_AT ? mAtLastRead : mLrLastRead;
        if (characteristic == null || requested || lastRead == null) { return; }

        var now = System.getTimer();
        var last = lastRead as Lang.Number;
        if (now >= last && now - last < 60000) { return; }
        requestBatteryRead(role);
    }

    private function requestBatteryRead(role as Lang.Number) as Void {
        var characteristic = role == ROLE_AT ? mAtCharacteristic : mLrCharacteristic;
        if (characteristic == null) { return; }
        if (role == ROLE_AT && mAtReadRequested) { return; }
        if (role == ROLE_LR && mLrReadRequested) { return; }

        if (role == ROLE_AT) {
            mAtReadRequested = true;
            mAtLastRead = System.getTimer();
        } else {
            mLrReadRequested = true;
            mLrLastRead = System.getTimer();
        }

        try {
            (characteristic as BluetoothLowEnergy.Characteristic).requestRead();
        } catch (e) {
            if (role == ROLE_AT) { mAtReadRequested = false; }
            else { mLrReadRequested = false; }
            System.println("[MAGENE BLE] requestRead error role=" + role + " err=" + e.getErrorMessage());
        }
    }

    private function ensureDiscovery() as Void {
        if (!mEnabled || !mProfileRegistered || mPairingRole != ROLE_NONE) { return; }
        if (mAtCharacteristic != null && mLrCharacteristic != null) {
            stopScan();
            return;
        }
        if (BluetoothLowEnergy.getAvailableConnectionCount() <= 0) {
            return;
        }
        startScan();
    }

    private function startScan() as Void {
        if (mScanning || !mEnabled || !mProfileRegistered || mPairingRole != ROLE_NONE) { return; }
        mScanning = true;
        System.println("[MAGENE BLE] scan started ATid=" + idText(mAtId) + " LRid=" + idText(mLrId));
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    private function stopScan() as Void {
        if (!mScanning) { return; }
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        mScanning = false;
    }

    private function connect(scanResult as BluetoothLowEnergy.ScanResult, role as Lang.Number) as Void {
        mPairingRole = role;
        try {
            var device = BluetoothLowEnergy.pairDevice(scanResult);
            if (device == null) {
                mPairingRole = ROLE_NONE;
                ensureDiscovery();
                return;
            }
            if (role == ROLE_AT) { mAtDevice = device; }
            else { mLrDevice = device; }
        } catch (e) {
            mPairingRole = ROLE_NONE;
            System.println("[MAGENE BLE] pair error role=" + role + " err=" + e.getErrorMessage());
            ensureDiscovery();
        }
    }

    private function findBatteryCharacteristic(device as BluetoothLowEnergy.Device, role as Lang.Number) as Void {
        var service = device.getService(BATTERY_SERVICE_UUID);
        if (service == null) {
            System.println("[MAGENE BLE] Battery Service missing role=" + role);
            return;
        }
        var characteristic = service.getCharacteristic(BATTERY_LEVEL_UUID);
        if (characteristic == null) {
            System.println("[MAGENE BLE] Battery Level missing role=" + role);
            return;
        }
        if (role == ROLE_AT) { mAtCharacteristic = characteristic; }
        else { mLrCharacteristic = characteristic; }
        requestBatteryRead(role);
    }

    private function disconnectRole(role as Lang.Number) as Void {
        var device = role == ROLE_AT ? mAtDevice : mLrDevice;
        if (device != null) {
            try { BluetoothLowEnergy.unpairDevice(device as BluetoothLowEnergy.Device); } catch (e) {}
        }
        clearConnection(role);
    }

    private function clearConnection(role as Lang.Number) as Void {
        if (role == ROLE_AT) {
            mAtDevice = null;
            mAtCharacteristic = null;
            mAtReadRequested = false;
        } else if (role == ROLE_LR) {
            mLrDevice = null;
            mLrCharacteristic = null;
            mLrReadRequested = false;
        }
    }

    private function roleForDevice(device as BluetoothLowEnergy.Device) as Lang.Number {
        if (mAtDevice != null && device == mAtDevice) { return ROLE_AT; }
        if (mLrDevice != null && device == mLrDevice) { return ROLE_LR; }
        return ROLE_NONE;
    }

    private function identifyRole(scanResult as BluetoothLowEnergy.ScanResult) as Lang.Number {
        var name = scanResult.getDeviceName();
        if (name == null) { return ROLE_NONE; }
        var upper = name.toUpper();

        if (mAtCharacteristic == null) {
            if (matchesId(name, mAtId) || upper.find("AT1600") != null || upper.find("AT1200") != null) {
                return ROLE_AT;
            }
        }
        if (mLrCharacteristic == null) {
            if (matchesId(name, mLrId) || upper.find("L508") != null || name.equals("19813-5")) {
                return ROLE_LR;
            }
        }
        return ROLE_NONE;
    }

    private function matchesId(name as String, id as Lang.Number?) as Boolean {
        if (id == null || id <= 0) { return false; }
        var text = id.format("%d");
        if (name.equals(text)) { return true; }
        return name.find(text + "-") == 0 || name.find(text + "_") == 0;
    }

    private function idText(id as Lang.Number?) as String {
        return id == null ? "--" : id.format("%d");
    }
}
