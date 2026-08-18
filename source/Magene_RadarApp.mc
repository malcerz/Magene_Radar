import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class Magene_RadarApp extends Application.AppBase {

    private var mL508BleManager as L508BleManager?;

    function initialize() {
        AppBase.initialize();
        mL508BleManager = new L508BleManager();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        if (mL508BleManager != null) {
            mL508BleManager.start();
        }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        if (mL508BleManager != null) {
            mL508BleManager.stop();
        }
    }

    function getL508BleManager() as L508BleManager? {
        return mL508BleManager;
    }

    //! Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new Magene_RadarView() ];
    }

}

function getApp() as Magene_RadarApp {
    return Application.getApp() as Magene_RadarApp;
}
