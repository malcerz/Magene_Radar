import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Magene_RadarView extends WatchUi.DataField {

    hidden var mBattery as String;
    hidden var mRadar as L508RadarManager;

    function initialize() {
        DataField.initialize();
        mBattery = "--%";
        mRadar = new L508RadarManager();
        mRadar.initialize();
        System.println("[L508] BUILD=TEST5-RADAR-DATA");
    }

    // Set your layout here. Anytime the size of obscurity of
    // the draw context is changed this will be called.
    function onLayout(dc as Dc) as Void {
        // Drawing is performed directly in onUpdate for all field sizes.
    }

    // The given info object contains all the current workout information.
    // Calculate a value and save it locally in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Void {
        var manager = getApp().getL508BleManager();
        if (manager != null) {
            manager.pollBatteryIfDue();
            var batteryPercent = manager.getBatteryPercent();
            if (batteryPercent != null) {
                mBattery = batteryPercent.format("%d") + "%";
            } else { mBattery = "--%"; }
        }
        mRadar.update(info);
    }

function onUpdate(dc as Dc) as Void {
    var bg = getBackgroundColor();

    dc.setColor(Graphics.COLOR_TRANSPARENT, bg);
    dc.clear();

    var fg = bg == Graphics.COLOR_BLACK
        ? Graphics.COLOR_WHITE
        : Graphics.COLOR_BLACK;

    dc.setColor(fg, bg);

    var w = dc.getWidth();
    var h = dc.getHeight();

    // TYLKO layout 10-polowy Edge 1040
    var batteryFont = Graphics.FONT_SMALL;
    // Larger values for the two primary metrics; unit labels stay XTINY.
    var valueFont   = Graphics.FONT_NUMBER_MILD;
    var labelFont   = Graphics.FONT_XTINY;

    var batteryY = h * 0.05;
    var valueY   = h * 0.38;
    var labelY   = h * 0.85;

    // Battery
    dc.drawText(
        w / 2,
        batteryY,
        batteryFont,
        "Battery: " + mBattery,
        Graphics.TEXT_JUSTIFY_CENTER
    );

    // Cars count
    dc.drawText(
        w / 4,
        valueY,
        valueFont,
        mRadar.getVehicleCount().format("%d"),
        Graphics.TEXT_JUSTIFY_CENTER
    );

    dc.drawText(
        w / 4,
        labelY,
        labelFont,
        "Cars",
        Graphics.TEXT_JUSTIFY_CENTER
    );

    // Last vehicle speed
    var speed = mRadar.getLastSpeed();

    dc.drawText(
        (w * 3) / 4,
        valueY,
        valueFont,
        speed == null ? "--" : speed.format("%d"),
        Graphics.TEXT_JUSTIFY_CENTER
    );

    dc.drawText(
        (w * 3) / 4,
        labelY,
        labelFont,
        "km/h",
        Graphics.TEXT_JUSTIFY_CENTER
    );
}    

}
