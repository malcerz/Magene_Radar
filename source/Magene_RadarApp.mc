import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Magene_RadarApp extends Application.AppBase {

    private var mBleManager as L508BleManager?;
    private var mLightNetwork as MageneLightNetworkManager?;
    private var mShowBattery as Boolean;
    private var mAtDeviceId as Lang.Number?;
    private var mLrDeviceId as Lang.Number?;

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
        mAtDeviceId = null;
        mLrDeviceId = null;

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
        if (mBleManager != null && mShowBattery) {
            mBleManager.start();
        }
        System.println("[MAGENE] start showBattery=" + mShowBattery + " AT=" + idText(mAtDeviceId) + " LR=" + idText(mLrDeviceId));
    }

    function onStop(state as Dictionary?) as Void {
        if (mBleManager != null) { mBleManager.stop(); }
    }

    function onSettingsChanged() as Void {
        loadSettings();
        applySettingsToBle();
        if (mBleManager != null) {
            mBleManager.setEnabled(mShowBattery);
            if (mShowBattery) { mBleManager.start(); }
        }
        WatchUi.requestUpdate();
    }

    private function loadSettings() as Void {
        mShowBattery = readBoolProperty("showBatteryStatus", true);
        mAtDeviceId = readIdProperty("atDeviceId");
        mLrDeviceId = readIdProperty("lrDeviceId");

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
    function getAtDeviceId() as Lang.Number? { return mAtDeviceId; }
    function getLrDeviceId() as Lang.Number? { return mLrDeviceId; }

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
