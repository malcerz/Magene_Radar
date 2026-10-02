import Toybox.Activity;
import Toybox.Ant;
import Toybox.AntPlus;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

//! Observer of the Garmin ANT+ Bike Lights network plus custom automatic
//! control for Magene AT1200/AT1600 and L508.
//!
//! The control path intentionally follows the proven SmartBikeLights approach:
//! once a concrete AntPlus.BikeLight object is reported, commands are sent with
//! BikeLight.setMode() instead of globally changing every headlight/taillight in
//! the Garmin network. Commands are confirmed by onBikeLightUpdate() and retried
//! when the light does not report the requested mode.
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
    private const CONTROL_OFF = 0;
    private const CONTROL_SOLAR = 1;
    private const CONTROL_SUNRISE_SUNSET = 2;

    // Direct-mode command confirmation/retry timing. ANT+ itself retries lower
    // level transfers, so we deliberately keep application retries conservative.
    private const COMMAND_RETRY_MS = 3000;
    private const COMMAND_BACKOFF_MS = 12000;
    private const MAX_FAST_RETRIES = 2;

    private var mNetwork;
    private var mListener;

    // Latest concrete lights reported by Garmin LightNetwork. With the user's
    // setup there is one AT headlight and one L508 taillight.
    private var mHeadlightLight as AntPlus.BikeLight?;
    private var mTailLightLight as AntPlus.BikeLight?;

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

    private var mLightControlMode as Lang.Number;
    private var mBrightnessUnder40 as Lang.Number;
    private var mBrightnessOver40 as Lang.Number;
    private var mControlTimer as Timer.Timer?;
    private var mSunTimes as SunTimes;
    private var mSolarFallbackLogged as Boolean;
    private var mLastLocation;

    // Requested modes and confirmation state.
    private var mDesiredHeadMode as Lang.Number?;
    private var mDesiredTailMode as Lang.Number?;
    private var mHeadPendingSince as Lang.Number?;
    private var mTailPendingSince as Lang.Number?;
    private var mHeadRetryCount as Lang.Number;
    private var mTailRetryCount as Lang.Number;

    function initialize() {
        mHeadlightLight = null;
        mTailLightLight = null;
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

        mLightControlMode = CONTROL_OFF;
        mBrightnessUnder40 = 60;
        mBrightnessOver40 = 100;
        mControlTimer = null;
        mSunTimes = new SunTimes();
        mSolarFallbackLogged = false;
        mLastLocation = null;

        mDesiredHeadMode = null;
        mDesiredTailMode = null;
        mHeadPendingSince = null;
        mTailPendingSince = null;
        mHeadRetryCount = 0;
        mTailRetryCount = 0;

        try {
            mListener = new MageneLightNetworkListener(self);
            mNetwork = new AntPlus.LightNetwork(mListener);
            System.println("[LIGHT ANT] LightNetwork initialized");
        } catch (e) {
            mNetwork = null;
            System.println("[LIGHT ANT] init error=" + e);
        }
    }

    //! mode: 0=off, 1=Solar, 2=sunrise/sunset.
    //! <=20 km/h is always Magene's lowest standard steady mode (ANT+ mode 5).
    function setLightControl(
        mode as Lang.Number,
        brightnessUnder40 as Lang.Number,
        brightnessOver40 as Lang.Number
    ) as Void {
        if (mode < CONTROL_OFF || mode > CONTROL_SUNRISE_SUNSET) { mode = CONTROL_OFF; }

        mBrightnessUnder40 = brightnessUnder40;
        mBrightnessOver40 = brightnessOver40;

        var oldMode = mLightControlMode;
        var wasActive = oldMode != CONTROL_OFF;
        var willBeActive = mode != CONTROL_OFF;
        mLightControlMode = mode;

        if (oldMode != mode) {
            resetCommandState();
            mSolarFallbackLogged = false;
        }

        if (willBeActive && !wasActive) {
            if (mControlTimer == null) { mControlTimer = new Timer.Timer(); }
            try {
                (mControlTimer as Timer.Timer).start(method(:onLightControlTick), 1000, true);
            } catch (e) {
                System.println("[LIGHT CTRL] timer start error=" + e);
            }
        } else if (!willBeActive && wasActive && mControlTimer != null) {
            try { (mControlTimer as Timer.Timer).stop(); } catch (e) {}
        }

        System.println("[LIGHT CTRL] mode=" + mLightControlMode
            + " <=20:MIN(mode5)"
            + " 20-40:" + mBrightnessUnder40
            + " >40:" + mBrightnessOver40);
    }

    function stop() as Void {
        if (mControlTimer != null) {
            try { (mControlTimer as Timer.Timer).stop(); } catch (e) {}
        }
        resetCommandState();
    }

    //! Runs once per second while custom light automation is enabled.
    private function onLightControlTick() as Void {
        if (mLightControlMode == CONTROL_OFF || mNetwork == null) { return; }

        var speedMps = null;
        var location = null;
        try {
            var info = Activity.getActivityInfo();
            if (info != null) {
                speedMps = info.currentSpeed;
                location = info.currentLocation;
            }
        } catch (e) {
        }

        if (location != null) { mLastLocation = location; }
        var usableLocation = location != null ? location : mLastLocation;
        var lightsOn = null;

        if (mLightControlMode == CONTROL_SOLAR) {
            var solar = getSolarIntensity();
            if (solar != null && solar >= 0) {
                // User rule: exactly zero means dark -> lights ON; any positive
                // solar intensity means lights OFF.
                lightsOn = (solar == 0);
            } else if (usableLocation != null) {
                // Edge 1040 and 1040 Solar share the same Connect IQ target.
                // On a non-Solar unit (or when Solar data is unavailable), use
                // sunrise/sunset instead of leaving the lamps uncontrolled.
                if (!mSolarFallbackLogged) {
                    mSolarFallbackLogged = true;
                    System.println("[LIGHT CTRL] Solar unavailable -> sunrise/sunset fallback");
                }
                lightsOn = mSunTimes.isNight(usableLocation);
            }
        } else if (mLightControlMode == CONTROL_SUNRISE_SUNSET && usableLocation != null) {
            lightsOn = mSunTimes.isNight(usableLocation);
        }

        if (lightsOn == null) { return; }
        applyLightState(lightsOn as Boolean, speedMps);
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

    //! on=false -> AT and LR OFF.
    //! on=true  -> AT steady intensity based on speed; LR restores the last
    //!             non-OFF L508 mode observed from the lamp.
    private function applyLightState(on as Boolean, speedMps) as Void {
        var desiredHead = AntPlus.LIGHT_MODE_OFF;
        var desiredTail = AntPlus.LIGHT_MODE_OFF;

        if (on) {
            var speedKph = 0.0;
            if (speedMps != null) { speedKph = speedMps * 3.6; }

            if (speedKph <= 20.0) {
                // SmartBikeLights' Magene mapping confirms mode 5 is Low and is
                // the standard ANT+ steady 0-20% bucket.
                desiredHead = supportedHeadlightMode(AntPlus.LIGHT_MODE_ST_0_20);
            } else if (speedKph <= 40.0) {
                desiredHead = supportedHeadlightMode(brightnessToMode(mBrightnessUnder40));
            } else {
                desiredHead = supportedHeadlightMode(brightnessToMode(mBrightnessOver40));
            }

            // Preserve rider-selected L508 mode. Known L508 modes are 4 Solid,
            // 5 Peloton, 6 Flash, 7 Quick Flash, 62 Pulse, 63 Rotation.
            desiredTail = mLastTailOnMode;
            if (desiredTail == null || desiredTail == AntPlus.LIGHT_MODE_OFF) {
                desiredTail = AntPlus.LIGHT_MODE_ST_21_40; // L508 Solid = mode 4
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

        // For standard steady modes 1..5 choose the nearest supported one.
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
        var changed = mDesiredHeadMode == null || mDesiredHeadMode != mode;
        if (changed) {
            mDesiredHeadMode = mode;
            mHeadPendingSince = null;
            mHeadRetryCount = 0;
        }

        if (mHeadlightMode != null && mHeadlightMode == mode) {
            mHeadPendingSince = null;
            mHeadRetryCount = 0;
            return;
        }
        if (mHeadlightLight == null) { return; }

        var now = System.getTimer();
        if (mHeadPendingSince == null) {
            sendHeadlightMode(mode, now, false);
            return;
        }

        var waitMs = mHeadRetryCount < MAX_FAST_RETRIES ? COMMAND_RETRY_MS : COMMAND_BACKOFF_MS;
        if (elapsedMs(now, mHeadPendingSince as Lang.Number) >= waitMs) {
            sendHeadlightMode(mode, now, true);
        }
    }

    private function commandTaillight(mode as Lang.Number) as Void {
        var changed = mDesiredTailMode == null || mDesiredTailMode != mode;
        if (changed) {
            mDesiredTailMode = mode;
            mTailPendingSince = null;
            mTailRetryCount = 0;
        }

        if (mTailLightMode != null && mTailLightMode == mode) {
            mTailPendingSince = null;
            mTailRetryCount = 0;
            return;
        }
        if (mTailLightLight == null) { return; }

        var now = System.getTimer();
        if (mTailPendingSince == null) {
            sendTaillightMode(mode, now, false);
            return;
        }

        var waitMs = mTailRetryCount < MAX_FAST_RETRIES ? COMMAND_RETRY_MS : COMMAND_BACKOFF_MS;
        if (elapsedMs(now, mTailPendingSince as Lang.Number) >= waitMs) {
            sendTaillightMode(mode, now, true);
        }
    }

    private function sendHeadlightMode(mode as Lang.Number, now as Lang.Number, retry as Boolean) as Void {
        try {
            (mHeadlightLight as AntPlus.BikeLight).setMode(mode);
            mHeadPendingSince = now;
            if (retry && mHeadRetryCount < MAX_FAST_RETRIES + 1) { mHeadRetryCount += 1; }
            System.println("[LIGHT CTRL] AT request mode=" + mode + " retry=" + mHeadRetryCount);
        } catch (e) {
            mHeadPendingSince = null;
            System.println("[LIGHT CTRL] AT setMode error=" + e);
        }
    }

    private function sendTaillightMode(mode as Lang.Number, now as Lang.Number, retry as Boolean) as Void {
        try {
            (mTailLightLight as AntPlus.BikeLight).setMode(mode);
            mTailPendingSince = now;
            if (retry && mTailRetryCount < MAX_FAST_RETRIES + 1) { mTailRetryCount += 1; }
            System.println("[LIGHT CTRL] LR request mode=" + mode + " retry=" + mTailRetryCount);
        } catch (e) {
            mTailPendingSince = null;
            System.println("[LIGHT CTRL] LR setMode error=" + e);
        }
    }

    private function elapsedMs(now as Lang.Number, then as Lang.Number) as Lang.Number {
        if (now >= then) { return now - then; }
        // System timer wrapped; make the command immediately eligible for retry.
        return COMMAND_BACKOFF_MS;
    }

    private function resetCommandState() as Void {
        mDesiredHeadMode = null;
        mDesiredTailMode = null;
        mHeadPendingSince = null;
        mTailPendingSince = null;
        mHeadRetryCount = 0;
        mTailRetryCount = 0;
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
                // Exact percent is read from page 19/BLE; this is fallback status.
            }
        }

        if (data.type == AntPlus.LIGHT_TYPE_HEADLIGHT) {
            mHeadlightLight = data;
            mHeadlightMode = data.mode;
            mHeadlightBatteryStatus = batteryStatus;
            try {
                var modes = data.getCapableModes();
                if (modes != null) { mHeadlightCapableModes = modes; }
            } catch (e) {
            }

            if (mDesiredHeadMode != null && data.mode == mDesiredHeadMode) {
                mHeadPendingSince = null;
                mHeadRetryCount = 0;
                System.println("[LIGHT CTRL] AT confirmed mode=" + data.mode);
            }
        } else if (data.type == AntPlus.LIGHT_TYPE_TAILLIGHT) {
            mTailLightLight = data;
            mTailLightMode = data.mode;
            mTailLightBatteryStatus = batteryStatus;
            if (data.mode != AntPlus.LIGHT_MODE_OFF) {
                mLastTailOnMode = data.mode;
            }

            if (mDesiredTailMode != null && data.mode == mDesiredTailMode) {
                mTailPendingSince = null;
                mTailRetryCount = 0;
                System.println("[LIGHT CTRL] LR confirmed mode=" + data.mode);
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
