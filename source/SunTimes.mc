import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Offline sunrise/sunset helper.
//!
//! The astronomical calculation follows the NOAA algorithm also used by
//! SmartBikeLights' SunsetDataField. Everything is evaluated in UTC seconds of
//! day, so no phone/network lookup or manual timezone handling is required.
class SunTimes {
    private var mLastCheck as Lang.Number?;
    private var mCachedNight as Lang.Boolean?;

    function initialize() {
        mLastCheck = null;
        mCachedNight = null;
    }

    //! Returns true between sunset and the next sunrise, false during daytime.
    //! Returns null until a usable GPS position is available or for polar dates
    //! where there is no normal sunrise/sunset.
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
            var utc = Gregorian.utcInfo(now, Time.FORMAT_SHORT);
            var position = location.toDegrees();

            var sunrise = getSunriseSet(true, utc, position);
            var sunset = getSunriseSet(false, utc, position);
            if (sunrise == null || sunset == null) { return null; }

            var nowSeconds = (utc.hour * 3600) + (utc.min * 60) + utc.sec;
            var night;
            if (sunrise <= sunset) {
                night = (nowSeconds < sunrise || nowSeconds >= sunset);
            } else {
                // Rare case where the daylight interval crosses UTC midnight.
                night = (nowSeconds >= sunset && nowSeconds < sunrise);
            }

            mCachedNight = night;
            return night;
        } catch (e) {
            System.println("[SUN] calculation error=" + e);
            return null;
        }
    }

    //! NOAA Solar Calculator style calculation. Returns UTC seconds of day.
    private function getSunriseSet(rise as Boolean, time, position) {
        var month = time.month;
        var year = time.year;
        if (month <= 2) {
            year -= 1;
            month += 12;
        }

        var a = Math.floor(year / 100);
        var b = 2 - a + Math.floor(a / 4);
        var jd = Math.floor(365.25 * (year + 4716))
            + Math.floor(30.6001 * (month + 1))
            + time.day + b - 1524.5;
        var t = (jd - 2451545.0) / 36525.0;

        var omega = degToRad(125.04 - 1934.136 * t);
        var l1 = 280.46646 + t * (36000.76983 + t * 0.0003032);
        while (l1 > 360.0) { l1 -= 360.0; }
        while (l1 < 0.0) { l1 += 360.0; }

        var l0 = degToRad(l1);
        var e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
        var mrad = degToRad(357.52911 + t * (35999.05029 - 0.0001537 * t));
        var ec = degToRad(
            (23.0 + (26.0 + ((21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))) / 60.0)) / 60.0)
            + 0.00256 * Math.cos(omega)
        );

        var y = Math.tan(ec / 2.0);
        y *= y;
        var sinm = Math.sin(mrad);
        var eqTime = (
            180.0 * (
                y * Math.sin(2.0 * l0)
                - 2.0 * e * sinm
                + 4.0 * e * y * sinm * Math.cos(2.0 * l0)
                - 0.5 * y * y * Math.sin(4.0 * l0)
                - 1.25 * e * e * Math.sin(2.0 * mrad)
            ) / 3.141593
        ) * 4.0;

        var sunEq = sinm * (1.914602 - t * (0.004817 + 0.000014 * t))
            + Math.sin(mrad + mrad) * (0.019993 - 0.000101 * t)
            + Math.sin(mrad + mrad + mrad) * 0.000289;

        var latitude = position[0].toFloat();
        var longitude = position[1].toFloat();
        var latRad = degToRad(latitude);
        var sdRad = degToRad(
            180.0 * Math.asin(
                Math.sin(ec) * Math.sin(
                    degToRad((l1 + sunEq) - 0.00569 - 0.00478 * Math.sin(omega))
                )
            ) / 3.141593
        );

        var cosHourAngle = Math.cos(degToRad(90.833))
            / (Math.cos(latRad) * Math.cos(sdRad))
            - Math.tan(latRad) * Math.tan(sdRad);

        if (cosHourAngle > 1.0 || cosHourAngle < -1.0) {
            return null;
        }

        var hourAngle = Math.acos(cosHourAngle);
        if (!rise) { hourAngle = -hourAngle; }

        var value = (
            720
            - (4.0 * (longitude + (180.0 * hourAngle / 3.141593)))
            - eqTime
        ) * 60;

        return getSecondsOfDay(value);
    }

    private function getSecondsOfDay(value) {
        var number = value.toNumber();
        if (number == null) { return null; }
        while (number < 0) { number += 86400; }
        return number % 86400;
    }

    private function degToRad(angleDeg) {
        return 3.141593 * angleDeg / 180.0;
    }
}
