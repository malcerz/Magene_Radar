import Toybox.Activity;
import Toybox.AntPlus;
import Toybox.System;
import Toybox.Math;
import Toybox.Lang;

class L508RadarManager {
    const PASS_DISTANCE_METERS = 10.0;
    const MATCH_DISTANCE_METERS = 20.0;

    private var mRadar;
    private var mTracks as Lang.Array<Lang.Dictionary> = [];

    // Session statistics.
    private var mVehicleCount as Lang.Number = 0;
    private var mLastSpeed as Lang.Number? = null;

    // Live data for the currently nearest radar target.
    private var mCurrentVehicleCount as Lang.Number = 0;
    private var mNearestDistance as Lang.Number? = null;
    private var mNearestRelativeSpeed as Lang.Number? = null;
    private var mNearestEstimatedSpeed as Lang.Number? = null;
    private var mNearestThreat as Lang.Number? = null;
    private var mNearestThreatSide as Lang.Number? = null;

    private var mReportedData as Lang.Boolean = false;
    private var mDeviceId as Lang.Number? = null;
    private var mBatteryStatus as Lang.Number? = null;

    function initialize() {
        try {
            mRadar = new AntPlus.BikeRadar(null);
            System.println("[L508 ANT] BikeRadar initialized");
        } catch (e) {
            mRadar = null;
            System.println("[L508 ANT] BikeRadar init error=" + e);
        }
    }

    function update(info) as Void {
        if (mRadar == null) { return; }
        updateDeviceId();
        updateBatteryStatus();

        var targets;
        try { targets = mRadar.getRadarInfo(); } catch (e) {
            System.println("[L508 ANT] getRadarInfo error=" + e);
            clearLiveData();
            return;
        }
        if (targets == null) {
            clearLiveData();
            return;
        }

        if (targets.size() > 0 && !mReportedData) {
            mReportedData = true;
            System.println("[L508 ANT] first radar data received");
        }

        // Rebuild live values on every radar update.
        clearLiveData();
        var nearestRange = null;

        for (var oi = 0; oi < mTracks.size(); oi++) { mTracks[oi]["seen"] = false; }

        for (var ti = 0; ti < targets.size(); ti++) {
            var target = targets[ti];
            if (target == null || target.threat == AntPlus.THREAT_LEVEL_NO_THREAT) { continue; }

            var range = target.range;
            if (range == null || range < 0) { continue; }

            mCurrentVehicleCount += 1;

            // The live distance/speed/threat fields describe the nearest target.
            if (nearestRange == null || range < nearestRange) {
                nearestRange = range;
                mNearestDistance = Math.round(range);
                mNearestRelativeSpeed = relativeSpeedKph(target.speed);
                mNearestEstimatedSpeed = estimatedSpeedKph(target.speed, info.currentSpeed);
                mNearestThreat = target.threat;
                mNearestThreatSide = target.threatSide;
            }

            var match = findTrack(range);
            var speed = estimatedSpeedKph(target.speed, info.currentSpeed);
            if (match == null) {
                match = {
                    "range" => range,
                    "close" => (range <= PASS_DISTANCE_METERS),
                    "speed" => speed,
                    "seen" => true
                };
                mTracks.add(match);
            } else {
                var wasClose = match["close"];
                match["range"] = range;
                match["seen"] = true;
                if (speed != null) { match["speed"] = speed; }
                if (!wasClose && range <= PASS_DISTANCE_METERS) { match["close"] = true; }
            }
        }

        var passed = 0;
        for (var i = mTracks.size() - 1; i >= 0; i--) {
            var track = mTracks[i];
            if (!track["seen"]) {
                if (track["close"]) {
                    mVehicleCount += 1;
                    passed += 1;
                    if (track["speed"] != null) { mLastSpeed = track["speed"]; }
                }
                mTracks.remove(track);
            }
        }

        if (passed > 0) {
            System.println("[L508 ANT] passed +" + passed + " total=" + mVehicleCount + " speed=" + (mLastSpeed == null ? "--" : mLastSpeed.format("%d")));
        }
    }

    private function clearLiveData() as Void {
        mCurrentVehicleCount = 0;
        mNearestDistance = null;
        mNearestRelativeSpeed = null;
        mNearestEstimatedSpeed = null;
        mNearestThreat = null;
        mNearestThreatSide = null;
    }

    private function updateDeviceId() as Void {
        try {
            var state = mRadar.getDeviceState();
            if (state != null && state.deviceNumber != null && state.deviceNumber > 0 && state.deviceNumber != mDeviceId) {
                mDeviceId = state.deviceNumber;
                System.println("[L508 ANT] device id=" + mDeviceId);
            }
        } catch (e) {
        }
    }

    private function updateBatteryStatus() as Void {
        try {
            var status = mRadar.getBatteryStatus(null);
            if (status != null && status.batteryStatus != null) {
                mBatteryStatus = status.batteryStatus;
            }
        } catch (e) {
        }
    }

    private function findTrack(range) {
        var best = null;
        var distance = MATCH_DISTANCE_METERS;
        for (var ti = 0; ti < mTracks.size(); ti++) {
            var track = mTracks[ti];
            if (!track["seen"]) {
                var delta = track["range"] - range;
                if (delta < 0) { delta = -delta; }
                if (delta < distance) { distance = delta; best = track; }
            }
        }
        return best;
    }

    private function relativeSpeedKph(relative) as Lang.Number? {
        if (relative == null) { return null; }
        return Math.round(relative * 3.6);
    }

    private function estimatedSpeedKph(relative, rider) as Lang.Number? {
        if (relative == null || rider == null) { return null; }
        return Math.round((relative + rider) * 3.6);
    }

    function resetSession() as Void {
        mTracks = [];
        mVehicleCount = 0;
        mLastSpeed = null;
        clearLiveData();
        System.println("[L508 ANT] session counter reset");
    }

    // Session values.
    function getVehicleCount() as Lang.Number { return mVehicleCount; }
    function getLastSpeed() as Lang.Number? { return mLastSpeed; }

    // Live nearest-target values.
    function getCurrentVehicleCount() as Lang.Number { return mCurrentVehicleCount; }
    function getNearestDistance() as Lang.Number? { return mNearestDistance; }
    function getNearestRelativeSpeed() as Lang.Number? { return mNearestRelativeSpeed; }
    function getNearestEstimatedSpeed() as Lang.Number? { return mNearestEstimatedSpeed; }
    function getNearestThreat() as Lang.Number? { return mNearestThreat; }
    function getNearestThreatSide() as Lang.Number? { return mNearestThreatSide; }

    function getDeviceId() as Lang.Number? { return mDeviceId; }
    function getBatteryStatus() as Lang.Number? { return mBatteryStatus; }
}
