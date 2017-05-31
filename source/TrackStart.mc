using Toybox.WatchUi as Ui;
using Toybox.System as System;

class TrackStart extends Ui.Confirmation {
    function initialize() {
        Confirmation.initialize(Ui.loadResource(Rez.Strings.trackStartTitle));
    }
}

class TrackStartDelegate extends Ui.ConfirmationDelegate {
    var mIntent;

    function initialize(intent) {
        ConfirmationDelegate.initialize();
        mIntent = intent;
    }

    function onResponse(response) {
        if (response == Ui.CONFIRM_YES) {
            System.exitTo(mIntent);
        }
    }
}
