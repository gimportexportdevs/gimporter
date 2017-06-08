using Toybox.WatchUi as Ui;
using Toybox.Application as App;
using Toybox.System as System;

class gimporterPost extends Ui.BehaviorDelegate {
    var app;
    var mCourse;

    function initialize(course) {
        BehaviorDelegate.initialize();
        app = App.getApp();
        mCourse = course;
        System.println("gimporterPost init app = " + app);
    }

    function onCancel() {
        System.println("gimporterPost onCancel");
        if (!app.acceptKey()) {
            Ui.popView(Ui.SLIDE_IMMEDIATE);
        }
    }

    function onKey(key) {
        System.println("gimporterPost key");
        var k = key.getKey();

        if (k == Ui.KEY_ENTER || k == Ui.KEY_START || k == Ui.KEY_RIGHT) {
            if (!app.acceptKey()) {
                    return true;
            }
            if (mCourse != null) {
                System.exitTo(mCourse.toIntent());
                mCourse = null;
                // FIXME: I would like to popView() here instead of exit()
                // but the Fenix5 bugs out
                var exitQuirk = app.getPropertyDef("ExitQuirks", false);
                if (exitQuirk) {
                    System.exit();
                }
                return true;
            }
        }
        return false;
    }
}