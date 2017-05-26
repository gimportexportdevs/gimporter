using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;
using Toybox.PersistedContent as PC;
using Toybox.System as System;

class TrackStart extends Ui.Menu {
    function initialize() {
	Menu.initialize();
	Menu.setTitle(Rez.Strings.trackStartTitle);
	Menu.addItem(Rez.Strings.NO, :NO);
	Menu.addItem(Rez.Strings.YES, :YES);
    }
}

class TrackStartDelegate extends Ui.MenuInputDelegate {
    var app;
    var trackToStart;

    function initialize(track) {
        MenuInputDelegate.initialize();
        app = App.getApp();
	trackToStart = track;
    }

    function onMenuItem(item) {
	if (!item.equals(:YES)) {
	    Ui.popView(Ui.SLIDE_IMMEDIATE);
	    return;
	}
	var cit = PC.getCourses();
	var course;
	while (true) {
	    course = cit.next();
	    if (course == null) {
		break;
	    }

	    if (course.getName().equals(trackToStart)) {
		System.exitTo(course.toIntent());
		return;
	    }
	}
	Ui.popView(Ui.SLIDE_IMMEDIATE);
    }
}
