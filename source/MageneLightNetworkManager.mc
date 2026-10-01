import Toybox.Activity;
import Toybox.Ant;
import Toybox.AntPlus;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

//! Observer of the Garmin ANT+ Bike Lights network plus optional custom
//! Solar-based control for Magene AT front light and L508 tail light.
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

    private var mHeadlightCapableModes;
    private var mLastTailOnMode as Lang.Number?;

    private var mSolarControlEnabled as Boolean;
    private var mBrightnessUnder20 as Lang.Number;
    private var mBrightnessUnder40 as Lang.Number;
    private var mBrightnessOver40 as Lang.Number;
    private var mControlTimer as Timer.Timer?;
    private var mLastCommandedHeadMode as Lang.Number?;
    private var mLastCommandedTailMode as Lang.Number?;

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

        mHeadlightCapableModes = null;
        mLastTailOnMode = null;

        mSolarControlEnabled = false;
        mBrightnessUnder20 = 40;
        mBrightnessUnder40 = 60;
        mBrightnessOver40 = 100;
        mControlTimer = null;
        mLastCommandedHeadMode = null;
        mLastCommandedTailMode = null;

        try {
            mListener = new MageneLightNetworkListener(self);
            mNetwork = new AntPlus.LightNetwork(mListener);
            System.println("[LIGHT ANT] LightNetwork initialized");
        } catch (e) {
            mNetwork = null;
            System.println("[LIGHT ANT] init error=" + e);
        }
    }

    function setSolarControl(
        enabled as Boolean,
        brightnessUnder20 as Lang.Number,
        brightnessUnder40 as Lang.Number,
        brightnessOver40 as Lang.Number
    ) as Void {
        mBrightnessUnder20 = brightnessUnder20;
        mBrightnessUnder40 = brightnessUnder40;
        mBrightnessOver40 = brightnessOver40;

        if (mSolarControlEnabled == enabled) { return; }

        mSolarControlEnabled = enabled;
        mLastCommandedHeadMode = null;
        mLastCommandedTailMode = null;

        if (enabled) {
            if (mControlTimer == null) { mControlTimer = new Timer.Timer(); }
            try {
                (mControlTimer as Timer.Timer).start(method(:onSolarControlTick), 1000, true);
            } catch (e) {
                System.println("[LIGHT CTRL] timer start error=" + e);
            }
        } else if (mControlTimer != null) {
            try { (mControlTimer as Timer.Timer).stop(); } catch (e) {}
        }

        System.println("[LIGHT CTRL] solar control=" + enabled
            + " <=20:" + mBrightnessUnder20
            + " <=40:" + mBrightnessUnder40
            + " >40:" + mBrightnessOver40);
    }

    function stop() as Void {
        if (mControlTimer != null) {
            try { (mControlTimer as Timer.Timer).stop(); } catch (e) {}
        }
    }

    //! Runs once per second while Solar automation is enabled.
    private function onSolarControlTick() as Void {
        if (!mSolarControlEnabled || mNetwork == null) { return; }

        var solar = getSolarIntensity();
        if (solar == null || solar < 0) {
            // null = not supported. Negative = device is not currently charging,
            // which is not a reliable darkness indication.
            return;
        }

        var speedMps = null;
        try {
            var info = Activity.getActivityInfo();
            if (info != null) { speedMps = info.currentSpeed; }
        } catch (e) {
        }

        applySolarState(solar, speedMps);
    }

    private function getSolarIntensity() as Lang.Number? {
        try {
            var stats = System.getSystemStats();
            if (stats has :solarIntensity) {
                var value = stats.solarIntensity;
                if (value != null) { return value as Lang.Number; }
            }
        } catch (e) {
        }
        return null;
    }

    //! solar > 0  -> both lights OFF
    //! solar == 0 -> AT steady intensity based on speed; LR restores its last ON mode.
    private function applySolarState(solar as Lang.Number, speedMps) as Void {
        var desiredHead = AntPlus.LIGHT_MODE_OFF;
        var desiredTail = AntPlus.LIGHT_MODE_OFF;

        if (solar == 0) {
            var speedKph = 0.0;
            if (speedMps != null) { speedKph = speedMps * 3.6; }

            var brightness = mBrightnessOver40;
            if (speedKph <= 20.0) {
                brightness = mBrightnessUnder20;
            } else if (speedKph <= 40.0) {
                brightness = mBrightnessUnder40;
            }

            desiredHead = supportedHeadlightMode(brightnessToMode(brightness));

            // Preserve the rider's existing L508 mode. If no ON mode has been
            // observed yet, mode 4 is steady 21-40% in ANT+ and the known
            // "Solid" mode reported by L508.
            desiredTail = mLastTailOnMode;
            if (desiredTail == null || desiredTail == AntPlus.LIGHT_MODE_OFF) {
                desiredTail = AntPlus.LIGHT_MODE_ST_21_40;
            }
        }

        commandHeadlight(desiredHead);
        commandTaillight(desiredTail);
    }

    private function brightnessToMode(brightness as Lang.Number) as Lang.Number {
        if (brightness <= 20) { return AntPlus.LIGHT_MODE_ST_0_20; }
        if (brightness <= 40) { return AntPlus.LIGHT_MODE_ST_21_40; }
        if (brightness <= 60) { return AntPlus.LIGHT_MODE_ST_41_60; }
        if (brightness <= 80) { return AntPlus.LIGHT_MODE_ST_61_80; }
        return AntPlus.LIGHT_MODE_ST_81_100;
    }

    private function supportedHeadlightMode(requested as Lang.Number) as Lang.Number {
        if (mHeadlightCapableModes == null || mHeadlightCapableModes.size() == 0) {
            return requested;
        }

        for (var i = 0; i < mHeadlightCapableModes.size(); i++) {
            if (mHeadlightCapableModes[i] == requested) { return requested; }
        }

        // For standard steady intensity modes 1..5 choose the closest supported one.
        var best = null;
        var bestDistance = 999;
        for (var j = 0; j < mHeadlightCapableModes.size(); j++) {
            var mode = mHeadlightCapableModes[j];
            if (mode >= AntPlus.LIGHT_MODE_ST_81_100 && mode <= AntPlus.LIGHT_MODE_ST_0_20) {
                var distance = mode - requested;
                if (distance < 0) { distance = -distance; }
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = mode;
                }
            }
        }
        return best == null ? requested : best;
    }

    private function commandHeadlight(mode as Lang.Number) as Void {
        if (mLastCommandedHeadMode != null && mLastCommandedHeadMode == mode) { return; }
        try {
            mNetwork.setHeadlightsMode(mode);
            mLastCommandedHeadMode = mode;
            System.println("[LIGHT CTRL] AT mode=" + mode);
        } catch (e) {
            System.println("[LIGHT CTRL] AT setMode error=" + e);
        }
    }

    private function commandTaillight(mode as Lang.Number) as Void {
        if (mLastCommandedTailMode != null && mLastCommandedTailMode == mode) { return; }
        try {
            mNetwork.setTaillightsMode(mode);
            mLastCommandedTailMode = mode;
            System.println("[LIGHT CTRL] LR mode=" + mode);
        } catch (e) {
            System.println("[LIGHT CTRL] LR setMode error=" + e);
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
            try {
                var modes = data.getCapableModes();
                if (modes != null) { mHeadlightCapableModes = modes; }
            } catch (e) {
            }
        } else if (data.type == AntPlus.LIGHT_TYPE_TAILLIGHT) {
            mTailLightMode = data.mode;
            mTailLightBatteryStatus = batteryStatus;
            if (data.mode != AntPlus.LIGHT_MODE_OFF) {
                mLastTailOnMode = data.mode;
            }
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
