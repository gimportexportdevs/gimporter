using Toybox.WatchUi as Ui;

class gimporterDelegate extends Ui.BehaviorDelegate {
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
                        if (view.tracks == null) {
                                view.getTracks();
                        } else {
                                view.loadTrack();
                        }
                        return true;
                }
                return BehaviorDelegate.onKey(key);
        }


        function onPreviousPage() {
                view.previousTrack();
                return true;
        }

        function onNextPage() {
                view.nextTrack();
                return true;
        }

        function onPreviousMode() {
                return onPreviousPage();
        }

        function onNextMode() {
                return onNextPage();
        }
}
