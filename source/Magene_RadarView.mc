import Toybox.Activity;
import Toybox.AntPlus;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Magene_RadarView extends WatchUi.DataField {

    hidden var mAtBattery as String;
    hidden var mLrBattery as String;
    hidden var mRadar as L508RadarManager;

    function initialize() {
        DataField.initialize();
        mAtBattery = "--%";
        mLrBattery = "--%";
        mRadar = new L508RadarManager();
        System.println("[MAGENE] BUILD=RADAR-LIGHT-AUTO-SBL-V5");
    }

    function onLayout(dc as Dc) as Void {
        // Drawing is performed directly in onUpdate for all field sizes.
    }

    function compute(info as Activity.Info) as Void {
        mRadar.update(info);

        // Rear L508: the paired BikeRadar channel exposes the tracked ANT ID.
        var lrAntId = mRadar.getDeviceId();
        if (lrAntId != null) {
            getApp().rememberLrDeviceId(lrAntId);
        }

        // Front AT1600/AT1200: raw Bike Lights page identifies HEADLIGHT and
        // carries the source Ant.Message.deviceNumber.
        var lightManager = getApp().getLightNetworkManager();
        if (lightManager != null) {
            var atAntId = lightManager.getHeadlightDeviceId();
            if (atAntId != null) { getApp().rememberAtDeviceId(atAntId); }
        }

        if (!getApp().getShowBatteryStatus()) { return; }

        var atPercent = null;
        var lrPercent = null;
        var manager = getApp().getBleManager();
        if (manager != null) {
            manager.setDeviceIds(getApp().getAtDeviceId(), getApp().getLrDeviceId());
            manager.pollBatteryIfDue();
            atPercent = manager.getAtBatteryPercent();
            lrPercent = manager.getLrBatteryPercent();
        }

        // If a light emits ANT+ Bike Lights supplementary page 19, it contains
        // an exact 0-100% battery value. Use it when BLE percentage is absent.
        var atStatus = null;
        var lrStatus = mRadar.getBatteryStatus();
        if (lightManager != null) {
            if (atPercent == null) {
                atPercent = lightManager.getBatteryPercentForDevice(getApp().getAtDeviceId());
            }
            if (lrPercent == null) {
                lrPercent = lightManager.getBatteryPercentForDevice(getApp().getLrDeviceId());
            }
            atStatus = lightManager.getHeadlightBatteryStatus();
            var lightLrStatus = lightManager.getTailLightBatteryStatus();
            if (lightLrStatus != null) { lrStatus = lightLrStatus; }
        }

        mAtBattery = formatBattery(atPercent, atStatus);
        mLrBattery = formatBattery(lrPercent, lrStatus);
    }

    function onTimerReset() as Void {
        mRadar.resetSession();
    }

    private function formatBattery(percent, status) as String {
        if (percent != null) { return (percent as Lang.Number).format("%d") + "%"; }
        if (status == null) { return "--%"; }
        if (status == AntPlus.BATT_STATUS_NEW) { return "NEW"; }
        if (status == AntPlus.BATT_STATUS_GOOD) { return "GOOD"; }
        if (status == AntPlus.BATT_STATUS_OK) { return "OK"; }
        if (status == AntPlus.BATT_STATUS_LOW) { return "LOW"; }
        if (status == AntPlus.BATT_STATUS_CRITICAL) { return "CRIT"; }
        return "--%";
    }

    function onUpdate(dc as Dc) as Void {
        var bg = getBackgroundColor();
        dc.setColor(Graphics.COLOR_TRANSPARENT, bg);
        dc.clear();

        var fg = bg == Graphics.COLOR_BLACK ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);

        var w = dc.getWidth();
        var h = dc.getHeight();
        var showBattery = getApp().getShowBatteryStatus();
        var contentTop = 1;

        if (showBattery) {
            contentTop = drawBatteries(dc, w, h);
        }

        var metrics = buildEnabledMetrics();
        var maxMetrics = maxMetricsForSlot(w, h);
        while (metrics.size() > maxMetrics) {
            metrics.remove(metrics[metrics.size() - 1]);
        }

        drawMetricGrid(dc, metrics, w, h, contentTop);
    }

    //! Battery values use a font one step larger than BatAT:/BatLR: labels.
    //! The whole row is intentionally lowered a few pixels compared with V2.
    private function drawBatteries(dc as Dc, w as Lang.Number, h as Lang.Number) as Lang.Number {
        var labelFont = Graphics.FONT_XTINY;
        var valueFont = Graphics.FONT_TINY;

        if (w >= 250 && h >= 150) {
            labelFont = Graphics.FONT_TINY;
            valueFont = Graphics.FONT_SMALL;
        }
        if (w >= 250 && h >= 350) {
            labelFont = Graphics.FONT_SMALL;
            valueFont = Graphics.FONT_MEDIUM;
        }

        var y = 4;
        var valueH = dc.getFontHeight(valueFont);
        var labelH = dc.getFontHeight(labelFont);
        var labelY = y + ((valueH - labelH) / 2);

        var atLabel = "BatAT: ";
        var lrLabel = "BatLR: ";

        var atLabelW = dc.getTextWidthInPixels(atLabel, labelFont);
        dc.drawText(2, labelY, labelFont, atLabel, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(2 + atLabelW, y, valueFont, mAtBattery, Graphics.TEXT_JUSTIFY_LEFT);

        var lrLabelW = dc.getTextWidthInPixels(lrLabel, labelFont);
        var lrValueW = dc.getTextWidthInPixels(mLrBattery, valueFont);
        var lrX = w - 2 - lrLabelW - lrValueW;
        dc.drawText(lrX, labelY, labelFont, lrLabel, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(lrX + lrLabelW, y, valueFont, mLrBattery, Graphics.TEXT_JUSTIFY_LEFT);

        return y + valueH + 3;
    }

    //! Settings define priority/order. A slot displays only the first N enabled
    //! fields that fit its layout profile.
    private function buildEnabledMetrics() as Lang.Array<Lang.Dictionary> {
        var out = [];

        if (getApp().getShowCurrentCars()) {
            out.add(metric("Cars", mRadar.getCurrentVehicleCount().format("%d"), true, "8"));
        }
        if (getApp().getShowRelativeSpeed()) {
            out.add(metric("Rel km/h", numberOrDash(mRadar.getNearestRelativeSpeed()), true, "999"));
        }
        if (getApp().getShowNearestDistance()) {
            out.add(metric("Dist m", numberOrDash(mRadar.getNearestDistance()), true, "999"));
        }
        if (getApp().getShowThreatLevel()) {
            out.add(metric("Threat", threatText(mRadar.getNearestThreat()), false, "!!"));
        }
        if (getApp().getShowThreatSide()) {
            out.add(metric("Side", threatSideText(mRadar.getNearestThreatSide()), false, "P"));
        }
        if (getApp().getShowSessionCounter()) {
            out.add(metric("Total", mRadar.getVehicleCount().format("%d"), true, "999"));
        }
        if (getApp().getShowEstimatedSpeed()) {
            out.add(metric("Car km/h", numberOrDash(mRadar.getNearestEstimatedSpeed()), true, "999"));
        }

        return out;
    }

    private function metric(label as String, value as String, numeric as Boolean, sample as String) as Lang.Dictionary {
        return {
            "label" => label,
            "value" => value,
            "numeric" => numeric,
            "sample" => sample
        };
    }

    private function numberOrDash(value as Lang.Number?) as String {
        return value == null ? "--" : value.format("%d");
    }

    private function threatText(value as Lang.Number?) as String {
        if (value == null || value == AntPlus.THREAT_LEVEL_NO_THREAT) { return "--"; }
        if (value == AntPlus.THREAT_LEVEL_VEHICLE_FAST_APPROACHING) { return "!!"; }
        if (value == AntPlus.THREAT_LEVEL_VEHICLE_APPROACHING) { return "!"; }
        return "--";
    }

    private function threatSideText(value as Lang.Number?) as String {
        if (value == AntPlus.THREAT_SIDE_LEFT) { return "L"; }
        if (value == AntPlus.THREAT_SIDE_RIGHT) { return "P"; }
        return "--";
    }

    //! Edge 1040 slot profiles used by the requested layouts:
    //! 10 fields ~141x94 -> first 2 enabled metrics
    //!  9 fields ~282x94 -> first 5 enabled metrics
    //!  7 fields ~282x188 -> first 5 enabled metrics, larger typography
    //!  1 field  ~282x470 -> all enabled metrics
    private function maxMetricsForSlot(w as Lang.Number, h as Lang.Number) as Lang.Number {
        if (w <= 160 && h <= 115) { return 2; }
        if (w >= 250 && h <= 115) { return 5; }
        if (w >= 250 && h <= 230) { return 5; }
        if (w >= 250 && h >= 350) { return 7; }

        // Safe responsive fallback for any other Edge slot.
        if (h < 115) { return w >= 220 ? 5 : 2; }
        if (h < 240) { return 5; }
        return 7;
    }

    private function drawMetricGrid(dc as Dc, metrics as Lang.Array<Lang.Dictionary>, w as Lang.Number, h as Lang.Number, top as Lang.Number) as Void {
        var count = metrics.size();
        if (count <= 0) { return; }

        var columns = 2;
        var rows = 1;

        if (w <= 160 && h <= 115) {
            columns = 2;
            rows = 1;
        }
        else if (w >= 250 && h <= 115) {
            columns = count;
            rows = 1;
        }
        else if (w >= 250 && h <= 230) {
            columns = 3;
            rows = 2;
        }
        else if (w >= 250 && h >= 350) {
            columns = 2;
            rows = (count + 1) / 2;
        }
        else {
            columns = w >= 230 ? 3 : 2;
            rows = (count + columns - 1) / columns;
        }

        var areaH = h - top;
        if (areaH <= 2) { return; }
        var cellW = w / columns;
        var cellH = areaH / rows;

        for (var i = 0; i < count; i++) {
            var row = i / columns;
            var col = i % columns;

            var x0 = col * cellW;
            if (columns == 3 && rows == 2 && count == 5 && row == 1) {
                x0 += cellW / 2;
            }

            drawMetricCell(dc, metrics[i], x0, top + row * cellH, cellW, cellH);
        }
    }

    private function drawMetricCell(dc as Dc, item as Lang.Dictionary, x as Lang.Number, y as Lang.Number, cellW as Lang.Number, cellH as Lang.Number) as Void {
        var label = item["label"] as String;
        var value = item["value"] as String;
        var sample = item["sample"] as String;
        var numeric = item["numeric"] as Boolean;

        var innerW = cellW - 6;
        if (innerW < 20) { innerW = cellW; }

        var labelFont = chooseLabelFont(dc, label, innerW, cellH);
        var labelH = dc.getFontHeight(labelFont);
        var valueMaxH = cellH - labelH - 2;
        if (valueMaxH < 8) { valueMaxH = 8; }

        var probe = sample;
        if (dc.getTextWidthInPixels(value, Graphics.FONT_XTINY) > dc.getTextWidthInPixels(sample, Graphics.FONT_XTINY)) {
            probe = value;
        }
        var valueFont = chooseValueFont(dc, probe, innerW, valueMaxH, numeric);
        var valueH = dc.getFontHeight(valueFont);

        var blockH = valueH + labelH;
        var blockY = y + ((cellH - blockH) / 2);
        if (blockY < y) { blockY = y; }

        var centerX = x + (cellW / 2);
        dc.drawText(centerX, blockY, valueFont, value, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(centerX, blockY + valueH, labelFont, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function chooseLabelFont(dc as Dc, text as String, maxW as Lang.Number, maxH as Lang.Number) {
        var fonts = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        var maxLabelH = maxH / 3;
        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            if (dc.getFontHeight(f) <= maxLabelH && dc.getTextWidthInPixels(text, f) <= maxW) {
                return f;
            }
        }
        return Graphics.FONT_XTINY;
    }

    private function chooseValueFont(dc as Dc, text as String, maxW as Lang.Number, maxH as Lang.Number, numeric as Boolean) {
        var fonts;
        if (numeric) {
            fonts = [
                Graphics.FONT_NUMBER_HOT,
                Graphics.FONT_NUMBER_MEDIUM,
                Graphics.FONT_NUMBER_MILD,
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_TINY,
                Graphics.FONT_XTINY
            ];
        } else {
            fonts = [
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_TINY,
                Graphics.FONT_XTINY
            ];
        }

        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            if (dc.getFontHeight(f) <= maxH && dc.getTextWidthInPixels(text, f) <= maxW) {
                return f;
            }
        }
        return Graphics.FONT_XTINY;
    }
}
