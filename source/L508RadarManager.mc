import Toybox.AntPlus;
import Toybox.System;
import Toybox.Math;
import Toybox.Lang;

class L508RadarManager {
    const PASS_DISTANCE_METERS = 10.0;
    const MATCH_DISTANCE_METERS = 20.0;
    private var mRadar;
    private var mTracks as Lang.Array<Lang.Dictionary> = [];
    private var mVehicleCount as Lang.Number = 0;
    private var mLastSpeed as Lang.Number? = null;
    private var mReportedData as Lang.Boolean = false;

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
        var targets;
        try { targets = mRadar.getRadarInfo(); } catch (e) {
            System.println("[L508 ANT] getRadarInfo error=" + e);
            return;
        }
        if (targets == null) { return; }
        if (targets.size() > 0 && !mReportedData) {
            mReportedData = true;
            System.println("[L508 ANT] first radar data received");
        }
        for (var oi = 0; oi < mTracks.size(); oi++) { mTracks[oi]["seen"] = false; }
        for (var ti = 0; ti < targets.size(); ti++) {
            var target = targets[ti];
            if (target == null || target.threat == AntPlus.THREAT_LEVEL_NO_THREAT) { continue; }
            var range = target.range;
            if (range == null || range < 0) { continue; }
            var match = findTrack(range);
            var speed = speedKph(target.speed, info.currentSpeed);
            if (match == null) {
                match = {"range" => range, "close" => (range <= PASS_DISTANCE_METERS), "speed" => speed, "seen" => true};
                mTracks.add(match);
                if (range <= PASS_DISTANCE_METERS) {
                    System.println("[L508 ANT] target close range=" + range.format("%.1f") + " speed=" + (speed == null ? "--" : speed.format("%d")));
                }
            } else {
                var wasClose = match["close"];
                match["range"] = range;
                match["seen"] = true;
                if (speed != null) { match["speed"] = speed; }
                if (!wasClose && range <= PASS_DISTANCE_METERS) {
                    match["close"] = true;
                    System.println("[L508 ANT] target close range=" + range.format("%.1f") + " speed=" + (speed == null ? "--" : speed.format("%d")));
                }
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
        if (passed == 1) {
            System.println("[L508 ANT] vehicle passed count=" + mVehicleCount.format("%d") + " speed=" + (mLastSpeed == null ? "--" : mLastSpeed.format("%d")));
        } else if (passed > 1) {
            System.println("[L508 ANT] vehicles passed +" + passed.format("%d") + " total=" + mVehicleCount.format("%d"));
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

    private function speedKph(relative, rider) {
        if (relative == null || rider == null) { return null; }
        return Math.round((relative + rider) * 3.6);
    }
    function getVehicleCount() as Lang.Number { return mVehicleCount; }
    function getLastSpeed() as Lang.Number? { return mLastSpeed; }
}
