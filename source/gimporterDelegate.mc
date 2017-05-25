using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class gimporterDelegate extends Ui.BehaviorDelegate {
    var app;

    function initialize() {
        BehaviorDelegate.initialize();
        app = App.getApp();
    }

    function onKey(key) {
        var k = key.getKey();

        if (k == Ui.KEY_ENTER || k == Ui.KEY_START || k == Ui.KEY_RIGHT) {
            if (!app.acceptKey()) {
                    return true;
            }
            app.loadTrackList();
            return true;
        }

        return BehaviorDelegate.onKey(key);
    }
}
