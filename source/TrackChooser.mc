import Toybox.Lang;

using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;
using Toybox.PersistedContent as PC;

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
                    app.normalizeName(tracks[i]["title"] as String),
                    $.itemToSym(i - off) );
            }
            return;
        }

        for(var i = off, iMax = 15 + off; i < iMax; i++) {
            Menu.addItem(
                app.normalizeName(tracks[i]["title"] as String),
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

// Menu2 (API 3.0+) scrolls through any number of items and fits long
// names; the old Menu cuts them off and holds only 16.
function pushTrackChooser() as Void {
    if (Ui has :Menu2) {
        pushMenu2(Rez.Strings.trackChooserTitle, $.getApp().getTracks(), false);
    } else {
        Ui.pushView(new TrackChooser(0), new TrackChooserDelegate(0), Ui.SLIDE_IMMEDIATE);
    }
}

function pushSimilarCourseChooser() as Void {
    if (Ui has :Menu2) {
        pushMenu2(Rez.Strings.SimilarCourseChooserTitle, $.getApp().getSimilarCourses(), true);
    } else {
        Ui.pushView(new SimilarCourseChooser(), new SimilarCourseChooserDelegate(), Ui.SLIDE_IMMEDIATE);
    }
}

// items: dir.json entries, or PersistedContent objects for similar courses
function pushMenu2(title as ResourceId, items as Array?, similar as Boolean) as Void {
    var menu = new Ui.Menu2({ :title => title });
    if (items != null) {
        for (var i = 0; i < items.size(); i++) {
            var label = similar ? (items[i] as PC.Course).getName() : (items[i] as Dictionary)["title"] as String;
            // "Tour.gpx" -> "Tour"
            label = $.getApp().normalizeName(label);
            menu.addItem(new Ui.MenuItem(label, null, i, {}));
        }
    }
    Ui.pushView(menu, new ChooserMenu2Delegate(similar), Ui.SLIDE_IMMEDIATE);
}

class ChooserMenu2Delegate extends Ui.Menu2InputDelegate {
    var mSimilar as Boolean;

    function initialize(similar as Boolean) {
        Menu2InputDelegate.initialize();
        mSimilar = similar;
    }

    function onSelect(item as Ui.MenuItem) as Void {
        var index = item.getId() as Number;
        // like the old Menu, which closes itself on a choice
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        if (mSimilar) {
            $.getApp().launchSimilarCourse(index);
        } else {
            $.getApp().loadTrackNum(index);
        }
    }
}
