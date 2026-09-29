import Toybox.Ant;
import Toybox.AntPlus;
import Toybox.Lang;
import Toybox.System;

//! Read-only observer of the Garmin ANT+ Bike Lights network.
//! It learns the ANT device number directly from raw light messages and also
//! captures the optional Bike Lights supplementary battery percentage page.
class MageneLightNetworkListener extends AntPlus.LightNetworkListener {
    private var mManager;

    function initialize(manager) {
        LightNetworkListener.initialize();
        mManager = manager;
    }

    function onMessage(msg as Ant.Message) as Void {
        mManager.onRawMessage(msg);
    }

    function onBikeLightUpdate(data as AntPlus.BikeLight) as Void {
        mManager.onBikeLightUpdate(data);
    }

    function onLightNetworkStateUpdate(data as AntPlus.LightNetworkState) as Void {
        mManager.onNetworkStateUpdate(data);
    }
}

class MageneLightNetworkManager {
    private var mNetwork;
    private var mListener;
    private var mHeadlightDeviceId as Lang.Number?;
    private var mTailLightDeviceId as Lang.Number?;
    private var mHeadlightMode as Lang.Number?;
    private var mTailLightMode as Lang.Number?;
    private var mHeadlightBatteryStatus as Lang.Number?;
    private var mTailLightBatteryStatus as Lang.Number?;
    private var mHeadlightBatteryPercent as Lang.Number?;
    private var mTailLightBatteryPercent as Lang.Number?;
    private var mBatteryByDevice as Lang.Dictionary;

    function initialize() {
        mHeadlightDeviceId = null;
        mTailLightDeviceId = null;
        mHeadlightMode = null;
        mTailLightMode = null;
        mHeadlightBatteryStatus = null;
        mTailLightBatteryStatus = null;
        mHeadlightBatteryPercent = null;
        mTailLightBatteryPercent = null;
        mBatteryByDevice = {};

        try {
            mListener = new MageneLightNetworkListener(self);
            mNetwork = new AntPlus.LightNetwork(mListener);
            System.println("[LIGHT ANT] LightNetwork initialized (read-only)");
        } catch (e) {
            mNetwork = null;
            System.println("[LIGHT ANT] init error=" + e);
        }
    }

    //! Parse raw Bike Lights pages. Ant.Message.deviceNumber is the source ANT ID.
    function onRawMessage(msg as Ant.Message) as Void {
        var deviceId = msg.deviceNumber;
        if (deviceId == null || deviceId <= 0) { return; }

        var payload;
        try { payload = msg.getPayload(); } catch (e) { return; }
        if (payload == null || payload.size() < 8) { return; }

        // Managed-network packets may use normal format (page in byte 0)
        // or shared format (light index in byte 0, page in byte 1).
        var page = payload[0];
        if (page != 0x01 && page != 0x13 && payload[1] != null) {
            page = payload[1];
        }

        if (page == 0x01) {
            // Data Page 1: bits 2..4 of byte 2 contain the light type.
            var lightType = (payload[2] >> 2) & 0x07;
            if (lightType == AntPlus.LIGHT_TYPE_HEADLIGHT) {
                if (mHeadlightDeviceId != deviceId) {
                    mHeadlightDeviceId = deviceId;
                    System.println("[LIGHT ANT] raw headlight id=" + deviceId);
                }
                applyStoredBattery(deviceId, true);
            } else if (lightType == AntPlus.LIGHT_TYPE_TAILLIGHT) {
                if (mTailLightDeviceId != deviceId) {
                    mTailLightDeviceId = deviceId;
                    System.println("[LIGHT ANT] raw taillight id=" + deviceId);
                }
                applyStoredBattery(deviceId, false);
            }
        } else if (page == 0x13) {
            // Data Page 19: byte 7 = remaining battery percentage; 0xFF = invalid.
            var percent = payload[7];
            if (percent >= 0 && percent <= 100) {
                mBatteryByDevice[deviceId.format("%d")] = percent;
                if (mHeadlightDeviceId == deviceId) { mHeadlightBatteryPercent = percent; }
                if (mTailLightDeviceId == deviceId) { mTailLightBatteryPercent = percent; }
                System.println("[LIGHT ANT] battery id=" + deviceId + " value=" + percent + "%");
            }
        }
    }

    private function applyStoredBattery(deviceId as Lang.Number, headlight as Boolean) as Void {
        var key = deviceId.format("%d");
        var value = mBatteryByDevice[key];
        if (value == null) { return; }
        if (headlight) { mHeadlightBatteryPercent = value as Lang.Number; }
        else { mTailLightBatteryPercent = value as Lang.Number; }
    }

    function onBikeLightUpdate(data as AntPlus.BikeLight) as Void {
        var batteryStatus = null;
        if (mNetwork != null && data.identifier != null) {
            try {
                var bs = mNetwork.getBatteryStatus(data.identifier);
                if (bs != null) { batteryStatus = bs.batteryStatus; }
            } catch (e) {
                // Exact percent is read from page 19/BLE; this is only fallback status.
            }
        }

        if (data.type == AntPlus.LIGHT_TYPE_HEADLIGHT) {
            mHeadlightMode = data.mode;
            mHeadlightBatteryStatus = batteryStatus;
        } else if (data.type == AntPlus.LIGHT_TYPE_TAILLIGHT) {
            mTailLightMode = data.mode;
            mTailLightBatteryStatus = batteryStatus;
        }
    }

    function onNetworkStateUpdate(state as AntPlus.LightNetworkState) as Void {
        System.println("[LIGHT ANT] network state=" + state);
    }

    function getBatteryPercentForDevice(id as Lang.Number?) as Lang.Number? {
        if (id == null || id <= 0) { return null; }
        var value = mBatteryByDevice[id.format("%d")];
        return value == null ? null : value as Lang.Number;
    }

    function getHeadlightDeviceId() as Lang.Number? { return mHeadlightDeviceId; }
    function getTailLightDeviceId() as Lang.Number? { return mTailLightDeviceId; }
    function getHeadlightMode() as Lang.Number? { return mHeadlightMode; }
    function getTailLightMode() as Lang.Number? { return mTailLightMode; }
    function getHeadlightBatteryStatus() as Lang.Number? { return mHeadlightBatteryStatus; }
    function getTailLightBatteryStatus() as Lang.Number? { return mTailLightBatteryStatus; }
    function getHeadlightBatteryPercent() as Lang.Number? { return mHeadlightBatteryPercent; }
    function getTailLightBatteryPercent() as Lang.Number? { return mTailLightBatteryPercent; }
}
