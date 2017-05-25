using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class gimporterView extends Ui.View {
    var version;
    var t1;
    var t2;
    var t3;
    var st;
    var app;

    function initialize() {
	View.initialize();
	app = App.getApp();
    }

    // Load your resources here
    function onLayout(dc) {
	setLayout(Rez.Layouts.MainLayout(dc));
	System.println("onLayout");
	t1 = findDrawableById("t1");
	t2 = findDrawableById("t2");
	t3 = findDrawableById("t3");
	st = findDrawableById("status");
	version = Ui.loadResource( Rez.Strings.AppVersion );
    }


    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() {
    }

    // Update the view
    function onUpdate(dc) {
	if (app.getTrackSize() > 0) {
	    if (app.showList()) {
		t1.setText("⏶⏶⏶");
		t3.setText("⏷⏷⏷");
	    } else {
		t1.setText("");
		t3.setText("");
	    }
	    t2.setText(app.getCurrentTrackTitle());
	} else {
	    if (app.showList()) {
		status = "no tracks!!!";
	    }
	}

	var status = app.getStatus();

	if (status.equals("")) {
	    st.setText(version);
	} else {
	    st.setText(status);
	}

	// Call the parent onUpdate function to redraw the layout
	View.onUpdate(dc);
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() {
    }
}
