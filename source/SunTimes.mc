import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Small offline sunrise/sunset helper. It uses the current GPS location and
//! Garmin's LocalMoment time-zone/DST conversion, so no phone or network is needed.
class SunTimes {
    private var mLastCheck as Lang.Number?;
    private var mCachedNight as Lang.Boolean?;

    function initialize() {
        mLastCheck = null;
        mCachedNight = null;
    }

    //! Returns true between sunset and the next sunrise, false during daytime.
    //! Returns null until a usable location/time conversion is available.
    function isNight(location as Position.Location) as Lang.Boolean? {
        var timer = System.getTimer();
        if (mCachedNight != null && mLastCheck != null) {
            var last = mLastCheck as Lang.Number;
            if (timer >= last && timer - last < 60000) {
                return mCachedNight;
            }
        }
        mLastCheck = timer;

        try {
            var now = Time.now();
            var local = Gregorian.localMoment(location, now);
            if (local == null) { return null; }
            var localMoment = local as Time.LocalMoment;
            var info = Gregorian.info(localMoment, Time.FORMAT_SHORT);
            var coords = location.toDegrees();
            var latitude = coords[0];
            var longitude = coords[1];
            var dayNumber = dayOfYear(info.year, info.month, info.day);

            var sunriseUtc = sunUtcHour(latitude, longitude, dayNumber, true);
            var sunsetUtc = sunUtcHour(latitude, longitude, dayNumber, false);
            if (sunriseUtc == null || sunsetUtc == null) {
                return null;
            }

            var offsetHours = localMoment.getOffset() / 3600.0;
            var sunriseLocal = normalizeHours(sunriseUtc + offsetHours);
            var sunsetLocal = normalizeHours(sunsetUtc + offsetHours);
            var nowLocal = info.hour + (info.min / 60.0) + (info.sec / 3600.0);

            var night;
            if (sunriseLocal <= sunsetLocal) {
                night = (nowLocal < sunriseLocal || nowLocal >= sunsetLocal);
            } else {
                // Daylight interval crosses local midnight.
                night = (nowLocal >= sunsetLocal && nowLocal < sunriseLocal);
            }

            mCachedNight = night;
            return night;
        } catch (e) {
            System.println("[SUN] calculation error=" + e);
            return null;
        }
    }

    private function dayOfYear(year, month, day) {
        var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        if (isLeapYear(year)) { days[1] = 29; }
        var result = day;
        for (var i = 1; i < month; i++) {
            result += days[i - 1];
        }
        return result;
    }

    private function isLeapYear(year) as Boolean {
        if ((year % 400) == 0) { return true; }
        if ((year % 100) == 0) { return false; }
        return (year % 4) == 0;
    }

    //! NOAA-style sunrise/sunset approximation. Returned value is UTC hours.
    private function sunUtcHour(latitude, longitude, dayNumber, sunrise) {
        var lngHour = longitude / 15.0;
        var approximateTime;
        if (sunrise) {
            approximateTime = dayNumber + ((6.0 - lngHour) / 24.0);
        } else {
            approximateTime = dayNumber + ((18.0 - lngHour) / 24.0);
        }

        var meanAnomaly = (0.9856 * approximateTime) - 3.289;
        var trueLongitude = meanAnomaly
            + (1.916 * Math.sin(Math.toRadians(meanAnomaly)))
            + (0.020 * Math.sin(Math.toRadians(2.0 * meanAnomaly)))
            + 282.634;
        trueLongitude = normalizeDegrees(trueLongitude);

        var rightAscension = Math.toDegrees(
            Math.atan(0.91764 * Math.tan(Math.toRadians(trueLongitude)))
        );
        rightAscension = normalizeDegrees(rightAscension);

        var longitudeQuadrant = Math.floor(trueLongitude / 90.0) * 90.0;
        var raQuadrant = Math.floor(rightAscension / 90.0) * 90.0;
        rightAscension = rightAscension + (longitudeQuadrant - raQuadrant);
        rightAscension = rightAscension / 15.0;

        var sinDeclination = 0.39782 * Math.sin(Math.toRadians(trueLongitude));
        var cosDeclination = Math.cos(Math.asin(sinDeclination));
        var zenith = 90.833;
        var cosHourAngle = (
            Math.cos(Math.toRadians(zenith))
            - (sinDeclination * Math.sin(Math.toRadians(latitude)))
        ) / (cosDeclination * Math.cos(Math.toRadians(latitude)));

        if (cosHourAngle > 1.0 || cosHourAngle < -1.0) {
            // Polar day/night: no normal sunrise or sunset on this date.
            return null;
        }

        var hourAngle = Math.toDegrees(Math.acos(cosHourAngle));
        if (sunrise) { hourAngle = 360.0 - hourAngle; }
        hourAngle = hourAngle / 15.0;

        var localMeanTime = hourAngle + rightAscension
            - (0.06571 * approximateTime) - 6.622;
        return normalizeHours(localMeanTime - lngHour);
    }

    private function normalizeDegrees(value) {
        while (value < 0.0) { value += 360.0; }
        while (value >= 360.0) { value -= 360.0; }
        return value;
    }

    private function normalizeHours(value) {
        while (value < 0.0) { value += 24.0; }
        while (value >= 24.0) { value -= 24.0; }
        return value;
    }
}
