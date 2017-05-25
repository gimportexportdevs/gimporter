using Toybox.Graphics as Gfx;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class TrackChooser extends Ui.Picker {
    var app;

    function initialize() {
        app = App.getApp();
        var title = new Ui.Text({:text=>Rez.Strings.trackChooserTitle,
         :locX =>Ui.LAYOUT_HALIGN_CENTER, :locY=>Ui.LAYOUT_VALIGN_BOTTOM, :color=>Gfx.COLOR_WHITE});
        var factory = new TrackFactory(app.getTracks(), {:font=>Gfx.FONT_XTINY});
        Picker.initialize({:title=>title, :pattern=>[factory]});
    }
/*
    function onUpdate(dc) {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        Picker.onUpdate(dc);
    }
    */
}

class TrackChooserDelegate extends Ui.PickerDelegate {
    var app;

    function initialize() {
        PickerDelegate.initialize();
        app = App.getApp();
                        System.println("TrackChooserDelegate init");

    }

    function onCancel() {
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }

    function onAccept(value) {
        app.loadTrack(value);
    }
}
