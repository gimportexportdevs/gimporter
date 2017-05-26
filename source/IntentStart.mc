using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;
using Toybox.PersistedContent as PC;
using Toybox.System as System;

class IntentStart extends Ui.Menu {
    function initialize() {
	Menu.initialize();
	Menu.setTitle(Rez.Strings.intentStartTitle);
	Menu.addItem(Rez.Strings.NO, :NO);
	Menu.addItem(Rez.Strings.YES, :YES);
    }
}

class IntentStartDelegate extends Ui.MenuInputDelegate {
    var app;
    var intentToStart;

    function initialize(intent) {
        MenuInputDelegate.initialize();
        app = App.getApp();
	intentToStart = intent;
    }

    function onMenuItem(item) {
	if (!item.equals(:YES)) {
	    return;
	}

	System.exitTo(intentToStart);
    }
}
