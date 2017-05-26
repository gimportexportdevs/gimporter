using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class TrackChooser extends Ui.Menu {

    function initialize(page) {
        var app = App.getApp();
	Menu.initialize();
	Menu.setTitle(Rez.Strings.trackChooserTitle);
	var tracks = app.getTracks();
	var num = tracks.size();
	var off = page*15;
	if ((num - off) <= 16) {
	    // simple case, all fit in
	    for(var i = page*15; i < num; i++) {
		Menu.addItem(tracks[i]["title"], toSym(i - off));
	    }
	    return;
	}

	for(var i = off; i < (15 + off); i++) {
	    Menu.addItem(tracks[i]["title"], toSym(i - off));
	}
	Menu.addItem(Rez.Strings.MORE, :MORE);
    }

    function toSym(i) {
	if (i == 0) {
	    return :ITEM_0;
	} else if (i == 1) {
	    return :ITEM_1;
	} else if (i == 2) {
	    return :ITEM_2;
	} else if (i == 3) {
	    return :ITEM_3;
	} else if (i == 4) {
	    return :ITEM_4;
	} else if (i == 5) {
	    return :ITEM_5;
	} else if (i == 6) {
	    return :ITEM_6;
	} else if (i == 7) {
	    return :ITEM_7;
	} else if (i == 8) {
	    return :ITEM_8;
	} else if (i == 9) {
	    return :ITEM_9;
	} else if (i == 10) {
	    return :ITEM_10;
	} else if (i == 11) {
	    return :ITEM_11;
	} else if (i == 12) {
	    return :ITEM_12;
	} else if (i == 13) {
	    return :ITEM_13;
	} else if (i == 14) {
	    return :ITEM_14;
	} else if (i == 15) {
	    return :ITEM_15;
	}
	return :ITEM_0;
    }
}

class TrackChooserDelegate extends Ui.MenuInputDelegate {
    var app;
    var page;

    function initialize(p) {
	page = p;

        MenuInputDelegate.initialize();
        app = App.getApp();
    }

    function toInt(sym) {
	if (sym.equals(:ITEM_0)) {
	    return 0;
	} else if (sym.equals(:ITEM_1)) {
	    return 1;
	} else if (sym.equals(:ITEM_2)) {
	    return 2;
	} else if (sym.equals(:ITEM_3)) {
	    return 3;
	} else if (sym.equals(:ITEM_4)) {
	    return 4;
	} else if (sym.equals(:ITEM_5)) {
	    return 5;
	} else if (sym.equals(:ITEM_6)) {
	    return 6;
	} else if (sym.equals(:ITEM_7)) {
	    return 7;
	} else if (sym.equals(:ITEM_8)) {
	    return 8;
	} else if (sym.equals(:ITEM_9)) {
	    return 9;
	} else if (sym.equals(:ITEM_10)) {
	    return 10;
	} else if (sym.equals(:ITEM_11)) {
	    return 11;
	} else if (sym.equals(:ITEM_12)) {
	    return 12;
	} else if (sym.equals(:ITEM_13)) {
	    return 13;
	} else if (sym.equals(:ITEM_14)) {
	    return 14;
	} else if (sym.equals(:ITEM_15)) {
	    return 15;
	}
	return 0;
    }

    function onMenuItem(item) {
	if (item.equals(:MORE)) {
	    Ui.pushView(new TrackChooser(page + 1), new TrackChooserDelegate(page + 1), Ui.SLIDE_IMMEDIATE);
	} else {
	    app.loadTrackNum(toInt(item) + page*15);
	}
    }
}
