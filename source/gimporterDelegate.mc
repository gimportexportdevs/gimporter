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
	    if (app.getTrackSize() > 0) {
		app.loadTrack();
	    } else {
		app.loadTrackList();
	    }
	    return true;
	} else if (k == Ui.KEY_UP) {
	    app.previousTrack();
	    return true;
	} else if (k == Ui.KEY_DOWN) {
	    app.nextTrack();
	    return true;
	}

	return BehaviorDelegate.onKey(key);
    }


    function onPreviousPage() {
	app.previousTrack();
	return true;
    }

    function onNextPage() {
	app.nextTrack();
	return true;
    }

    function onPreviousMode() {
	return onPreviousPage();
    }

    function onNextMode() {
	return onNextPage();
    }
}
