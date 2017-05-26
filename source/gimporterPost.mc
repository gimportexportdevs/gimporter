using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class gimporterPost extends Ui.BehaviorDelegate {
    var app;

    function initialize() {
        BehaviorDelegate.initialize();
        app = App.getApp();
    }

    function onKey(key) {
        if (!app.acceptKey()) {
	    return false;
        }
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        return true;
    }
}
