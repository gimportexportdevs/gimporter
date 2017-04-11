using Toybox.WatchUi as Ui;

class importerDelegate extends Ui.BehaviorDelegate {
	var view;

	function initialize(v) {
		BehaviorDelegate.initialize();
		view = v;
	}

    function onMenu() {
        Ui.pushView(new Rez.Menus.MainMenu(), new importerMenuDelegate(), Ui.SLIDE_UP);
        return true;
    }
    
	function onKey(key) {
		var k = key.getKey();
		if (k == Ui.KEY_ENTER || k == Ui.KEY_START || k == Ui.KEY_RIGHT) {
			view.loadTrack();
			return true;
		}
		return BehaviorDelegate.onKey(key);
	}

}