using Toybox.WatchUi as Ui;

class importerDelegate extends Ui.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() {
        Ui.pushView(new Rez.Menus.MainMenu(), new importerMenuDelegate(), Ui.SLIDE_UP);
        return true;
    }

}