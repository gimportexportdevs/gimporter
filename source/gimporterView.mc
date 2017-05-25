using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class gimporterView extends Ui.View {
    var st;
    var ps;
    var app;

    function initialize() {
        View.initialize();
        app = App.getApp();
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.MainLayout(dc));
        st = findDrawableById("status");
        ps = Ui.loadResource(Rez.Strings.PressStart);
    }

    function onUpdate(dc) {
        var status = app.getStatus();
        if (status.equals("")) {
            st.setText(ps);
        } else {
            st.setText(status);
        }

        View.onUpdate(dc);
    }

}
