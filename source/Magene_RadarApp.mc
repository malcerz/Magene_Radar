import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Magene_RadarApp extends Application.AppBase {

    private var mBleManager as L508BleManager?;
    private var mLightNetwork as MageneLightNetworkManager?;
    private var mShowBattery as Boolean;
    private var mTurnOffAtOnStop as Boolean;
    private var mAtDeviceId as Lang.Number?;
    private var mLrDeviceId as Lang.Number?;

    // Light automation: 0=off, 1=Solar, 2=sunrise/sunset.
    private var mLightControlMode as Lang.Number;
    private var mBrightnessUnder20 as Lang.Number;
    private var mBrightnessUnder40 as Lang.Number;
    private var mBrightnessOver40 as Lang.Number;

    // Radar field switches. The view takes the first N enabled fields depending
    // on the physical slot size: 10-layout=2, 9-layout=5, 7-layout=5, 1-layout=all.
    private var mShowCurrentCars as Boolean;
    private var mShowRelativeSpeed as Boolean;
    private var mShowNearestDistance as Boolean;
    private var mShowThreatLevel as Boolean;
    private var mShowThreatSide as Boolean;
    private var mShowSessionCounter as Boolean;
    private var mShowEstimatedSpeed as Boolean;

    function initialize() {
        AppBase.initialize();
        mBleManager = new L508BleManager();
        mLightNetwork = new MageneLightNetworkManager();
        mShowBattery = true;
        mTurnOffAtOnStop = true;
        mAtDeviceId = null;
        mLrDeviceId = null;

        mLightControlMode = 0;
        // <=20 km/h is fixed to the lowest steady ANT+ headlight mode.
        mBrightnessUnder20 = 20;
        mBrightnessUnder40 = 60;
        mBrightnessOver40 = 100;

        mShowCurrentCars = true;
        mShowRelativeSpeed = true;
        mShowNearestDistance = true;
        mShowThreatLevel = true;
        mShowThreatSide = true;
        mShowSessionCounter = true;
        mShowEstimatedSpeed = true;
    }

    function onStart(state as Dictionary?) as Void {
        loadSettings();
        applySettingsToBle();
        applySettingsToLights();
        if (mBleManager != null && mShowBattery) {
            mBleManager.start();
        }
        System.println("[MAGENE] start showBattery=" + mShowBattery
            + " lightControlMode=" + mLightControlMode
            + " AT=" + idText(mAtDeviceId)
            + " LR=" + idText(mLrDeviceId));
    }

    function onStop(state as Dictionary?) as Void {
        if (mBleManager != null) { mBleManager.stop(); }
        if (mLightNetwork != null) { mLightNetwork.stop(); }
    }

    function onSettingsChanged() as Void {
        loadSettings();
        applySettingsToBle();
        applySettingsToLights();
        if (mBleManager != null) {
            mBleManager.setEnabled(mShowBattery);
            if (mShowBattery) { mBleManager.start(); }
        }
        WatchUi.requestUpdate();
    }

    private function loadSettings() as Void {
        mShowBattery = readBoolProperty("showBatteryStatus", true);
        mTurnOffAtOnStop = readBoolProperty("turnOffAtOnStop", true);
        mAtDeviceId = readIdProperty("atDeviceId");
        mLrDeviceId = readIdProperty("lrDeviceId");

        mLightControlMode = readNumberProperty("lightControlMode", 0);
        if (mLightControlMode < 0 || mLightControlMode > 2) { mLightControlMode = 0; }
        // Always use the minimum steady-light bucket below/equal 20 km/h.
        mBrightnessUnder20 = 20;
        mBrightnessUnder40 = readNumberProperty("brightnessUnder40", 60);
        mBrightnessOver40 = readNumberProperty("brightnessOver40", 100);

        mShowCurrentCars = readBoolProperty("showCurrentCars", true);
        mShowRelativeSpeed = readBoolProperty("showRelativeSpeed", true);
        mShowNearestDistance = readBoolProperty("showNearestDistance", true);
        mShowThreatLevel = readBoolProperty("showThreatLevel", true);
        mShowThreatSide = readBoolProperty("showThreatSide", true);
        mShowSessionCounter = readBoolProperty("showSessionCounter", true);
        mShowEstimatedSpeed = readBoolProperty("showEstimatedSpeed", true);
    }

    private function readBoolProperty(key as String, fallback as Boolean) as Boolean {
        try {
            var value = Application.Properties.getValue(key);
            if (value != null) { return value as Boolean; }
        } catch (e) {
        }
        return fallback;
    }

    private function readNumberProperty(key as String, fallback as Lang.Number) as Lang.Number {
        try {
            var value = Application.Properties.getValue(key);
            if (value != null) { return value as Lang.Number; }
        } catch (e) {
        }
        return fallback;
    }

    private function readIdProperty(key as String) as Lang.Number? {
        try {
            var value = Application.Properties.getValue(key);
            if (value != null) {
                var number = value as Lang.Number;
                if (number > 0) { return number; }
            }
        } catch (e) {
        }
        return null;
    }

    private function applySettingsToBle() as Void {
        if (mBleManager == null) { return; }
        mBleManager.setEnabled(mShowBattery);
        mBleManager.setDeviceIds(mAtDeviceId, mLrDeviceId);
    }

    private function applySettingsToLights() as Void {
        if (mLightNetwork == null) { return; }
        mLightNetwork.setLightControl(
            mLightControlMode,
            mBrightnessUnder40,
            mBrightnessOver40
        );
    }

    //! Store an automatically learned ANT id only when the setting is empty.
    //! The property is linked to the phone IQ settings, so reopening settings
    //! shows the learned value. A manually entered non-zero id is never replaced.
    function rememberAtDeviceId(id as Lang.Number?) as Void {
        if (id == null || id <= 0 || mAtDeviceId != null) { return; }
        mAtDeviceId = id;
        try { Application.Properties.setValue("atDeviceId", id); } catch (e) {}
        if (mBleManager != null) { mBleManager.setDeviceIds(mAtDeviceId, mLrDeviceId); }
        System.println("[MAGENE] saved auto AT id=" + id);
    }

    function rememberLrDeviceId(id as Lang.Number?) as Void {
        if (id == null || id <= 0 || mLrDeviceId != null) { return; }
        mLrDeviceId = id;
        try { Application.Properties.setValue("lrDeviceId", id); } catch (e) {}
        if (mBleManager != null) { mBleManager.setDeviceIds(mAtDeviceId, mLrDeviceId); }
        System.println("[MAGENE] saved auto LR id=" + id);
    }

    function getBleManager() as L508BleManager? { return mBleManager; }
    function getL508BleManager() as L508BleManager? { return mBleManager; }
    function getLightNetworkManager() as MageneLightNetworkManager? { return mLightNetwork; }
    function getShowBatteryStatus() as Boolean { return mShowBattery; }
    function getTurnOffAtOnStop() as Boolean { return mTurnOffAtOnStop; }
    function getAtDeviceId() as Lang.Number? { return mAtDeviceId; }
    function getLrDeviceId() as Lang.Number? { return mLrDeviceId; }

    function getLightControlMode() as Lang.Number { return mLightControlMode; }
    function getBrightnessUnder20() as Lang.Number { return mBrightnessUnder20; }
    function getBrightnessUnder40() as Lang.Number { return mBrightnessUnder40; }
    function getBrightnessOver40() as Lang.Number { return mBrightnessOver40; }

    function getShowCurrentCars() as Boolean { return mShowCurrentCars; }
    function getShowRelativeSpeed() as Boolean { return mShowRelativeSpeed; }
    function getShowNearestDistance() as Boolean { return mShowNearestDistance; }
    function getShowThreatLevel() as Boolean { return mShowThreatLevel; }
    function getShowThreatSide() as Boolean { return mShowThreatSide; }
    function getShowSessionCounter() as Boolean { return mShowSessionCounter; }
    function getShowEstimatedSpeed() as Boolean { return mShowEstimatedSpeed; }

    private function idText(id as Lang.Number?) as String {
        return id == null ? "--" : id.format("%d");
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new Magene_RadarView() ];
    }
}

function getApp() as Magene_RadarApp {
    return Application.getApp() as Magene_RadarApp;
}
