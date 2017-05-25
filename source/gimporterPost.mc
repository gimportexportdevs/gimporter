using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class gimporterPost extends Ui.BehaviorDelegate {
    var app;

    function initialize() {
        BehaviorDelegate.initialize();
        app = App.getApp();
    }

    function onCancel() {
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }

    function onKey(key) {
        if (!app.acceptKey()) {
                        return true;
        }
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        return true;
    }
}
