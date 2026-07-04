import Toybox.Lang;

using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class TrackChooser extends Ui.Menu {

    function initialize(page as Number) {
        var app = $.getApp();
        Menu.initialize();
        Menu.setTitle(Rez.Strings.trackChooserTitle);
        var tracks = app.getTracks() as [ Dictionary ];
        var num = tracks.size();
        var off = page*15;
        if ((num - off) <= 16) {
            // simple case, all fit in
            for(var i = page*15; i < num; i++) {
                Menu.addItem(
                    tracks[i]["title"] as String,
                    $.itemToSym(i - off) );
            }
            return;
        }

        for(var i = off, iMax = 15 + off; i < iMax; i++) {
            Menu.addItem(
                tracks[i]["title"] as String,
                $.itemToSym(i - off) );
        }
        Menu.addItem(Rez.Strings.MORE, :MORE);
    }
}

class TrackChooserDelegate extends Ui.MenuInputDelegate {
    var app as gimporterApp;
    var page as Number;

    function initialize(p as Number) {
        page = p;

        MenuInputDelegate.initialize();
        app = $.getApp();
    }

    function onMenuItem(item as Symbol) as Void {
        if (item.equals(:MORE)) {
            Ui.pushView(new TrackChooser(page + 1), new TrackChooserDelegate(page + 1), Ui.SLIDE_IMMEDIATE);
        } else {
            app.loadTrackNum($.symToItem(item) + page*15);
        }
    }
}
